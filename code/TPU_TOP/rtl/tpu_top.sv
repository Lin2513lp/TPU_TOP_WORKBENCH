`timescale 1ns/1ps
`default_nettype none

// Integrated 16x16 TPU. Existing AXI wrappers own their FIFOs.
// Legal software order and CDC constraints are in docs/TOP_INTEGRATION.md.
module tpu_top (
    input wire logic sys_clk,
    input wire logic ahb_clk,
    input wire logic sys_rst_n,
    input wire logic dft_glb_gt_se,
    input wire logic dft_mode,
    input wire logic dft_lgc_rst_n,
    input wire logic hsel,
    input wire logic [2:0] hsize,
    input wire logic [31:0] haddr,
    input wire logic [2:0] hburst,
    input wire logic [1:0] htrans,
    input wire logic hwrite,
    input wire logic [31:0] hwdata,
    input wire logic hreadyin,
    input wire logic [3:0] hprot,
    output logic hready,
    output logic [31:0] hrdata,
    output logic hresp,
    output logic rd_tready,
    input wire logic rd_tvalid,
    input wire logic [511:0] rd_tdata,
    input wire logic [63:0] rd_tkeep,
    input wire logic [63:0] rd_tstrb,
    input wire logic rd_tlast,
    input wire logic rd_tid,
    input wire logic rd_tdest,
    input wire logic rd_tuser,
    input wire logic wr_tready,
    output logic wr_tvalid,
    output logic [511:0] wr_tdata,
    output logic [63:0] wr_tkeep,
    output logic [63:0] wr_tstrb,
    output logic wr_tlast,
    output logic wr_tid,
    output logic wr_tdest,
    output logic wr_tuser
);

    logic sys_ckg, tpu_rst_n, ahb_rst_n;
    logic [63:0] pe_ckg;
    (* async_reg = "true" *) logic ahb_reset_meta_q, ahb_reset_sync_q;
    // CRG owns common async assertion (global/software/DFT). Release AHB
    // independently of gated SYS, so CPU can recover even with gates closed.
    always_ff @(posedge ahb_clk or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            ahb_reset_meta_q <= 1'b0;
            ahb_reset_sync_q <= 1'b0;
        end else begin
            ahb_reset_meta_q <= 1'b1;
            ahb_reset_sync_q <= ahb_reset_meta_q;
        end
    end
    assign ahb_rst_n = dft_mode ? tpu_rst_n : ahb_reset_sync_q;

    logic [9:0] ahb_addr;
    logic [31:0] ahb_wr_data, ahb_rd_data;
    logic ahb_wr_en, ahb_rd_en;
    logic cpu_tpu_en, cpu_sw_rst, cpu_tpu_start, cpu_tpu_crg_bypass;
    logic cpu_tpu_crg_en, cpu_dat_in_b_lock, cpu_done_clear_req;
    logic done_clear_ack;
    logic [3:0] cpu_h_size, cpu_w_size, cpu_dat_in_b_sel;
    logic [1:0] cpu_cpt_mode;
    logic [511:0] cpu_dat_in_b;
    logic cpu_tpu_en_sync, cpu_tpu_start_sync;
    logic fifo_in_re, fifo_empty, fifo_in_rd_dat_last;
    logic [511:0] fifo_in_rdata, dat_in_a, dat_out;
    logic dat_in_vld, dat_in_last, dat_out_vld, dat_out_last;
    // Reserved SA diagnostic output; software waits for CTRL DONE and TX LAST.
    /* verilator lint_off UNUSEDSIGNAL */
    logic sa_pipeline_empty;
    /* verilator lint_on UNUSEDSIGNAL */
    logic compute_done_sys, rpt_error_sys;
    logic [31:0] rpt_active_size_sys, rpt_cpt_cyc_sys, rpt_dat_in_cnt_sys;
    logic [2:0] rpt_error_state_sys;

    // Existing CTRL/SA modules synchronize START, EN and weight LOCK.
    // Software opens the clocks before commands and holds configuration and
    // weight data stable for the existing CDC capture, then throughout use.
    // Reports return directly; this TOP adds no snapshot or busy/clock guard.

    ahb_slave u_ahb (
        .ahb_clk(ahb_clk),
        .tpu_rst_n(ahb_rst_n),
        .hsel(hsel),
        .hsize(hsize),
        .haddr(haddr),
        .hburst(hburst),
        .htrans(htrans),
        .hwrite(hwrite),
        .hwdata(hwdata),
        .hreadyin(hreadyin),
        .hprot(hprot),
        .hready(hready),
        .hrdata(hrdata),
        .hresp(hresp),
        .ahb_rd_data(ahb_rd_data),
        .ahb_addr(ahb_addr),
        .ahb_wr_data(ahb_wr_data),
        .ahb_wr_en(ahb_wr_en),
        .ahb_rd_en(ahb_rd_en)
    );

    reg_list u_reg (
        .hclk(ahb_clk),
        .hrstn(ahb_rst_n),
        .ahb_addr(ahb_addr),
        .ahb_wr_data(ahb_wr_data),
        .ahb_wr_en(ahb_wr_en),
        .ahb_rd_en(ahb_rd_en),
        .ahb_rd_data(ahb_rd_data),
        .cpu_tpu_en(cpu_tpu_en),
        .cpu_sw_rst(cpu_sw_rst),
        .cpu_tpu_start(cpu_tpu_start),
        .cpu_tpu_crg_bypass(cpu_tpu_crg_bypass),
        .cpu_h_size(cpu_h_size),
        .cpu_w_size(cpu_w_size),
        .cpu_cpt_mode(cpu_cpt_mode),
        .cpu_dat_in_b_sel(cpu_dat_in_b_sel),
        .cpu_dat_in_b_lock(cpu_dat_in_b_lock),
        .cpu_tpu_crg_en(cpu_tpu_crg_en),
        .cpu_done_clear_req(cpu_done_clear_req),
        .done_clear_ack(done_clear_ack),
        .cpu_dat_in_b(cpu_dat_in_b),
        .rpt_active_size(rpt_active_size_sys),
        .rpt_cpt_cyc(rpt_cpt_cyc_sys),
        .rpt_dat_in_cnt(rpt_dat_in_cnt_sys),
        .rpt_error(rpt_error_sys),
        .rpt_error_state(rpt_error_state_sys),
        .rpt_cpt_done(compute_done_sys)
    );

    tpu_crg u_crg (
        .dft_glb_gt_se(dft_glb_gt_se),
        .dft_mode(dft_mode),
        .dft_lgc_rst_n(dft_lgc_rst_n),
        .sys_clk(sys_clk),
        .ahb_clk(ahb_clk),
        .sys_rst_n(sys_rst_n),
        .cpu_tpu_crg_en(cpu_tpu_crg_en),
        .cpu_tpu_sw_rst(cpu_sw_rst),
        .cpu_h_size(cpu_h_size),
        .cpu_w_size(cpu_w_size),
        .cpu_tpu_crg_bypass(cpu_tpu_crg_bypass),
        .sys_ckg(sys_ckg),
        .pe_ckg(pe_ckg),
        .tpu_rst_n(tpu_rst_n)
    );

    AXI_M_TOP u_m (
        .sys_ckg(sys_ckg),
        .tpu_rst_n(tpu_rst_n),
        .cpu_tpu_en_sync(cpu_tpu_en_sync),
        .cpu_tpu_start_sync(cpu_tpu_start_sync),
        .rd_tready(rd_tready),
        .rd_tvalid(rd_tvalid),
        .rd_tdata(rd_tdata),
        .rd_tkeep(rd_tkeep),
        .rd_tstrb(rd_tstrb),
        .rd_tlast(rd_tlast),
        .rd_tid(rd_tid),
        .rd_tdest(rd_tdest),
        .rd_tuser(rd_tuser),
        .fifo_in_re(fifo_in_re),
        .fifo_empty(fifo_empty),
        .fifo_in_rdata(fifo_in_rdata),
        .fifo_in_rd_dat_last(fifo_in_rd_dat_last)
    );

    tpu_ctrl u_ctrl (
        .sys_ckg(sys_ckg),
        .tpu_rst_n(tpu_rst_n),
        .cpu_tpu_en(cpu_tpu_en),
        .cpu_tpu_start(cpu_tpu_start),
        .cpu_done_clear_req(cpu_done_clear_req),
        .done_clear_ack(done_clear_ack),
        .cpu_cpt_mode(cpu_cpt_mode),
        .cpu_h_size(cpu_h_size),
        .cpu_w_size(cpu_w_size),
        .fifo_empty(fifo_empty),
        .fifo_in_rdata(fifo_in_rdata),
        .fifo_in_rd_dat_last(fifo_in_rd_dat_last),
        .data_out_last(dat_out_vld && dat_out_last),
        .fifo_in_re(fifo_in_re),
        .cpu_tpu_en_sync(cpu_tpu_en_sync),
        .cpu_tpu_start_sync(cpu_tpu_start_sync),
        .dat_in_a(dat_in_a),
        .dat_in_vld(dat_in_vld),
        .dat_in_last(dat_in_last),
        .rpt_cpt_done(compute_done_sys),
        .rpt_dat_in_cnt(rpt_dat_in_cnt_sys),
        .rpt_error(rpt_error_sys),
        .rpt_error_state(rpt_error_state_sys)
    );

    sa_top u_sa (
        .sys_ckg(sys_ckg),
        .pe_ckg(pe_ckg),
        .tpu_rst_n(tpu_rst_n),
        .cpu_tpu_start_sync(cpu_tpu_start_sync),
        .cpu_tpu_en_sync(cpu_tpu_en_sync),
        .dat_in_a(dat_in_a),
        .dat_in_vld(dat_in_vld),
        .dat_in_last(dat_in_last),
        .cpu_dat_in_b_lock(cpu_dat_in_b_lock),
        .cpu_dat_in_b(cpu_dat_in_b),
        .cpu_dat_in_b_sel(cpu_dat_in_b_sel),
        .cpu_h_size(cpu_h_size),
        .cpu_w_size(cpu_w_size),
        .cpu_cpt_mode(cpu_cpt_mode),
        .rpt_active_size(rpt_active_size_sys),
        .dat_out(dat_out),
        .dat_out_vld(dat_out_vld),
        .dat_out_last(dat_out_last),
        .sa_pipeline_empty(sa_pipeline_empty)
    );

    AXI_S_TOP u_s (
        .sys_ckg(sys_ckg),
        .tpu_rst_n(tpu_rst_n),
        .cpu_tpu_en_sync(cpu_tpu_en_sync),
        .cpu_tpu_start_sync(cpu_tpu_start_sync),
        .cpu_cpt_mode(cpu_cpt_mode),
        .rpt_cpt_cyc(rpt_cpt_cyc_sys),
        .data_out(dat_out),
        .dat_out_vld(dat_out_vld),
        .dat_out_last(dat_out_last),
        .wr_tready(wr_tready),
        .wr_tvalid(wr_tvalid),
        .wr_tdata(wr_tdata),
        .wr_tkeep(wr_tkeep),
        .wr_tstrb(wr_tstrb),
        .wr_tlast(wr_tlast),
        .wr_tid(wr_tid),
        .wr_tdest(wr_tdest),
        .wr_tuser(wr_tuser)
    );

endmodule
`default_nettype wire
