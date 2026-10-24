`timescale 1ns/1ps
`default_nettype none

// Exposes the PE-array bottom-row wavefront as the SA output stream.
// No column realignment or data buffering is performed in this module.
module output_collector #(
    parameter int unsigned DATA_WIDTH   = 32,
    parameter int unsigned MODE_WIDTH   = 2,
    parameter int unsigned ARRAY_W      = 16,
    parameter int unsigned W_SIZE_WIDTH = 4
) (
    input  logic                                  sys_ckg,
    input  logic                                  tpu_rst_n,

    // Task context from sa_ctrl. W uses size-minus-one encoding.
    input  logic [W_SIZE_WIDTH-1:0]               active_w_size,
    input  logic                                  task_input_last,
    input  logic [MODE_WIDTH-1:0]                 cpt_mode,

    // Direct outputs from all PEs in the physical bottom row.
    input  logic [DATA_WIDTH*ARRAY_W-1:0]         raw_dat_in,
    input  logic [ARRAY_W-1:0]                    raw_dat_in_vld,

    output logic [DATA_WIDTH*ARRAY_W-1:0]         dat_out,
    output logic                                  dat_out_vld,
    output logic                                  dat_out_last
);

    localparam logic [MODE_WIDTH-1:0] MODE_INT4 = 2'b00;
    localparam logic [MODE_WIDTH-1:0] MODE_INT8 = 2'b01;
    localparam logic [MODE_WIDTH-1:0] MODE_FP16 = 2'b10;
    localparam logic [MODE_WIDTH-1:0] MODE_FP32 = 2'b11;

    typedef enum logic [1:0] {
        IDLE,   // Waiting for the final valid A beat
        WAIT,   // Waiting for the selected PE pipeline latency
        OUTPUT  // Sending one bottom-row wavefront snapshot per cycle
    } collector_state_t;

    collector_state_t state_q; // Current collector phase

    logic [2:0]              mode_latency; // INT4/8=1, FP32=4, FP16=7 cycles
    logic [2:0]              wait_count_q; // Remaining edges before OUTPUT
    logic [W_SIZE_WIDTH-1:0] output_step_q; // Output beat index, 0..active_w_size
    logic [DATA_WIDTH*ARRAY_W-1:0] result_hold_q; // Completed column results from earlier output beats

    // PE result latency L from the workbench timing diagrams.
    always_comb begin
        unique case (cpt_mode)
            MODE_INT4,
            MODE_INT8: mode_latency = 3'd1;
            MODE_FP32: mode_latency = 3'd4;
            MODE_FP16: mode_latency = 3'd7;
            default:   mode_latency = 3'd1;
        endcase
    end

    // The task_input_last sampling edge is PE pipeline cycle 1. Integer modes
    // can open the output window immediately; longer modes wait L-1 more edges.
    always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            state_q       <= IDLE;
            wait_count_q  <= '0;
            output_step_q <= '0;
        end else begin
            unique case (state_q)
                IDLE: begin
                    output_step_q <= '0;

                    if (task_input_last) begin
                        if (mode_latency == 1) begin
                            state_q <= OUTPUT;
                        end else begin
                            wait_count_q <= mode_latency - 2'd2;
                            state_q      <= WAIT;
                        end
                    end
                end

                WAIT: begin
                    if (wait_count_q == 0) begin
                        output_step_q <= '0;
                        state_q       <= OUTPUT;
                    end else begin
                        wait_count_q <= wait_count_q - 1'b1;
                    end
                end

                OUTPUT: begin
                    if (output_step_q == active_w_size) begin
                        output_step_q <= '0;
                        state_q       <= IDLE;
                    end else begin
                        output_step_q <= output_step_q + 1'b1;
                    end
                end

                default: begin
                    state_q       <= IDLE;
                    wait_count_q  <= '0;
                    output_step_q <= '0;
                end
            endcase
        end
    end

    // Keep every completed bottom-row result. task_input_last starts a new
    // output transaction, so stale results from the previous task are cleared.
    always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            result_hold_q <= '0;
        end else if (task_input_last) begin
            result_hold_q <= '0;
        end else begin
            for (int unsigned col_idx = 0; col_idx < ARRAY_W; col_idx++) begin
                if ((col_idx <= int'(active_w_size)) &&
                    raw_dat_in_vld[col_idx]) begin
                    result_hold_q[col_idx*DATA_WIDTH +: DATA_WIDTH] <=
                        raw_dat_in[col_idx*DATA_WIDTH +: DATA_WIDTH];
                end
            end
        end
    end

    // Previously completed columns come from result_hold_q. The currently
    // completing column is overlaid directly so no extra output cycle is added.
    always_comb begin
        dat_out      = '0;
        dat_out_vld  = (state_q == OUTPUT);
        dat_out_last = (state_q == OUTPUT) &&
                        (output_step_q == active_w_size);

        if (state_q == OUTPUT) begin
            dat_out = result_hold_q;

            for (int unsigned col_idx = 0; col_idx < ARRAY_W; col_idx++) begin
                if ((col_idx <= int'(active_w_size)) &&
                    raw_dat_in_vld[col_idx]) begin
                    dat_out[col_idx*DATA_WIDTH +: DATA_WIDTH] =
                        raw_dat_in[col_idx*DATA_WIDTH +: DATA_WIDTH];
                end
            end
        end
    end

endmodule

`default_nettype wire
