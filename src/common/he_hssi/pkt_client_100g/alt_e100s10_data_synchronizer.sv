// Copyright (C) 2001-2021 Intel Corporation
// SPDX-License-Identifier: MIT

`include "fpga_defines.vh"

module alt_e100s10_data_synchronizer #(
    parameter SIM_EMULATE = 0
) (
    input   logic           i_arst,

    input   logic           i_clk_w,
    input   logic   [0:519] i_data,
    input   logic           i_valid,

    input   logic           i_clk_r,
    output  logic   [0:519] o_data,
    output  logic   [0:7]   o_valid
);

    logic           w_reset;
    logic           r_reset;
    logic   [0:8]   w_reset_reg;    /* synthesis dont_merge */

    fim_resync #(
      .INIT_VALUE            (1),
      .SYNC_CHAIN_LENGTH     (3)
    ) rsw (
       .clk   (i_clk_w),
       .reset (i_arst),
       .d     (1'b0),
       .q     (w_reset)
    );
 
    fim_resync #(
      .INIT_VALUE            (1),
      .SYNC_CHAIN_LENGTH     (3)
    ) rsr (
       .clk   (i_clk_r),
       .reset (i_arst),
       .d     (1'b0),
       .q     (r_reset)
    );

    logic   [0:519] i_data_reg;
    logic   [0:8]   i_valid_reg;    /* synthesis dont_merge */

    always_ff @(posedge i_clk_w) begin
        i_data_reg  <= i_data;
    end

    logic   [4:0]   wptr            [0:8];  /* synthesis dont_merge */
    logic   [4:0]   wptr_sync_reg   [0:7];  /* synthesis dont_merge */
    logic   [4:0]   wptr_sync;
    logic   [4:0]   rptr            [0:7];  /* synthesis dont_merge */

    logic   [0:519] read_data;

    alt_e100s10_pointer_synchronizer #(
        .WIDTH  (5)
    ) ps (
        .clk_in     (i_clk_w),
        .ptr_in     (wptr[8]),
        .clk_out    (i_clk_r),
        .ptr_out    (wptr_sync)
    );

    genvar i;
    generate
        for (i = 0; i < 8; i++) begin : rptr_loop

            always_ff @(posedge i_clk_r) begin
                wptr_sync_reg[i]    <= wptr_sync;

                if (r_reset) begin
                    rptr[i] <= 5'd0;
                    o_valid[i]  <= 1'b0;
                end else begin
                    if (rptr[i] === wptr_sync_reg[i]) begin
                        rptr[i] <= rptr[i];
                        o_valid[i]  <= 1'b0;
                    end else begin
                        rptr[i] <= rptr[i] + 1'd1;
                        o_valid[i]  <= 1'b1;
                    end
                end
            end

            `ifdef DEVICE_FAMILY_IS_S10
               alt_e100s10_mlab  #(
            `elsif INCLUDE_FTILE
               intc_mlab #(
            `else
               alt_ehipc3_fm_mlab #(
            `endif 
                .WIDTH      (65),
                .ADDR_WIDTH (5),
                .SIM_EMULATE(SIM_EMULATE)
            ) mem (
                .wclk       (i_clk_w),
                .wdata_reg  (i_data_reg[65*i+:65]),
                .wena       (1'b1),
                .waddr_reg  (wptr[i]),
                .raddr      (rptr[i]),
                .rdata      (read_data[65*i+:65])
            );
       end

        always_ff @(posedge i_clk_r) begin
            o_data <= read_data;
        end

        for (i = 0; i < 9; i++) begin : wptr_loop
            always_ff @(posedge i_clk_w) begin
                w_reset_reg[i]  <= w_reset;
                i_valid_reg[i]  <= i_valid;

                if (w_reset_reg[i]) begin
                    wptr[i] <= 5'd0;
                end else begin
                    if (i_valid_reg[i]) begin
                        wptr[i] <= wptr[i] + 1'd1;
                    end else begin
                        wptr[i] <= wptr[i];
                    end
                end
            end
        end
    endgenerate

endmodule
