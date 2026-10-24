`timescale 1ns/1ps
`default_nettype none

module sa_top #(
    parameter int unsigned DATA_WIDTH   = 32,
    parameter int unsigned MODE_WIDTH   = 2,
    parameter int unsigned ARRAY_H      = 16,
    parameter int unsigned ARRAY_W      = 16,
    parameter int unsigned H_SIZE_WIDTH = 4,
    parameter int unsigned W_SIZE_WIDTH = 4,
    parameter int unsigned B_SEL_WIDTH  = 4,
    parameter int unsigned PE_CKG_NUM   = 64
) (
    // System Interface
    input  logic                                  sys_ckg,
    input  logic [PE_CKG_NUM-1:0]                 pe_ckg,
    input  logic                                  tpu_rst_n,

    // Ctrl Interface
    input  logic                                  cpu_tpu_start_sync,
    input  logic                                  cpu_tpu_en_sync,
    input  logic [DATA_WIDTH*ARRAY_H-1:0]         dat_in_a,
    input  logic                                  dat_in_vld,
    input  logic                                  dat_in_last,

    // RegMap Interface
    input  logic                                  cpu_dat_in_b_lock,
    input  logic [DATA_WIDTH*ARRAY_W-1:0]         cpu_dat_in_b,
    input  logic [B_SEL_WIDTH-1:0]                cpu_dat_in_b_sel,
    input  logic [H_SIZE_WIDTH-1:0]               cpu_h_size,
    input  logic [W_SIZE_WIDTH-1:0]               cpu_w_size,
    input  logic [MODE_WIDTH-1:0]                 cpu_cpt_mode,
    output logic [31:0]                           rpt_active_size,

    // Output Interface
    output logic [DATA_WIDTH*ARRAY_W-1:0]         dat_out,
    output logic                                  dat_out_vld,
    output logic                                  dat_out_last
);

    logic                                  pe_tpu_rst_n;
    logic [PE_CKG_NUM-1:0]                 pe_ckg_bus;
    logic [MODE_WIDTH-1:0]                 pe_cpt_mode;
    logic [DATA_WIDTH*ARRAY_H-1:0]         pe_dat_in_a;
    logic                                  pe_dat_in_vld;
    logic [DATA_WIDTH*ARRAY_W-1:0]         pe_dat_in_b;
    logic [ARRAY_H-1:0]                    pe_b_lock_row;
    logic [ARRAY_H*ARRAY_W-1:0]            pe_en;
    logic [W_SIZE_WIDTH-1:0]               active_w_size;
    logic                                  task_input_last;
    logic [DATA_WIDTH*ARRAY_W-1:0]         raw_dat_out;
    logic [ARRAY_W-1:0]                    raw_dat_out_vld;

    sa_ctrl #(
        .DATA_WIDTH   (DATA_WIDTH),
        .MODE_WIDTH   (MODE_WIDTH),
        .ARRAY_H      (ARRAY_H),
        .ARRAY_W      (ARRAY_W),
        .H_SIZE_WIDTH (H_SIZE_WIDTH),
        .W_SIZE_WIDTH (W_SIZE_WIDTH),
        .B_SEL_WIDTH  (B_SEL_WIDTH),
        .PE_CKG_NUM   (PE_CKG_NUM)
    ) u_sa_ctrl (
        .sys_ckg,
        .pe_ckg,
        .tpu_rst_n,
        .cpu_tpu_en_sync,
        .dat_in_a,
        .dat_in_vld,
        .dat_in_last,
        .cpu_dat_in_b_lock,
        .cpu_dat_in_b,
        .cpu_dat_in_b_sel,
        .cpu_h_size,
        .cpu_w_size,
        .cpu_cpt_mode,
        .rpt_active_size,
        .pe_tpu_rst_n,
        .pe_ckg_out    (pe_ckg_bus),
        .pe_cpt_mode,
        .pe_dat_in_a,
        .pe_dat_in_vld,
        .pe_dat_in_b,
        .pe_b_lock_row,
        .pe_en,
        .active_w_size,
        .task_input_last
    );

    pe_array_16x16 #(
        .DATA_WIDTH (DATA_WIDTH),
        .MODE_WIDTH (MODE_WIDTH),
        .ARRAY_H    (ARRAY_H),
        .ARRAY_W    (ARRAY_W),
        .PE_CKG_NUM (PE_CKG_NUM)
    ) u_pe_array (
        .pe_ckg          (pe_ckg_bus),
        .tpu_rst_n       (pe_tpu_rst_n),
        .pe_en,
        .cpt_mode        (pe_cpt_mode),
        .dat_in_a        (pe_dat_in_a),
        .dat_in_vld      (pe_dat_in_vld),
        .dat_in_b        (pe_dat_in_b),
        .b_lock_row      (pe_b_lock_row),
        .raw_dat_out,
        .raw_dat_out_vld
    );

    output_collector #(
        .DATA_WIDTH   (DATA_WIDTH),
        .MODE_WIDTH   (MODE_WIDTH),
        .ARRAY_W      (ARRAY_W),
        .W_SIZE_WIDTH (W_SIZE_WIDTH)
    ) u_output_collector (
        .sys_ckg,
        .tpu_rst_n,
        .active_w_size,
        .task_input_last,
        .cpt_mode        (pe_cpt_mode),
        .raw_dat_in      (raw_dat_out),
        .raw_dat_in_vld  (raw_dat_out_vld),
        .dat_out,
        .dat_out_vld,
        .dat_out_last
    );

endmodule

`default_nettype wire
