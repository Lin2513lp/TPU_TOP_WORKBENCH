`timescale 1ns/1ps
`default_nettype none
module rst_sync (
    input wire logic  sys_clk,
    input wire logic  sys_rst_n,
    input wire logic  cpu_tpu_sw_rst,
    input wire logic  dft_mode,
    input wire logic  dft_lgc_rst_n,
    output wire logic tpu_rst_n
);
    wire logic functional_rst_n;
    wire logic selected_rst_n;
    logic reset_d1;
    logic reset_d2;

    // In functional mode, either global reset or software reset resets the TPU.
    assign functional_rst_n = sys_rst_n & ~cpu_tpu_sw_rst;

    // Select the reset source for the two synchronizer flip-flops.
    assign selected_rst_n = dft_mode ? dft_lgc_rst_n : functional_rst_n;

    // Assert reset asynchronously; release it after two sys_clk rising edges.
    always_ff @(posedge sys_clk or negedge selected_rst_n) begin
        if (!selected_rst_n) begin
            reset_d1 <= 1'b0;
            reset_d2 <= 1'b0;
        end else begin
            reset_d1 <= 1'b1;
            reset_d2 <= reset_d1;
        end
    end

    // Bypass the synchronizer in DFT mode so test reset works without sys_clk.
    assign tpu_rst_n = dft_mode ? dft_lgc_rst_n : reset_d2;
endmodule
`default_nettype wire
