`timescale 1ns/1ps
`default_nettype none

// Optional bound SVA checker for tools supporting bind and concurrent assertions.
// Not in synthesizable filelist.f; see reports/regmap_20261008/validation.md.
module reg_list_assertions (
    input wire logic hclk, hrstn,
    input wire logic [9:0] ahb_addr,
    input wire logic [31:0] ahb_wr_data, ahb_rd_data,
    input wire logic ahb_wr_en, ahb_rd_en,
    input wire logic cpu_sw_rst, cpu_tpu_start, cpu_dat_in_b_lock,
    input wire logic cpu_tpu_en, cpu_tpu_crg_en
);
    default clocking cb @(posedge hclk); endclocking
    default disable iff (!hrstn);

    p_sw_rst_w1p: assert property (
        1'b1 |=> cpu_sw_rst == $past(ahb_wr_en && (ahb_addr == 10'h001) && ahb_wr_data[0]));
    p_start_w1p: assert property (
        1'b1 |=> cpu_tpu_start == $past(ahb_wr_en && (ahb_addr == 10'h002) && ahb_wr_data[0]));
    p_b_lock_w1p: assert property (
        1'b1 |=> cpu_dat_in_b_lock == $past(ahb_wr_en && (ahb_addr == 10'h008) && ahb_wr_data[0]));
    p_crg_en_write: assert property (
        (ahb_wr_en && (ahb_addr == 10'h105)) |=> cpu_tpu_crg_en == $past(ahb_wr_data[0]));
    p_crg_en_hold: assert property (
        !(ahb_wr_en && (ahb_addr == 10'h105)) |=> $stable(cpu_tpu_crg_en));
    p_tpu_en_write: assert property (
        (ahb_wr_en && (ahb_addr == 10'h000)) |=> cpu_tpu_en == $past(ahb_wr_data[0]));
    p_tpu_en_hold: assert property (
        !(ahb_wr_en && (ahb_addr == 10'h000)) |=> $stable(cpu_tpu_en));
    p_read_disabled: assert property (!ahb_rd_en |-> (ahb_rd_data == 32'd0));
    p_w1p_read_zero: assert property (
        (ahb_rd_en && ((ahb_addr == 10'h001) || (ahb_addr == 10'h002) || (ahb_addr == 10'h008)))
        |-> (ahb_rd_data == 32'd0));
endmodule

bind reg_list reg_list_assertions u_reg_list_assertions (
    .hclk(hclk), .hrstn(hrstn), .ahb_addr(ahb_addr),
    .ahb_wr_data(ahb_wr_data), .ahb_rd_data(ahb_rd_data),
    .ahb_wr_en(ahb_wr_en), .ahb_rd_en(ahb_rd_en),
    .cpu_sw_rst(cpu_sw_rst), .cpu_tpu_start(cpu_tpu_start),
    .cpu_dat_in_b_lock(cpu_dat_in_b_lock),
    .cpu_tpu_en(cpu_tpu_en), .cpu_tpu_crg_en(cpu_tpu_crg_en)
);

`default_nettype wire
