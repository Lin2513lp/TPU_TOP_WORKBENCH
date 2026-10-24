`timescale 1ns/1ps
`default_nettype none

// Original SA contract: source vectors are contiguous within one packet.
// CTRL supplies OR(skew valid) and LAST on the final physical skew lane.
// Arbitrary source bubbles cannot be reconstructed from the OR-reduced valid.
module output_collector #(
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned MODE_WIDTH = 2,
    parameter int unsigned ARRAY_H = 16,
    parameter int unsigned ARRAY_W = 16,
    parameter int unsigned H_SIZE_WIDTH = 4,
    parameter int unsigned W_SIZE_WIDTH = 4
) (
    input wire logic sys_ckg,
    input wire logic tpu_rst_n,
    input wire logic stream_enable,
    input wire logic [H_SIZE_WIDTH-1:0] active_h_size,
    input wire logic [W_SIZE_WIDTH-1:0] active_w_size,
    input wire logic [MODE_WIDTH-1:0] cpt_mode,
    input wire logic dat_in_vld,
    input wire logic dat_in_last,
    input wire logic [DATA_WIDTH*ARRAY_W-1:0] raw_dat_in,
    input wire logic [ARRAY_W-1:0] raw_dat_in_vld,
    output logic [DATA_WIDTH*ARRAY_W-1:0] dat_out,
    output logic dat_out_vld,
    output logic dat_out_last,
    output logic collector_empty
);
    localparam int unsigned SKEW_TAIL = ARRAY_H - 1;
    localparam int unsigned TOKEN_STAGES = ARRAY_H + ARRAY_W + 5;
    localparam int unsigned LAST_COUNT_WIDTH = $clog2(TOKEN_STAGES + 1);
    logic input_seen_q, source_window_q;
    logic first_input, delayed_first, source_valid;
    logic [TOKEN_STAGES-1:0] result_valid_q;
    logic [LAST_COUNT_WIDTH-1:0] last_count_q;
    logic [2:0] mode_extra_cycles;
    logic [DATA_WIDTH*ARRAY_W-1:0] delayed_raw_data;
    logic [ARRAY_W-1:0] delayed_raw_valid, final_lane_valid;

    assign first_input = dat_in_vld && !input_seen_q;
    assign source_valid = source_window_q || delayed_first;
    assign collector_empty = !input_seen_q && !(|result_valid_q);

    // Reconstruct source timestamps after existing LAST can delimit them.
    // Retain early PE results by the same delay, including valid zero results.
    generate
        if (SKEW_TAIL == 0) begin : g_no_tail
            assign delayed_first = first_input;
            assign delayed_raw_data = raw_dat_in;
            assign delayed_raw_valid = raw_dat_in_vld;
        end else begin : g_tail
            logic [SKEW_TAIL-1:0] first_q;
            logic [DATA_WIDTH*ARRAY_W-1:0] data_q [0:SKEW_TAIL-1];
            logic [ARRAY_W-1:0] valid_q [0:SKEW_TAIL-1];
            assign delayed_first = first_q[SKEW_TAIL-1];
            assign delayed_raw_data = data_q[SKEW_TAIL-1];
            assign delayed_raw_valid = valid_q[SKEW_TAIL-1];
            always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
                if (!tpu_rst_n) begin
                    first_q <= '0;
                    for (int d=0; d<SKEW_TAIL; d++) begin
                        data_q[d] <= '0;
                        valid_q[d] <= '0;
                    end
                end else if (!stream_enable || dat_out_last) begin
                    first_q <= '0;
                    for (int d=0; d<SKEW_TAIL; d++) begin
                        data_q[d] <= '0;
                        valid_q[d] <= '0;
                    end
                end else begin
                    first_q <= (first_q << 1) | SKEW_TAIL'(first_input);
                    data_q[0] <= raw_dat_in;
                    valid_q[0] <= raw_dat_in_vld;
                    for (int d=1; d<SKEW_TAIL; d++) begin
                        data_q[d] <= data_q[d-1];
                        valid_q[d] <= valid_q[d-1];
                    end
                end
            end
        end
    endgenerate

    always_comb begin
        unique case (cpt_mode)
            2'b10: mode_extra_cycles = 3'd6;
            2'b11: mode_extra_cycles = 3'd3;
            default: mode_extra_cycles = 3'd0;
        endcase
    end

    always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            input_seen_q <= 1'b0;
            source_window_q <= 1'b0;
            result_valid_q <= '0;
            last_count_q <= '0;
        end else if (!stream_enable || dat_out_last) begin
            input_seen_q <= 1'b0;
            source_window_q <= 1'b0;
            result_valid_q <= '0;
            last_count_q <= '0;
        end else begin
            if (first_input) input_seen_q <= 1'b1;
            if (dat_in_vld && dat_in_last) source_window_q <= 1'b0;
            else if (delayed_first) source_window_q <= 1'b1;
            result_valid_q <= {result_valid_q[TOKEN_STAGES-2:0], source_valid};
            if (source_valid && dat_in_vld && dat_in_last)
                last_count_q <= LAST_COUNT_WIDTH'(
                    int'(active_h_size) + int'(active_w_size) +
                    int'(mode_extra_cycles) + 1);
            else if (last_count_q > 1)
                last_count_q <= last_count_q - 1'b1;
        end
    end

    // Preserve the PE lane wavefront, shifted by SKEW_TAIL SYS edges.
    always_comb begin
        dat_out = '0;
        final_lane_valid = '0;
        dat_out_last = 1'b0;
        for (int unsigned col=0; col<ARRAY_W; col++) begin
            if (stream_enable && (int'(active_h_size)<ARRAY_H) &&
                (col<=int'(active_w_size))) begin
                final_lane_valid[col] = delayed_raw_valid[col] &&
                    result_valid_q[int'(active_h_size)+col+int'(mode_extra_cycles)];
                if (final_lane_valid[col])
                    dat_out[col*DATA_WIDTH+:DATA_WIDTH] =
                        delayed_raw_data[col*DATA_WIDTH+:DATA_WIDTH];
                if (col==int'(active_w_size))
                    dat_out_last = final_lane_valid[col] && (last_count_q==1);
            end
        end
        dat_out_vld = |final_lane_valid;
    end
endmodule
`default_nettype wire
