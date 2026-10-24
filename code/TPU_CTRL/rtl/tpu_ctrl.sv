`timescale 1ns/1ps
`default_nettype none

// CTRL 固定处理 16 路 x 32 bit 输入，第 r 路延迟 r 拍；空白位置补 0。
// H/W/mode 不改变 FIFO 读法或错位数据；物理尾部 LAST 保留在 CTRL 内部。
// 输入包数由实际 FIFO 数据及输入 LAST 决定，不由 H/W 决定。
module tpu_ctrl (
    // Always-on control while a task/CDC handshake is in progress; SYS clock
    // gating and reset release remain the external CRG responsibility.
    input  wire logic sys_ckg,
    input  wire logic tpu_rst_n,
    input  wire logic cpu_tpu_en,
    input  wire logic cpu_tpu_start,
    // AHB-domain clear request toggle; CTRL returns the processed toggle.
    input  wire logic cpu_done_clear_req,
    output      logic done_clear_ack,
    // 静态配置接口：START 前到 DONE 期间保持稳定；H/W 使用尺寸减 1 编码。
    // 本 CTRL 不直接使用配置计算数据路径或计数，SA 使用配置完成计算。
    input  wire logic [1:0] cpu_cpt_mode,
    input  wire logic [3:0] cpu_h_size,
    input  wire logic [3:0] cpu_w_size,
    input  wire logic fifo_empty,
    input  wire logic [511:0] fifo_in_rdata,
    input  wire logic fifo_in_rd_dat_last,
    // Wire SA dat_out_vld && dat_out_last here. This is SA completion, not
    // acknowledgment by the AXI output consumer.
    input  wire logic data_out_last,
    output      logic fifo_in_re,
    output      logic cpu_tpu_en_sync,
    output      logic cpu_tpu_start_sync,
    output      logic [511:0] dat_in_a,
    // Lane0 vector sampling markers; dat_in_a remains row-skewed.
    // VALID=0 does not mean all lanes are empty; LAST is not lane15 tail.
    output      logic dat_in_vld,
    output      logic dat_in_last,
    // Sticky DONE: fixed input tail + eligible SA LAST; next accepted START or W1C clears.
    output      logic rpt_cpt_done,
    // 每次实际 FIFO 读取加 1，START 清零；相同输入三种 H/W 均应计数 16。
    output      logic [31:0] rpt_dat_in_cnt,
    // 本次任务检测到提前 SA LAST 后保持为 1；复位或新 START 清零。
    output      logic rpt_error,
    // 提前 SA LAST 的错误次数，最大为 7；regmap 字段为 rpt_error_state。
    output      logic [2:0] rpt_error_state
);
    (* async_reg = "true" *) logic done_clear_meta_q, done_clear_sync_q;
    logic done_clear_event;
    assign done_clear_event = done_clear_sync_q != done_clear_ack;
    always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            done_clear_meta_q <= 1'b0;
            done_clear_sync_q <= 1'b0;
            done_clear_ack <= 1'b0;
        end else begin
            done_clear_meta_q <= cpu_done_clear_req;
            done_clear_sync_q <= done_clear_meta_q;
            // Mismatch is processed exactly once, including after gated-clock wakeup.
            done_clear_ack <= done_clear_sync_q;
        end
    end

    logic start_prev_q;
    logic task_active_q;
    logic input_last_seen_q;
    logic skew_last_seen_q;
    logic output_last_seen_q;
    logic start_accept;
    logic skew_clear;
    logic skew_dat_in_vld, skew_dat_in_last;
    logic bad_last;
    logic bad_last_prev_q;
    // H/W/mode 仅保留配置接口，不裁剪 16 路数据，也不改变各路延迟。
    // H/W 可通过 SA 的 LAST 反馈影响 DONE 时刻，而非直接设定计时。
    // rpt_dat_in_cnt 统计实际读取，不应直接赋成 H/W 或 H*W。
    logic unused_static_config;
    assign unused_static_config = ^{cpu_cpt_mode, cpu_h_size, cpu_w_size};

    tpu_ctrl_sync u_sync (
        .sys_ckg, .tpu_rst_n, .cpu_tpu_en, .cpu_tpu_start,
        .cpu_tpu_en_sync, .cpu_tpu_start_sync
    );

    assign start_accept = cpu_tpu_en_sync && cpu_tpu_start_sync &&
                          !start_prev_q && !task_active_q;
    assign fifo_in_re = tpu_rst_n && cpu_tpu_en_sync && task_active_q &&
                        !input_last_seen_q && !fifo_empty;
    assign skew_clear = !cpu_tpu_en_sync || !task_active_q || start_accept;
    tpu_ctrl_skew u_skew (
        .sys_ckg, .tpu_rst_n, .clear(skew_clear),
        .input_data(fifo_in_rdata), .input_valid(fifo_in_re),
        .input_last(fifo_in_rd_dat_last),
        .output_data(dat_in_a), .output_valid(skew_dat_in_vld),
        .output_last(skew_dat_in_last)
    );

    // Lane0 sampling metadata is owned by CTRL; the data bus remains skewed.
    assign dat_in_vld = fifo_in_re;
    assign dat_in_last = fifo_in_re && fifo_in_rd_dat_last;

    // No FSM: task and completion flags delimit the stream.
    // Rising START during a task is ignored. A held-high START never retriggers.
    always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            start_prev_q <= 1'b0;
            task_active_q <= 1'b0;
            input_last_seen_q <= 1'b0;
            skew_last_seen_q <= 1'b0;
            output_last_seen_q <= 1'b0;
            rpt_dat_in_cnt <= '0;
            rpt_cpt_done <= 1'b0;
        end else begin
            start_prev_q <= cpu_tpu_start_sync;
            if (done_clear_event) rpt_cpt_done <= 1'b0;
            if (!cpu_tpu_en_sync) begin
                task_active_q <= 1'b0;
                input_last_seen_q <= 1'b0;
                skew_last_seen_q <= 1'b0;
                output_last_seen_q <= 1'b0;
            end else if (start_accept) begin
                rpt_cpt_done <= 1'b0;
                task_active_q <= 1'b1;
                input_last_seen_q <= 1'b0;
                skew_last_seen_q <= 1'b0;
                output_last_seen_q <= 1'b0;
                rpt_dat_in_cnt <= '0;
            end else if (task_active_q) begin
                if (fifo_in_re) begin
                    rpt_dat_in_cnt <= rpt_dat_in_cnt + 32'd1;
                    if (fifo_in_rd_dat_last) input_last_seen_q <= 1'b1;
                end
                if (skew_dat_in_vld && skew_dat_in_last) skew_last_seen_q <= 1'b1;
                // 小尺寸 SA 的有效结果可能早于固定 16 路输入尾巴结束。
                // 先记住 SA LAST，仍然把所有路尾巴送完后再报告 DONE。
                // 不根据 H/W 提前截断 dat_in_a / VALID / LAST。
                // 与 FIFO 最后一包同拍的 SA LAST 视为提前反馈；
                // 最短 PE 路径也只能在之后的采样沿把结果返回 CTRL。
                if (data_out_last && input_last_seen_q)
                    output_last_seen_q <= 1'b1;
                if ((skew_last_seen_q || (skew_dat_in_vld && skew_dat_in_last)) &&
                    (output_last_seen_q || (data_out_last && input_last_seen_q))) begin
                    // A new completion wins a simultaneous software clear.
                    rpt_cpt_done <= 1'b1;
                    task_active_q <= 1'b0;
                end
            end
        end
    end

    // FIFO 最后一包尚未在此前时钟沿读入，SA 就上报 LAST，是提前反馈。
    // 与 FIFO LAST 同拍的反馈也无效，判据与上面的 DONE 接收条件一致。
    // FIFO 空闲等待和输入气泡本身不属于错误，不改变读取/补 0/完成逻辑。
    assign bad_last = cpu_tpu_en_sync && task_active_q &&
                      data_out_last && !input_last_seen_q;

    // 连续拉高的同一次提前 LAST 只计一次；拉低后再出现才是新错误。
    // 计数在 7 饱和，任务结束或关闭 EN 后保留，供 CPU 读取。
    always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            bad_last_prev_q <= 1'b0;
            rpt_error_state <= 3'd0;
        end else if (start_accept) begin
            bad_last_prev_q <= 1'b0;
            rpt_error_state <= 3'd0;
        end else begin
            bad_last_prev_q <= bad_last;
            if (bad_last && !bad_last_prev_q && rpt_error_state != 3'd7)
                rpt_error_state <= rpt_error_state + 3'd1;
        end
    end

    // 有累计错误即保持错误标志；无需再保存一份相同含义的寄存器。
    assign rpt_error = |rpt_error_state;
endmodule
`default_nettype wire
