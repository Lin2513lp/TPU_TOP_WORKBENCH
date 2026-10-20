module FIX2FP
(
    // system interface
    input wire          clk,
    input wire          rst_n,
    // input interface
    input wire          en,
    input wire          vld_in,
    input wire [31:0]   data_in,
    // output interface
    output reg          vld_out,
    output reg [31:0]   data_out
);

// ======================== signal inst ============================ //

    wire        data_in_s;              //signature 符号位
    wire [31:0] data_in_gat;
    wire [30:0] data_in_temp4;
    wire [15:0] data_in_temp3;
    wire [7:0]  data_in_temp2;
    wire [3:0]  data_in_temp1;
    wire [1:0]  data_in_temp0;
    wire [4:0]  lod_index;
    reg  [4:0]  lod_index_reg;
    // lod_index表示除了符号位之外第一个为1的位置，最低为5'd0，最高为5'd30

    reg  [7:0]  exp;
    reg  [7:0]  exp_reg;

    reg  [22:0] data_out_f;
    reg         data_out_s;
    reg         data_out_s_reg;

    reg         vld_in_reg1;
    reg         vld_in_reg2;
    reg         vld_in_reg3;

    reg  [31:0] data_in_reg;
    reg  [30:0] data_in_temp4_reg;

// ==================== data gating for power management ======================== //

    assign data_in_gat = (en && vld_in) ? data_in : 32'b0;

// ======================== seperate data ======================== //
    assign data_in_s = data_in_gat[31];
    assign data_in_temp4 = data_in_s ? ~(data_in_gat[30:0] - 1'b1) : data_in_gat[30:0];       //如果是负数，先取反再加1，得到绝对值

// ======================== Leading one detect ver 1 ======================== //
    assign lod_index[4] = ({1'b0, data_in_temp4[30:16]} == 16'h0) ? 1'b0 : 1'b1;
    assign data_in_temp3 = lod_index[4] ? {1'b0, data_in_temp4[30:16]} : data_in_temp4[15:0];  //如果高16位没有1，就看低16位，否则继续看高16位

    assign lod_index[3] = (data_in_temp3[15:8] == 8'h0) ? 1'b0 : 1'b1;
    assign data_in_temp2 = lod_index[3] ? data_in_temp3[15:8] : data_in_temp3[7:0];

    assign lod_index[2] = (data_in_temp2[7:4] == 4'h0) ? 1'b0 : 1'b1;
    assign data_in_temp1 = lod_index[2] ? data_in_temp2[7:4] : data_in_temp2[3:0];

    assign lod_index[1] = (data_in_temp1[3:2] == 2'b0) ? 1'b0 : 1'b1;
    assign data_in_temp0 = lod_index[1] ? data_in_temp1[3:2] : data_in_temp1[1:0];

    assign lod_index[0] = data_in_temp0[1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vld_out     <= 1'b0;
            vld_in_reg1 <= 1'b0;
            vld_in_reg2 <= 1'b0;
            vld_in_reg3 <= 1'b0;
        end
        else if (en == 1'b0) begin
            vld_out     <= 1'b0;
            vld_in_reg1 <= 1'b0;
            vld_in_reg2 <= 1'b0;
            vld_in_reg3 <= 1'b0;
        end
        else begin
            vld_out     <= vld_in_reg2;
            vld_in_reg1 <= vld_in;
            vld_in_reg2 <= vld_in_reg1;
            vld_in_reg3 <= vld_in_reg2;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_in_reg       <= 32'd0;
            data_in_temp4_reg <= 31'd0;
            lod_index_reg     <= 5'd0;
        end
        else if (en == 1'b0) begin
            data_in_reg       <= 32'd0;
            data_in_temp4_reg <= 31'd0;
            lod_index_reg     <= 5'd0;
        end
        else if (vld_in) begin
            data_in_reg       <= data_in;
            data_in_temp4_reg <= data_in_temp4;
            lod_index_reg     <= lod_index;
        end
        else begin
            data_in_reg       <= 32'd0;
            data_in_temp4_reg <= 31'd0;
            lod_index_reg     <= 5'd0;
        end
    end

// ======================== get exp ======================== //

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exp_reg <= 8'd0;
        end
        else if (en == 1'b0) begin
            exp_reg <= 8'd0;
        end
        else if ((vld_in) && data_in != 32'd0 && data_in != 32'h80000000) begin
            exp_reg <= {3'b0, lod_index} + 8'd127;              //8'b01111111
        end
        else if ((vld_in_reg1) && data_in == 32'd0) begin
            exp_reg <= 8'd0;
        end
        else if ((vld_in_reg1) && data_in == 32'h80000000) begin
            exp_reg <= 8'd158;                                 //-2^31的指数为158
        end
        else begin
            exp_reg <= 8'd0;
        end
    end

// ======================== get f_code ======================== //
    always @(posedge clk or negedge rst_n) begin                 //截取+四舍五入，不再保留首位1
        if (rst_n == 1'b0) begin
            data_out_f <= 23'd0;
            exp        <= 8'd0;
        end
        else if (en == 1'b0) begin
            data_out_f <= 23'd0;
            exp        <= 8'd0;
        end
        else if (lod_index_reg > 23 && (vld_in_reg1) && data_in_reg != 32'd0 && data_in_reg != 32'h80000000) begin
            if (data_in_temp4_reg[lod_index_reg-24] == 1'b1 && data_in_temp4_reg[lod_index_reg-1-:23] != 23'h7fffff) begin //判断截断的时候是否要进位
                data_out_f <= data_in_temp4_reg[lod_index_reg-1-:23] + 1'b1;
                exp        <= exp_reg;
            end
            else if (data_in_temp4_reg[lod_index_reg-24] == 1'b1 && data_in_temp4_reg[lod_index_reg-1-:23] == 23'h7fffff) begin
                data_out_f <= 23'd0;
                exp        <= exp_reg + 1'b1;                   //如果要进位但尾数全是1，则尾数变为0，指数加1
            end
            else begin
                data_out_f <= data_in_temp4_reg[lod_index_reg-1-:23];
                exp        <= exp_reg;
            end
        end
        else if (lod_index_reg <= 23 && (vld_in_reg1) && data_in_reg != 32'd0 && data_in_reg != 32'h80000000) begin
            data_out_f <= data_in_temp4_reg << (23-lod_index_reg);
            exp        <= exp_reg;
        end
        else if ((vld_in_reg1) && ((data_in_reg == 32'd0) || data_in_reg == 32'h80000000)) begin
            data_out_f <= 23'd0;
            exp        <= exp_reg;
        end
        else begin
            data_out_f <= 23'd0;
            exp        <= 8'd0;
        end
    end

// ============ DFF of align ============ //
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out_s     <= 1'b0;
            data_out_s_reg <= 1'b0;
        end
        else if (en == 1'b0) begin
            data_out_s     <= 1'b0;
            data_out_s_reg <= 1'b0;
        end
        else if (vld_in || vld_in_reg1) begin
            data_out_s     <= data_out_s_reg;
            data_out_s_reg <= data_in_s;
        end
        else begin
            data_out_s     <= 1'b0;
            data_out_s_reg <= 1'b0;
        end
    end

// ======================== get f_code ======================== //

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= 32'd0;
        end
        else if (en == 1'b0) begin
            data_out <= 32'd0;
        end
        else if (vld_in_reg2) begin
            data_out <= {data_out_s, exp, data_out_f};
        end
        else begin
            data_out <= 32'd0;
        end
    end

endmodule
