`default_nettype none

// AXI-Stream input (rd_*) to FIFO_IN bridge.
// Three-process FSM: state register, next-state decode, output decode.
module axi2fifo #(
  parameter int unsigned DATA_WIDTH = 512,
  parameter int unsigned KEEP_WIDTH = DATA_WIDTH / 8
) (
  input  logic                  sys_ckg,
  input  logic                  tpu_rst_n,

  input  logic                  cpu_tpu_en_sync,
  input  logic                  cpu_tpu_start_sync,

  output logic                  rd_tready,
  input  logic                  rd_tvalid,
  input  logic [DATA_WIDTH-1:0] rd_tdata,
  input  logic [KEEP_WIDTH-1:0] rd_tkeep,
  input  logic [KEEP_WIDTH-1:0] rd_tstrb,
  input  logic                  rd_tlast,
  input  logic                  rd_tid,
  input  logic                  rd_tdest,
  input  logic                  rd_tuser,

  output logic                  fifo_in_we,
  input  logic                  fifo_in_pre_full,
  output logic [DATA_WIDTH-1:0] fifo_in_wdata,
  output logic                  rd_dat_last
);

  typedef enum logic {
    RX_IDLE,
    RX_ACTIVE
  } rx_state_t;

  rx_state_t rx_state_cur;
  rx_state_t rx_state_next;

  logic rx_fire;
  logic _unused_axi_sideband;

  assign rx_fire = rd_tvalid && rd_tready;

  // The current design transports full 512-bit beats. These AXI sidebands are
  // retained at the boundary for protocol completeness but are not stored.
  assign _unused_axi_sideband = ^{rd_tkeep, rd_tstrb, rd_tid, rd_tdest,
                                  rd_tuser};

  // Process 1: state register.
  always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
    if (!tpu_rst_n) begin
      rx_state_cur <= RX_IDLE;
    end else begin
      rx_state_cur <= rx_state_next;
    end
  end

  // Process 2: next-state logic.
  always_comb begin
    unique case (rx_state_cur)
      RX_IDLE: begin
        if (cpu_tpu_en_sync && cpu_tpu_start_sync) begin
          rx_state_next = RX_ACTIVE;
        end else begin
          rx_state_next = RX_IDLE;
        end
      end

      RX_ACTIVE: begin
        if (!cpu_tpu_en_sync) begin
          rx_state_next = RX_IDLE;
        end else if (rx_fire && rd_tlast) begin
          rx_state_next = RX_IDLE;
        end else begin
          rx_state_next = RX_ACTIVE;
        end
      end

      default: begin
        rx_state_next = RX_IDLE;
      end
    endcase
  end

  // Process 3: Moore/Mealy output decode. FIFO_IN is written only for an AXI
  // handshake, so PRE_FULL backpressure cannot create a partial transfer.
  always_comb begin
    rd_tready    = 1'b0;
    fifo_in_we   = 1'b0;
    fifo_in_wdata = rd_tdata;
    rd_dat_last  = 1'b0;

    unique case (rx_state_cur)
      RX_ACTIVE: begin
        rd_tready   = cpu_tpu_en_sync && !fifo_in_pre_full;
        fifo_in_we  = rd_tvalid && rd_tready;
        rd_dat_last = fifo_in_we && rd_tlast;
      end

      default: begin
        // Outputs retain their safe idle values.
      end
    endcase
  end

endmodule

`default_nettype wire
