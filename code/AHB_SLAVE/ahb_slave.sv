`timescale 1ns/1ps
`default_nettype none

module ahb_slave (
    /* AHB-Lite bus interface */
    input  wire logic        ahb_clk,
    input  wire logic        tpu_rst_n,
    input  wire logic        hsel,
    input  wire logic [2:0]  hsize,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire logic [31:0] haddr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire logic [2:0]  hburst,
    input  wire logic [1:0]  htrans,
    input  wire logic        hwrite,
    input  wire logic [31:0] hwdata,
    input  wire logic        hreadyin,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire logic [3:0]  hprot,
    /* verilator lint_on UNUSEDSIGNAL */

    output logic        hready,
    output logic [31:0] hrdata,
    output logic        hresp,

    /* Internal register-map interface */
    input  wire logic [31:0] ahb_rd_data,
    /* 10-bit register word index: HADDR[11:2], not a byte offset. */
    output logic [9:0]  ahb_addr,
    output logic [31:0] ahb_wr_data,
    output logic        ahb_wr_en,
    output logic        ahb_rd_en
);

    localparam logic [1:0] HTRANS_NONSEQ = 2'b10;
    localparam logic [2:0] HSIZE_WORD     = 3'b010;
    localparam logic [2:0] HBURST_SINGLE  = 3'b000;

    /*
     * IDLE:            wait for HSEL; do not sample address/control
     * SAMPLE_ADDR_CTR: sample and validate address/control when HREADYIN is high
     * SAMPLE_DATA:     complete a write data phase and optionally capture the next request
     * SEND_DATA:       complete a read data phase and optionally capture the next request
     * ERROR_1:         first ERROR cycle, HREADY is low
     * ERROR_2:         second ERROR cycle, HREADY is high and ERROR completes
     */
    localparam logic [2:0] IDLE            = 3'b000;
    localparam logic [2:0] SAMPLE_ADDR_CTR = 3'b001;
    localparam logic [2:0] SAMPLE_DATA     = 3'b010;
    localparam logic [2:0] SEND_DATA       = 3'b011;
    localparam logic [2:0] ERROR_1         = 3'b100;
    localparam logic [2:0] ERROR_2         = 3'b101;

    logic [2:0] state;
    logic [2:0] next_state;

    /* Registered address/control information used by the data phase. */
    logic       legal_transfer_r;
    logic       hwrite_r;
    logic [9:0] haddr_r;

    logic address_control_valid;
    logic legal_transfer;

    function automatic logic address_is_mapped(input logic [9:0] word_address);
        begin
            /*
             * Register-map addresses are word indices. 0x009..0x018 is
             * the 16-entry PE data array; 0x100..0x104 is the report area (DONE RO).
             * 0x105 is the independent TPU clock-gating enable register.
             * 0x106 is the read-only independent error-flag report register.
             */
            address_is_mapped = (word_address <= 10'h018)
                             || ((word_address >= 10'h100)
                              && (word_address <= 10'h106));
        end
    endfunction

    /* HSEL only starts the controller. Address/control are accepted here later. */
    assign address_control_valid = hreadyin && htrans[1];
    assign legal_transfer        = address_control_valid
                                 && (htrans == HTRANS_NONSEQ)
                                 && (hsize == HSIZE_WORD)
                                 && (hburst == HBURST_SINGLE)
                                 && (haddr[1:0] == 2'b00)
                                 && address_is_mapped(haddr[11:2]);

    // State machine stage 1: state register and one-cycle request cache.
    always_ff @(posedge ahb_clk or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            state            <= IDLE;
            legal_transfer_r <= 1'b0;
            hwrite_r         <= 1'b0;
            haddr_r          <= 10'h000;
        end else begin
            state <= next_state;

            unique case (state)
                IDLE: begin
                    legal_transfer_r <= 1'b0;
                    hwrite_r         <= 1'b0;
                    haddr_r          <= 10'h000;
                end

                SAMPLE_ADDR_CTR: begin
                    legal_transfer_r <= 1'b0;
                    if (address_control_valid) begin
                        haddr_r          <= haddr[11:2];
                        hwrite_r         <= hwrite;
                        legal_transfer_r <= legal_transfer;
                    end
                end

                SAMPLE_DATA,
                SEND_DATA: begin
                    /*
                     * The old cache still drives the completing data phase at
                     * this edge. Non-blocking assignments below prepare only
                     * the following data phase, preserving write address/data
                     * pairing for back-to-back transfers.
                     */
                    legal_transfer_r <= 1'b0;
                    hwrite_r         <= 1'b0;
                    haddr_r          <= 10'h000;

                    if (hsel && address_control_valid) begin
                        haddr_r          <= haddr[11:2];
                        hwrite_r         <= hwrite;
                        legal_transfer_r <= legal_transfer;
                    end
                end

                ERROR_1,
                ERROR_2: begin
                    /* ERROR states never access the register map. */
                    legal_transfer_r <= 1'b0;
                    hwrite_r         <= 1'b0;
                    haddr_r          <= 10'h000;
                end

                default: begin
                    legal_transfer_r <= 1'b0;
                    hwrite_r         <= 1'b0;
                    haddr_r          <= 10'h000;
                end
            endcase
        end
    end

    // State machine stage 2: next-state logic.
    always_comb begin
        next_state = state;

        unique case (state)
            IDLE: begin
                if (hsel) begin
                    next_state = SAMPLE_ADDR_CTR;
                end
            end

            SAMPLE_ADDR_CTR: begin
                if (address_control_valid) begin
                    if (!legal_transfer) begin
                        next_state = ERROR_1;
                    end else if (hwrite) begin
                        next_state = SAMPLE_DATA;
                    end else begin
                        next_state = SEND_DATA;
                    end
                end
            end

            SAMPLE_DATA,
            SEND_DATA: begin
                if (hsel && address_control_valid) begin
                    if (!legal_transfer) begin
                        next_state = ERROR_1;
                    end else if (hwrite) begin
                        next_state = SAMPLE_DATA;
                    end else begin
                        next_state = SEND_DATA;
                    end
                end else begin
                    next_state = IDLE;
                end
            end

            ERROR_1: begin
                next_state = ERROR_2;
            end

            ERROR_2: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // State machine stage 3: response and register-map output logic.
    always_comb begin
        hready      = 1'b0;
        hresp       = 1'b0;
        hrdata      = 32'h0000_0000;
        ahb_addr    = haddr_r;
        ahb_wr_data = hwdata;
        ahb_wr_en   = 1'b0;
        ahb_rd_en   = 1'b0;

        unique case (state)
            IDLE: begin
                hready = 1'b0;
                hrdata = 32'h0000_0000;
            end

            SAMPLE_ADDR_CTR: begin
                hready = 1'b0;
            end

            SAMPLE_DATA: begin
                hready = 1'b1;
                if (legal_transfer_r && hwrite_r) begin
                    ahb_wr_en = 1'b1;
                end
            end

            SEND_DATA: begin
                hready = 1'b1;
                if (legal_transfer_r && !hwrite_r) begin
                    ahb_rd_en = 1'b1;
                    hrdata    = ahb_rd_data;
                end
            end

            ERROR_1: begin
                hready = 1'b0;
                hresp  = 1'b1;
            end

            ERROR_2: begin
                hready = 1'b1;
                hresp  = 1'b1;
            end

            default: begin
                hready = 1'b0;
            end
        endcase
    end

endmodule

`default_nettype wire
