`timescale 1ns/1ps
`default_nettype none

module reg_list (
    /* always-on: AHB configuration must remain accessible while TPU is gated. */
    input  wire logic        hclk,
    input  wire logic        hrstn,

    /* Word index HADDR[11:2]: 0x000, 0x001, ...; not byte offsets. */
    input  wire logic [9:0]  ahb_addr,
    input  wire logic [31:0] ahb_wr_data,
    input  wire logic        ahb_wr_en,
    input  wire logic        ahb_rd_en,
    output logic [31:0] ahb_rd_data,

    /* RW and write-one-pulse controls; all outputs are in hclk domain. */
    output logic        cpu_tpu_en,
    output logic        cpu_sw_rst,
    output logic        cpu_tpu_start,
    output logic        cpu_tpu_crg_bypass,
    output logic [3:0]  cpu_h_size,
    output logic [3:0]  cpu_w_size,
    output logic [1:0]  cpu_cpt_mode,
    output logic [3:0]  cpu_dat_in_b_sel,
    output logic        cpu_dat_in_b_lock,
    output logic        cpu_tpu_crg_en,
    output logic [511:0] cpu_dat_in_b,

    /* Read-only status must already be coherent in hclk domain. */
    input  wire logic [31:0] rpt_active_size,
    input  wire logic [31:0] rpt_cpt_cyc,
    input  wire logic [31:0] rpt_dat_in_cnt,
    /* Independent error flag, read at word0x106 (byte offset0x418). */
    input  wire logic        rpt_error,
    /* rpt_error_state: read-only 3-bit error count, provided by CTRL. */
    input  wire logic [2:0]  rpt_error_state,
    input  wire logic        rpt_cpt_done
);

    localparam logic [9:0] ADDR_TPU_EN          = 10'h000;
    localparam logic [9:0] ADDR_TPU_SW_RST      = 10'h001;
    localparam logic [9:0] ADDR_TPU_START       = 10'h002;
    localparam logic [9:0] ADDR_TPU_CKG_BYPASS  = 10'h003;
    localparam logic [9:0] ADDR_PE_ARRAY_H      = 10'h004;
    localparam logic [9:0] ADDR_PE_ARRAY_W      = 10'h005;
    localparam logic [9:0] ADDR_CPT_MODE        = 10'h006;
    localparam logic [9:0] ADDR_DAT_IN_B_SEL    = 10'h007;
    localparam logic [9:0] ADDR_DAT_IN_B_LOCK   = 10'h008;
    localparam logic [9:0] ADDR_DAT_IN_B_0      = 10'h009;
    localparam logic [9:0] ADDR_DAT_IN_B_1      = 10'h00a;
    localparam logic [9:0] ADDR_DAT_IN_B_2      = 10'h00b;
    localparam logic [9:0] ADDR_DAT_IN_B_3      = 10'h00c;
    localparam logic [9:0] ADDR_DAT_IN_B_4      = 10'h00d;
    localparam logic [9:0] ADDR_DAT_IN_B_5      = 10'h00e;
    localparam logic [9:0] ADDR_DAT_IN_B_6      = 10'h00f;
    localparam logic [9:0] ADDR_DAT_IN_B_7      = 10'h010;
    localparam logic [9:0] ADDR_DAT_IN_B_8      = 10'h011;
    localparam logic [9:0] ADDR_DAT_IN_B_9      = 10'h012;
    localparam logic [9:0] ADDR_DAT_IN_B_10     = 10'h013;
    localparam logic [9:0] ADDR_DAT_IN_B_11     = 10'h014;
    localparam logic [9:0] ADDR_DAT_IN_B_12     = 10'h015;
    localparam logic [9:0] ADDR_DAT_IN_B_13     = 10'h016;
    localparam logic [9:0] ADDR_DAT_IN_B_14     = 10'h017;
    localparam logic [9:0] ADDR_DAT_IN_B_15     = 10'h018;
    localparam logic [9:0] ADDR_RPT_ACTIVE_SIZE = 10'h100;
    localparam logic [9:0] ADDR_RPT_CPT_CYC     = 10'h101;
    localparam logic [9:0] ADDR_RPT_DAT_IN_CNT  = 10'h102;
    localparam logic [9:0] ADDR_RPT_ERROR_STATE = 10'h103;
    localparam logic [9:0] ADDR_RPT_DONE        = 10'h104;
    localparam logic [9:0] ADDR_TPU_CRG_EN      = 10'h105;
    localparam logic [9:0] ADDR_RPT_ERROR       = 10'h106;

    // DONE is read-only; writes to ADDR_RPT_DONE are ignored.

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_tpu_en <= 1'b0;
        end else if (ahb_wr_en && (ahb_addr == ADDR_TPU_EN)) begin
            cpu_tpu_en <= ahb_wr_data[0];
        end
    end

    /* W1P: accepted write1 asserts for this AHB cycle; reads return zero. */
    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_sw_rst <= 1'b0;
        end else if (ahb_wr_en && (ahb_addr == ADDR_TPU_SW_RST)) begin
            cpu_sw_rst <= ahb_wr_data[0];
        end else begin
            cpu_sw_rst <= 1'b0;
        end
    end

    /* W1P: accepted write1 asserts for this AHB cycle; reads return zero. */
    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_tpu_start <= 1'b0;
        end else if (ahb_wr_en && (ahb_addr == ADDR_TPU_START)) begin
            cpu_tpu_start <= ahb_wr_data[0];
        end else begin
            cpu_tpu_start <= 1'b0;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_tpu_crg_bypass <= 1'b0;
        end else if (ahb_wr_en && (ahb_addr == ADDR_TPU_CKG_BYPASS)) begin
            cpu_tpu_crg_bypass <= ahb_wr_data[0];
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_h_size <= 4'd3;
        end else if (ahb_wr_en && (ahb_addr == ADDR_PE_ARRAY_H)) begin
            cpu_h_size <= ahb_wr_data[3:0];
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_w_size <= 4'd3;
        end else if (ahb_wr_en && (ahb_addr == ADDR_PE_ARRAY_W)) begin
            cpu_w_size <= ahb_wr_data[3:0];
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_cpt_mode <= 2'd0;
        end else if (ahb_wr_en && (ahb_addr == ADDR_CPT_MODE)) begin
            cpu_cpt_mode <= ahb_wr_data[1:0];
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b_sel <= 4'd0;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_SEL)) begin
            cpu_dat_in_b_sel <= ahb_wr_data[3:0];
        end
    end

    /* W1P: accepted write1 asserts for this AHB cycle; reads return zero. */
    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b_lock <= 1'b0;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_LOCK)) begin
            cpu_dat_in_b_lock <= ahb_wr_data[0];
        end else begin
            cpu_dat_in_b_lock <= 1'b0;
        end
    end

    /* Independent clock-gating request; do not alias cpu_tpu_en. */
    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_tpu_crg_en <= 1'b0;
        end else if (ahb_wr_en && (ahb_addr == ADDR_TPU_CRG_EN)) begin
            cpu_tpu_crg_en <= ahb_wr_data[0];
        end
    end

    /* PE index0 is low32 bits; index15 is high32 bits of the 512-bit bus. */
    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[31:0] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_0)) begin
            cpu_dat_in_b[31:0] <= ahb_wr_data;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[63:32] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_1)) begin
            cpu_dat_in_b[63:32] <= ahb_wr_data;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[95:64] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_2)) begin
            cpu_dat_in_b[95:64] <= ahb_wr_data;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[127:96] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_3)) begin
            cpu_dat_in_b[127:96] <= ahb_wr_data;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[159:128] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_4)) begin
            cpu_dat_in_b[159:128] <= ahb_wr_data;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[191:160] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_5)) begin
            cpu_dat_in_b[191:160] <= ahb_wr_data;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[223:192] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_6)) begin
            cpu_dat_in_b[223:192] <= ahb_wr_data;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[255:224] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_7)) begin
            cpu_dat_in_b[255:224] <= ahb_wr_data;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[287:256] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_8)) begin
            cpu_dat_in_b[287:256] <= ahb_wr_data;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[319:288] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_9)) begin
            cpu_dat_in_b[319:288] <= ahb_wr_data;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[351:320] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_10)) begin
            cpu_dat_in_b[351:320] <= ahb_wr_data;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[383:352] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_11)) begin
            cpu_dat_in_b[383:352] <= ahb_wr_data;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[415:384] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_12)) begin
            cpu_dat_in_b[415:384] <= ahb_wr_data;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[447:416] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_13)) begin
            cpu_dat_in_b[447:416] <= ahb_wr_data;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[479:448] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_14)) begin
            cpu_dat_in_b[479:448] <= ahb_wr_data;
        end
    end

    always_ff @(posedge hclk or negedge hrstn) begin
        if (!hrstn) begin
            cpu_dat_in_b[511:480] <= 32'h0000_0000;
        end else if (ahb_wr_en && (ahb_addr == ADDR_DAT_IN_B_15)) begin
            cpu_dat_in_b[511:480] <= ahb_wr_data;
        end
    end

    always_comb begin
        ahb_rd_data = 32'h0000_0000;

        if (ahb_rd_en) begin
            unique case (ahb_addr)
                ADDR_TPU_EN:          ahb_rd_data = {31'b0, cpu_tpu_en};
                ADDR_TPU_SW_RST:      ahb_rd_data = 32'h0000_0000;
                ADDR_TPU_START:       ahb_rd_data = 32'h0000_0000;
                ADDR_TPU_CKG_BYPASS:  ahb_rd_data = {31'b0, cpu_tpu_crg_bypass};
                ADDR_PE_ARRAY_H:      ahb_rd_data = {28'b0, cpu_h_size};
                ADDR_PE_ARRAY_W:      ahb_rd_data = {28'b0, cpu_w_size};
                ADDR_CPT_MODE:        ahb_rd_data = {30'b0, cpu_cpt_mode};
                ADDR_DAT_IN_B_SEL:    ahb_rd_data = {28'b0, cpu_dat_in_b_sel};
                ADDR_DAT_IN_B_LOCK:   ahb_rd_data = 32'h0000_0000;
                ADDR_DAT_IN_B_0:      ahb_rd_data = cpu_dat_in_b[31:0];
                ADDR_DAT_IN_B_1:      ahb_rd_data = cpu_dat_in_b[63:32];
                ADDR_DAT_IN_B_2:      ahb_rd_data = cpu_dat_in_b[95:64];
                ADDR_DAT_IN_B_3:      ahb_rd_data = cpu_dat_in_b[127:96];
                ADDR_DAT_IN_B_4:      ahb_rd_data = cpu_dat_in_b[159:128];
                ADDR_DAT_IN_B_5:      ahb_rd_data = cpu_dat_in_b[191:160];
                ADDR_DAT_IN_B_6:      ahb_rd_data = cpu_dat_in_b[223:192];
                ADDR_DAT_IN_B_7:      ahb_rd_data = cpu_dat_in_b[255:224];
                ADDR_DAT_IN_B_8:      ahb_rd_data = cpu_dat_in_b[287:256];
                ADDR_DAT_IN_B_9:      ahb_rd_data = cpu_dat_in_b[319:288];
                ADDR_DAT_IN_B_10:     ahb_rd_data = cpu_dat_in_b[351:320];
                ADDR_DAT_IN_B_11:     ahb_rd_data = cpu_dat_in_b[383:352];
                ADDR_DAT_IN_B_12:     ahb_rd_data = cpu_dat_in_b[415:384];
                ADDR_DAT_IN_B_13:     ahb_rd_data = cpu_dat_in_b[447:416];
                ADDR_DAT_IN_B_14:     ahb_rd_data = cpu_dat_in_b[479:448];
                ADDR_DAT_IN_B_15:     ahb_rd_data = cpu_dat_in_b[511:480];
                ADDR_RPT_ACTIVE_SIZE: ahb_rd_data = rpt_active_size;
                ADDR_RPT_CPT_CYC:     ahb_rd_data = rpt_cpt_cyc;
                ADDR_RPT_DAT_IN_CNT:  ahb_rd_data = rpt_dat_in_cnt;
                ADDR_RPT_ERROR_STATE: ahb_rd_data = {29'b0, rpt_error_state};
                ADDR_RPT_DONE:        ahb_rd_data = {31'b0, rpt_cpt_done};
                ADDR_TPU_CRG_EN:      ahb_rd_data = {31'b0, cpu_tpu_crg_en};
                ADDR_RPT_ERROR:       ahb_rd_data = {31'b0, rpt_error};
                default:             ahb_rd_data = 32'h0000_0000;
            endcase
        end
    end

endmodule

`default_nettype wire
