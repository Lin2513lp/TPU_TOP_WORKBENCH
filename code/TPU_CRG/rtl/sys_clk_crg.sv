`timescale 1ns/1ps
`default_nettype none
module sys_clk_crg (
    input  wire logic sys_clk,
    input  wire logic tpu_rst_n,
    input  wire logic cpu_tpu_crg_en,
    input  wire logic cpu_tpu_crg_bypass,
    input  wire logic dft_glb_gt_se,
    output wire logic tpu_crg_sync,
    output wire logic sys_ckg
);
    // 1. Merge the functional and bypass clock requests.
    wire logic tpu_crg;
    assign tpu_crg = cpu_tpu_crg_en | cpu_tpu_crg_bypass;

    // 2. Synchronize the request to the always-on sys_clk in two stages.
    logic tpu_crg_d1;
    logic tpu_crg_d2;
    always_ff @(posedge sys_clk or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            tpu_crg_d1 <= 1'b0;
            tpu_crg_d2 <= 1'b0;
        end else begin
            tpu_crg_d1 <= tpu_crg;
            tpu_crg_d2 <= tpu_crg_d1;
        end
    end
    assign tpu_crg_sync = tpu_crg_d2;

    // 3. Keep the gate enabled for two cycles after the request falls.
    logic tail_d1;
    logic tail_d2;
    wire logic tpu_crg_sync_tail;
    always_ff @(posedge sys_clk or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            tail_d1 <= 1'b0;
            tail_d2 <= 1'b0;
        end else begin
            tail_d1 <= tpu_crg_sync;
            tail_d2 <= tail_d1;
        end
    end
    assign tpu_crg_sync_tail = tpu_crg_sync | tail_d1 | tail_d2;

    // 4. Use the integrated clock gate to generate sys_ckg.
    crg_icg u_icg (
        .clk_in(sys_clk),
        .enable(tpu_crg_sync_tail),
        .test_enable(dft_glb_gt_se),
        .clk_out(sys_ckg)
    );
endmodule
`default_nettype wire
