`timescale 1ns/1ps
`default_nettype none

// Export complete PE results immediately. Original FIFO valid/last distinguish
// real vectors from bubbles/padding; shared skew valid cannot do this.
module output_collector #(
    parameter int unsigned DATA_WIDTH   = 32,
    parameter int unsigned MODE_WIDTH   = 2,
    parameter int unsigned ARRAY_H      = 16,
    parameter int unsigned ARRAY_W      = 16,
    parameter int unsigned H_SIZE_WIDTH = 4,
    parameter int unsigned W_SIZE_WIDTH = 4
) (
    // SYS metadata; external CRG owns clock gating.
    input  wire logic                                  sys_ckg,
    input  wire logic                                  tpu_rst_n,
    input  wire logic                                  stream_enable,
    input  wire logic [H_SIZE_WIDTH-1:0]                active_h_size,
    input  wire logic [W_SIZE_WIDTH-1:0]                active_w_size,
    input  wire logic [MODE_WIDTH-1:0]                  cpt_mode,
    input  wire logic                                  vector_in_vld,
    input  wire logic                                  vector_in_last,
    input  wire logic [DATA_WIDTH*ARRAY_W-1:0]           raw_dat_in,
    input  wire logic [ARRAY_W-1:0]                      raw_dat_in_vld,
    output      logic [DATA_WIDTH*ARRAY_W-1:0]           dat_out,
    output      logic                                  dat_out_vld,
    output      logic                                  dat_out_last
);
    // valid 历史需要覆盖最慢结果的延迟：(ARRAY_H-1)+(ARRAY_W-1)+(L_max-1)。
    // 当前 FP16 最慢，L_max=7；再加上表示当前采样沿的位置0，得到 ARRAY_H+ARRAY_W+5。
    // 默认16x16时共37位，索引0..36；这是常量，不会生成37位数值数据缓存。
    localparam int unsigned TOKEN_STAGES = ARRAY_H + ARRAY_W + 5;

    // LAST 倒计时加载“最后一列的延迟+1”，最大值为 TOKEN_STAGES。
    // 计数器须表示0..TOKEN_STAGES，共 TOKEN_STAGES+1 个值；$clog2 向上取整求位宽。
    // 默认需表示0..37，所以位宽为6；该常量本身不占用寄存器。
    localparam int unsigned LAST_COUNT_WIDTH = $clog2(TOKEN_STAGES + 1);

    // 寄存器：保存每拍原始 FIFO 向量的 valid，不保存数值数据；默认37位。
    // 采样沿之后 bit0 是本拍 valid，bit1 是前一拍 valid，以此类推；气泡也照常移位。
    // 第col列选取 H-1+col+(L-1) 位置，用来判断当前 PE 输出对应的向量是否有效。
    logic [TOKEN_STAGES-1:0] vector_valid_q;

    // 寄存器：只跟踪本任务唯一一次 LAST；默认6位，替代另一条37位 LAST 移位链。
    // 最后一次 FIFO 读取时加载 H-1+W-1+(L-1)+1；0=空闲，>1逐拍递减。
    // 1=到达最终输出时刻；须同时有末列有效结果才产生 LAST，采样后清零。
    logic [LAST_COUNT_WIDTH-1:0] last_count_q;

    // 组合信号：每列“最终结果有效”的标记，默认16位；不增加寄存器。
    // 由该列的延迟 valid 与 raw_dat_in_vld 相与得到；无效列输出0，或归约得到整拍valid。
    logic [ARRAY_W-1:0] final_lane_vld;

    // 组合信号：精度模式的额外延迟 L-1；INT4/INT8/FP16/FP32分别为0/0/6/3。
    // 最大为6，需3位表示；用于选择 valid 历史位置及计算 LAST 倒计时初值。
    logic [2:0] mode_extra_cycles;

    // Existing INT4/INT8/FP16/FP32 latencies are L=1/1/7/4.
    always_comb begin
        unique case (cpt_mode)
            2'b00, 2'b01: mode_extra_cycles = 3'd0;
            2'b10:        mode_extra_cycles = 3'd6;
            2'b11:        mode_extra_cycles = 3'd3;
            default:      mode_extra_cycles = 3'd0;
        endcase
    end

    // Advance through bubbles too; numeric data stays in the PE array.
    always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            vector_valid_q <= '0;
            last_count_q   <= '0;
        end else if (!stream_enable || dat_out_last) begin
            // Flush so later H/W changes cannot select stale deeper tokens.
            vector_valid_q <= '0;
            last_count_q   <= '0;
        end else begin
            vector_valid_q <= {vector_valid_q[TOKEN_STAGES-2:0], vector_in_vld};
            // One LAST per task: 0=idle, 1=LAST now. Load delay+1 for H=W=L=1;
            // hold at 1 until its valid output is sampled and flushed above.
            if (vector_in_vld && vector_in_last)
                last_count_q <= LAST_COUNT_WIDTH'(
                    int'(active_h_size) + int'(active_w_size) +
                    int'(mode_extra_cycles) + 1);
            else if (last_count_q > 1)
                last_count_q <= last_count_q - 1'b1;
        end
    end

    // H/W/mode stable through DONE. Disabled rows bypass, so delay uses H.
    always_comb begin
        dat_out       = '0;
        final_lane_vld = '0;
        dat_out_last  = 1'b0;
        for (int unsigned col = 0; col < ARRAY_W; col++) begin
            if (stream_enable && (int'(active_h_size) < ARRAY_H) &&
                (col <= int'(active_w_size))) begin
                final_lane_vld[col] =
                    vector_valid_q[int'(active_h_size) + col + int'(mode_extra_cycles)] &&
                    raw_dat_in_vld[col];
                if (final_lane_vld[col]) begin
                    dat_out[col*DATA_WIDTH +: DATA_WIDTH] =
                        raw_dat_in[col*DATA_WIDTH +: DATA_WIDTH];
                end
                if (col == int'(active_w_size)) begin
                    dat_out_last = final_lane_vld[col] &&
                        (last_count_q == 1);
                end
            end
        end
        dat_out_vld = |final_lane_vld;
    end
endmodule

`default_nettype wire
