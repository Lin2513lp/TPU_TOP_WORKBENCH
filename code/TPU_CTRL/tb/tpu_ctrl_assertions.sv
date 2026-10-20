`timescale 1ns/1ps
`default_nettype none

// Protocol checks for the new CTRL only; arithmetic is checked independently
// by the integration scoreboard against the actual unmodified SA hierarchy.
module tpu_ctrl_assertions (
    input wire logic sys_ckg, tpu_rst_n,
    input wire logic fifo_in_re, fifo_empty, cpu_tpu_en_sync,
    input wire logic dat_in_vld, dat_in_last,
    input wire logic rpt_cpt_done, data_out_last,
    input wire logic start_accept, done_clear_event,
    input wire logic task_active_q,skew_last_seen_q,output_last_seen_q,input_last_seen_q,
    input wire logic rpt_error,
    input wire logic [2:0] rpt_error_state
);
    assert property (@(posedge sys_ckg) disable iff (!tpu_rst_n)
        fifo_in_re |-> (cpu_tpu_en_sync && !fifo_empty));
    assert property (@(posedge sys_ckg) disable iff (!tpu_rst_n)
        dat_in_last |-> dat_in_vld);
    assert property (@(posedge sys_ckg) disable iff (!tpu_rst_n)
        (rpt_cpt_done && !start_accept && !done_clear_event) |=> rpt_cpt_done);
    assert property (@(posedge sys_ckg) disable iff (!tpu_rst_n)
        $rose(rpt_cpt_done) |-> $past(task_active_q && cpu_tpu_en_sync &&
            (skew_last_seen_q || (dat_in_vld && dat_in_last)) &&
            (output_last_seen_q || (data_out_last && input_last_seen_q))));
    assert property (@(posedge sys_ckg) disable iff (!tpu_rst_n)
        rpt_error == (rpt_error_state != 3'b000));
endmodule

bind tpu_ctrl tpu_ctrl_assertions u_protocol_checks (
    .sys_ckg, .tpu_rst_n, .fifo_in_re, .fifo_empty, .cpu_tpu_en_sync,
    .dat_in_vld, .dat_in_last, .rpt_cpt_done, .data_out_last,
    .start_accept, .done_clear_event,
    .rpt_error, .rpt_error_state,
    .task_active_q, .skew_last_seen_q, .output_last_seen_q, .input_last_seen_q
);
`default_nettype wire
