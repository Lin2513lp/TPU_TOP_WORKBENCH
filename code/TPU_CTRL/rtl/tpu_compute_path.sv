`timescale 1ns/1ps
`default_nettype none

// Local integration of the real upstream FIFO and SA, with wiring only.
// pe_ckg and reset come from CRG. REG_MAP/AHB and FIFO_OUT/AXI are external.
module tpu_compute_path #(
    parameter int unsigned FIFO_DEPTH = 8
) (
    input wire logic sys_ckg,
    input wire logic [63:0] pe_ckg,
    input wire logic tpu_rst_n,
    input wire logic cpu_tpu_en, cpu_tpu_start,
    input wire logic cpu_done_clear_req,
    output logic done_clear_ack,
    input wire logic [1:0] cpu_cpt_mode,
    input wire logic [3:0] cpu_h_size, cpu_w_size,
    input wire logic cpu_dat_in_b_lock,
    input wire logic [511:0] cpu_dat_in_b,
    input wire logic [3:0] cpu_dat_in_b_sel,
    input wire logic fifo_in_we,
    input wire logic [511:0] fifo_in_wdata,
    input wire logic rd_dat_last,
    output logic fifo_in_pre_full,
    output logic [511:0] dat_out,
    output logic dat_out_vld, dat_out_last,
    output logic [31:0] rpt_active_size,
    output logic rpt_cpt_done,
    output logic [31:0] rpt_dat_in_cnt,
    // Sticky flag for premature SA LAST errors in the current task.
    output logic rpt_error,
    // 3-bit error count, read as regmap field rpt_error_state.
    output logic [2:0] rpt_error_state
);
    logic fifo_empty, fifo_in_re, fifo_in_rd_dat_last;
    logic [511:0] fifo_in_rdata, dat_in_a;
    logic cpu_tpu_en_sync, cpu_tpu_start_sync, dat_in_vld, dat_in_last;
    fifo_in #(.DEPTH(FIFO_DEPTH)) u_fifo (
        .sys_ckg, .tpu_rst_n, .fifo_in_we, .fifo_in_wdata, .rd_dat_last,
        .fifo_in_pre_full, .fifo_in_re, .fifo_empty, .fifo_in_rdata,
        .fifo_in_rd_dat_last
    );
    tpu_ctrl u_ctrl (
        .sys_ckg, .tpu_rst_n, .cpu_tpu_en, .cpu_tpu_start,
        .cpu_done_clear_req, .done_clear_ack,
        .cpu_cpt_mode, .cpu_h_size, .cpu_w_size,
        .fifo_empty, .fifo_in_rdata, .fifo_in_rd_dat_last,
        .data_out_last(dat_out_vld && dat_out_last), .fifo_in_re,
        .cpu_tpu_en_sync, .cpu_tpu_start_sync, .dat_in_a,
        .dat_in_vld, .dat_in_last, .rpt_cpt_done, .rpt_dat_in_cnt,
        .rpt_error, .rpt_error_state
    );
    sa_top u_sa (
        .sys_ckg, .pe_ckg, .tpu_rst_n,
        .vector_in_vld(fifo_in_re),
        .vector_in_last(fifo_in_re && fifo_in_rd_dat_last),
        .cpu_tpu_start_sync, .cpu_tpu_en_sync, .dat_in_a,
        .dat_in_vld, .dat_in_last,
        .cpu_dat_in_b_lock, .cpu_dat_in_b, .cpu_dat_in_b_sel,
        .cpu_h_size, .cpu_w_size, .cpu_cpt_mode, .rpt_active_size,
        .dat_out, .dat_out_vld, .dat_out_last, .sa_pipeline_empty()
    );
endmodule
`default_nettype wire


