`timescale 1ns/1ps
`default_nettype none
module tpu_crg (
    input  wire logic        dft_glb_gt_se,
    input  wire logic        dft_mode,
    input  wire logic        dft_lgc_rst_n,
    input  wire logic        sys_clk,
    input  wire logic        ahb_clk,
    input  wire logic        sys_rst_n,
    input  wire logic        cpu_tpu_crg_en,
    input  wire logic        cpu_tpu_sw_rst,
    input  wire logic [3:0]  cpu_h_size,
    input  wire logic [3:0]  cpu_w_size,
    input  wire logic        cpu_tpu_crg_bypass,
    output wire logic        sys_ckg,
    output wire logic [63:0] pe_ckg,
    output wire logic        tpu_rst_n
);
    wire logic tpu_crg_sync;

    // Generate the TPU reset: asynchronous assertion and synchronous release.
    // DFT mode selects the direct test reset path.
    rst_sync u_reset (
        .sys_clk         (sys_clk),
        .sys_rst_n       (sys_rst_n),
        .cpu_tpu_sw_rst  (cpu_tpu_sw_rst),
        .dft_mode        (dft_mode),
        .dft_lgc_rst_n   (dft_lgc_rst_n),
        .tpu_rst_n       (tpu_rst_n)
    );

    // Synchronize the clock request and add a two-cycle system clock tail.
    sys_clk_crg u_sys_clk (
        .sys_clk            (sys_clk),
        .tpu_rst_n          (tpu_rst_n),
        .cpu_tpu_crg_en     (cpu_tpu_crg_en),
        .cpu_tpu_crg_bypass (cpu_tpu_crg_bypass),
        .dft_glb_gt_se      (dft_glb_gt_se),
        .tpu_crg_sync       (tpu_crg_sync),
        .sys_ckg            (sys_ckg)
    );

    // Gate the 64 PE groups using the synchronized request and size mask.
    pe_crg u_pe_clk (
        .sys_clk       (sys_clk),
        .tpu_rst_n     (tpu_rst_n),
        .tpu_crg_sync  (tpu_crg_sync),
        .cpu_h_size    (cpu_h_size),
        .cpu_w_size    (cpu_w_size),
        .dft_glb_gt_se (dft_glb_gt_se),
        .pe_ckg        (pe_ckg)
    );

    // ahb_clk is reserved by the interface; this module has no AHB registers.
endmodule
`default_nettype wire
