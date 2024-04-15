// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: MIT

//-----------------------------------------------------------------------------
// Description
//
// Macros for connecting IP memory channels to OFS Interfaces. Use for collapsing
// long port lists of an IP. Mem SS port list is large because each possible 
// memory port is wrapped in a preprocessor switch.
//
//-----------------------------------------------------------------------------

// A Macro to connect an OFS AXI-MM interface to a PD interconnect port mapping
`define CONNECT_OFS_FIM_AXI_MM_PORT(IPORT, OPORT, IFC) \
// Write address channel \
.``OPORT``_awready (``IFC``.awready), \
   .``IPORT``_awvalid (``IFC``.awvalid), \
   .``IPORT``_awid    (``IFC``.awid), \
   .``IPORT``_awaddr  (``IFC``.awaddr), \
   .``IPORT``_awlen   (``IFC``.awlen), \
   .``IPORT``_awsize  (``IFC``.awsize), \
   .``IPORT``_awburst (``IFC``.awburst), \
   .``IPORT``_awlock  (``IFC``.awlock), \
   .``IPORT``_awcache (``IFC``.awcache), \
   .``IPORT``_awprot  (``IFC``.awprot), \
   .``IPORT``_awuser  (``IFC``.awuser), \
   // Write data channel \
   .``OPORT``_wready  (``IFC``.wready), \
   .``IPORT``_wvalid  (``IFC``.wvalid), \
   .``IPORT``_wdata   (``IFC``.wdata), \
   .``IPORT``_wstrb   (``IFC``.wstrb), \
   .``IPORT``_wlast   (``IFC``.wlast), \
   // Write response channel \
   .``IPORT``_bready  (``IFC``.bready), \
   .``OPORT``_bvalid  (``IFC``.bvalid), \
   .``OPORT``_bid     (``IFC``.bid), \
   .``OPORT``_bresp   (``IFC``.bresp), \
   .``OPORT``_buser   (``IFC``.buser), \
   // Read address channel \
   .``OPORT``_arready (``IFC``.arready), \
   .``IPORT``_arvalid (``IFC``.arvalid), \
   .``IPORT``_arid    (``IFC``.arid), \
   .``IPORT``_araddr  (``IFC``.araddr), \
   .``IPORT``_arlen   (``IFC``.arlen), \
   .``IPORT``_arsize  (``IFC``.arsize), \
   .``IPORT``_arburst (``IFC``.arburst), \
   .``IPORT``_arlock  (``IFC``.arlock), \
   .``IPORT``_arcache (``IFC``.arcache), \
   .``IPORT``_arprot  (``IFC``.arprot), \
   .``IPORT``_aruser  (``IFC``.aruser), \
   //Read response channel \
   .``IPORT``_rready  (``IFC``.rready), \
   .``OPORT``_rvalid  (``IFC``.rvalid), \
   .``OPORT``_rid     (``IFC``.rid), \
   .``OPORT``_rdata   (``IFC``.rdata), \
   .``OPORT``_rresp   (``IFC``.rresp), \
   .``OPORT``_rlast   (``IFC``.rlast)

`define CONNECT_OFS_FIM_DDR4_PORT(IPORT, OPORT, IFC) \
// DDR4 Interface \
.``IPORT``_pll_ref_clk  (``IFC``.ref_clk), \
   .``IPORT``_oct_rzqin    (``IFC``.oct_rzqin), \
   .``OPORT``_ck           (``IFC``.ck), \
   .``OPORT``_ck_n         (``IFC``.ck_n), \
   .``OPORT``_a            (``IFC``.a), \
   .``OPORT``_act_n        (``IFC``.act_n), \
   .``OPORT``_ba           (``IFC``.ba), \
   .``OPORT``_bg           (``IFC``.bg), \
   .``OPORT``_cke          (``IFC``.cke), \
   .``OPORT``_cs_n         (``IFC``.cs_n), \
   .``OPORT``_odt          (``IFC``.odt), \
   .``OPORT``_reset_n      (``IFC``.reset_n), \
   .``OPORT``_par          (``IFC``.par), \
   .``OPORT``_alert_n      (``IFC``.alert_n), \
   .``OPORT``_dqs          (``IFC``.dqs), \
   .``OPORT``_dqs_n        (``IFC``.dqs_n), \
   .``OPORT``_dq           (``IFC``.dq), \
   .``OPORT``_dbi_n        (``IFC``.dbi_n)

// Declares A bundle of AXI wires with `WIRE` prefix and attaches `PARAM` prefixed parameters
// Useful when using .* for implicit connectsions to PD hierarchies since unimplemented ports will 
// leave dangling nets instead of needing special handling
`define DECLARE_OFS_FIM_AXI_MM_WIRES(WIRE, PARAM) \
logic ``WIRE``_clk_clk; \
logic ``WIRE``_rst_n_reset_n; \
// Write address channel \
logic ``WIRE``_awready; \
logic ``WIRE``_awvalid; \
logic [``PARAM``_AWID_WIDTH-1:0] ``WIRE``_awid; \
logic [``PARAM``_AWADDR_WIDTH-1:0]``WIRE``_awaddr; \
logic [``PARAM``_BURST_LEN_WIDTH-1:0] ``WIRE``_awlen; \
logic [2:0] ``WIRE``_awsize; \
logic [1:0] ``WIRE``_awburst; \
logic ``WIRE``_awlock; \
logic [3:0] ``WIRE``_awcache; \
logic [2:0] ``WIRE``_awprot; \
logic [3:0] ``WIRE``_awqos; \
logic [``PARAM``_AWUSER_WIDTH-1:0] ``WIRE``_awuser; \
// Write data channel \
logic ``WIRE``_wready; \
logic ``WIRE``_wvalid; \
logic [``PARAM``_WDATA_WIDTH-1:0] ``WIRE``_wdata; \
logic [(``PARAM``_WDATA_WIDTH/8)-1:0] ``WIRE``_wstrb; \
logic ``WIRE``_wlast; \
logic [``PARAM``_WUSER_WIDTH-1:0] ``WIRE``_wuser; \
// Write response channel \
logic ``WIRE``_bready; \
logic ``WIRE``_bvalid; \
logic [``PARAM``_BID_WIDTH-1:0] ``WIRE``_bid; \
logic [1:0] ``WIRE``_bresp; \
logic [``PARAM``_BUSER_WIDTH-1:0] ``WIRE``_buser; \
// Read address channel \
logic ``WIRE``_arready; \
logic ``WIRE``_arvalid; \
logic [``PARAM``_ARID_WIDTH-1:0] ``WIRE``_arid; \
logic [``PARAM``_ARADDR_WIDTH-1:0] ``WIRE``_araddr; \
logic [``PARAM``_BURST_LEN_WIDTH-1:0] ``WIRE``_arlen; \
logic [2:0] ``WIRE``_arsize; \
logic [1:0] ``WIRE``_arburst; \
logic ``WIRE``_arlock; \
logic [3:0] ``WIRE``_arcache; \
logic [2:0] ``WIRE``_arprot; \
logic [3:0] ``WIRE``_arqos; \
logic [``PARAM``_ARUSER_WIDTH-1:0] ``WIRE``_aruser; \
//Read response channel \
logic ``WIRE``_rready; \
logic ``WIRE``_rvalid; \
logic [``PARAM``_RID_WIDTH-1:0] ``WIRE``_rid; \
logic [``PARAM``_RDATA_WIDTH-1:0] ``WIRE``_rdata; \
logic [``PARAM``_RUSER_WIDTH-1:0] ``WIRE``_ruser; \
logic [1:0] ``WIRE``_rresp; \
logic ``WIRE``_rlast; 

// Connect AXI interface `IFC` signals to wires with `WIRE` prefix
`define CONNECT_OFS_FIM_AXI_MM_WIRES(WIRE, IFC) \
always_comb begin \
   // clock/reset \
   ``WIRE``_clk_clk = ``IFC``.clk; \
   ``WIRE``_rst_n_reset_n = ``IFC``.rst_n; \
   // Write address channel \
   ``IFC``.awready  = ``WIRE``_awready; \
   ``WIRE``_awvalid = ``IFC``.awvalid; \
   ``WIRE``_awid    = ``IFC``.awid; \
   ``WIRE``_awaddr  = ``IFC``.awaddr; \
   ``WIRE``_awlen   = ``IFC``.awlen; \
   ``WIRE``_awsize  = ``IFC``.awsize; \
   ``WIRE``_awburst = ``IFC``.awburst; \
   ``WIRE``_awlock  = ``IFC``.awlock; \
   ``WIRE``_awcache = ``IFC``.awcache; \
   ``WIRE``_awprot  = ``IFC``.awprot; \
   ``WIRE``_awqos   = ``IFC``.awqos; \
   ``WIRE``_awuser  = ``IFC``.awuser; \
   // Write data channel \
   ``IFC``.wready   = ``WIRE``_wready; \
   ``WIRE``_wvalid  = ``IFC``.wvalid; \
   ``WIRE``_wdata   = ``IFC``.wdata; \
   ``WIRE``_wstrb   = ``IFC``.wstrb; \
   ``WIRE``_wlast   = ``IFC``.wlast; \
   ``WIRE``_wuser   = ``IFC``.wuser; \
   // Write response channel \
   ``WIRE``_bready  = ``IFC``.bready; \
   ``IFC``.bvalid   = ``WIRE``_bvalid; \
   ``IFC``.bid      = ``WIRE``_bid; \
   ``IFC``.bresp    = ``WIRE``_bresp; \
   ``IFC``.buser    = ``WIRE``_buser; \
   // Read address channel \
   ``IFC``.arready  = ``WIRE``_arready; \
   ``WIRE``_arvalid = ``IFC``.arvalid; \
   ``WIRE``_arid    = ``IFC``.arid; \
   ``WIRE``_araddr  = ``IFC``.araddr; \
   ``WIRE``_arlen   = ``IFC``.arlen; \
   ``WIRE``_arsize  = ``IFC``.arsize; \
   ``WIRE``_arburst = ``IFC``.arburst; \
   ``WIRE``_arlock  = ``IFC``.arlock; \
   ``WIRE``_arcache = ``IFC``.arcache; \
   ``WIRE``_arprot  = ``IFC``.arprot; \
   ``WIRE``_arqos   = ``IFC``.arqos; \
   ``WIRE``_aruser  = ``IFC``.aruser; \
   // Read response channel \
   ``WIRE``_rready  = ``IFC``.rready; \
   ``IFC``.rvalid   = ``WIRE``_rvalid; \
   ``IFC``.rid      = ``WIRE``_rid; \
   ``IFC``.rdata    = ``WIRE``_rdata; \
   ``IFC``.rresp    = ``WIRE``_rresp; \
   ``IFC``.rlast    = ``WIRE``_rlast; \
   ``IFC``.ruser    = ``WIRE``_ruser; \
end
