`timescale 1ns/1ps
`default_nettype none

module ahb_slave_regmap (
    /* AHB-Lite bus interface */
    /* always-on: CPU register access must wake/configure the gated TPU. */
    input  wire logic        ahb_clk,
    input  wire logic        tpu_rst_n,
    input  wire logic        hsel,
    input  wire logic [2:0]  hsize,
    input  wire logic [31:0] haddr,
    input  wire logic [2:0]  hburst,
    input  wire logic [1:0]  htrans,
    input  wire logic        hwrite,
    input  wire logic [31:0] hwdata,
    input  wire logic        hreadyin,
    input  wire logic [3:0]  hprot,

    output logic        hready,
    output logic [31:0] hrdata,
    output logic        hresp,

    /* Register-map control outputs, AHB clock domain. */
    output logic        cpu_tpu_en,
    output logic        cpu_sw_rst,
    output logic        cpu_tpu_start,
    output logic        cpu_tpu_crg_bypass,
    output logic [3:0]  cpu_h_size,
    output logic [3:0]  cpu_w_size,
    output logic [1:0]  cpu_cpt_mode,
    output logic [3:0]  cpu_dat_in_b_sel,
    output logic        cpu_dat_in_b_lock,
    output logic        cpu_tpu_crg_en,
    output logic        cpu_done_clear_req,
    input  wire logic   done_clear_ack,
    output logic [511:0] cpu_dat_in_b,

    /* Status inputs must be coherent in the AHB clock domain. */
    input  wire logic [31:0] rpt_active_size,
    input  wire logic [31:0] rpt_cpt_cyc,
    input  wire logic [31:0] rpt_dat_in_cnt,
    /* Independent error flag and 3-bit count from CTRL. */
    input  wire logic        rpt_error,
    input  wire logic [2:0]  rpt_error_state,
    /* Sticky SYS-domain DONE; synchronized here before AHB readback. */
    input  wire logic        rpt_cpt_done
);

    (* async_reg = "true" *) logic done_meta_q, done_sync_q;
    always_ff @(posedge ahb_clk or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            done_meta_q <= 1'b0;
            done_sync_q <= 1'b0;
        end else begin
            done_meta_q <= rpt_cpt_done;
            done_sync_q <= done_meta_q;
        end
    end

    logic [9:0]  regmap_addr;
    logic [31:0] regmap_wr_data;
    logic [31:0] regmap_rd_data;
    logic        regmap_wr_en;
    logic        regmap_rd_en;

    ahb_slave u_ahb_slave (
        .ahb_clk     (ahb_clk),
        .tpu_rst_n   (tpu_rst_n),
        .hsel        (hsel),
        .hsize       (hsize),
        .haddr       (haddr),
        .hburst      (hburst),
        .htrans      (htrans),
        .hwrite      (hwrite),
        .hwdata      (hwdata),
        .hreadyin    (hreadyin),
        .hprot       (hprot),
        .hready      (hready),
        .hrdata      (hrdata),
        .hresp       (hresp),
        .ahb_rd_data (regmap_rd_data),
        .ahb_addr    (regmap_addr),
        .ahb_wr_data (regmap_wr_data),
        .ahb_wr_en   (regmap_wr_en),
        .ahb_rd_en   (regmap_rd_en)
    );

    reg_list u_reg_list (
        .hclk               (ahb_clk),
        .hrstn              (tpu_rst_n),
        .ahb_addr           (regmap_addr),
        .ahb_wr_data        (regmap_wr_data),
        .ahb_wr_en          (regmap_wr_en),
        .ahb_rd_en          (regmap_rd_en),
        .ahb_rd_data        (regmap_rd_data),
        .cpu_tpu_en         (cpu_tpu_en),
        .cpu_sw_rst         (cpu_sw_rst),
        .cpu_tpu_start      (cpu_tpu_start),
        .cpu_tpu_crg_bypass (cpu_tpu_crg_bypass),
        .cpu_h_size         (cpu_h_size),
        .cpu_w_size         (cpu_w_size),
        .cpu_cpt_mode       (cpu_cpt_mode),
        .cpu_dat_in_b_sel   (cpu_dat_in_b_sel),
        .cpu_dat_in_b_lock  (cpu_dat_in_b_lock),
        .cpu_tpu_crg_en     (cpu_tpu_crg_en),
        .cpu_done_clear_req (cpu_done_clear_req),
        .done_clear_ack     (done_clear_ack),
        .cpu_dat_in_b       (cpu_dat_in_b),
        .rpt_active_size    (rpt_active_size),
        .rpt_cpt_cyc        (rpt_cpt_cyc),
        .rpt_dat_in_cnt     (rpt_dat_in_cnt),
        .rpt_error          (rpt_error),
        .rpt_error_state    (rpt_error_state),
        .rpt_cpt_done       (done_sync_q)
    );

endmodule

`default_nettype wire
