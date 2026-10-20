`timescale 1ns/1ps
`default_nettype none
module tb_tpu_task_bridge;
    logic ahb_clk=0,base_sys=0,sys_run=1;
    always #5 ahb_clk=~ahb_clk;
    always #1.25 base_sys=~base_sys;
    wire sys_ckg=base_sys&&sys_run;
    logic ahb_rst_n=0,tpu_rst_n=0,task_start_ahb=0,task_start_sys=0;
    logic compute_done_sys=0,tx_last_sys=0,cpu_done_clear_req=0,ctrl_done_clear_ack=0;
    logic [31:0] rpt_active_size_sys=0,rpt_cpt_cyc_sys=0,rpt_dat_in_cnt_sys=0;
    logic [2:0] rpt_error_state_sys=0;
    wire [31:0] rpt_active_size_ahb,rpt_cpt_cyc_ahb,rpt_dat_in_cnt_ahb;
    wire [2:0] rpt_error_state_ahb;
    wire done_clear_ack,rpt_error_ahb,rpt_done_ahb,busy_ahb;
    tpu_task_bridge #(.DRAIN_CYCLES(4)) dut(.*);
    int checks=0,cases=0;
    logic [98:0] held_payload='0,expected_payload='0;
    bit pending_previous=0;
    bit observe=0,published=0;

    task automatic check(input bit ok,input string label);
        checks++;
        if(!ok)$fatal(1,"BRIDGE_CHECK_FAIL case=%0d %s at %0t",cases,label,$time);
    endtask
    task automatic sys_ticks(input int count);
        repeat(count)@(negedge base_sys);
    endtask
    task automatic bus_ticks(input int count);
        repeat(count)@(negedge ahb_clk);
    endtask
    task automatic wait_done;
        int timeout;
        timeout=0;
        while(!rpt_done_ahb)begin bus_ticks(1);timeout++;check(timeout<100,"publication timeout");end
        check({rpt_active_size_ahb,rpt_cpt_cyc_ahb,rpt_dat_in_cnt_ahb,rpt_error_state_ahb}===expected_payload,"coherent four-word mailbox payload");
        check(rpt_error_ahb==(|expected_payload[2:0]),"error flag derived from snapshot count");
    endtask
    task automatic wait_idle;
        int timeout;
        timeout=0;
        while(busy_ahb)begin bus_ticks(1);timeout++;check(timeout<100,"drain and acknowledgment timeout");end
        check(dut.report_ack_sync_q==dut.report_req_q,"busy release waits for source acknowledgement");
        check(dut.drain_q==0,"busy release waits for drain");
    endtask
    task automatic clear_done(input bit stop_sys);
        if(stop_sys)begin @(negedge base_sys);sys_run=0;end
        @(negedge ahb_clk);cpu_done_clear_req=~cpu_done_clear_req;
        bus_ticks(2);check(!rpt_done_ahb,"local sticky DONE clears while SYS stopped");
        check(done_clear_ack!=cpu_done_clear_req,"aggregate clear waits for CTRL acknowledgement");
        check({rpt_active_size_ahb,rpt_cpt_cyc_ahb,rpt_dat_in_cnt_ahb,rpt_error_state_ahb}===expected_payload,"W1C retains report payload");
        bus_ticks(3);check(done_clear_ack!=cpu_done_clear_req,"clear request remains pending without CTRL");
        if(stop_sys)begin @(negedge base_sys);sys_run=1;end
        sys_ticks(3);ctrl_done_clear_ack=cpu_done_clear_req;
        bus_ticks(5);check(done_clear_ack==cpu_done_clear_req,"aggregate clear acknowledgment completes");
    endtask

    // Immediate checker assertions also work in the supported non-UVM Questa setup.
    always @(posedge sys_ckg)begin
        #0.05;
        if(tpu_rst_n)begin
            if(pending_previous)
                check(dut.report_hold_q===held_payload,"source payload stable until synchronized mailbox ACK");
            held_payload=dut.report_hold_q;
            pending_previous=(dut.report_req_q!=dut.report_ack_sync_q);
        end else pending_previous=0;
    end
    always @(posedge ahb_clk)begin
        #0.1;
        if(observe&&rpt_done_ahb&&!published)begin
            check(dut.compute_seen_q&&dut.tx_seen_q,"publication requires both registered completion histories");
            check({rpt_active_size_ahb,rpt_cpt_cyc_ahb,rpt_dat_in_cnt_ahb,rpt_error_state_ahb}===expected_payload,"publication atomically installs complete expected payload");
            published=1;
        end
    end

    task automatic begin_case(input int identity);
        cases++;observe=0;published=0;
        compute_done_sys=0;tx_last_sys=0;
        rpt_active_size_sys=32'h55aa0000+32'(identity);
        rpt_cpt_cyc_sys=32'h80000001+32'(identity);
        rpt_dat_in_cnt_sys=32'h13572468+32'(identity);
        rpt_error_state_sys=3'(identity%8);
        expected_payload={rpt_active_size_sys,rpt_cpt_cyc_sys,rpt_dat_in_cnt_sys,rpt_error_state_sys};
        @(negedge ahb_clk);task_start_ahb=1;
        @(negedge ahb_clk);task_start_ahb=0;
        check(busy_ahb&&!rpt_done_ahb,"accepted START clears local DONE and holds busy");
        @(negedge base_sys);task_start_sys=1;sys_ticks(1);task_start_sys=0;
        observe=1;
    endtask
    task automatic complete_events(input int order);
        if(order==0)begin
            compute_done_sys=1;sys_ticks(5);
            check(!rpt_done_ahb,"compute alone cannot publish");
            tx_last_sys=1;sys_ticks(1);tx_last_sys=0;
        end else if(order==1)begin
            tx_last_sys=1;sys_ticks(1);tx_last_sys=0;sys_ticks(5);
            check(!rpt_done_ahb,"TX alone cannot publish");
            compute_done_sys=1;
        end else begin
            compute_done_sys=1;tx_last_sys=1;sys_ticks(1);tx_last_sys=0;
        end
        // Wait for actual source capture then corrupt all live source inputs;
        // mailbox receiver must obtain the held snapshot, not those live values.
        while(!dut.captured_q)sys_ticks(1);
        rpt_active_size_sys=32'hdeadbeef;rpt_cpt_cyc_sys=32'h11223344;
        rpt_dat_in_cnt_sys=32'haabbccdd;rpt_error_state_sys=7;
        wait_done();wait_idle();observe=0;
    endtask

    initial begin
        bus_ticks(3);ahb_rst_n=1;tpu_rst_n=1;bus_ticks(3);
        for(int order=0;order<3;order++)begin
            begin_case(order);complete_events(order);clear_done(order==1);
        end
        // W1C before TX cannot erase a compute history already observed.
        begin_case(3);compute_done_sys=1;sys_ticks(3);
        @(negedge ahb_clk);cpu_done_clear_req=~cpu_done_clear_req;
        compute_done_sys=0;ctrl_done_clear_ack=cpu_done_clear_req;
        bus_ticks(5);check(dut.compute_seen_q,"early W1C retains prior compute completion");
        tx_last_sys=1;sys_ticks(1);tx_last_sys=0;
        wait_done();wait_idle();observe=0;clear_done(0);
        // W1C after TX cannot erase the independently retained TX history.
        begin_case(4);tx_last_sys=1;sys_ticks(1);tx_last_sys=0;
        @(negedge ahb_clk);cpu_done_clear_req=~cpu_done_clear_req;
        ctrl_done_clear_ack=cpu_done_clear_req;bus_ticks(5);
        check(dut.tx_seen_q,"early W1C retains prior TX completion");
        compute_done_sys=1;wait_done();wait_idle();observe=0;clear_done(0);
        // Publication and local W1C land on exactly the same AHB edge.
        begin_case(5);compute_done_sys=1;tx_last_sys=1;sys_ticks(1);tx_last_sys=0;
        while(dut.release_sync_q==dut.release_seen_q)@(negedge ahb_clk);
        cpu_done_clear_req=~cpu_done_clear_req;
        @(posedge ahb_clk);#0.2;
        check(rpt_done_ahb,"fresh publication dominates same-edge software clear");
        ctrl_done_clear_ack=cpu_done_clear_req;
        wait_done();wait_idle();bus_ticks(5);observe=0;clear_done(0);
        // Reset an in-flight request and prove a fresh request survives afterwards.
        begin_case(6);compute_done_sys=1;tx_last_sys=1;sys_ticks(1);tx_last_sys=0;
        observe=0;ahb_rst_n=0;tpu_rst_n=0;bus_ticks(3);
        cpu_done_clear_req=0;ctrl_done_clear_ack=0;task_start_sys=0;
        check(!rpt_done_ahb&&!busy_ahb,"reset discards unfinished mailbox");
        ahb_rst_n=1;tpu_rst_n=1;bus_ticks(3);
        begin_case(7);complete_events(2);clear_done(1);
        $display("BRIDGE_REGRESSION_PASS cases=%0d checks=%0d event_orders=3 clear_races=3",cases,checks);
        $finish;
    end
    initial begin #500000;$fatal(1,"bridge global timeout");end
endmodule
`default_nettype wire
