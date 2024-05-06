// Copyright 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Skid buffer for crossing PR boundaries or other long-distances. Incoming data
// is written unconditionally to an ingress register. The register feeds a skid
// buffer. tvalid/tready are managed as usual. The module internally manages
// skid buffer space so that valid data arriving on a ready cycle is never lost,
// despite the unconditional register update.
//

module ofs_fim_axis_long_skid
#( 
    parameter TREADY_RST_VAL       = 0, // 0: tready deasserted during reset 
                                        // 1: tready asserted during reset
    parameter PRESERVE_REG         = "OFF"
)(
    input logic            clk,
    input logic            rst_n,
    pcie_ss_axis_if.sink   axis_s,
    pcie_ss_axis_if.source axis_m
);

    localparam TDATA_WIDTH = axis_s.DATA_W;
    localparam TUSER_WIDTH = axis_s.USER_W;
    localparam PL_DEPTH = 2;

    // synthesis translate_off
    initial begin
        assert (TDATA_WIDTH == axis_m.DATA_W) else
            $fatal(2, "Error %m: DATA WIDTH mismatch axis_s (%0d) vs. axis_m (%0d)", axis_s.DATA_W, axis_m.DATA_W);

        assert (TUSER_WIDTH == axis_m.USER_W) else
            $fatal(2, "Error %m: USER WIDTH mismatch axis_s (%0d) vs. axis_m (%0d)", axis_s.USER_W, axis_m.USER_W);
    end
    // synthesis translate_on

    // Unused ofs_fim_axis_register parameters
    localparam TID_WIDTH   = 8;
    localparam TDEST_WIDTH = 8;

    (* altera_attribute = {"-name PRESERVE_REGISTER ON"} *) reg [3:0] rst_n_q = 4'b0;
    always @(posedge clk) begin
        rst_n_q <= { rst_n_q[2:0], rst_n };
    end

    pcie_ss_axis_if#(.DATA_W(TDATA_WIDTH), .USER_W(TUSER_WIDTH)) axis_pl[PL_DEPTH:0] (clk, rst_n);


    // The source sees tready only when there are at least two empty
    // positions in the buffer. This ensures that new data written
    // to the ingress register will also have space in the skid
    // buffers.
    always_comb begin
        casez ({ axis_pl[0].tvalid, axis_pl[0].tready, axis_pl[1].tready })
            3'b01?: axis_s.tready = 1'b1;
            3'b0?1: axis_s.tready = 1'b1;
            3'b?11: axis_s.tready = 1'b1;
            default: axis_s.tready = 1'b0;
        endcase
    end

    // Write to the ingress register unconditionally. axis_s.tready is managed
    // so that there is a guaranteed home in the skid buffer for any data
    // arriving during a ready cycle.
    always_ff @(posedge clk) begin
        axis_pl[0].tvalid       <= axis_s.tvalid && axis_s.tready;
        axis_pl[0].tlast        <= axis_s.tlast;
        axis_pl[0].tuser_vendor <= axis_s.tuser_vendor;
        axis_pl[0].tdata        <= axis_s.tdata;
        axis_pl[0].tkeep        <= axis_s.tkeep;
    end

    // synthesis translate_off
    always_ff @(posedge clk) begin
        // Check the required skid buffer availability
        if (rst_n) begin
            if (axis_pl[0].tvalid && !axis_pl[0].tready)
                $fatal(2, "Error %m: protocol error -- valid pipeline register but skid buffer not ready!");
        end
    end
    // synthesis translate_on


    // Normal connection from the output of the skid buffers to axis_m
    assign axis_m.tvalid = axis_pl[PL_DEPTH].tvalid;
    assign axis_pl[PL_DEPTH].tready = axis_m.tready;

    always_comb begin
        axis_m.tlast        = axis_pl[PL_DEPTH].tlast;
        axis_m.tuser_vendor = axis_pl[PL_DEPTH].tuser_vendor;
        axis_m.tdata        = axis_pl[PL_DEPTH].tdata;
        axis_m.tkeep        = axis_pl[PL_DEPTH].tkeep;
    end

    
    // A pair of connected skid buffers
    for (genvar n = 0; n < PL_DEPTH; n = n + 1) begin : axis_pl_stage
        ofs_fim_axis_register #(
            .MODE           ( 0              ), // Skid buffer
            .TREADY_RST_VAL ( TREADY_RST_VAL ),
            .ENABLE_TKEEP   ( 1              ),
            .ENABLE_TLAST   ( 1              ),
            .ENABLE_TID     ( 0              ),
            .ENABLE_TDEST   ( 0              ),
            .ENABLE_TUSER   ( 1              ),
            .TDATA_WIDTH    ( TDATA_WIDTH    ),
            .TID_WIDTH      ( TID_WIDTH      ),
            .TDEST_WIDTH    ( TDEST_WIDTH    ),
            .PRESERVE_REG   ( n == 0 ? PRESERVE_REG : "OFF" ),
            .REG_IN         ( 0              ),
            .TUSER_WIDTH    ( TUSER_WIDTH    )
            )
          axis_reg_inst (
            .clk     (clk),
            .rst_n   (rst_n_q[3]),

            .s_tready(axis_pl[n].tready),
            .s_tvalid(axis_pl[n].tvalid),
            .s_tdata (axis_pl[n].tdata),
            .s_tkeep (axis_pl[n].tkeep),
            .s_tlast (axis_pl[n].tlast),
            .s_tid   (),
            .s_tdest (),
            .s_tuser (axis_pl[n].tuser_vendor),
            
            .m_tready(axis_pl[n+1].tready),
            .m_tvalid(axis_pl[n+1].tvalid),
            .m_tdata (axis_pl[n+1].tdata),
            .m_tkeep (axis_pl[n+1].tkeep),
            .m_tlast (axis_pl[n+1].tlast),
            .m_tid   (),
            .m_tdest (), 
            .m_tuser (axis_pl[n+1].tuser_vendor)
            );
    end

endmodule // ofs_fim_axis_long_skid
