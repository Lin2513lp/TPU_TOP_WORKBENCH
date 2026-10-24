`default_nettype none

// Input path: external AXI-Stream -> axi2fifo -> fifo_in -> TPU.
// Both instances use sys_ckg and the same active-low reset.
module AXI_M_TOP #(
  parameter int unsigned DATA_WIDTH = 512,
  parameter int unsigned KEEP_WIDTH = DATA_WIDTH / 8,
  parameter int unsigned FIFO_DEPTH = 8,
  parameter int unsigned PRE_FULL_THRESHOLD = (FIFO_DEPTH > 1) ? FIFO_DEPTH - 1 : 1
) (
  input var logic sys_ckg,
  input var logic tpu_rst_n,
  input var logic cpu_tpu_en_sync,
  input var logic cpu_tpu_start_sync,
  output logic rd_tready,
  input var logic rd_tvalid,
  input var logic [DATA_WIDTH-1:0] rd_tdata,
  input var logic [KEEP_WIDTH-1:0] rd_tkeep,
  input var logic [KEEP_WIDTH-1:0] rd_tstrb,
  input var logic rd_tlast,
  input var logic rd_tid,
  input var logic rd_tdest,
  input var logic rd_tuser,
  input var logic fifo_in_re,
  output logic fifo_empty,
  output logic [DATA_WIDTH-1:0] fifo_in_rdata,
  output logic fifo_in_rd_dat_last
);
  logic fifo_in_we;
  logic fifo_in_pre_full;
  logic [DATA_WIDTH-1:0] fifo_in_wdata;
  logic rd_dat_last;

  axi2fifo #(.DATA_WIDTH(DATA_WIDTH), .KEEP_WIDTH(KEEP_WIDTH)) u_axi2fifo (
    .sys_ckg(sys_ckg), .tpu_rst_n(tpu_rst_n),
    .cpu_tpu_en_sync(cpu_tpu_en_sync), .cpu_tpu_start_sync(cpu_tpu_start_sync),
    .rd_tready(rd_tready), .rd_tvalid(rd_tvalid), .rd_tdata(rd_tdata),
    .rd_tkeep(rd_tkeep), .rd_tstrb(rd_tstrb), .rd_tlast(rd_tlast),
    .rd_tid(rd_tid), .rd_tdest(rd_tdest), .rd_tuser(rd_tuser),
    .fifo_in_we(fifo_in_we), .fifo_in_pre_full(fifo_in_pre_full),
    .fifo_in_wdata(fifo_in_wdata), .rd_dat_last(rd_dat_last)
  );

  fifo_in #(
    .DATA_WIDTH(DATA_WIDTH), .DEPTH(FIFO_DEPTH),
    .PRE_FULL_THRESHOLD(PRE_FULL_THRESHOLD)
  ) u_fifo_in (
    .sys_ckg(sys_ckg), .tpu_rst_n(tpu_rst_n),
    .fifo_in_we(fifo_in_we), .fifo_in_wdata(fifo_in_wdata),
    .rd_dat_last(rd_dat_last), .fifo_in_pre_full(fifo_in_pre_full),
    .fifo_in_re(fifo_in_re), .fifo_empty(fifo_empty),
    .fifo_in_rdata(fifo_in_rdata), .fifo_in_rd_dat_last(fifo_in_rd_dat_last)
  );
endmodule

`default_nettype wire
