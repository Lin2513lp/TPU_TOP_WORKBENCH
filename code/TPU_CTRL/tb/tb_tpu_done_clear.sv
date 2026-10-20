`timescale 1ns/1ps
`default_nettype none
module tb_tpu_done_clear;
    logic ahb_clk=0, raw_sys_clk=0, sys_run=1;
    always #3.5 ahb_clk=~ahb_clk;
    always #1.25 raw_sys_clk=~raw_sys_clk;
    wire sys_ckg=raw_sys_clk && sys_run;
    logic tpu_rst_n=0;
    logic hsel=0, hwrite=0, hreadyin=1;
    logic [2:0] hsize=3'b010,hburst=0;
    logic [1:0] htrans=0;
    logic [31:0] haddr=0,hwdata=0,hrdata;
    logic [3:0] hprot=0;
    logic hready,hresp;
    logic cpu_tpu_en,cpu_sw_rst,cpu_tpu_start,cpu_tpu_crg_bypass;
    logic [3:0] cpu_h_size,cpu_w_size,cpu_dat_in_b_sel;
    logic [1:0] cpu_cpt_mode;
    logic cpu_dat_in_b_lock,cpu_tpu_crg_en;
    logic [511:0] cpu_dat_in_b;
    logic cpu_done_clear_req,done_clear_ack,rpt_cpt_done,rpt_error;
    logic [2:0] rpt_error_state;
    logic [31:0] rpt_dat_in_cnt;
    logic fifo_empty=1,fifo_in_rd_dat_last=0,data_out_last=0;
    logic [511:0] fifo_in_rdata=512'h1234,dat_in_a;
    logic fifo_in_re,cpu_tpu_en_sync,cpu_tpu_start_sync,dat_in_vld,dat_in_last;
    logic [31:0] read_value;
    logic saved_req;
    integer checks=0;
    ahb_slave_regmap u_reg (
        .ahb_clk,.tpu_rst_n,.hsel,.hsize,.haddr,.hburst,.htrans,.hwrite,.hwdata,
        .hreadyin,.hprot,.hready,.hrdata,.hresp,
        .cpu_tpu_en,.cpu_sw_rst,.cpu_tpu_start,.cpu_tpu_crg_bypass,
        .cpu_h_size,.cpu_w_size,.cpu_cpt_mode,.cpu_dat_in_b_sel,
        .cpu_dat_in_b_lock,.cpu_tpu_crg_en,.cpu_dat_in_b,
        .cpu_done_clear_req,.done_clear_ack,
        .rpt_active_size(32'h0001_0001),.rpt_cpt_cyc(32'd1),
        .rpt_dat_in_cnt,.rpt_error(1'b1),.rpt_error_state,.rpt_cpt_done
    );
    tpu_ctrl u_ctrl (
        .sys_ckg,.tpu_rst_n,.cpu_tpu_en,.cpu_tpu_start,
        .cpu_done_clear_req,.done_clear_ack,.cpu_cpt_mode,.cpu_h_size,.cpu_w_size,
        .fifo_empty,.fifo_in_rdata,.fifo_in_rd_dat_last,.data_out_last,
        .fifo_in_re,.cpu_tpu_en_sync,.cpu_tpu_start_sync,.dat_in_a,
        .dat_in_vld,.dat_in_last,.rpt_cpt_done,.rpt_dat_in_cnt,.rpt_error,.rpt_error_state
    );
    task automatic check(input logic ok,input string msg);
        checks++;
        if(ok !== 1'b1) $fatal(1,"DONE_CLEAR %s at %0t",msg,$time);
    endtask
    task automatic access_reg(input logic wr,input logic [31:0] addr,
                              input logic [31:0] data,input logic err);
        @(negedge ahb_clk);
        hsel=1;htrans=2'b10;hwrite=wr;haddr=addr;hwdata=data;
        repeat(2) @(posedge ahb_clk);
        #0.1;
        check(hresp===err,"AHB response");
        check(hready===!err,"AHB first response READY");
        if(!wr && !err) read_value=hrdata;
        @(negedge ahb_clk);hsel=0;htrans=0;
        @(posedge ahb_clk);#0.1;
        if(err) check(hresp && hready,"AHB second ERROR cycle");
        repeat(2) @(posedge ahb_clk);
        #0.1;
    endtask
    task automatic read_done(input logic expected_done);
        access_reg(0,32'h410,0,0);
        check(read_value=={31'b0,expected_done},"AHB synchronized DONE readback");
    endtask
    task automatic start_and_drain;
        access_reg(1,32'h008,1,0);
        repeat(4) @(negedge sys_ckg);
        check(!rpt_cpt_done,"next accepted START clears retained DONE");
        fifo_empty=0;fifo_in_rd_dat_last=1;
        @(negedge sys_ckg);
        check(rpt_dat_in_cnt==1,"one original FIFO beat accepted");
        fifo_empty=1;fifo_in_rd_dat_last=0;
        repeat(18) @(negedge sys_ckg);
        check(!rpt_cpt_done,"input tail alone cannot complete");
    endtask
    task automatic finish_task;
        data_out_last=1;
        @(negedge sys_ckg);data_out_last=0;
        check(rpt_cpt_done,"eligible LAST sets DONE");
        repeat(16) @(negedge sys_ckg);
        check(rpt_cpt_done,"DONE retained across many business clocks");
    endtask
    initial begin
        #0.1;tpu_rst_n=0;
        repeat(4) @(negedge ahb_clk);tpu_rst_n=1;
        read_done(0);
        access_reg(1,32'h414,1,0);access_reg(0,32'h414,0,0);
        check(read_value==1,"CRG enable at word105 is accessible");
        access_reg(0,32'h418,0,0);check(read_value==1,"independent error flag at word106");
        access_reg(1,32'h418,0,0);access_reg(0,32'h418,0,0);
        check(read_value==1,"error flag remains read-only");
        access_reg(0,32'h41c,0,1);
        access_reg(1,32'h000,1,0);
        start_and_drain();finish_task();read_done(1);
        saved_req=cpu_done_clear_req;
        access_reg(1,32'h410,32'hffff_fffe,0);
        check(cpu_done_clear_req===saved_req,"write-zero bit0 is no-op");read_done(1);
        access_reg(1,32'h000,0,0);
        repeat(8) @(negedge sys_ckg);
        check(rpt_cpt_done,"EN disable retains DONE");read_done(1);
        @(negedge raw_sys_clk);sys_run=0;
        access_reg(1,32'h410,1,0);
        check(cpu_done_clear_req!==done_clear_ack,"clear request stays pending while SYS gated");
        saved_req=cpu_done_clear_req;
        repeat(3) access_reg(1,32'h410,1,0);
        check(cpu_done_clear_req===saved_req,"repeated W1C coalesces without toggle cancellation");
        check(rpt_cpt_done,"stopped SYS retains DONE until request can execute");read_done(1);
        @(negedge raw_sys_clk);sys_run=1;
        repeat(8) @(negedge sys_ckg);
        check(!rpt_cpt_done && done_clear_ack===cpu_done_clear_req,"wake processes clear exactly once");
        read_done(0);
        access_reg(1,32'h000,1,0);
        start_and_drain();finish_task();read_done(1);
        // A new START, without a W1C, clears the prior task's sticky completion.
        start_and_drain();
        // Align a genuine AHB-originated clear event with the completion edge.
        fork
            begin access_reg(1,32'h410,1,0); end
            begin
                wait(u_ctrl.done_clear_event===1'b1);
                @(negedge sys_ckg);data_out_last=1;
                @(negedge sys_ckg);data_out_last=0;
                check(rpt_cpt_done,"hardware completion dominates coincident software clear");
            end
        join
        repeat(16) @(negedge sys_ckg);
        check(rpt_cpt_done,"processed clear cannot erase completion again");read_done(1);
        access_reg(1,32'h410,1,0);read_done(0);
        // Reset must discard an outstanding request and align both toggle endpoints.
        @(negedge raw_sys_clk);sys_run=0;
        access_reg(1,32'h410,1,0);
        #0.2;tpu_rst_n=0;#0.2;
        check(!rpt_cpt_done && !cpu_done_clear_req && !done_clear_ack,"reset aligns handshake and clears DONE");
        @(negedge raw_sys_clk);sys_run=1;
        repeat(4) @(negedge ahb_clk);tpu_rst_n=1;
        repeat(8) @(negedge sys_ckg);read_done(0);
        $display("DONE_CLEAR_PASS checks=%0d",checks);
        $finish;
    end
    initial begin #20000;$fatal(1,"DONE_CLEAR watchdog");end
endmodule
`default_nettype wire
