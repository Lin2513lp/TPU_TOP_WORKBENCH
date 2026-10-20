`timescale 1ns/1ps
`default_nettype none

// One-entry bundled-data mailbox. Payload remains stable until the SYS side
// acknowledges the command AFTER its receiving CTRL/SA pipeline has settled.
// START and LOCK are single SYS pulses, so START cannot repeatedly reset TX count.
module tpu_command_bridge (
    input wire logic ahb_clk,
    input wire logic ahb_rst_n,
    input wire logic sys_ckg,
    input wire logic tpu_rst_n,
    input wire logic start_ahb,
    input wire logic lock_ahb,
    input wire logic enable_ahb,
    input wire logic task_busy_ahb,
    input wire logic clear_busy_ahb,
    input wire logic [511:0] weight_ahb,
    input wire logic [3:0] weight_row_ahb,
    output logic pending_ahb,
    output logic task_start_ahb,
    output logic start_sys,
    output logic lock_sys,
    output logic [511:0] weight_sys,
    output logic [3:0] weight_row_sys
);
    logic req_q, ack_q, is_start_q;
    logic [511:0] weight_hold_q;
    logic [3:0] row_hold_q;
    (* async_reg = "true" *) logic ack_meta_q, ack_sync_q;
    (* async_reg = "true" *) logic req_meta_q, req_sync_q;
    logic [4:0] delay_q;
    logic executing_q;

    assign pending_ahb = req_q != ack_sync_q;
    // The registered reg_list pulses occupy the cycle BEFORE this acceptance.
    assign task_start_ahb = start_ahb && enable_ahb && !task_busy_ahb &&
                            !pending_ahb && !clear_busy_ahb;

    always_ff @(posedge ahb_clk or negedge ahb_rst_n) begin
        if (!ahb_rst_n) begin
            req_q <= 1'b0;
            is_start_q <= 1'b0;
            weight_hold_q <= '0;
            row_hold_q <= '0;
            ack_meta_q <= 1'b0;
            ack_sync_q <= 1'b0;
        end else begin
            ack_meta_q <= ack_q;
            ack_sync_q <= ack_meta_q;
            if (!pending_ahb && !task_busy_ahb && !clear_busy_ahb &&
                enable_ahb && (start_ahb || lock_ahb)) begin
                req_q <= ~req_q;
                is_start_q <= start_ahb;
                weight_hold_q <= weight_ahb;
                row_hold_q <= weight_row_ahb;
            end
        end
    end

    always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            req_meta_q <= 1'b0;
            req_sync_q <= 1'b0;
            ack_q <= 1'b0;
            delay_q <= '0;
            executing_q <= 1'b0;
            start_sys <= 1'b0;
            lock_sys <= 1'b0;
            weight_sys <= '0;
            weight_row_sys <= '0;
        end else begin
            req_meta_q <= req_q;
            req_sync_q <= req_meta_q;
            start_sys <= 1'b0;
            lock_sys <= 1'b0;
            if (!executing_q && req_sync_q != ack_q) begin
                // Bundled payload has been held across both synchronizer stages.
                weight_sys <= weight_hold_q;
                weight_row_sys <= row_hold_q;
                executing_q <= 1'b1;
                delay_q <= 5'd20;
            end else if (executing_q) begin
                delay_q <= delay_q - 5'd1;
                // Eight settling clocks also let CTRL synchronize EN after wake.
                if (delay_q == 5'd12) begin
                    start_sys <= is_start_q;
                    lock_sys <= !is_start_q;
                end
                if (delay_q == 5'd1) begin
                    ack_q <= req_sync_q;
                    executing_q <= 1'b0;
                end
            end
        end
    end
endmodule
`default_nettype wire
