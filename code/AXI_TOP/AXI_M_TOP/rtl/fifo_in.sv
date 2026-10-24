`default_nettype none

// Single-clock, first-word-fall-through FIFO for the AXI input path.
// DATA and LAST are stored together; RE consumes the currently visible head.
module fifo_in #(
  parameter int unsigned DATA_WIDTH = 512,
  parameter int unsigned DEPTH = 8,
  parameter int unsigned PRE_FULL_THRESHOLD = (DEPTH > 1) ? DEPTH - 1 : 1
) (
  input  var logic                  sys_ckg,
  input  var logic                  tpu_rst_n,
  input  var logic                  fifo_in_we,
  input  var logic [DATA_WIDTH-1:0] fifo_in_wdata,
  input  var logic                  rd_dat_last,
  output     logic                  fifo_in_pre_full,
  input  var logic                  fifo_in_re,
  output     logic                  fifo_empty,
  output     logic [DATA_WIDTH-1:0] fifo_in_rdata,
  output     logic                  fifo_in_rd_dat_last
);

  localparam int unsigned PTR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  localparam int unsigned COUNT_WIDTH = (DEPTH > 1) ? $clog2(DEPTH + 1) : 1;

  logic [DATA_WIDTH:0] memory [0:DEPTH-1];
  logic [PTR_WIDTH-1:0] write_ptr_q;
  logic [PTR_WIDTH-1:0] read_ptr_q;
  logic [COUNT_WIDTH-1:0] count_q;
  logic fifo_full;
  logic push_accept;
  logic pop_accept;

  assign fifo_empty = (count_q == '0);
  assign fifo_full = (count_q == COUNT_WIDTH'(DEPTH));
  assign fifo_in_pre_full = (count_q >= COUNT_WIDTH'(PRE_FULL_THRESHOLD));

  // A read of an empty FIFO is ignored (no same-cycle empty bypass).
  // At full occupancy, an accepted read can free the slot for a new write.
  assign pop_accept = tpu_rst_n && fifo_in_re && !fifo_empty;
  assign push_accept = tpu_rst_n && fifo_in_we && (!fifo_full || pop_accept);

  always_comb begin
    if (!fifo_empty) begin
      fifo_in_rdata = memory[read_ptr_q][DATA_WIDTH-1:0];
      fifo_in_rd_dat_last = memory[read_ptr_q][DATA_WIDTH];
    end else begin
      fifo_in_rdata = '0;
      fifo_in_rd_dat_last = 1'b0;
    end
  end

  // Do not reset the memory array: empty/count hides old or uninitialized data.
  always_ff @(posedge sys_ckg) begin
    if (push_accept) begin
      memory[write_ptr_q] <= {rd_dat_last, fifo_in_wdata};
    end
  end

  always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
    if (!tpu_rst_n) begin
      write_ptr_q <= '0;
      read_ptr_q <= '0;
      count_q <= '0;
    end else begin
      if (push_accept) begin
        if (write_ptr_q == PTR_WIDTH'(DEPTH - 1)) begin
          write_ptr_q <= '0;
        end else begin
          write_ptr_q <= write_ptr_q + PTR_WIDTH'(1);
        end
      end

      if (pop_accept) begin
        if (read_ptr_q == PTR_WIDTH'(DEPTH - 1)) begin
          read_ptr_q <= '0;
        end else begin
          read_ptr_q <= read_ptr_q + PTR_WIDTH'(1);
        end
      end

      unique case ({push_accept, pop_accept})
        2'b10: count_q <= count_q + COUNT_WIDTH'(1);
        2'b01: count_q <= count_q - COUNT_WIDTH'(1);
        default: count_q <= count_q;
      endcase
    end
  end

  // synthesis translate_off
  initial begin
    if (DATA_WIDTH < 1 || DEPTH < 1) begin
      $fatal(1, "fifo_in: DATA_WIDTH and DEPTH must be positive");
    end
    if (PRE_FULL_THRESHOLD < 1 || PRE_FULL_THRESHOLD > DEPTH) begin
      $fatal(1, "fifo_in: PRE_FULL_THRESHOLD must be in [1, DEPTH]");
    end
  end
  // synthesis translate_on
endmodule

`default_nettype wire
