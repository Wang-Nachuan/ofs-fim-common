// Copyright 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//-----------------------------------------------------------------------------
// Description
//-----------------------------------------------------------------------------
//
// CDC FIFO to cross clock domain between two AXI-S interface.
//
// Optionally, guarantee that outbound packets have no empty cycles.
//
//-----------------------------------------------------------------------------

module ofs_fim_axis_cdc #(
   parameter DEPTH_LOG2         = 6,
   parameter ALMFULL_THRESHOLD  = 2,

   // Guarantee that outbound packets have no breaks? If non-zero, outbound
   // packets are held until the entire packet has been pushed into the FIFO.
   parameter DENSE_OUTPUT       = 0
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

logic out_is_sop;
always_ff @(posedge axis_m.clk) begin
   if (axis_m.tvalid && axis_m.tready)
      out_is_sop <= axis_m.tlast;

   if (~axis_m.rst_n)
      out_is_sop <= 1'b1;
end

logic fifo_rvalid;
logic tlast_fifo_rvalid;
assign axis_m.tvalid = fifo_rvalid && (!out_is_sop || tlast_fifo_rvalid);

fim_rdack_dcfifo #(
   .DATA_WIDTH            (DATA_WIDTH),
   .DEPTH_LOG2            (DEPTH_LOG2),
   .ALMOST_FULL_THRESHOLD (ALMFULL_THRESHOLD+2),
   .READ_ACLR_SYNC        ("ON")
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
   .rvalid    (fifo_rvalid)
);

generate
if (DENSE_OUTPUT == 0) begin : nd
    assign tlast_fifo_rvalid = 1'b1;
end
else
begin : d
   // For dense output, track input tlast. Outbound packets are held until tlast
   // arrives on the input.
   fim_rdack_dcfifo #(
      .DATA_WIDTH            (1),
      .DEPTH_LOG2            (DEPTH_LOG2),
      .ALMOST_FULL_THRESHOLD (ALMFULL_THRESHOLD+2),
      .READ_ACLR_SYNC        ("ON")
   ) tlast_fifo (
      .wclk      (axis_s.clk),
      .rclk      (axis_m.clk),
      .aclr      (~axis_s.rst_n),
      .wdata     (1'b0), // Payload is unimportant. Only FIFO control matters.
      .wreq      (axis_s.tvalid && axis_s.tready && axis_s.tlast),
      .rdack     (axis_m.tvalid && axis_m.tready && out_is_sop),
      .rdata     (),
      .wusedw    (),
      .rusedw    (),
      .wfull     (),
      .wempty    (),
      .almfull   (),
      .rempty    (),
      .rfull     (),
      .rvalid    (tlast_fifo_rvalid)
   );
end
endgenerate

endmodule // ofs_fim_axis_cdc
