// Copyright (C) 2020 Intel Corporation.
// SPDX-License-Identifier: MIT

//
// Description
//-----------------------------------------------------------------------------
//
//  Definition of AXI-4 Memory Mapped Interfaces used in CoreFIM
//  This interface is parameterized with FIM-specific bus widths.
//
//-----------------------------------------------------------------------------

interface ofs_fim_emif_axi_mm_if #(
   parameter AWID_WIDTH   = ofs_fim_mem_if_pkg::AXI_MEM_AWID_WIDTH,
   parameter AWADDR_WIDTH = ofs_fim_mem_if_pkg::AXI_MEM_AWADDR_WIDTH,
   parameter AWUSER_WIDTH = ofs_fim_mem_if_pkg::AXI_MEM_AWUSER_WIDTH,
   parameter AWLEN_WIDTH  = ofs_fim_mem_if_pkg::AXI_MEM_BURST_LEN_WIDTH,
   parameter WDATA_WIDTH  = ofs_fim_mem_if_pkg::AXI_MEM_WDATA_WIDTH,
   parameter WUSER_WIDTH  = ofs_fim_mem_if_pkg::AXI_MEM_WUSER_WIDTH,
   parameter BID_WIDTH    = ofs_fim_mem_if_pkg::AXI_MEM_BID_WIDTH,
   parameter BUSER_WIDTH  = ofs_fim_mem_if_pkg::AXI_MEM_BUSER_WIDTH,
   parameter ARID_WIDTH   = ofs_fim_mem_if_pkg::AXI_MEM_ARID_WIDTH,
   parameter ARADDR_WIDTH = ofs_fim_mem_if_pkg::AXI_MEM_ARADDR_WIDTH,
   parameter ARUSER_WIDTH = ofs_fim_mem_if_pkg::AXI_MEM_ARUSER_WIDTH,
   parameter ARLEN_WIDTH  = ofs_fim_mem_if_pkg::AXI_MEM_BURST_LEN_WIDTH,
   parameter RDATA_WIDTH  = ofs_fim_mem_if_pkg::AXI_MEM_RDATA_WIDTH,
   parameter RID_WIDTH    = ofs_fim_mem_if_pkg::AXI_MEM_RID_WIDTH,
   parameter RUSER_WIDTH  = ofs_fim_mem_if_pkg::AXI_MEM_RUSER_WIDTH 
);
   logic                       clk;
   logic                       rst_n;

   // Write address channel
   logic                       awready;
   logic                       awvalid;
   logic [AWID_WIDTH-1:0]      awid;
   logic [AWADDR_WIDTH-1:0]    awaddr;
   logic [AWLEN_WIDTH-1:0]     awlen;
   logic [2:0]                 awsize;
   logic [1:0]                 awburst;
   logic                       awlock;
   logic [3:0]                 awcache;
   logic [2:0]                 awprot;
   logic [3:0]                 awqos;
   logic [AWUSER_WIDTH-1:0]    awuser;

   // Write data channel
   logic                       wready;
   logic                       wvalid;
   logic [WDATA_WIDTH-1:0]     wdata;
   logic [(WDATA_WIDTH/8-1):0] wstrb;
   logic                       wlast;
   logic [WUSER_WIDTH-1:0]     wuser;

   // Write response channel
   logic                       bready;
   logic                       bvalid;
   logic [BID_WIDTH-1:0]       bid;
   logic [1:0]                 bresp;
   logic [BUSER_WIDTH-1:0]     buser;

   // Read address channel
   logic                       arready;
   logic                       arvalid;
   logic [ARID_WIDTH-1:0]      arid;
   logic [ARADDR_WIDTH-1:0]    araddr;
   logic [ARLEN_WIDTH-1:0]     arlen;
   logic [2:0]                 arsize;
   logic [1:0]                 arburst;
   logic                       arlock;
   logic [3:0]                 arcache;
   logic [2:0]                 arprot;
   logic [3:0]                 arqos;
   logic [ARUSER_WIDTH-1:0]    aruser;

   // Read response channel
   logic                       rready;
   logic                       rvalid;
   logic [RID_WIDTH-1:0]       rid;
   logic [RDATA_WIDTH-1:0]     rdata;
   logic [1:0]                 rresp;
   logic                       rlast;
   logic [RUSER_WIDTH-1:0]     ruser;

   // AFU <-> MemSS Modports, clock & reset are native from EMIF
   modport user (
        input  clk, rst_n, 
               awready, wready, 
               bvalid, bid, bresp, buser,
               arready,
               rvalid, rid, rdata, rresp, rlast, ruser,
        output awvalid, awid, awaddr, awlen, awsize, awburst, awlock,
               awcache, awprot, awuser, awqos,
               wvalid, wdata, wstrb, wlast, wuser,
               bready, 
               arvalid, arid, araddr, arlen, arsize, arburst, 
               arcache, arprot, aruser, arlock, arqos,
               rready
   );

   modport emif (
        output clk, rst_n, 
               awready, wready, 
               bvalid, bid, bresp, buser,
               arready, 
               rvalid, rid, rdata, rresp, rlast, ruser,
        input  awvalid, awid, awaddr, awlen, awsize, awburst, awlock,
               awcache, awprot, awuser, awqos,
               wvalid, wdata, wstrb, wlast, wuser,
               bready, 
               arvalid, arid, araddr, arlen, arsize, arburst,
               arcache, arprot, aruser, arlock, arqos,
               rready
   );

endinterface : ofs_fim_emif_axi_mm_if
