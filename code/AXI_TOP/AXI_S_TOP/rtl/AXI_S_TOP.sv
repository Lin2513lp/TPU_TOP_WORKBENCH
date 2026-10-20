`default_nettype none

// Result path: TPU packed lanes -> fifo_out -> fifo2axi -> external AXI-Stream.
// Lane 0 is the least-significant lane. The producer is scheduled so that no
// more than FIFO_DEPTH results remain unconsumed; no FULL port is required.
// Default layout: 16 lanes x 32 bits = 512 bits; lane 0 maps to bits [31:0].
module AXI_S_TOP #(
  parameter int unsigned LANE_COUNT = 16,
  parameter int unsigned LANE_WIDTH = 32,
  parameter int unsigned FIFO_DEPTH = 8,
  parameter int unsigned COUNT_WIDTH = 32
) (
  input var logic sys_ckg,
  input var logic tpu_rst_n,
  input var logic cpu_tpu_en_sync,
  input var logic cpu_tpu_start_sync,
  input var logic [1:0] cpu_cpt_mode,
  output logic [COUNT_WIDTH-1:0] rpt_cpt_cyc,
  input var logic [LANE_COUNT-1:0][LANE_WIDTH-1:0] data_out,
  input var logic dat_out_vld,
  input var logic dat_out_last,
  input var logic wr_tready,
  output logic wr_tvalid,
  output logic [LANE_COUNT*LANE_WIDTH-1:0] wr_tdata,
  output logic [(LANE_COUNT*LANE_WIDTH)/8-1:0] wr_tkeep,
  output logic [(LANE_COUNT*LANE_WIDTH)/8-1:0] wr_tstrb,
  output logic wr_tlast,
  output logic wr_tid,
  output logic wr_tdest,
  output logic wr_tuser
);
  logic fifo_out_re;
  logic fifo_out_empty;
  logic [LANE_COUNT*LANE_WIDTH-1:0] fifo_out_rdata;
  logic data_out_last;

  fifo_out #(
    .LANE_COUNT(LANE_COUNT), .LANE_WIDTH(LANE_WIDTH), .DEPTH(FIFO_DEPTH)
  ) u_fifo_out (
    .sys_ckg(sys_ckg), .tpu_rst_n(tpu_rst_n),
    .data_out(data_out), .dat_out_vld(dat_out_vld), .dat_out_last(dat_out_last),
    .fifo_out_re(fifo_out_re), .fifo_out_empty(fifo_out_empty),
    .fifo_out_rdata(fifo_out_rdata), .data_out_last(data_out_last)
  );

  fifo2axi #(
    .DATA_WIDTH(LANE_COUNT*LANE_WIDTH), .KEEP_WIDTH((LANE_COUNT*LANE_WIDTH)/8),
    .COUNT_WIDTH(COUNT_WIDTH)
  ) u_fifo2axi (
    .sys_ckg(sys_ckg), .tpu_rst_n(tpu_rst_n),
    .cpu_tpu_en_sync(cpu_tpu_en_sync), .cpu_tpu_start_sync(cpu_tpu_start_sync),
    .cpu_cpt_mode(cpu_cpt_mode), .rpt_cpt_cyc(rpt_cpt_cyc),
    .wr_tready(wr_tready), .wr_tvalid(wr_tvalid), .wr_tdata(wr_tdata),
    .wr_tkeep(wr_tkeep), .wr_tstrb(wr_tstrb), .wr_tlast(wr_tlast),
    .wr_tid(wr_tid), .wr_tdest(wr_tdest), .wr_tuser(wr_tuser),
    .fifo_out_re(fifo_out_re), .fifo_out_empty(fifo_out_empty),
    .fifo_out_rdata(fifo_out_rdata), .data_out_last(data_out_last)
  );
endmodule

`default_nettype wire
