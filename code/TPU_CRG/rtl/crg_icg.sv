`timescale 1ns/1ps
`default_nettype none
module crg_icg (
    input wire logic clk_in,
    input wire logic enable,
    input wire logic test_enable,
    output logic clk_out
);
    // Capture the functional enable only while the source clock is low.
    logic enable_latched;
    always_latch begin
        if (!clk_in) enable_latched <= enable;
    end

    // Apply the DFT override after the latch, then gate the source clock.
    // Change test_enable only while clk_in is low to preserve full pulses.
    assign clk_out = clk_in & (enable_latched | test_enable);
endmodule
`default_nettype wire
