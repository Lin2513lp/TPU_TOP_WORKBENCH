`timescale 1ns/1ps
`default_nettype none

// PE_MP_v1
// cpt_mode:
//   2'b00: INT4
//   2'b01: INT8
//   2'b10: FP16
//   2'b11: FP32
//
// dat_in_add is controlled and aligned by the external module. This PE does
// not delay dat_in_add internally; it accumulates when the selected product
// valid is high, assuming dat_in_add is already aligned to that valid.
module PE_MP_v1 #(
    parameter DATA_WIDTH = 32,
    parameter MODE_WIDTH = 2
)(
    input  wire                  pe_ckg,
    input  wire                  tpu_rst_n,

    input  wire                  pe_en,
    input  wire [DATA_WIDTH-1:0] dat_in_b,
    input  wire                  in_b_lock,
    input  wire [MODE_WIDTH-1:0] cpt_mode,

    input  wire [DATA_WIDTH-1:0] dat_in_a,
    input  wire                  dat_in_vld,
    input  wire [DATA_WIDTH-1:0] dat_in_add,
    input  wire                  dat_in_add_vld,

    output wire [DATA_WIDTH-1:0] dat_out,
    output wire                  dat_out_vld,
    output wire [DATA_WIDTH-1:0] out_a,
    output wire                  out_a_vld
);

    localparam MODE_INT4 = 2'b00;
    localparam MODE_INT8 = 2'b01;
    localparam MODE_FP16 = 2'b10;
    localparam MODE_FP32 = 2'b11;

    reg [DATA_WIDTH-1:0] b_reg;

    // Keep the stationary B operand while PE is enabled. The lock pulse has
    // priority so software/control logic can preload B even when pe_en is low.
    always @(posedge pe_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            b_reg <= {DATA_WIDTH{1'b0}};
        end
        else if (in_b_lock) begin
            b_reg <= dat_in_b;
        end
        else if (!pe_en) begin
            b_reg <= {DATA_WIDTH{1'b0}};
        end
    end

    // One-hot mode enables. Each datapath also gates its input valid with the
    // selected mode so inactive paths stay cleared.
    wire enable_INT4 = pe_en && (cpt_mode == MODE_INT4);
    wire enable_INT8 = pe_en && (cpt_mode == MODE_INT8);
    wire enable_FP16 = pe_en && (cpt_mode == MODE_FP16);
    wire enable_FP32 = pe_en && (cpt_mode == MODE_FP32);

    wire int4_data_in_vld = enable_INT4 && dat_in_vld;
    wire int8_data_in_vld = enable_INT8 && dat_in_vld;
    wire fp16_data_in_vld = enable_FP16 && dat_in_vld;
    wire fp32_data_in_vld = enable_FP32 && dat_in_vld;

    reg [DATA_WIDTH-1:0] out_a_temp;
    reg                  out_a_vld_temp;

    // Forward A to the next PE only when this PE is active. When pe_en is low,
    // the inactive PE passes dat_in_add to dat_out and keeps out_a invalid.
    always @(posedge pe_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            out_a_temp     <= {DATA_WIDTH{1'b0}};
            out_a_vld_temp <= 1'b0;
        end
        else if (!pe_en) begin
            out_a_temp     <= {DATA_WIDTH{1'b0}};
            out_a_vld_temp <= 1'b0;
        end
        else begin
            out_a_temp     <= dat_in_a;
            out_a_vld_temp <= dat_in_vld;
        end
    end

    assign out_a     = out_a_temp;
    assign out_a_vld = out_a_vld_temp;

    // ============================= INT4 PATH =============================

    wire [31:0] int4_data_in_a;
    wire [31:0] int4_data_in_b;
    wire [31:0] int4_data_in_add;
    wire [31:0] int4_muti_out;
    reg  [31:0] int4_sum_out;
    reg         int4_sum_vld;

    // INT4 follows the reference template: the input is already provided as a
    // 32-bit signed value by upstream logic, so no local sign extension is done.
    assign int4_data_in_a   = dat_in_a;
    assign int4_data_in_b   = b_reg;
    assign int4_data_in_add = dat_in_add;
    assign int4_muti_out    = $signed(int4_data_in_a) * $signed(int4_data_in_b);

    // Integer modes are single-cycle MAC paths. dat_in_add is expected to be
    // aligned with dat_in_vld, so no extra dat_in_add_vld gate is needed here.
    always @(posedge pe_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            int4_sum_out <= 32'd0;
        end
        else if (!enable_INT4) begin
            int4_sum_out <= 32'd0;
        end
        else if (int4_data_in_vld) begin
            int4_sum_out <= $signed(int4_muti_out) + $signed(int4_data_in_add);
        end
    end

    always @(posedge pe_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            int4_sum_vld <= 1'b0;
        end
        else if (!enable_INT4) begin
            int4_sum_vld <= 1'b0;
        end
        else begin
            int4_sum_vld <= int4_data_in_vld;
        end
    end

    wire [31:0] int4_out     = int4_sum_out;
    wire        int4_out_vld = int4_sum_vld;

    // ============================= INT8 PATH =============================

    wire [31:0] int8_data_in_a;
    wire [31:0] int8_data_in_b;
    wire [31:0] int8_data_in_add;
    wire [31:0] int8_muti_out;
    reg  [31:0] int8_sum_out;
    reg         int8_sum_vld;

    // INT8 follows the reference template: the input is already provided as a
    // 32-bit signed value by upstream logic, so no local sign extension is done.
    assign int8_data_in_a   = dat_in_a;
    assign int8_data_in_b   = b_reg;
    assign int8_data_in_add = dat_in_add;
    assign int8_muti_out    = $signed(int8_data_in_a) * $signed(int8_data_in_b);

    always @(posedge pe_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            int8_sum_out <= 32'd0;
        end
        else if (!enable_INT8) begin
            int8_sum_out <= 32'd0;
        end
        else if (int8_data_in_vld) begin
            int8_sum_out <= $signed(int8_muti_out) + $signed(int8_data_in_add);
        end
    end

    always @(posedge pe_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            int8_sum_vld <= 1'b0;
        end
        else if (!enable_INT8) begin
            int8_sum_vld <= 1'b0;
        end
        else begin
            int8_sum_vld <= int8_data_in_vld;
        end
    end

    wire [31:0] int8_out     = int8_sum_out;
    wire        int8_out_vld = int8_sum_vld;

    // ============================= FP32 PATH =============================

    wire [31:0] fp32_multiply_out;
    wire        fp32_muti_vld;
    wire [31:0] fp32_adder_out;
    reg  [31:0] fp32_out;
    reg         fp32_out_vld;

    FP32_MUTI U_FP32_MUTI (
        .clk         (pe_ckg),
        .rst_n       (tpu_rst_n),
        .vld_in      (fp32_data_in_vld),
        .cpt_en      (pe_en),
        .a           (dat_in_a),
        .b           (b_reg),
        .vld_out     (fp32_muti_vld),
        .out         (fp32_multiply_out),
        .out_is_zero (),
        .out_is_inf  (),
        .out_is_nan  (),
        .out_is_of   (),
        .out_is_uf   ()
    );

    FP32_ADDER U_FP32_ADDER_FP32 (
        .src1 (fp32_multiply_out),
        .src2 (dat_in_add),
        .out  (fp32_adder_out)
    );

    // The FP32 multiplier owns its internal latency. The external controller
    // must present dat_in_add when fp32_muti_vld is asserted.
    always @(posedge pe_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            fp32_out     <= 32'd0;
            fp32_out_vld <= 1'b0;
        end
        else if (!enable_FP32) begin
            fp32_out     <= 32'd0;
            fp32_out_vld <= 1'b0;
        end
        else begin
            fp32_out_vld <= fp32_muti_vld;
            if (fp32_muti_vld) begin
                fp32_out <= fp32_adder_out;
            end
        end
    end

    // ============================= FP16 PATH =============================

    wire signed [15:0] fp16_fix_a;
    wire signed [15:0] fp16_fix_b;
    wire               fp16_fix_a_vld;
    wire               fp16_fix_b_vld;
    wire signed [31:0] fp16_muti_out;
    wire               fp16_muti_vld;
    wire [31:0]        fp16_fix2fp_out;
    wire               fp16_fix2fp_out_vld;
    wire [31:0]        fp16_adder_out;
    reg  [31:0]        fp16_out;
    reg                fp16_out_vld;

    // FP16 path follows the reference architecture:
    // FP16 A/B -> signed INT16 -> integer multiply -> FP32 -> FP32 add.
    FP2FIX U_FP2FIX_A (
        .clk       (pe_ckg),
        .rst_n     (tpu_rst_n),
        .en        (pe_en),
        .vld_in    (fp16_data_in_vld),
        .data_in   (dat_in_a[15:0]),
        .data_out  (fp16_fix_a),
        .overflow  (),
        .underflow (),
        .vld_out   (fp16_fix_a_vld)
    );

    FP2FIX U_FP2FIX_B (
        .clk       (pe_ckg),
        .rst_n     (tpu_rst_n),
        .en        (pe_en),
        .vld_in    (fp16_data_in_vld),
        .data_in   (b_reg[15:0]),
        .data_out  (fp16_fix_b),
        .overflow  (),
        .underflow (),
        .vld_out   (fp16_fix_b_vld)
    );

    // Both FP2FIX instances must finish before the integer product is accepted.
    assign fp16_muti_out = $signed(fp16_fix_a) * $signed(fp16_fix_b);
    assign fp16_muti_vld = fp16_fix_a_vld && fp16_fix_b_vld;

    FIX2FP U_FIX2FP_FP16 (
        .clk      (pe_ckg),
        .rst_n    (tpu_rst_n),
        .en       (pe_en),
        .vld_in   (fp16_muti_vld),
        .data_in  (fp16_muti_out),
        .vld_out  (fp16_fix2fp_out_vld),
        .data_out (fp16_fix2fp_out)
    );

    FP32_ADDER U_FP32_ADDER_FP16 (
        .src1 (fp16_fix2fp_out),
        .src2 (dat_in_add),
        .out  (fp16_adder_out)
    );

    // As with FP32, dat_in_add is externally aligned to the converted product
    // valid. The PE captures the add result when the product valid is high.
    always @(posedge pe_ckg or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            fp16_out     <= 32'd0;
            fp16_out_vld <= 1'b0;
        end
        else if (!enable_FP16) begin
            fp16_out     <= 32'd0;
            fp16_out_vld <= 1'b0;
        end
        else begin
            fp16_out_vld <= fp16_fix2fp_out_vld;
            if (fp16_fix2fp_out_vld) begin
                fp16_out <= fp16_adder_out;
            end
        end
    end

    // ============================= Output Select =============================

    // Only one mode should be active at a time. The priority mux is defensive
    // and returns zero when no datapath has a valid result.
    wire [31:0] calc_dat_out =
        fp16_out_vld ? fp16_out :
        fp32_out_vld ? fp32_out :
        int8_out_vld ? int8_out :
        int4_out_vld ? int4_out :
                       32'd0;

    wire calc_dat_out_vld = fp16_out_vld |
                            fp32_out_vld |
                            int8_out_vld |
                            int4_out_vld;

    assign dat_out     = pe_en ? calc_dat_out     : dat_in_add;
    assign dat_out_vld = pe_en ? calc_dat_out_vld : dat_in_add_vld;

endmodule

`default_nettype wire
