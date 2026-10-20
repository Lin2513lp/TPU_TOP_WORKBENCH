`timescale 1ns/1ps
`default_nettype none

// Two-stage level CDC. CPU pulses must cover at least two SYS sampling edges.
module tpu_ctrl_sync (
    input  wire logic sys_ckg,
    input  wire logic tpu_rst_n,
    input  wire logic cpu_tpu_en,
    input  wire logic cpu_tpu_start,
    output      logic cpu_tpu_en_sync,
    output      logic cpu_tpu_start_sync
);
    (* ASYNC_REG = "TRUE" *) logic en_meta_q, start_meta_q;
    (* ASYNC_REG = "TRUE" *) logic en_sync_q, start_sync_q;

    always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            en_meta_q    <= 1'b0;
            en_sync_q    <= 1'b0;
            start_meta_q <= 1'b0;
            start_sync_q <= 1'b0;
        end else begin
            en_meta_q    <= cpu_tpu_en;
            en_sync_q    <= en_meta_q;
            start_meta_q <= cpu_tpu_start;
            start_sync_q <= start_meta_q;
        end
    end
    assign cpu_tpu_en_sync    = en_sync_q;
    assign cpu_tpu_start_sync = start_sync_q;
endmodule
`default_nettype wire
