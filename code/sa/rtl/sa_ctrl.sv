`timescale 1ns/1ps
`default_nettype none

module sa_ctrl #(
    parameter int unsigned DATA_WIDTH   = 32,
    parameter int unsigned MODE_WIDTH   = 2,
    parameter int unsigned ARRAY_H      = 16,
    parameter int unsigned ARRAY_W      = 16,
    parameter int unsigned H_SIZE_WIDTH = 4,
    parameter int unsigned W_SIZE_WIDTH = 4,
    parameter int unsigned B_SEL_WIDTH  = 4,
    parameter int unsigned PE_CKG_NUM   = 64
) (
    // System
    input  logic                                  sys_ckg,
    input  logic [PE_CKG_NUM-1:0]                 pe_ckg,
    input  logic                                  tpu_rst_n,
    input  logic                                  cpu_tpu_en_sync,

    // A stream
    input  logic [DATA_WIDTH*ARRAY_H-1:0]         dat_in_a,
    input  logic                                  dat_in_vld,
    input  logic                                  dat_in_last,

    // B weight interface, sourced by the 100 MHz CPU clock domain
    input  logic                                  cpu_dat_in_b_lock,
    input  logic [DATA_WIDTH*ARRAY_W-1:0]         cpu_dat_in_b,
    input  logic [B_SEL_WIDTH-1:0]                cpu_dat_in_b_sel,

    // Static configuration
    input  logic [H_SIZE_WIDTH-1:0]               cpu_h_size,
    input  logic [W_SIZE_WIDTH-1:0]               cpu_w_size,
    input  logic [MODE_WIDTH-1:0]                 cpu_cpt_mode,
    output logic [31:0]                           rpt_active_size,

    // PE array interface
    output logic                                  pe_tpu_rst_n,
    output logic [PE_CKG_NUM-1:0]                 pe_ckg_out,
    output logic [MODE_WIDTH-1:0]                 pe_cpt_mode,
    output logic [DATA_WIDTH*ARRAY_H-1:0]         pe_dat_in_a,
    output logic                                  pe_dat_in_vld,
    output logic [DATA_WIDTH*ARRAY_W-1:0]         pe_dat_in_b,
    output logic [ARRAY_H-1:0]                    pe_b_lock_row,
    output logic [ARRAY_H*ARRAY_W-1:0]            pe_en,

    // Output-collector context
    output logic [W_SIZE_WIDTH-1:0]               active_w_size,
    output logic                                  task_input_last
);

    // B-interface CDC
    // Bundled-data CDC contract:
    //   - cpu_dat_in_b and cpu_dat_in_b_sel are stable before lock rises.
    //   - the CPU holds both buses stable for at least four sys_ckg cycles.
    //   - only lock passes through the two-flop synchronizer.
    logic                          b_lock_d1;       // Lock delayed one sys_ckg cycle; first CDC stage
    logic                          b_lock_d2;       // Lock delayed two sys_ckg cycles; second CDC stage
    logic                          b_lock_d3;       // Lock delayed three cycles; used with d2 for edge detection
    logic                          b_lock_rise;     // Rising-edge pulse generated from b_lock_d2 and b_lock_d3
    logic                          b_load_accept;   // B load accepted only while TPU enable is high

    logic                          b_load_accept_d1; // Accepted B load delayed one cycle for PE weight write
    logic [DATA_WIDTH*ARRAY_W-1:0] b_data_q;        // B weight bus sampled on b_load_accept
    logic [B_SEL_WIDTH-1:0]        b_row_sel_q;     // PE target row sampled together with b_data_q

    always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            b_lock_d1 <= 1'b0;
            b_lock_d2 <= 1'b0;
            b_lock_d3 <= 1'b0;
        end else begin
            b_lock_d1 <= cpu_dat_in_b_lock;
            b_lock_d2 <= b_lock_d1;
            b_lock_d3 <= b_lock_d2;
        end
    end

    assign b_lock_rise = b_lock_d2 && !b_lock_d3;
    assign b_load_accept = b_lock_rise && cpu_tpu_en_sync;

    always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            b_data_q    <= '0;
            b_row_sel_q <= '0;
        end else if (b_load_accept) begin
            b_data_q    <= cpu_dat_in_b;
            b_row_sel_q <= cpu_dat_in_b_sel;
        end
    end

    // Delay the PE write by one cycle so sampled data and row select are stable.
    always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            b_load_accept_d1 <= 1'b0;
        end else begin
            b_load_accept_d1 <= b_load_accept;
        end
    end

    always_comb begin
        pe_b_lock_row = '0;

        if (cpu_tpu_en_sync &&
            b_load_accept_d1 &&
            (int'(b_row_sel_q) < ARRAY_H)) begin
            pe_b_lock_row[b_row_sel_q] = 1'b1;
        end
    end

    assign pe_dat_in_b = b_data_q;

    // Static configuration
    // H/W use size-minus-one encoding and stay stable for the whole task.
    logic [15:0] active_h_count; // Actual active row count: cpu_h_size + 1
    logic [15:0] active_w_count; // Actual active column count: cpu_w_size + 1

    assign active_h_count =
        {{(16-H_SIZE_WIDTH){1'b0}}, cpu_h_size} + 16'd1;
    assign active_w_count =
        {{(16-W_SIZE_WIDTH){1'b0}}, cpu_w_size} + 16'd1;

    assign rpt_active_size = {active_h_count, active_w_count};
    assign active_w_size   = cpu_w_size;
    assign pe_cpt_mode     = cpu_cpt_mode;

    // PE enable matrix
    // cpu_tpu_en_sync is high from B preload through output drain.
    always_comb begin
        pe_en = '0;

        for (int unsigned row = 0; row < ARRAY_H; row++) begin
            for (int unsigned col = 0; col < ARRAY_W; col++) begin
                pe_en[row*ARRAY_W + col] =
                    cpu_tpu_en_sync &&
                    (row <= cpu_h_size) &&
                    (col <= cpu_w_size);
            end
        end
    end

    // The collector starts its output schedule only on the final valid A beat.
    assign task_input_last = cpu_tpu_en_sync && dat_in_vld && dat_in_last;

    assign pe_dat_in_a   = dat_in_a;
    assign pe_dat_in_vld = dat_in_vld;

    // System pass-through
    assign pe_tpu_rst_n = tpu_rst_n;
    assign pe_ckg_out   = pe_ckg;

endmodule

`default_nettype wire
