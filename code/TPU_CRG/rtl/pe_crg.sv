`timescale 1ns/1ps
`default_nettype none
module pe_crg (
    input wire logic sys_clk,
    input wire logic tpu_rst_n,
    input wire logic tpu_crg_sync,
    input wire logic [3:0] cpu_h_size,
    input wire logic [3:0] cpu_w_size,
    input wire logic dft_glb_gt_se,
    output logic [63:0] pe_ckg
);
    // 1. Each 2x2 PE group uses one clock; size is encoded as N-1.
    wire logic [2:0] last_group_row;
    wire logic [2:0] last_group_col;
    assign last_group_row = cpu_h_size[3:1];
    assign last_group_col = cpu_w_size[3:1];

    // 2. Capture the selected groups while functional PE clocks are stopped.
    // Size inputs must be stable here; hold the mask while clocks are running.
    logic [63:0] group_mask_q;
    always_ff @(posedge sys_clk or negedge tpu_rst_n) begin
        if (!tpu_rst_n) begin
            group_mask_q <= '0;
        end else if (!tpu_crg_sync) begin
            for (integer row = 0; row < 8; row = row+1) begin
                for (integer col = 0; col < 8; col = col+1) begin
                    group_mask_q[row*8+col] <=
                        (row <= last_group_row) &&
                        (col <= last_group_col);
                end
            end
        end
    end

    // 3. Gate each group with the synchronized request and its saved mask.
    // The ICG test enable opens all groups regardless of that mask.
    for (genvar group_idx = 0; group_idx < 64; group_idx++) begin : gen_group
        crg_icg u_icg (
            .clk_in(sys_clk),
            .enable(tpu_crg_sync & group_mask_q[group_idx]),
            .test_enable(dft_glb_gt_se),
            .clk_out(pe_ckg[group_idx])
        );
    end
endmodule
`default_nettype wire
