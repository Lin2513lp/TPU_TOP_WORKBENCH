module FP2FIX
(
    input wire                 clk,
    input wire                 rst_n,          // Active low reset
    input wire                 en,             // enable
    input wire                 vld_in,         // input valid
    input wire [15:0]          data_in,

    output reg signed [15:0]   data_out,
    output reg                 overflow,
    output reg                 underflow,
    output reg                 vld_out
);


// ==================== signal inst ==================== //

    reg         is_zero_flag;
    reg         is_zero_flag_reg;
    wire [10:0] f_bits;
    wire        s_bits;
    wire [4:0]  e_bits;
    reg  [10:0] f_bits_reg;

    wire [5:0]  real_e;
    reg  [5:0]  shift_bits;
    reg  [5:0]  shift_bits_reg;

    reg         overflow_pre1;
    reg         overflow_pre2;
    reg         underflow_pre1;
    reg         underflow_pre2;

    reg  [15:0] f_shift;
    reg  [15:0] f_round;

    reg         s_bits_1d;
    reg         s_bits_2d;

    reg         vld_in_1d;
    reg         vld_in_2d;
    reg  [15:0] data_out_temp;

// ==================== data_in proc ==================== //

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            is_zero_flag     <= 1'b0;
            is_zero_flag_reg <= 1'b0;
        end
        else if (en == 1'b0) begin
            is_zero_flag     <= 1'b0;
            is_zero_flag_reg <= 1'b0;
        end
        else if ((vld_in || vld_in_1d || vld_in_2d) && (data_in[14:0] == 15'h000)) begin
            is_zero_flag     <= 1'b1;
            is_zero_flag_reg <= is_zero_flag;
        end
        else begin
            is_zero_flag     <= 1'b0;
            is_zero_flag_reg <= is_zero_flag;
        end
    end

    assign s_bits = (vld_in || vld_in_1d || vld_in_2d) ? data_in[15]    : 1'b0;
    assign e_bits = (vld_in || vld_in_1d || vld_in_2d) ? data_in[14:10] : 5'b0;
    assign f_bits = (vld_in || vld_in_1d || vld_in_2d) ? {1'b1,data_in[9:0]} : 11'b0;       // data gating for low power

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_bits_1d <= 1'b0;
            s_bits_2d <= 1'b0;
            vld_in_1d <= 1'b0;
            vld_in_2d <= 1'b0;
            vld_out   <= 1'b0;
            f_bits_reg <= 11'b0;
        end
        else if (en == 1'b0) begin
            s_bits_1d <= 1'b0;
            s_bits_2d <= 1'b0;
            vld_in_1d <= 1'b0;
            vld_in_2d <= 1'b0;
            vld_out   <= 1'b0;
            f_bits_reg <= 11'b0;
        end
        else if (vld_in || vld_in_1d || vld_in_2d) begin
            s_bits_1d <= s_bits;
            s_bits_2d <= s_bits_1d;
            vld_in_1d <= vld_in;
            vld_in_2d <= vld_in_1d;
            vld_out   <= vld_in_2d;
            f_bits_reg <= f_bits;
        end
        else begin
            s_bits_1d <= 1'b0;
            s_bits_2d <= 1'b0;
            vld_in_1d <= 1'b0;
            vld_in_2d <= 1'b0;
            vld_out   <= 1'b0;
            f_bits_reg <= 11'b0;
        end
    end

// ==================== get real e ==================== //

    assign real_e = {1'b0,e_bits} - 6'd15;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            overflow_pre1 <= 1'b0;
            overflow_pre2 <= 1'b0;
        end
        else if (en == 1'b0) begin
            overflow_pre1 <= 1'b0;
            overflow_pre2 <= 1'b0;
        end
        else if (($signed(real_e) >= 15) && (vld_in || vld_in_1d || vld_in_2d)) begin
            overflow_pre1 <= 1'b1;
            overflow_pre2 <= overflow_pre1;
        end
        else if (vld_in || vld_in_1d || vld_in_2d) begin
            overflow_pre1 <= 1'b0;
            overflow_pre2 <= overflow_pre1;
        end
        else begin
            overflow_pre1 <= 1'b0;
            overflow_pre2 <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            underflow_pre1 <= 1'b0;
            underflow_pre2 <= 1'b0;
        end
        else if (en == 1'b0) begin
            underflow_pre1 <= 1'b0;
            underflow_pre2 <= 1'b0;
        end
        else if (($signed(real_e) < (-5'sd14)) && (vld_in || vld_in_1d || vld_in_2d)) begin
            underflow_pre1 <= 1'b1;
            underflow_pre2 <= underflow_pre1;
        end
        else if (vld_in || vld_in_1d || vld_in_2d) begin
            underflow_pre1 <= 1'b0;
            underflow_pre2 <= underflow_pre1;
        end
        else begin
            underflow_pre1 <= 1'b0;
            underflow_pre2 <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            overflow  <= 1'b0;
            underflow <= 1'b0;
        end
        else if (en == 1'b0) begin
            overflow  <= 1'b0;
            underflow <= 1'b0;
        end
        else if (vld_in || vld_in_1d || vld_in_2d) begin
            overflow  <= overflow_pre2;
            underflow <= underflow_pre2;
        end
        else begin
            overflow  <= 1'b0;
            underflow <= 1'b0;
        end
    end

// ==================== shift bits ==================== //

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_bits     <= 6'h0;
            shift_bits_reg <= 6'h0;
        end
        else if (en == 1'b0) begin
            shift_bits     <= 6'h0;
            shift_bits_reg <= 6'h0;
        end
        else if (vld_in || vld_in_1d || vld_in_2d) begin
            shift_bits     <= $signed(real_e) - 6'd10;
            shift_bits_reg <= shift_bits;
        end
        else begin
            shift_bits     <= 6'h0;
            shift_bits_reg <= 6'h0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            f_shift <= 16'h0;
        else if (en == 1'b0)
            f_shift <= 16'h0;
        else if ((vld_in || vld_in_1d || vld_in_2d) && shift_bits[5] == 1'b0)
            f_shift <= f_bits_reg << shift_bits[4:0];
        else if ((vld_in || vld_in_1d || vld_in_2d) && shift_bits[5] == 1'b1)
            f_shift <= f_bits_reg >> (-$signed(shift_bits) - 1'b1);
    end

// ==================== get f_round ==================== //

    always @(*) begin
        // Assign every combinational path; never retain a previous result.
        f_round = 16'h0000;
        if (s_bits_2d == 1'b1) begin
            if (f_shift[0] == 1'b1 && shift_bits_reg[5] == 1'b1) begin
                f_round = {1'b1,~(f_shift[15:1] + 1'b1) + 1'b1};
            end
            else if (f_shift[0] == 1'b0 && shift_bits_reg[5] == 1'b1) begin
                // INT16 has no negative zero; do not force its sign bit when
                // the rounded magnitude is zero. Otherwise 0 becomes 16'h8000.
                if (f_shift[15:1] == 15'd0)
                    f_round = 16'h0000;
                else
                    f_round = {1'b1,~(f_shift[15:1]) + 1'b1};
            end
            else if (shift_bits_reg[5] == 1'b0) begin
                f_round = {1'b1,~f_shift[14:0] + 1'b1};
            end
        end
        else if (s_bits_2d == 1'b0) begin
            if (f_shift[0] == 1'b1 && shift_bits_reg[5] == 1'b1) begin
                f_round = {1'b0,f_shift[15:1] + 1'b1};
            end
            else if (f_shift[0] == 1'b0 && shift_bits_reg[5] == 1'b1) begin
                f_round = {1'b0,f_shift[15:1]};
            end
            else if (shift_bits_reg[5] == 1'b0) begin
                f_round = {1'b0,f_shift[14:0]};
            end
        end
    end

// ==================== data_out proc ==================== //

    always @(*) begin
        if (is_zero_flag_reg) begin
            data_out_temp = 16'h0;
        end
        else if (underflow_pre2 == 1'b1) begin
            data_out_temp = 16'h0;
        end
        else if (overflow_pre2 == 1'b1 && s_bits_2d == 1'b1) begin
            data_out_temp = 16'sh8000;
        end
        else if (overflow_pre2 == 1'b1 && s_bits_2d == 1'b0) begin
            data_out_temp = 16'sh7fff;
        end
        else if (vld_in || vld_in_1d || vld_in_2d) begin
            data_out_temp = f_round;
        end
        else begin
            data_out_temp = 16'h0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data_out <= 16'd0;
        else if (en == 1'b0) begin
            data_out <= 16'd0;
        end
        else if (vld_in_2d) begin
            data_out <= data_out_temp;
        end
        else
            data_out <= 16'd0;
    end

endmodule
