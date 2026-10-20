`timescale 1ns/1ps
`default_nettype none

// Native Questa regression of the real AHB -> CTRL -> SA -> FIFO -> AXI path.
// No arithmetic DUT modules are reused by the reference model.
module tb_tpu_top;
    logic sys_clk=0, ahb_clk=0;
    always #1.25 sys_clk=~sys_clk;
    always #5 ahb_clk=~ahb_clk;
    logic sys_rst_n=0, dft_glb_gt_se=0, dft_mode=0, dft_lgc_rst_n=1;
    logic hsel=0, hwrite=0, hreadyin=1;
    logic [2:0] hsize=2, hburst=0;
    logic [31:0] haddr=0, hwdata=0;
    logic [1:0] htrans=0;
    logic [3:0] hprot=0;
    wire hready,hresp;
    wire [31:0] hrdata;
    logic rd_tvalid=0,rd_tlast=0,rd_tid=0,rd_tdest=0,rd_tuser=0;
    logic [511:0] rd_tdata=0;
    logic [63:0] rd_tkeep='1,rd_tstrb='1;
    wire rd_tready;
    logic wr_tready=1;
    wire wr_tvalid,wr_tlast,wr_tid,wr_tdest,wr_tuser;
    wire [511:0] wr_tdata;
    wire [63:0] wr_tkeep,wr_tstrb;
    tpu_top dut(.*);

    int checks=0,jobs=0,mode=0,n=1,length=1,tx_count=0,rx_count=0;
    int tx_lasts=0,sa_count=0,sa_lasts=0,publications=0,start_pulses=0;
    int arithmetic_lanes=0,seed=1,initial_seed=1,zero_lanes=0;
    bit observing=0,tx_last_seen=0,compute_seen=0;
    bit prior_done=0;
    logic [98:0] prior_reports='0;
    int a[0:127][0:15],b[0:15][0:15];
    logic [31:0] golden[0:127][0:15];
    logic [511:0] expected_stream[0:143];
    bit covered[0:3][0:2][0:2];
    int summary;

    task automatic check(input bit ok,input string label);
        checks++;
        if(!ok) $fatal(1,"TOP_CHECK_FAIL job=%0d mode=%0d N=%0d len=%0d seed=%0d %s at %0t",
                       jobs,mode,n,length,initial_seed,label,$time);
    endtask

    function automatic logic [31:0] small_fp32(input int value);
        int msb;
        logic [31:0] normalized;
        logic [7:0] exponent;
        if(value==0) return 0;
        msb=0;
        for(int k=0;k<31;k++) if(value[k]) msb=k;
        normalized=32'(value) << (23-msb);
        exponent=8'(127+msb);
        return {1'b0,exponent,normalized[22:0]};
    endfunction

    function automatic logic [31:0] operand(input int value);
        if(mode<2) return 32'(value);
        if(mode==3) return small_fp32(value);
        case(value)
          0:return 0;1:return 'h3c00;2:return 'h4000;
          3:return 'h4200;default:return 'h4400;
        endcase
    endfunction

    function automatic int unsigned rng();
        seed=seed^(seed<<13);seed=seed^(seed>>17);seed=seed^(seed<<5);
        return unsigned'(seed);
    endfunction

    task automatic ahb_transfer(input bit write_access,input int word_addr,
                                input logic [31:0] data,output logic [31:0] value);
        // Preserve the existing slave's documented IDLE wake/address/data phases.
        @(negedge ahb_clk);
        hsel=1;htrans=2;haddr=32'(word_addr*4);hwrite=write_access;hwdata=data;
        @(posedge ahb_clk);@(posedge ahb_clk);#0.1;
        check(hready&&!hresp,"legal AHB word transfer completed");
        value=hrdata;
        @(negedge ahb_clk);hsel=0;htrans=0;
        @(posedge ahb_clk);#0.1;
        @(posedge ahb_clk);#0.1;
    endtask
    task automatic write_reg(input int address,input logic[31:0] value);
        logic[31:0] unused_value;
        ahb_transfer(1,address,value,unused_value);
    endtask
    task automatic read_check(input int address,input logic[31:0] expected);
        logic[31:0] actual;
        ahb_transfer(0,address,0,actual);
        check(actual===expected,$sformatf("AHB[%03h] got %08h expected %08h",address,actual,expected));
    endtask
    task automatic wait_idle;
        int timeout;
        timeout=0;
        while(dut.task_busy_ahb||dut.command_pending_ahb||dut.clear_busy_ahb) begin
            @(negedge ahb_clk);timeout++;
            check(timeout<1000,"task/mailbox/clear returned idle");
        end
    endtask

    task automatic reset_global;
        observing=0;rd_tvalid=0;rd_tlast=0;hsel=0;htrans=0;
        @(negedge ahb_clk);sys_rst_n=0;
        repeat(5)@(negedge ahb_clk);sys_rst_n=1;
        repeat(10)@(negedge ahb_clk);
        check(dut.ahb_rst_n,"AHB reset released with SYS gate off");
        read_check('h104,0);read_check('h100,0);read_check('h101,0);read_check('h102,0);
    endtask

    task automatic prepare;
        int sum;
        wait_idle();
        write_reg('h105,0);
        repeat(8)@(negedge ahb_clk);
        check(!dut.sys_ckg,"SYS gate closed before changing dimensions");
        write_reg(4,32'(n-1));write_reg(5,32'(n-1));write_reg(6,32'(mode));
        read_check(4,32'(n-1));read_check(5,32'(n-1));read_check(6,32'(mode));
        write_reg('h105,1);write_reg(0,1);
        repeat(8)@(negedge ahb_clk);
        if(jobs==2)begin
            write_reg('h105,0);repeat(8)@(negedge ahb_clk);
            check(!dut.sys_ckg,"weight LOCK begins with SYS stopped");
        end
        for(int r=0;r<n;r++) begin
            write_reg(7,32'(r));
            for(int c=0;c<16;c++) begin
                b[r][c]=1+int'(rng()%4);
                write_reg(9+c,operand(b[r][c]));
            end
            write_reg(8,1);wait_idle();
        end
        if(jobs==2)begin
            repeat(8)@(negedge ahb_clk);
            check(!dut.sys_ckg,"LOCK mailbox completes then permits SYS gate to close");
            write_reg('h105,1);repeat(8)@(negedge ahb_clk);
        end
        for(int k=0;k<length;k++) begin
            for(int r=0;r<16;r++) begin
                // Explicit real zero vectors (including LAST) plus signed integers.
                if(k%7==0 || k==length-1) a[k][r]=0;
                else if(mode<2) a[k][r]=int'(rng()%13)-6;
                else a[k][r]=1+int'(rng()%4);
            end
            for(int c=0;c<n;c++) begin
                sum=0;
                for(int r=0;r<n;r++) sum+=a[k][r]*b[r][c];
                golden[k][c]=(mode<2)?32'(sum):small_fp32(sum);
            end
        end
        // Continuous vectors produce staggered columns: beat j, lane c = C[j-c,c].
        for(int j=0;j<length+n-1;j++) begin
            expected_stream[j]='0;
            for(int c=0;c<n;c++) if(j>=c && j-c<length)
                expected_stream[j][c*32+:32]=golden[j-c][c];
        end
    endtask

    task automatic send_packet;
        int sent,timeout;
        sent=0;timeout=0;
        @(negedge sys_clk);rd_tvalid=1;
        while(sent<length) begin
            for(int r=0;r<16;r++) rd_tdata[r*32+:32]=operand(a[sent][r]);
            rd_tlast=(sent==length-1);
            @(posedge sys_clk);
            if(rd_tready) sent++;
            @(negedge sys_clk);timeout++;
            check(timeout<2000,"RX ready timeout");
        end
        rd_tvalid=0;rd_tlast=0;
    endtask

    always @(posedge dut.sys_ckg) if(observing) begin
        if(dut.cpu_tpu_start_sync)begin start_pulses++;compute_seen=0;end
        if(rd_tvalid&&rd_tready)rx_count++;
        if(!dut.cpu_tpu_start_sync&&dut.compute_done_sys)compute_seen=1;
        if(dut.dat_out_vld)begin sa_count++;if(dut.dat_out_last)sa_lasts++;end
        if(wr_tvalid&&wr_tready)begin
            check(tx_count<length+n-1,"no extra AXI output");
            check(wr_tdata===expected_stream[tx_count],
                $sformatf("independent arithmetic/full512 beat %0d got %0128h expected %0128h",tx_count,wr_tdata,expected_stream[tx_count]));
            check(wr_tlast===(tx_count==length+n-2),"LAST only on final output beat");
            check(wr_tkeep==='1&&wr_tstrb==='1,"output byte metadata");
            check(wr_tid==0&&wr_tdest==0&&wr_tuser==mode[1],"output sideband metadata");
            for(int c=0;c<n;c++) if(tx_count>=c&&tx_count-c<length)begin
                arithmetic_lanes++;
                if(expected_stream[tx_count][c*32+:32]==0)zero_lanes++;
            end
            tx_count++;
            if(wr_tlast)begin tx_lasts++;tx_last_seen=1;end
        end
    end

    // Reports change atomically only when a fresh task is published.
    always @(posedge ahb_clk) begin
        #0.2;
        if(dut.ahb_rst_n&&observing)begin
            if(dut.rpt_done_ahb&&!prior_done)begin
                publications++;
                check(!dut.task_busy_ahb,"CPU DONE exposes immediate next-task admission after drain/ACK");
                check(tx_last_seen&&compute_seen,"CPU DONE waits for CTRL and final TX handshake");
                check(dut.rpt_active_size_ahb=={16'(n),16'(n)},"atomic active-size snapshot");
                check(dut.rpt_cpt_cyc_ahb==32'(length+n-1),"atomic TX count includes LAST");
                check(dut.rpt_dat_in_cnt_ahb==32'(length),"atomic input-count snapshot");
                check(dut.rpt_error_state_ahb==0&&!dut.rpt_error_ahb,"atomic error snapshot");
            end
            if({dut.rpt_active_size_ahb,dut.rpt_cpt_cyc_ahb,dut.rpt_dat_in_cnt_ahb,dut.rpt_error_state_ahb}!==prior_reports)
                check(dut.rpt_done_ahb&&!prior_done,"report payload changes only with publication");
        end
        prior_done=dut.rpt_done_ahb;
        prior_reports={dut.rpt_active_size_ahb,dut.rpt_cpt_cyc_ahb,dut.rpt_dat_in_cnt_ahb,dut.rpt_error_state_ahb};
    end

    task automatic run_job(input bit auto_gate,input bit busy_writes);
        int timeout;
        jobs++;prepare();tx_count=0;rx_count=0;tx_lasts=0;sa_count=0;sa_lasts=0;
        publications=0;start_pulses=0;tx_last_seen=0;compute_seen=0;
        if(jobs==2)read_check('h104,1);
        observing=1;
        if(auto_gate)begin
            write_reg('h105,0);repeat(8)@(negedge ahb_clk);
            check(!dut.sys_ckg,"START test begins with SYS stopped");
        end
        write_reg(2,1);
        check(!dut.rpt_done_ahb,"accepted START clears the previous sticky CPU DONE");
        // Leave START enough time to traverse the mailbox; rdready is independently monitored.
        repeat(15)@(negedge sys_clk);
        if(busy_writes)begin
            write_reg(6,32'((mode+1)%4));write_reg(0,0);write_reg(2,1);
            write_reg(4,32'((n+3)%16));write_reg(9,32'hdeadbeef);write_reg(8,1);
            read_check(6,32'(mode));read_check(0,1);read_check(4,32'(n-1));
            read_check(9,operand(b[n-1][0]));
        end
        send_packet();
        timeout=0;
        while(!dut.rpt_done_ahb)begin
            @(negedge ahb_clk);timeout++;
            check(timeout<1000,"CPU DONE timeout");
        end
        wait_idle();
        read_check('h104,1);read_check('h100,{16'(n),16'(n)});
        read_check('h101,32'(length+n-1));read_check('h102,32'(length));
        read_check('h103,0);read_check('h106,0);
        check(rx_count==length,"all RX beats accepted");
        check(tx_count==length+n-1&&sa_count==tx_count,"exact SA/AXI schedule and no dropped result");
        check(tx_lasts==1&&sa_lasts==1,"one SA and one AXI LAST");
        check(start_pulses==1,"START is one SYS pulse; TX counter cannot be reset repeatedly");
        check(publications==1,"exactly one CPU publication");
        repeat(12)@(negedge ahb_clk);read_check('h104,1);
        observing=0;
        // Complete-task report persists when only DONE is cleared. Zero writes do nothing.
        write_reg('h104,0);read_check('h104,1);
        write_reg('h105,0);repeat(12)@(negedge ahb_clk);
        check(!dut.sys_ckg,"clock closed after publication/drain");
        // Job1 deliberately retains DONE: job2 must launch directly without W1C.
        if(jobs!=1)begin
            write_reg('h104,1);write_reg('h104,1);wait_idle();
            read_check('h104,0);
        end else read_check('h104,1);
        read_check('h100,{16'(n),16'(n)});
        read_check('h101,32'(length+n-1));read_check('h102,32'(length));
        check(dut.cpu_done_clear_req==dut.done_clear_ack,"W1C aggregate acknowledgment after wake");
        $fwrite(summary,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,PASS\n",jobs,mode,n,length,initial_seed,tx_count,start_pulses);
        $display("TOP_JOB_PASS job=%0d mode=%0d N=%0d len=%0d seed=%0d beats=%0d",jobs,mode,n,length,initial_seed,tx_count);
    endtask

    initial begin
        summary=$fopen("top_jobs.csv","w");
        $fwrite(summary,"job,mode,N,length,seed,tx_beats,start_pulses,status\n");
        reset_global();
        for(int m=0;m<4;m++)for(int ni=0;ni<3;ni++)for(int li=0;li<3;li++)begin
            mode=m;n=(ni==0)?1:(ni==1)?4:16;length=(li==0)?1:(li==1)?16:32;
            initial_seed=1+m*91+ni*17+li*7;seed=initial_seed;
            run_job((li==0),(li==1));covered[m][ni][li]=1;
        end
        // At least ten independent fixed seeds after all P0 mode/size/length bins pass.
        for(int s=1;s<=10;s++)begin
            initial_seed=32'h13579b+s*7919;seed=initial_seed;
            mode=int'(rng()%4);n=(s%3==0)?16:(s%3==1)?1:4;length=2+int'(rng()%63);
            run_job(s%2==0,0);
        end
        // Reset an active partial input task, then run a new task with new configuration.
        mode=3;n=16;length=16;prepare();write_reg(2,1);
        repeat(20)@(negedge sys_clk);
        rd_tvalid=1;rd_tlast=0;rd_tdata='0;
        repeat(6)@(negedge sys_clk);
        reset_global();
        mode=1;n=4;length=16;initial_seed=77;seed=77;run_job(1,0);
        // Exercise the actual AHB software-reset path and prove post-reset recovery.
        write_reg(1,1);repeat(15)@(negedge ahb_clk);
        read_check(0,0);read_check('h104,0);read_check('h101,0);
        mode=2;n=1;length=4;initial_seed=99;seed=99;run_job(1,0);
        for(int m=0;m<4;m++)for(int ni=0;ni<3;ni++)for(int li=0;li<3;li++)
            check(covered[m][ni][li],"mode/size/length coverage bin");
        $fclose(summary);
        $display("TOP_REGRESSION_PASS jobs=%0d checks=%0d arithmetic_lanes=%0d zero_lanes=%0d bins=36/36 random_seeds=10",jobs,checks,arithmetic_lanes,zero_lanes);
        $finish;
    end
    initial begin #20000000;$fatal(1,"global simulation timeout");end
endmodule
`default_nettype wire
