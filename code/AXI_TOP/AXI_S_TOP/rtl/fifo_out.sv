`default_nettype none

// Single-clock FWFT FIFO for SA_TOP results. No numeric conversion is applied:
// lane 0 occupies the least-significant LANE_WIDTH bits of the output beat.
// Default layout: 16 lanes x 32 bits = 512 bits; lane 0 maps to bits [31:0].
// DATA and LAST share one stored entry and remain aligned until a valid read.
module fifo_out #(
  parameter int unsigned LANE_COUNT = 16,
  parameter int unsigned LANE_WIDTH = 32,
  parameter int unsigned DEPTH = 8
) (
  input  var logic sys_ckg,
  input  var logic tpu_rst_n,
  input  var logic [LANE_COUNT-1:0][LANE_WIDTH-1:0] data_out,
  input  var logic dat_out_vld,
  input  var logic dat_out_last,
  input  var logic fifo_out_re,
  output logic fifo_out_empty,
  output logic [LANE_COUNT*LANE_WIDTH-1:0] fifo_out_rdata,
  output logic data_out_last
);

  localparam int unsigned DATA_WIDTH = LANE_COUNT * LANE_WIDTH;
  localparam int unsigned PTR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  localparam int unsigned COUNT_WIDTH = (DEPTH > 1) ? $clog2(DEPTH + 1) : 1;

  logic [DATA_WIDTH:0] memory [0:DEPTH-1];
  logic [PTR_WIDTH-1:0] write_ptr_q;
  logic [PTR_WIDTH-1:0] read_ptr_q;
  logic [COUNT_WIDTH-1:0] count_q;
  logic fifo_full;
  logic push_accept;
  logic pop_accept;

  assign fifo_out_empty = (count_q == '0);
  assign fifo_full = (count_q == COUNT_WIDTH'(DEPTH));
  // Empty read/write enqueues the new result, without same-cycle bypass.
  // A simultaneous read of a full FIFO frees its slot for a replacement write.
  assign pop_accept = tpu_rst_n && fifo_out_re && !fifo_out_empty;
  // FULL is deliberately internal: the system-level producer guarantees that
  // it never presents more than DEPTH unconsumed results. The guard still
  // prevents an accidental extra write from corrupting unread entries.
  assign push_accept = tpu_rst_n && dat_out_vld && (!fifo_full || pop_accept);

  always_comb begin
    if (!fifo_out_empty) begin
      fifo_out_rdata = memory[read_ptr_q][DATA_WIDTH-1:0];
      data_out_last = memory[read_ptr_q][DATA_WIDTH];
    end else begin
      fifo_out_rdata = '0;
      data_out_last = 1'b0;
    end
  end

  // Packed multidimensional DATA flattens with lane 0 in the low bits.
  // Memory is not reset: the reset occupancy hides old/uninitialized contents.
  always_ff @(posedge sys_ckg) begin
    if (push_accept) begin
      memory[write_ptr_q] <= {dat_out_last, data_out};
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
    if (LANE_COUNT < 1 || LANE_WIDTH < 1 || DEPTH < 1) begin
      $fatal(1, "fifo_out: LANE_COUNT, LANE_WIDTH and DEPTH must be positive");
    end
  end
  // synthesis translate_on
endmodule

`default_nettype wire
