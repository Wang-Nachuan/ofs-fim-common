// Copyright 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//-----------------------------------------------------------------------------
// Description
//-----------------------------------------------------------------------------
//
// CDC FIFO to cross clock domain between two AXI-S interface 
//
//-----------------------------------------------------------------------------

module ofs_fim_axis_cdc #(
   parameter DEPTH_LOG2         = 6,
   parameter ALMFULL_THRESHOLD  = 2
)(
    pcie_ss_axis_if.sink   axis_s,
    pcie_ss_axis_if.source axis_m
);

localparam DATA_WIDTH = $bits(axis_s.tdata) + $bits(axis_s.tkeep) + $bits(axis_s.tuser_vendor) + 1;
localparam DATA_WIDTH_CHECK = $bits(axis_m.tdata) + $bits(axis_m.tkeep) + $bits(axis_m.tuser_vendor) + 1;

// synthesis translate_off
initial
begin : error_proc
   if (DATA_WIDTH != DATA_WIDTH_CHECK)
      $fatal(2, "** ERROR ** %m: DATA width mismatch (in %0d, out %0d)", DATA_WIDTH, DATA_WIDTH_CHECK);
end
// synthesis translate_on

logic fifo_almfull;
assign axis_s.tready = ~fifo_almfull;

fim_rdack_dcfifo #(
   .DATA_WIDTH            (DATA_WIDTH),
   .DEPTH_LOG2            (DEPTH_LOG2),          // depth 64 
   .ALMOST_FULL_THRESHOLD (ALMFULL_THRESHOLD+2), // allow 4 pipelines
   .READ_ACLR_SYNC        ("ON")                 // add aclr synchronizer on read side
) fifo (
   .wclk      (axis_s.clk),
   .rclk      (axis_m.clk),
   .aclr      (~axis_s.rst_n),
   .wdata     ({ axis_s.tdata, axis_s.tkeep, axis_s.tuser_vendor, axis_s.tlast }), 
   .wreq      (axis_s.tvalid && axis_s.tready),
   .rdack     (axis_m.tvalid && axis_m.tready),
   .rdata     ({ axis_m.tdata, axis_m.tkeep, axis_m.tuser_vendor, axis_m.tlast }), 
   .wusedw    (),
   .rusedw    (),
   .wfull     (),
   .wempty    (),
   .almfull   (fifo_almfull),
   .rempty    (),
   .rfull     (),
   .rvalid    (axis_m.tvalid)
);

endmodule // ofs_fim_axis_cdc
