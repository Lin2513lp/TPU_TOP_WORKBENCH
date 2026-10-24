`timescale 1ns/1ps
`default_nettype none

// 每拍输入一列，默认 16 路 x 32 bit；第 r 路延迟 r 拍。
// 连续输入 P0、P1、P2 时，SA 在 T0 / T1 / T2 上升沿采到：
//   第 0 路： P0[0]  P1[0]  P2[0]
//   第 1 路：   0    P0[1]  P1[1]
//   第 2 路：   0      0    P0[2]
module tpu_ctrl_skew #(
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned LANES = 16
) (
    input  wire logic sys_ckg,
    input  wire logic tpu_rst_n,
    input  wire logic clear,
    input  wire logic [LANES*DATA_WIDTH-1:0] input_data,
    input  wire logic input_valid,
    input  wire logic input_last,
    output      logic [LANES*DATA_WIDTH-1:0] output_data,
    output      logic output_valid,
    output      logic output_last
);
    // 1. 先补 0：这一拍没有读到 FIFO，整个输入列直接替换成 0。
    logic [LANES*DATA_WIDTH-1:0] padded_input;
    assign padded_input = input_valid ? input_data : '0;

    // 2. 再错开：lane_data[r] 保存第 r 路延迟 r 拍后的数据。
    logic [DATA_WIDTH-1:0] lane_data [0:LANES-1];
    assign lane_data[0] = padded_input[0 +: DATA_WIDTH];

    for (genvar row = 1; row < LANES; row++) begin : gen_lane
        // row=1：输入 -> data_q[0] -> 输出
        // row=2：输入 -> data_q[0] -> data_q[1] -> 输出
        // row=3：输入 -> data_q[0] -> data_q[1] -> data_q[2] -> 输出
        logic [DATA_WIDTH-1:0] data_q [0:row-1];
        always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
            if (!tpu_rst_n) begin
                for (int stage = 0; stage < row; stage++) data_q[stage] <= '0;
            end else if (clear) begin
                for (int stage = 0; stage < row; stage++) data_q[stage] <= '0;
            end else begin
                // 第一级接收本路数据；无效输入已在前面补成 0。
                data_q[0] <= padded_input[row*DATA_WIDTH +: DATA_WIDTH];
                // 后续级每拍接收前一级旧值，FIFO 为空也不停移位。
                for (int stage = 1; stage < row; stage++)
                    data_q[stage] <= data_q[stage-1];
            end
        end
        assign lane_data[row] = data_q[row-1];
    end

    // 3. 标记跟随数据：共用一条历史链，第 r 位表示延迟 r 拍。
    // 有效数据也可能等于 0，所以 valid 仍需单独保存。
    logic [LANES-1:0] valid_history;
    logic [LANES-1:0] last_history;
    assign valid_history[0] = input_valid;
    assign last_history[0] = input_valid && input_last;
    for (genvar delay = 1; delay < LANES; delay++) begin : gen_marker
        always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
            if (!tpu_rst_n) begin
                valid_history[delay] <= 1'b0;
                last_history[delay] <= 1'b0;
            end else if (clear) begin
                valid_history[delay] <= 1'b0;
                last_history[delay] <= 1'b0;
            end else begin
                valid_history[delay] <= valid_history[delay-1];
                last_history[delay] <= last_history[delay-1];
            end
        end
    end
    // 4. 明确拼出输出列：有效位置放数据，其他位置放一整个字的 0。
    logic [LANES-1:0] lane_valid;
    assign lane_valid = valid_history & {LANES{!clear}};

    if (LANES == 16 && DATA_WIDTH == 32) begin : gen_output_16
        // 大括号左边是高位第 15 路，右边是低位第 0 路。
        // T0: {15 个零字, P0[0]}
        // T1: {14 个零字, P0[1], P1[0]}
        // T2: {13 个零字, P0[2], P1[1], P2[0]}
        assign output_data = {
            lane_valid[15] ? lane_data[15] : 32'b0,
            lane_valid[14] ? lane_data[14] : 32'b0,
            lane_valid[13] ? lane_data[13] : 32'b0,
            lane_valid[12] ? lane_data[12] : 32'b0,
            lane_valid[11] ? lane_data[11] : 32'b0,
            lane_valid[10] ? lane_data[10] : 32'b0,
            lane_valid[ 9] ? lane_data[ 9] : 32'b0,
            lane_valid[ 8] ? lane_data[ 8] : 32'b0,
            lane_valid[ 7] ? lane_data[ 7] : 32'b0,
            lane_valid[ 6] ? lane_data[ 6] : 32'b0,
            lane_valid[ 5] ? lane_data[ 5] : 32'b0,
            lane_valid[ 4] ? lane_data[ 4] : 32'b0,
            lane_valid[ 3] ? lane_data[ 3] : 32'b0,
            lane_valid[ 2] ? lane_data[ 2] : 32'b0,
            lane_valid[ 1] ? lane_data[ 1] : 32'b0,
            lane_valid[ 0] ? lane_data[ 0] : 32'b0
        };
    end else begin : gen_output_other_lanes
        // 保留其他路数或字宽配置；每路仍按相同规则补 0。
        for (genvar row = 0; row < LANES; row++) begin : gen_word
            assign output_data[row*DATA_WIDTH +: DATA_WIDTH] =
                lane_valid[row] ? lane_data[row] : {DATA_WIDTH{1'b0}};
        end
    end

    // clear 立即把所有路补成 0，下一上升沿同时清空内部寄存器。
    // 任意一路有效，整列 valid 就为 1；LAST 跟随物理最后一路。
    assign output_valid = !clear && (|valid_history);
    assign output_last = !clear && last_history[LANES-1];
endmodule
`default_nettype wire
