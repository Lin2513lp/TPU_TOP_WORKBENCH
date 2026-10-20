`default_nettype none

// FIFO_OUT to AXI-Stream output (wr_*) bridge.
//
// FIFO_OUT contract: show-ahead/FWFT. While fifo_out_empty is low, rdata and
// data_out_last describe the current head and stay aligned until fifo_out_re.
// The HOLD state snapshots the complete AXI payload whenever backpressure is
// encountered, so wr_* remains stable even if upstream control pulses change.
module fifo2axi #(
  parameter int unsigned DATA_WIDTH  = 512,
  parameter int unsigned KEEP_WIDTH  = DATA_WIDTH / 8,
  parameter int unsigned COUNT_WIDTH = 32
) (
  input  logic                   sys_ckg,
  input  logic                   tpu_rst_n,

  input  logic                   cpu_tpu_en_sync,
  input  logic                   cpu_tpu_start_sync,
  input  logic [1:0]             cpu_cpt_mode,
  output logic [COUNT_WIDTH-1:0] rpt_cpt_cyc,

  input  logic                   wr_tready,
  output logic                   wr_tvalid,
  output logic [DATA_WIDTH-1:0]  wr_tdata,
  output logic [KEEP_WIDTH-1:0]  wr_tkeep,
  output logic [KEEP_WIDTH-1:0]  wr_tstrb,
  output logic                   wr_tlast,
  output logic                   wr_tid,
  output logic                   wr_tdest,
  output logic                   wr_tuser,

  output logic                   fifo_out_re,
  input  logic                   fifo_out_empty,
  input  logic [DATA_WIDTH-1:0]  fifo_out_rdata,
  input  logic                   data_out_last
);

  typedef enum logic [1:0] {
    TX_IDLE,
    TX_HOLD,
    TX_PASS
  } tx_state_t;

  tx_state_t tx_state_cur;
  tx_state_t tx_state_next;

  logic [DATA_WIDTH-1:0] hold_data_q;
  logic                  hold_last_q;
  logic                  hold_user_q;
  logic                  tx_fire;
  logic                  capture_head;

  assign tx_fire = wr_tvalid && wr_tready;

  // Process 1: state and state-associated data registers.
  always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
    if (!tpu_rst_n) begin
      tx_state_cur   <= TX_IDLE;
      hold_data_q  <= '0;
      hold_last_q  <= 1'b0;
      hold_user_q  <= 1'b0;
      rpt_cpt_cyc  <= '0;
    end else begin
      tx_state_cur <= tx_state_next;

      if (capture_head) begin
        hold_data_q <= fifo_out_rdata;
        hold_last_q <= data_out_last;
        hold_user_q <= cpu_cpt_mode[1];
      end

      if (cpu_tpu_start_sync) begin
        rpt_cpt_cyc <= '0;
      end else if (tx_fire) begin
        rpt_cpt_cyc <= rpt_cpt_cyc + {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
      end
    end
  end

  // Process 2: next-state logic.
  always_comb begin
    unique case (tx_state_cur)
      TX_IDLE: begin
        if (cpu_tpu_en_sync && !fifo_out_empty) begin
          // Snapshot the first FWFT head before exposing it to AXI.
          tx_state_next = TX_HOLD;
        end else begin
          tx_state_next = TX_IDLE;
        end
      end

      TX_HOLD: begin
        // Once VALID is asserted it is not withdrawn until the beat transfers,
        // even if the block enable changes during downstream backpressure.
        if (wr_tready) begin
          if (cpu_tpu_en_sync) begin
            tx_state_next = TX_PASS;
          end else begin
            tx_state_next = TX_IDLE;
          end
        end else begin
          tx_state_next = TX_HOLD;
        end
      end

      TX_PASS: begin
        if (fifo_out_empty) begin
          tx_state_next = TX_IDLE;
        end else if (!wr_tready) begin
          // A beat already advertised in PASS must be captured even if enable
          // drops; AXI VALID cannot be withdrawn while READY is low.
          tx_state_next = TX_HOLD;
        end else if (!cpu_tpu_en_sync) begin
          // READY is high, so the outstanding beat completes this cycle.
          tx_state_next = TX_IDLE;
        end else begin
          tx_state_next = TX_PASS;
        end
      end

      default: begin
        tx_state_next = TX_IDLE;
      end
    endcase
  end

  // Process 3: output decode. TX_PASS is a zero-bubble direct FWFT path;
  // TX_HOLD supplies the registered copy until it is accepted. capture_head
  // is decoded here as a state-associated datapath control, keeping the FSM in
  // the requested three-process form.
  always_comb begin
    wr_tvalid   = 1'b0;
    wr_tdata    = '0;
    wr_tkeep    = {KEEP_WIDTH{1'b1}};
    wr_tstrb    = {KEEP_WIDTH{1'b1}};
    wr_tlast    = 1'b0;
    wr_tid      = 1'b0;
    wr_tdest    = 1'b0;
    wr_tuser    = 1'b0;
    fifo_out_re = 1'b0;
    capture_head = 1'b0;

    unique case (tx_state_cur)
      TX_IDLE: begin
        // Snapshot the first head without consuming it.
        capture_head = cpu_tpu_en_sync && !fifo_out_empty;
      end

      TX_HOLD: begin
        wr_tvalid = 1'b1;
        wr_tdata  = hold_data_q;
        wr_tlast  = hold_last_q;
        wr_tuser  = hold_user_q;
      end

      TX_PASS: begin
        // Entry into PASS was enable-qualified. Once here, the current beat is
        // independent of later enable changes until it handshakes.
        wr_tvalid = !fifo_out_empty;
        wr_tdata  = fifo_out_rdata;
        wr_tlast  = wr_tvalid && data_out_last;
        wr_tuser  = cpu_cpt_mode[1];
        // At the first stalled cycle, preserve the complete payload locally.
        capture_head = wr_tvalid && !wr_tready;
      end

      default: begin
        // Outputs retain their safe idle values.
      end
    endcase

    // FIFO_OUT advances exactly when the currently presented AXI beat is
    // accepted. This also makes the count event identical to a FIFO pop.
    fifo_out_re = wr_tvalid && wr_tready;
  end

endmodule

`default_nettype wire
