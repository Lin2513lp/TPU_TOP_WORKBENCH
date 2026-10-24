`timescale 1ns/1ps
`default_nettype none

module pe_array_16x16 #(
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned MODE_WIDTH = 2,
    parameter int unsigned ARRAY_H    = 16,
    parameter int unsigned ARRAY_W    = 16,
    parameter int unsigned PE_CKG_NUM = 64
) (
    // Control
    input  logic [PE_CKG_NUM-1:0]         pe_ckg,
    input  logic                          tpu_rst_n,
    input  logic [ARRAY_H*ARRAY_W-1:0]    pe_en,
    input  logic [MODE_WIDTH-1:0]         cpt_mode,

    // A enters the first PE column. Upstream logic has already skewed A.
    input  logic [DATA_WIDTH*ARRAY_H-1:0] dat_in_a,
    input  logic                          dat_in_vld,

    // One B transfer carries one weight for every PE column.
    // b_lock_row selects the PE row that stores the transfer.
    input  logic [DATA_WIDTH*ARRAY_W-1:0] dat_in_b,
    input  logic [ARRAY_H-1:0]            b_lock_row,

    // Results leave the physical bottom PE row.
    output logic [DATA_WIDTH*ARRAY_W-1:0] raw_dat_out,
    output logic [ARRAY_W-1:0]            raw_dat_out_vld
);

    // One pe_ckg bit is shared by each 2x2 PE group.
    localparam int unsigned CKG_GROUP_COLS = (ARRAY_W + 1) / 2;

    // PE enable index : row*ARRAY_W + col
    // PE clock index  : (row/2)*CKG_GROUP_COLS + col/2

    // PE[row][col] forwards A to PE[row][col+1].
    logic [DATA_WIDTH-1:0] a_right     [0:ARRAY_H-1][0:ARRAY_W-1];
    logic                  a_right_vld [0:ARRAY_H-1][0:ARRAY_W-1];

    // PE[row][col] forwards its partial sum to PE[row+1][col].
    logic [DATA_WIDTH-1:0] psum_down     [0:ARRAY_H-1][0:ARRAY_W-1];
    logic                  psum_down_vld [0:ARRAY_H-1][0:ARRAY_W-1];

    generate
        // -----------------------------------------------------------------
        // 1. Top-left PE: PE[0][0]
        //    A comes from input row 0. The initial partial sum is zero.
        // -----------------------------------------------------------------
        PE_MP_v1 #(
            .DATA_WIDTH (DATA_WIDTH),
            .MODE_WIDTH (MODE_WIDTH)
        ) u_pe_0_0 (
            .pe_ckg         (pe_ckg[0]),
            .tpu_rst_n      (tpu_rst_n),
            .pe_en          (pe_en[0]),
            .dat_in_b       (dat_in_b[DATA_WIDTH-1:0]),
            .in_b_lock      (b_lock_row[0]),
            .cpt_mode       (cpt_mode),
            .dat_in_a       (dat_in_a[DATA_WIDTH-1:0]),
            .dat_in_vld     (dat_in_vld),
            .dat_in_add     ({DATA_WIDTH{1'b0}}),
            .dat_in_add_vld (1'b0),
            .dat_out        (psum_down[0][0]),
            .dat_out_vld    (psum_down_vld[0][0]),
            .out_a          (a_right[0][0]),
            .out_a_vld      (a_right_vld[0][0])
        );

        // -----------------------------------------------------------------
        // 2. Remaining PEs in the first row: PE[0][1] ... PE[0][ARRAY_W-1]
        //    A comes from the PE on the left. The initial partial sum is zero.
        // -----------------------------------------------------------------
        for (genvar col_idx = 1; col_idx < ARRAY_W; col_idx++) begin : gen_top_row_pe
            localparam int unsigned PE_INDEX  = col_idx;
            localparam int unsigned CKG_INDEX = col_idx / 2;

            PE_MP_v1 #(
                .DATA_WIDTH (DATA_WIDTH),
                .MODE_WIDTH (MODE_WIDTH)
            ) u_pe (
                .pe_ckg         (pe_ckg[CKG_INDEX]),
                .tpu_rst_n      (tpu_rst_n),
                .pe_en          (pe_en[PE_INDEX]),
                .dat_in_b       (dat_in_b[col_idx*DATA_WIDTH +: DATA_WIDTH]),
                .in_b_lock      (b_lock_row[0]),
                .cpt_mode       (cpt_mode),
                .dat_in_a       (a_right[0][col_idx-1]),
                .dat_in_vld     (a_right_vld[0][col_idx-1]),
                .dat_in_add     ({DATA_WIDTH{1'b0}}),
                .dat_in_add_vld (1'b0),
                .dat_out        (psum_down[0][col_idx]),
                .dat_out_vld    (psum_down_vld[0][col_idx]),
                .out_a          (a_right[0][col_idx]),
                .out_a_vld      (a_right_vld[0][col_idx])
            );
        end

        // -----------------------------------------------------------------
        // 3. Remaining PEs in the first column: PE[1][0] ... PE[ARRAY_H-1][0]
        //    A comes from the corresponding external row. The partial sum
        //    comes from the PE directly above.
        // -----------------------------------------------------------------
        for (genvar row_idx = 1; row_idx < ARRAY_H; row_idx++) begin : gen_left_col_pe
            localparam int unsigned PE_INDEX  = row_idx * ARRAY_W;
            localparam int unsigned CKG_INDEX = (row_idx / 2) * CKG_GROUP_COLS;

            PE_MP_v1 #(
                .DATA_WIDTH (DATA_WIDTH),
                .MODE_WIDTH (MODE_WIDTH)
            ) u_pe (
                .pe_ckg         (pe_ckg[CKG_INDEX]),
                .tpu_rst_n      (tpu_rst_n),
                .pe_en          (pe_en[PE_INDEX]),
                .dat_in_b       (dat_in_b[DATA_WIDTH-1:0]),
                .in_b_lock      (b_lock_row[row_idx]),
                .cpt_mode       (cpt_mode),
                .dat_in_a       (dat_in_a[row_idx*DATA_WIDTH +: DATA_WIDTH]),
                .dat_in_vld     (dat_in_vld),
                .dat_in_add     (psum_down[row_idx-1][0]),
                .dat_in_add_vld (psum_down_vld[row_idx-1][0]),
                .dat_out        (psum_down[row_idx][0]),
                .dat_out_vld    (psum_down_vld[row_idx][0]),
                .out_a          (a_right[row_idx][0]),
                .out_a_vld      (a_right_vld[row_idx][0])
            );
        end

        // -----------------------------------------------------------------
        // 4. Internal PEs: PE[1][1] ... PE[ARRAY_H-1][ARRAY_W-1]
        //    A comes from the left and the partial sum comes from above.
        // -----------------------------------------------------------------
        for (genvar row_idx = 1; row_idx < ARRAY_H; row_idx++) begin : gen_inner_row
            for (genvar col_idx = 1; col_idx < ARRAY_W; col_idx++) begin : gen_inner_col
                localparam int unsigned PE_INDEX = row_idx*ARRAY_W + col_idx;
                localparam int unsigned CKG_INDEX =
                    (row_idx/2)*CKG_GROUP_COLS + (col_idx/2);

                PE_MP_v1 #(
                    .DATA_WIDTH (DATA_WIDTH),
                    .MODE_WIDTH (MODE_WIDTH)
                ) u_pe (
                    .pe_ckg         (pe_ckg[CKG_INDEX]),
                    .tpu_rst_n      (tpu_rst_n),
                    .pe_en          (pe_en[PE_INDEX]),
                    .dat_in_b       (dat_in_b[col_idx*DATA_WIDTH +: DATA_WIDTH]),
                    .in_b_lock      (b_lock_row[row_idx]),
                    .cpt_mode       (cpt_mode),
                    .dat_in_a       (a_right[row_idx][col_idx-1]),
                    .dat_in_vld     (a_right_vld[row_idx][col_idx-1]),
                    .dat_in_add     (psum_down[row_idx-1][col_idx]),
                    .dat_in_add_vld (psum_down_vld[row_idx-1][col_idx]),
                    .dat_out        (psum_down[row_idx][col_idx]),
                    .dat_out_vld    (psum_down_vld[row_idx][col_idx]),
                    .out_a          (a_right[row_idx][col_idx]),
                    .out_a_vld      (a_right_vld[row_idx][col_idx])
                );
            end
        end

        // The collector receives one raw result lane from each bottom PE.
        for (genvar col_idx = 0; col_idx < ARRAY_W; col_idx++) begin : gen_array_output
            assign raw_dat_out[col_idx*DATA_WIDTH +: DATA_WIDTH] =
                psum_down[ARRAY_H-1][col_idx];
            assign raw_dat_out_vld[col_idx] =
                psum_down_vld[ARRAY_H-1][col_idx];
        end
    endgenerate

endmodule

`default_nettype wire
