// Copyright 2020 Intel Corporation
// SPDX-License-Identifier: MIT

// Description
//-----------------------------------------------------------------------------
//
// AXI MMIO interface pipeline register
// 
//-----------------------------------------------------------------------------

module ofs_fim_axi_mmio_reg
  #(
    // Register mode for write address channel
    parameter AW_REG_MODE          = 0, // 0: skid buffer 1: simple buffer 2: bypass
    // Register mode for write data channel
    parameter W_REG_MODE           = 0, // 0: skid buffer 1: simple buffer 2: bypass
    // Regiter mode for write response channel
    parameter B_REG_MODE           = 0, // 0: skid buffer 1: simple buffer 2: bypass
    // Register mode for read address channel
    parameter AR_REG_MODE          = 0, // 0: skid buffer 1: simple buffer 2: bypass
    // Register mode for read data channel
    parameter R_REG_MODE           = 0  // 0: skid buffer 1: simple buffer 2: bypass
    )
   (
    input  logic clk,
    input  logic rst_n,
    ofs_fim_axi_mmio_if.slave  s_mmio,
    ofs_fim_axi_mmio_if.master m_mmio
    );

    axi_register
      #(
        .AW_REG_MODE(AW_REG_MODE),
        .W_REG_MODE(W_REG_MODE),
        .B_REG_MODE(B_REG_MODE),
        .AR_REG_MODE(AR_REG_MODE),
        .R_REG_MODE(R_REG_MODE),
        .ENABLE_AWUSER(1),
        .ENABLE_WUSER(1),
        .ENABLE_BUSER(1),
        .ENABLE_ARUSER(1),
        .ENABLE_RUSER(1),
        .AWID_WIDTH(s_mmio.AWID_WIDTH),
        .AWADDR_WIDTH(s_mmio.AWADDR_WIDTH),
        .AWUSER_WIDTH(s_mmio.AWUSER_WIDTH),
        .WDATA_WIDTH(s_mmio.WDATA_WIDTH),
        .WUSER_WIDTH(s_mmio.WUSER_WIDTH),
        .BUSER_WIDTH(s_mmio.BUSER_WIDTH),
        .ARID_WIDTH(s_mmio.ARID_WIDTH),
        .ARADDR_WIDTH(s_mmio.ARADDR_WIDTH),
        .ARUSER_WIDTH(s_mmio.ARUSER_WIDTH),
        .RDATA_WIDTH(s_mmio.RDATA_WIDTH),
        .RUSER_WIDTH(s_mmio.RUSER_WIDTH)
        )
      axi_reg
       (
        .clk,
        .rst_n,

        .s_awready(s_mmio.awready),
        .s_awvalid(s_mmio.awvalid),
        .s_awid(s_mmio.awid),
        .s_awaddr(s_mmio.awaddr),
        .s_awlen(s_mmio.awlen),
        .s_awsize(s_mmio.awsize),
        .s_awburst(s_mmio.awburst),
        .s_awlock(s_mmio.awlock),
        .s_awcache(s_mmio.awcache),
        .s_awprot(s_mmio.awprot),
        .s_awqos(s_mmio.awqos),
        .s_awregion(),
        .s_awuser(s_mmio.awuser),
          
        .s_wready(s_mmio.wready),
        .s_wvalid(s_mmio.wvalid),
        .s_wdata(s_mmio.wdata),
        .s_wstrb(s_mmio.wstrb),
        .s_wlast(s_mmio.wlast),
        .s_wuser(s_mmio.wuser),
          
        .s_bready(s_mmio.bready),
        .s_bvalid(s_mmio.bvalid),
        .s_bid(s_mmio.bid),
        .s_bresp(s_mmio.bresp),
        .s_buser(s_mmio.buser),
          
        .s_arready(s_mmio.arready),
        .s_arvalid(s_mmio.arvalid),
        .s_arid(s_mmio.arid),
        .s_araddr(s_mmio.araddr),
        .s_arlen(s_mmio.arlen),
        .s_arsize(s_mmio.arsize),
        .s_arburst(s_mmio.arburst),
        .s_arlock(s_mmio.arlock),
        .s_arcache(s_mmio.arcache),
        .s_arprot(s_mmio.arprot),
        .s_arqos(s_mmio.arqos),
        .s_arregion(),
        .s_aruser(s_mmio.aruser),

        .s_rready(s_mmio.rready),
        .s_rvalid(s_mmio.rvalid),
        .s_rid(s_mmio.rid),
        .s_rdata(s_mmio.rdata),
        .s_rresp(s_mmio.rresp),
        .s_rlast(s_mmio.rlast),
        .s_ruser(s_mmio.ruser),
          
          
        .m_awready(m_mmio.awready),
        .m_awvalid(m_mmio.awvalid),
        .m_awid(m_mmio.awid),
        .m_awaddr(m_mmio.awaddr),
        .m_awlen(m_mmio.awlen),
        .m_awsize(m_mmio.awsize),
        .m_awburst(m_mmio.awburst),
        .m_awlock(m_mmio.awlock),
        .m_awcache(m_mmio.awcache),
        .m_awprot(m_mmio.awprot),
        .m_awqos(m_mmio.awqos),
        .m_awregion(),
        .m_awuser(m_mmio.awuser),
          
        .m_wready(m_mmio.wready),
        .m_wvalid(m_mmio.wvalid),
        .m_wdata(m_mmio.wdata),
        .m_wstrb(m_mmio.wstrb),
        .m_wlast(m_mmio.wlast),
        .m_wuser(m_mmio.wuser),

        .m_bready(m_mmio.bready),
        .m_bvalid(m_mmio.bvalid),
        .m_bid(m_mmio.bid),
        .m_bresp(m_mmio.bresp),
        .m_buser(m_mmio.buser),
          
        .m_arready(m_mmio.arready),
        .m_arvalid(m_mmio.arvalid),
        .m_arid(m_mmio.arid),
        .m_araddr(m_mmio.araddr),
        .m_arlen(m_mmio.arlen),
        .m_arsize(m_mmio.arsize),
        .m_arburst(m_mmio.arburst),
        .m_arlock(m_mmio.arlock),
        .m_arcache(m_mmio.arcache),
        .m_arprot(m_mmio.arprot),
        .m_arqos(m_mmio.arqos),
        .m_arregion(),
        .m_aruser(m_mmio.aruser),

        .m_rready(m_mmio.rready),
        .m_rvalid(m_mmio.rvalid),
        .m_rid(m_mmio.rid),
        .m_rdata(m_mmio.rdata),
        .m_rresp(m_mmio.rresp),
        .m_rlast(m_mmio.rlast),
        .m_ruser(m_mmio.ruser)
        );
endmodule
