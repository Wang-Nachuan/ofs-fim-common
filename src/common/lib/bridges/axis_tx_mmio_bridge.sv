// Copyright 2021 Intel Corporation
// SPDX-License-Identifier: MIT

// Description
//-----------------------------------------------------------------------------
// AXI-S Tx MMIO Bridge
//-----------------------------------------------------------------------------

`include "fpga_defines.vh"


module  axis_tx_mmio_bridge #(
    parameter PF_NUM            = 0,
    parameter VF_NUM            = 0,
    parameter VF_ACTIVE         = 0,
    parameter AVMM_DATA_WIDTH   = 64
)(
    input                   clk,
    input                   rst_n,
    
    pcie_ss_axis_if.source  axis_tx_if,    
    output  logic           axis_tx_error,
    
    input   logic                               avmm_s2m_readdatavalid,
    input   logic   [AVMM_DATA_WIDTH-1:0]       avmm_s2m_readdata,

    input   logic                               tlp_rd_strb,
    input   logic   [9:0]                       tlp_rd_tag,
    input   logic   [13:0]                      tlp_rd_length,
    input   logic   [15:0]                      tlp_rd_req_id,
    input   logic   [23:0]                      tlp_rd_low_addr
);

import pcie_ss_hdr_pkg::*;

pcie_ss_hdr_pkg::PCIe_PUCplHdr_t    cpl_hdr;

logic   [AVMM_DATA_WIDTH-1:0]   avmm_s2m_readdata_1;
logic                           avmm_s2m_readdatavalid_1;

logic   [AVMM_DATA_WIDTH-1:0]   avmm_s2m_readdata_2;
logic                           avmm_s2m_readdatavalid_2;

logic           rsp_fifo_wrreq;
logic   [511:0] rsp_fifo_din;

logic           rsp_fifo_rdack;
logic   [511:0] rsp_fifo_dout;

logic           rsp_fifo_valid;

logic   [1:0]   rsp_fifo_eccstatus;

typedef struct packed {
    logic   [9:0]   tag;
    logic   [13:0]  length;
    logic   [15:0]  req_id;
    logic   [23:0]  low_addr;
} ctt_t;

ctt_t   ctt_fifo_din;
ctt_t   ctt_fifo_dout;

logic           ctt_fifo_wrreq;
logic           ctt_fifo_rdack;

logic   [1:0]   ctt_fifo_eccstatus;

logic   [2:0]   ctt_fifo_error_pipe;

//--------------------------------------------------------
// AXIS Tx Source Interface
//--------------------------------------------------------

pcie_ss_axis_if #(.DATA_W(axis_tx_if.DATA_W), .USER_W(axis_tx_if.USER_W)) tx_if(.clk, .rst_n);

always_comb
begin
    tx_if.tlast        = rsp_fifo_valid;
    tx_if.tvalid       = rsp_fifo_valid;
    
    tx_if.tdata        = rsp_fifo_dout;
    tx_if.tkeep        = {$bits(tx_if.tkeep){1'b1}};
    tx_if.tuser_vendor = {$bits(tx_if.tuser_vendor){1'b0}};
    
    axis_tx_error      = ctt_fifo_error_pipe[2] || rsp_fifo_eccstatus[0];
end

ofs_fim_axis_pipeline tx_skid (
    .clk,
    .rst_n,
    .axis_s(tx_if),
    .axis_m(axis_tx_if)
);

//--------------------------------------------------------
// AVMM Slave to Master Interface + FIFO
//--------------------------------------------------------
// Construct TLP -> Response FIFO DIN
always_comb
begin    
    // Right-shift empty readdata due to unaligned address
    rsp_fifo_din        <= { { ( 256 - $bits(avmm_s2m_readdata_2) ) {1'b0} }, 
                                avmm_s2m_readdata_2 >> ( 8 * cpl_hdr.low_addr[2:0] ), 
                                                                            cpl_hdr };
    rsp_fifo_wrreq      <= avmm_s2m_readdatavalid_2;
end

// +2 pipeline to ensure CTT FIFO wrreq -> Q latency
always_ff @ ( posedge clk )
begin
    if ( !rst_n )
    begin
        avmm_s2m_readdatavalid_2    <= 1'b0;
        avmm_s2m_readdatavalid_1    <= 1'b0;
        avmm_s2m_readdata_2         <= 0;
        avmm_s2m_readdata_1         <= 0;
    end
    else
    begin
        avmm_s2m_readdata_2         <= avmm_s2m_readdata_1;
        avmm_s2m_readdatavalid_2    <= avmm_s2m_readdatavalid_1;

        avmm_s2m_readdata_1         <= avmm_s2m_readdata;
        avmm_s2m_readdatavalid_1    <= avmm_s2m_readdatavalid;
    end
end

// Hold DOUT until sink capture on AVST 'ready' and 'valid'
always_comb
begin
    rsp_fifo_rdack = tx_if.tready && tx_if.tvalid;
end

// RSP FIFO
fim_rdack_scfifo #(
    .DATA_WIDTH($bits(rsp_fifo_din)),
    .DEPTH_LOG2(8))
rsp_fifo (
    .clk            (clk),
    .sclr           (!rst_n),
    
    .wreq           (rsp_fifo_wrreq),
    .wdata          (rsp_fifo_din),
    
    .rdack          (rsp_fifo_rdack),
    .rdata          (rsp_fifo_dout),
    .rvalid         (rsp_fifo_valid),
    
    .rusedw         ( ),
    .rempty         ( ),

    .wfull          ( ),
    .almfull        (rsp_fifo_almostfull),      // No overflow backpressure
    .wusedw         ( )
);

assign rsp_fifo_eccstatus = '0;


//--------------------------------------------------------
// Cache Tag Tracker FIFO
// TLP Read Request Sideband from Rx Bridge
//--------------------------------------------------------
always_comb
begin
    ctt_fifo_din.tag        = tlp_rd_tag;
    ctt_fifo_din.length     = tlp_rd_length;
    ctt_fifo_din.req_id     = tlp_rd_req_id;
    ctt_fifo_din.low_addr   = tlp_rd_low_addr;
    
    ctt_fifo_wrreq          = tlp_rd_strb;
    ctt_fifo_rdack          = avmm_s2m_readdatavalid_2;
end

always_ff @ ( posedge clk )
begin
    ctt_fifo_error_pipe[2]  <= ctt_fifo_error_pipe[1];
    ctt_fifo_error_pipe[1]  <= ctt_fifo_error_pipe[0];
    ctt_fifo_error_pipe[0]  <= ctt_fifo_rdack && ctt_fifo_eccstatus[0];
end

// CTT FIFO
fim_rdack_scfifo #(
    .DATA_WIDTH($bits(ctt_t)),
    .DEPTH_LOG2(8))
ctt_fifo (
    .clk            (clk),
    .sclr           (!rst_n),
    
    .wreq           (ctt_fifo_wrreq),
    .wdata          (ctt_fifo_din),
    
    .rdack          (ctt_fifo_rdack),
    .rdata          (ctt_fifo_dout),
    
    .rvalid         ( ),
    .rempty         ( ),
    .rusedw         ( ),

    .wfull          ( ),
    .almfull        ( ),
    .wusedw         ( )
);

assign ctt_fifo_eccstatus = '0;

//--------------------------------------------------------
// Construct Completion Header
//--------------------------------------------------------
always_comb
begin
    cpl_hdr                 = {$bits(cpl_hdr){1'b0}};

    cpl_hdr.pf_num          = PF_NUM;
    cpl_hdr.vf_num          = VF_NUM;
    cpl_hdr.vf_active       = VF_ACTIVE;

    cpl_hdr.fmt_type        = DM_CPL;

    {cpl_hdr.tag_h,
     cpl_hdr.tag_m,
     cpl_hdr.tag_l}         = ctt_fifo_dout.tag[9:0];
    
    cpl_hdr.length          = ctt_fifo_dout.length[11:2];    
    cpl_hdr.low_addr        = ctt_fifo_dout.low_addr[6:0];
    cpl_hdr.req_id          = ctt_fifo_dout.req_id[15:0];
    cpl_hdr.byte_count      = ctt_fifo_dout.length[11:0];

    cpl_hdr.comp_id[2:0]    = PF_NUM;
    cpl_hdr.comp_id[3]      = VF_ACTIVE;
    cpl_hdr.comp_id[15:4]   = VF_NUM;
    cpl_hdr.cpl_status      = 3'b000;                           // SUCCESS
end

endmodule

