`timescale 1ns/1ps
`default_nettype none

// Task report mailbox. The source holds the entire payload until the AHB
// receiver stores it and returns the synchronized acknowledgement toggle.
// Control/reset CDC requires common reset assertion; deassert each reset in
// its receiving domain. This RTL handshake is not a physical CDC signoff.
module tpu_task_bridge #(
    parameter int unsigned DRAIN_CYCLES = 64
) (
    /* always-on: reports and clear requests survive a stopped SYS clock. */
    input  wire logic        ahb_clk,
    input  wire logic        ahb_rst_n,
    // The parent holds the existing CRG open while busy_ahb is asserted.
    input  wire logic        sys_ckg,
    input  wire logic        tpu_rst_n,
    // Already admitted AHB command; the command mailbox rejects busy STARTs.
    input  wire logic        task_start_ahb,
    // Rising CTRL cpu_tpu_start_sync, coincident with CTRL START acceptance.
    input  wire logic        task_start_sys,
    input  wire logic        compute_done_sys,
    input  wire logic        tx_last_sys,
    input  wire logic [31:0] rpt_active_size_sys,
    input  wire logic [31:0] rpt_cpt_cyc_sys,
    input  wire logic [31:0] rpt_dat_in_cnt_sys,
    input  wire logic [2:0]  rpt_error_state_sys,
    input  wire logic        cpu_done_clear_req,
    input  wire logic        ctrl_done_clear_ack,
    output logic        done_clear_ack,
    output logic [31:0] rpt_active_size_ahb,
    output logic [31:0] rpt_cpt_cyc_ahb,
    output logic [31:0] rpt_dat_in_cnt_ahb,
    output logic [2:0]  rpt_error_state_ahb,
    output logic        rpt_error_ahb,
    output logic        rpt_done_ahb,
    output logic        busy_ahb
);
    localparam int unsigned DRAIN_WIDTH =
        (DRAIN_CYCLES < 1) ? 1 : $clog2(DRAIN_CYCLES + 1);
    localparam int unsigned PAYLOAD_WIDTH = 99;

    // Bundled-data mailbox: these bits do not change while request is pending.
    logic [PAYLOAD_WIDTH-1:0] report_hold_q;
    logic [PAYLOAD_WIDTH-1:0] report_stage_q;
    logic report_req_q, report_ack_q;
    (* async_reg = "true" *) logic report_req_meta_q, report_req_sync_q;
    (* async_reg = "true" *) logic report_ack_meta_q, report_ack_sync_q;
    logic task_start_prev_q, task_active_q;
    logic compute_seen_q, tx_seen_q, captured_q;
    logic [DRAIN_WIDTH-1:0] drain_q;
    logic release_toggle_q;
    (* async_reg = "true" *) logic release_meta_q, release_sync_q;
    logic release_seen_q;

    (* async_reg = "true" *) logic clear_ack_meta_q, clear_ack_sync_q;
    logic clear_seen_q;

    always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            report_ack_meta_q <= 1'b0;
            report_ack_sync_q <= 1'b0;
        end else begin
            report_ack_meta_q <= report_ack_q;
            report_ack_sync_q <= report_ack_meta_q;
        end
    end

    always_ff @(posedge sys_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            task_start_prev_q <= 1'b0;
            task_active_q <= 1'b0;
            compute_seen_q <= 1'b0;
            tx_seen_q <= 1'b0;
            captured_q <= 1'b0;
            drain_q <= '0;
            report_hold_q <= '0;
            report_req_q <= 1'b0;
            release_toggle_q <= 1'b0;
        end else begin
            task_start_prev_q <= task_start_sys;
            if (task_start_sys && !task_start_prev_q && !task_active_q) begin
                task_active_q <= 1'b1;
                compute_seen_q <= 1'b0;
                tx_seen_q <= 1'b0;
                captured_q <= 1'b0;
                drain_q <= '0;
            end else if (task_active_q) begin
                // W1C intentionally does not touch either completion history.
                // Sampling sticky CTRL DONE also retains a same-edge clear:
                // CTRL's new completion dominates clear at its source.
                if (compute_done_sys) compute_seen_q <= 1'b1;
                if (tx_last_sys) tx_seen_q <= 1'b1;

                // Both histories were registered on an earlier edge. Thus the
                // final fifo2axi TX count increment is included without adding
                // an increment here (which could double count).
                if (!captured_q && compute_seen_q && tx_seen_q) begin
                    report_hold_q <= {rpt_active_size_sys, rpt_cpt_cyc_sys,
                                      rpt_dat_in_cnt_sys, rpt_error_state_sys};
                    report_req_q <= !report_req_q;
                    captured_q <= 1'b1;
                    drain_q <= DRAIN_WIDTH'(DRAIN_CYCLES);
                end else if (captured_q) begin
                    if (drain_q != '0) drain_q <= drain_q - 1'b1;
                    // Delay admission until the receiver has stored the full
                    // payload and all enabled PE pipelines have drained.
                    if ((drain_q == '0) && (report_ack_sync_q == report_req_q)) begin
                        task_active_q <= 1'b0;
                        release_toggle_q <= !release_toggle_q;
                    end
                end
            end
        end
    end

    always_ff @(posedge ahb_clk or negedge ahb_rst_n) begin
        if (!ahb_rst_n) begin
            report_req_meta_q <= 1'b0;
            report_req_sync_q <= 1'b0;
            release_meta_q <= 1'b0;
            release_sync_q <= 1'b0;
            clear_ack_meta_q <= 1'b0;
            clear_ack_sync_q <= 1'b0;
        end else begin
            report_req_meta_q <= report_req_q;
            report_req_sync_q <= report_req_meta_q;
            release_meta_q <= release_toggle_q;
            release_sync_q <= release_meta_q;
            clear_ack_meta_q <= ctrl_done_clear_ack;
            clear_ack_sync_q <= clear_ack_meta_q;
        end
    end

    always_ff @(posedge ahb_clk or negedge ahb_rst_n) begin
        if (!ahb_rst_n) begin
            report_ack_q <= 1'b0;
            release_seen_q <= 1'b0;
            clear_seen_q <= 1'b0;
            done_clear_ack <= 1'b0;
            report_stage_q <= '0;
            rpt_active_size_ahb <= '0;
            rpt_cpt_cyc_ahb <= '0;
            rpt_dat_in_cnt_ahb <= '0;
            rpt_error_state_ahb <= '0;
            rpt_done_ahb <= 1'b0;
            busy_ahb <= 1'b0;
        end else begin
            if (release_sync_q != release_seen_q) begin
                release_seen_q <= release_sync_q;
                busy_ahb <= 1'b0;
            end
            if (task_start_ahb && !busy_ahb &&
                (cpu_done_clear_req == done_clear_ack)) begin
                busy_ahb <= 1'b1;
                rpt_done_ahb <= 1'b0;
            end
            if (cpu_done_clear_req != clear_seen_q) begin
                clear_seen_q <= cpu_done_clear_req;
                rpt_done_ahb <= 1'b0;
            end
            // Aggregate acknowledgement covers BOTH locally retained DONE
            // and CTRL sticky DONE. It never acknowledges just the raw CTRL.
            if ((clear_seen_q == cpu_done_clear_req) &&
                (clear_ack_sync_q == cpu_done_clear_req))
                done_clear_ack <= cpu_done_clear_req;

            if (report_req_sync_q != report_ack_q) begin
                report_stage_q <= report_hold_q;
                report_ack_q <= report_req_sync_q;
            end
            if (release_sync_q != release_seen_q) begin
                // A fresh completion wins a simultaneous W1C, matching CTRL.
                // Source release requires report ACK and pipeline drain. Thus
                // all words are already saved, and polling DONE also means a
                // subsequent START/configuration write can be admitted.
                {rpt_active_size_ahb, rpt_cpt_cyc_ahb,
                 rpt_dat_in_cnt_ahb, rpt_error_state_ahb} <= report_stage_q;
                rpt_done_ahb <= 1'b1;
            end
        end
    end

    assign rpt_error_ahb = |rpt_error_state_ahb;
endmodule

`default_nettype wire
