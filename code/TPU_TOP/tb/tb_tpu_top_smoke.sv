`timescale 1ns/1ps
`default_nettype none

// A short, fully self-checking teaching waveform of the real integrated TOP.
// One INT8 4x4 task: A[k,r]=(k+1)*(r+1), B[r,c]=r+c+1.
// Therefore C[k,c]=(k+1)*(30+10*c), independently of DUT internals.
module tb_tpu_top_smoke;
    // All 36 external ports are explicitly named for the Verdi waveform.
    // Clock/reset/DFT: 6 ports.
    logic sys_clk=0,ahb_clk=0;
    always #1.25 sys_clk=~sys_clk;
    always #5 ahb_clk=~ahb_clk;
    logic sys_rst_n=0,dft_glb_gt_se=0,dft_mode=0,dft_lgc_rst_n=1;
    // AHB-Lite: 12 ports.
    logic hsel=0,hwrite=0,hreadyin=1;
    logic [2:0] hsize=3'b010,hburst=3'b000;
    logic [31:0] haddr=0,hwdata=0;
    logic [1:0] htrans=2'b00;
    logic [3:0] hprot=0;
    wire hready,hresp;
    wire [31:0] hrdata;
    // Input AXI stream: 9 ports.
    logic rd_tvalid=0,rd_tlast=0,rd_tid=0,rd_tdest=0,rd_tuser=0;
    logic [511:0] rd_tdata=0;
    logic [63:0] rd_tkeep='1,rd_tstrb='1;
    wire rd_tready;
    // Output AXI stream: 9 ports.
    logic wr_tready=1;
    wire wr_tvalid,wr_tlast,wr_tid,wr_tdest,wr_tuser;
    wire [511:0] wr_tdata;
    wire [63:0] wr_tkeep,wr_tstrb;
    tpu_top dut (
        .sys_clk(sys_clk),
        .ahb_clk(ahb_clk),
        .sys_rst_n(sys_rst_n),
        .dft_glb_gt_se(dft_glb_gt_se),
        .dft_mode(dft_mode),
        .dft_lgc_rst_n(dft_lgc_rst_n),
        .hsel(hsel),
        .hsize(hsize),
        .haddr(haddr),
        .hburst(hburst),
        .htrans(htrans),
        .hwrite(hwrite),
        .hwdata(hwdata),
        .hreadyin(hreadyin),
        .hprot(hprot),
        .hready(hready),
        .hrdata(hrdata),
        .hresp(hresp),
        .rd_tready(rd_tready),
        .rd_tvalid(rd_tvalid),
        .rd_tdata(rd_tdata),
        .rd_tkeep(rd_tkeep),
        .rd_tstrb(rd_tstrb),
        .rd_tlast(rd_tlast),
        .rd_tid(rd_tid),
        .rd_tdest(rd_tdest),
        .rd_tuser(rd_tuser),
        .wr_tready(wr_tready),
        .wr_tvalid(wr_tvalid),
        .wr_tdata(wr_tdata),
        .wr_tkeep(wr_tkeep),
        .wr_tstrb(wr_tstrb),
        .wr_tlast(wr_tlast),
        .wr_tid(wr_tid),
        .wr_tdest(wr_tdest),
        .wr_tuser(wr_tuser)
    );

    // phase: 0 reset, 1 config, 2 weights, 3 START, 4 RX/compute,
    // 5 poll DONE, 6 report reads, 7 W1C, 8 complete.
    logic [3:0] phase=0;
    int checks=0,rx_count=0,tx_count=0,tx_lasts=0,start_pulses=0;
    int arithmetic_lanes=0,start_accepts=0;
    bit observing=0,compute_seen=0,done_seen=0,start_prev=0;
    time t_start=0,t_rx_first=0,t_rx_last=0,t_tx_first=0,t_tx_last=0,t_cpu_done=0,t_w1c=0;
    logic [31:0] cpu_done_read=0;
    logic [511:0] expected_bus;
    string fsdb_file="waves/tpu_top_smoke.fsdb";
    string vcd_file="waves/tpu_top_smoke.vcd";

`ifdef FSDB_TRACE
    initial begin
        if($value$plusargs("FSDB_FILE=%s",fsdb_file))begin end
        $fsdbDumpfile(fsdb_file);
        $fsdbDumpvars(0,tb_tpu_top_smoke);
    end
`endif
`ifdef VCD_TRACE
    initial begin
        if($value$plusargs("VCD_FILE=%s",vcd_file))begin end
        $dumpfile(vcd_file);
        $dumpvars(0,tb_tpu_top_smoke);
    end
`endif

    task automatic check(input bit ok,input string label);
        checks++;
        if(!ok)$fatal(1,"TPU_TOP_SMOKE_FAIL %s at %0t",label,$time);
    endtask

    // Existing slave: IDLE wake, address capture, then data completion.
    // HADDR is a byte address; the helper argument is a register word index.
    task automatic ahb_transfer(input bit write_access,input int word_address,
                                input logic[31:0] data,output logic[31:0] value);
        @(negedge ahb_clk);
        hsel=1;htrans=2'b10;haddr=32'(word_address*4);hwrite=write_access;hwdata=data;
        @(posedge ahb_clk);@(posedge ahb_clk);#0.1;
        check(hready&&!hresp,"legal AHB word transfer");value=hrdata;
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
        check(actual===expected,$sformatf("AHB word%03h got%08h expected%08h",address,actual,expected));
    endtask

    function automatic logic[511:0] output_oracle(input int beat);
        logic[511:0] result;
        int k,sum;
        result='0;
        for(int c=0;c<4;c++)begin
            k=beat-c;
            if(k>=0&&k<4)begin
                sum=0;
                // Dot product from the original stimulus equations only.
                for(int r=0;r<4;r++)sum+=(k+1)*(r+1)*(r+c+1);
                result[c*32+:32]=32'(sum);
            end
        end
        return result;
    endfunction

    always @(posedge dut.sys_ckg)if(observing)begin
        // Existing CTRL synchronizes the AHB W1P level: it can span several
        // SYS cycles. Count its rising edge and actual task acceptance once.
        if(dut.cpu_tpu_start_sync&&!start_prev)begin start_pulses++;compute_seen=0;end
        start_prev=dut.cpu_tpu_start_sync;
        if(dut.u_ctrl.start_accept)start_accepts++;
        if(!dut.cpu_tpu_start_sync&&dut.compute_done_sys)compute_seen=1;
        if(rd_tvalid&&rd_tready)begin
            if(rx_count==0)t_rx_first=$time;
            rx_count++;
            if(rd_tlast)t_rx_last=$time;
        end
        if(wr_tvalid&&wr_tready)begin
            if(tx_count==0)t_tx_first=$time;
            check(tx_count<7,"no excess output beat");
            expected_bus=output_oracle(tx_count);
            check(wr_tdata===expected_bus,$sformatf("full512 independent arithmetic beat%0d got%0128h expected%0128h",tx_count,wr_tdata,expected_bus));
            check(wr_tlast===(tx_count==6),"only seventh output beat carries LAST");
            check(wr_tkeep==='1&&wr_tstrb==='1,"all output bytes valid");
            check({wr_tid,wr_tdest,wr_tuser}===3'b000,"INT8 output sidebands");
            for(int c=0;c<4;c++)if(tx_count>=c&&tx_count-c<4)arithmetic_lanes++;
            $display("SMOKE_TX time=%0t beat=%0d lane0=%0d lane1=%0d lane2=%0d lane3=%0d last=%0b",
                     $time,tx_count,wr_tdata[31:0],wr_tdata[63:32],wr_tdata[95:64],wr_tdata[127:96],wr_tlast);
            tx_count++;
            if(wr_tlast)begin tx_lasts++;t_tx_last=$time;end
        end
    end
    always @(posedge ahb_clk)begin
        #0.2;
        if(observing&&dut.u_reg.rpt_cpt_done&&!done_seen)begin
            done_seen=1;t_cpu_done=$time;
            // The direct CTRL DONE can be visible after NBA before the next
            // SYS monitor sample; include the actual completion source.
            check((compute_seen||dut.u_ctrl.rpt_cpt_done)&&tx_lasts==1,
                  "smoke DONE follows compute and accepted TX LAST");
            check(dut.u_reg.rpt_active_size===32'h00040004&&
                  dut.u_reg.rpt_cpt_cyc===32'd7&&dut.u_reg.rpt_dat_in_cnt===32'd4&&
                  dut.u_reg.rpt_error===1'b0&&dut.u_reg.rpt_error_state===3'd0,
                  "direct report inputs have expected smoke values at DONE");
            $display("SMOKE_CPU_DONE time=%0t active=00040004 tx_count=7 input_count=4 errors=0",$time);
        end
    end

    initial begin
        $timeformat(-9,2," ns",10);
        $display("SMOKE_PHASE RESET time=%0t",$time);
        repeat(5)@(negedge ahb_clk);sys_rst_n=1;
        repeat(10)@(negedge ahb_clk);
        read_check('h104,0);
        phase=1;$display("SMOKE_PHASE CONFIG time=%0t",$time);
        // Gates are closed from reset; size is encoded as dimension minus one.
        write_reg(4,3);write_reg(5,3);write_reg(6,1);write_reg(0,1);write_reg('h105,1);
        read_check(6,1);
        phase=2;$display("SMOKE_PHASE WEIGHTS time=%0t",$time);
        for(int r=0;r<4;r++)begin
            write_reg(7,32'(r));
            // Only active columns need writes. Inactive register words retain reset0.
            for(int c=0;c<4;c++)write_reg(9+c,32'(r+c+1));
            write_reg(8,1);
            #200; // Documented software delay, independent of private pending flags.
            $display("SMOKE_WEIGHT_ROW_LOADED row=%0d time=%0t",r,$time);
        end
        read_check(9,4);read_check(12,7);
        phase=3;observing=1;t_start=$time;
        $display("SMOKE_PHASE START time=%0t",$time);write_reg(2,1);
        #200;
        phase=4;$display("SMOKE_PHASE RX time=%0t",$time);
        @(negedge sys_clk);rd_tvalid=1;
        for(int k=0;k<4;k++)begin
            rd_tdata='0;
            for(int r=0;r<4;r++)rd_tdata[r*32+:32]=32'((k+1)*(r+1));
            rd_tlast=(k==3);
            do @(posedge sys_clk);while(!rd_tready);
            @(negedge sys_clk);
        end
        rd_tvalid=0;rd_tlast=0;rd_tdata=0;
        phase=5;$display("SMOKE_PHASE POLL_DONE time=%0t",$time);
        for(int poll=0;poll<100;poll++)begin
            ahb_transfer(0,'h104,0,cpu_done_read);
            if(cpu_done_read==1)break;
        end
        check(cpu_done_read===1,"AHB polling observed CPU DONE");
        phase=6;$display("SMOKE_PHASE REPORT_READS time=%0t",$time);
        read_check('h100,'h00040004);read_check('h101,7);read_check('h102,4);
        read_check('h103,0);read_check('h106,0);read_check('h104,1);
        #100;read_check('h104,1);
        check(rx_count==4&&tx_count==7&&tx_lasts==1,"exact RX/TX counts and one LAST");
        check(start_pulses==1&&arithmetic_lanes==16,"one SYS START edge and16 independently checked result lanes");
        check(start_accepts==1,"CTRL accepts exactly one task from synchronized START");
        phase=7;t_w1c=$time;$display("SMOKE_PHASE W1C time=%0t",$time);
        write_reg('h104,1);#200;
        read_check('h104,0);read_check('h100,'h00040004);read_check('h101,7);read_check('h102,4);
        check(dut.u_reg.cpu_done_clear_req===dut.u_reg.done_clear_ack&&
              dut.u_reg.cpu_done_clear_req===dut.u_reg.done_clear_ack_sync_q,
              "W1C request processed by CTRL and acknowledgment synchronized in reg_list");
        observing=0;phase=8;
        write_reg('h105,0);#100;
        check(!dut.sys_ckg,"SYS clock closes after completed work and clear");
        $display("SMOKE_TIMES start=%0t rx_first=%0t rx_last=%0t tx_first=%0t tx_last=%0t cpu_done=%0t w1c=%0t",
                 t_start,t_rx_first,t_rx_last,t_tx_first,t_tx_last,t_cpu_done,t_w1c);
        $display("TPU_TOP_SMOKE_PASS checks=%0d rx_beats=%0d tx_beats=%0d arithmetic_lanes=%0d start_edges=%0d start_accepts=%0d",
                 checks,rx_count,tx_count,arithmetic_lanes,start_pulses,start_accepts);
        #50;$finish;
    end
    initial begin #20000;$fatal(1,"TPU_TOP_SMOKE_FAIL global timeout");end
endmodule
`default_nettype wire
