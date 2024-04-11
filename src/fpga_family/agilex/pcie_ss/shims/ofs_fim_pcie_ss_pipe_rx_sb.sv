// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: MIT

//
// Pipeline to map the PCIe SS AXI-S interface to OFS FIM RX and RXREQ interfaces
// when headers are side-band.
//
// Stages include:
//  - Split incoming traffic into completions (RX) and requests/messages (RXREQ)
//  - Buffer incoming traffic to avoid losing messages
//  - Clock crossing to FIM
//

`include "ofs_ip_cfg_db.vh"

module ofs_fim_pcie_ss_pipe_rx_sb
  #(
    parameter TDATA_WIDTH = 512,
    parameter TKEEP_WIDTH = TDATA_WIDTH / 8,
    parameter NUM_OF_SEG = 1,
    parameter CFG_HAS_RXCRDT = 0
    )
   (
    input  logic hip_clk,
    input  logic hip_rst_n,

    // st_rx clocked by hip_clk
    input  logic ss_app_st_rx_tvalid,
    input  logic [TDATA_WIDTH-1:0] ss_app_st_rx_tdata,
    input  logic [TKEEP_WIDTH-1:0] ss_app_st_rx_tkeep,
    input  logic ss_app_st_rx_tlast,
    input  logic [NUM_OF_SEG-1:0] ss_app_st_rx_tuser_vendor,
    input  logic [NUM_OF_SEG-1:0] ss_app_st_rx_tuser_last_segment,
    input  logic [NUM_OF_SEG-1:0] ss_app_st_rx_tuser_hvalid,
    input  logic [NUM_OF_SEG-1:0][255:0] ss_app_st_rx_tuser_hdr,
    // tready manages the RX flow control between the PCIe SS (HIP) when
    // CFG_HAS_RXCRDT is 0.
    output logic app_ss_st_rx_tready,
    // rxcrdt becomes the RX flow control mechanism between the HIP and here
    // when CFG_HAS_RXCRDT is set.
    output logic ss_app_st_rxcrdt_tvalid,
    output logic [18:0] ss_app_st_rxcrdt_tdata,

    // FIM interfaces share a clock (separate from hip_clk)
    pcie_ss_axis_if.source axi_st_rxreq_if,
    pcie_ss_axis_if.source axi_st_rx_if
    );

    localparam HDR_WIDTH = 256;
    localparam BUFFER_DEPTH = 512;

    wire fim_clk = axi_st_rxreq_if.clk;
    bit fim_rst_n = 1'b0;
    always @(posedge fim_clk) begin
        fim_rst_n <= axi_st_rxreq_if.rst_n;
    end

    // Map the incoming tuser ports to a single data structure and store it
    // in the tuser_vendor field of the standard OFS pcie_ss_axis_if. This
    // is the format expected by the shims instantiated in the RX pipeline.
    ofs_fim_pcie_ss_shims_pkg::t_tuser_seg [NUM_OF_SEG-1:0] rx_in_tuser;
    for (genvar i = 0; i < NUM_OF_SEG; i += 1) begin
        assign rx_in_tuser[i].vendor = ss_app_st_rx_tuser_vendor[i];
        assign rx_in_tuser[i].last_segment = ss_app_st_rx_tuser_last_segment[i];
        assign rx_in_tuser[i].hvalid = ss_app_st_rx_tuser_hvalid[i];
        assign rx_in_tuser[i].hdr = ss_app_st_rx_tuser_hdr[i];
    end

    pcie_ss_axis_if#(.DATA_W(TDATA_WIDTH), .USER_W($bits(rx_in_tuser))) rx_in(hip_clk, hip_rst_n);

    assign rx_in.tvalid = ss_app_st_rx_tvalid;
    assign rx_in.tlast = ss_app_st_rx_tlast;
    assign rx_in.tuser_vendor = rx_in_tuser;
    assign rx_in.tdata = ss_app_st_rx_tdata;
    assign rx_in.tkeep = ss_app_st_rx_tkeep;
    assign app_ss_st_rx_tready = (CFG_HAS_RXCRDT == 0) ? rx_in.tready : 1'b1;


    // Clock crossing FIFO. In addition to moving to the FIM clock, this is the
    // buffer for which RX credits are managed. Credits are only between the HIP's
    // RX buffers and the FIM so doesn't have to be too large.
    pcie_ss_axis_if#(.DATA_W(TDATA_WIDTH), .USER_W($bits(rx_in_tuser))) rx_buf(fim_clk, fim_rst_n);
    pcie_ss_axis_if#(.DATA_W(TDATA_WIDTH), .USER_W($bits(rx_in_tuser))) rx_buf_skid(fim_clk, fim_rst_n);

    ofs_fim_axis_cdc
      #(
        .DEPTH_LOG2($clog2(BUFFER_DEPTH))
        )
      rx_cdc(.axis_s(rx_in), .axis_m(rx_buf));

    ofs_fim_axis_pipeline
      #(
        .TDATA_WIDTH(TDATA_WIDTH),
        .TUSER_WIDTH($bits(rx_in_tuser))
        )
      pipe_rx_buf(.clk(fim_clk), .rst_n(fim_rst_n), .axis_s(rx_buf), .axis_m(rx_buf_skid));

    // Split the RX stream into two: completions (rx) and everything else (rxreq).
    // The streams still have side-band headers.
    pcie_ss_axis_if#(.DATA_W(TDATA_WIDTH), .USER_W($bits(rx_in_tuser))) rx_sb(fim_clk, fim_rst_n);
    pcie_ss_axis_if#(.DATA_W(TDATA_WIDTH), .USER_W($bits(rx_in_tuser))) rxreq_sb(fim_clk, fim_rst_n);

    ofs_fim_pcie_ss_rx_dual_stream
      #(
        .NUM_OF_SEG(NUM_OF_SEG),
        .SB_HEADERS(1)
        )
      rx_dual_stream
       (
        .stream_in(rx_buf_skid),
        .stream_out_cpld(rx_sb),
        .stream_out_req(rxreq_sb)
        );


    // Reduce each stream so that headers are only at bit 0. USER_W is narrower
    // now since there is only a single header field.
    pcie_ss_axis_if#(.DATA_W(TDATA_WIDTH), .USER_W($bits(ofs_fim_pcie_ss_shims_pkg::t_tuser_seg)))
        rx_sb_aligned(fim_clk, fim_rst_n);
    pcie_ss_axis_if#(.DATA_W(TDATA_WIDTH), .USER_W($bits(ofs_fim_pcie_ss_shims_pkg::t_tuser_seg)))
        rxreq_sb_aligned(fim_clk, fim_rst_n);

    ofs_fim_pcie_ss_rx_seg_align
      #(
        .NUM_OF_SEG(NUM_OF_SEG)
        )
      rx_seg_align
       (
        .stream_in(rx_sb),
        .stream_out(rx_sb_aligned)
        );

    ofs_fim_pcie_ss_rx_seg_align
      #(
        .NUM_OF_SEG(NUM_OF_SEG)
        )
      rxreq_seg_align
       (
        .stream_in(rxreq_sb),
        .stream_out(rxreq_sb_aligned)
        );


    // Map side-band to in-band headers. The sb2ib module takes the header plus
    // one tuser_vendor bit as input in tuser and produces a tuser_vendor with
    // just one bit -- the DM/PU encoding flag.
    pcie_ss_axis_if#(.DATA_W(TDATA_WIDTH), .USER_W(HDR_WIDTH+1)) rx_sb2ib_in(fim_clk, fim_rst_n);
    pcie_ss_axis_if#(.DATA_W(TDATA_WIDTH), .USER_W(1)) rx_ib(fim_clk, fim_rst_n);

    ofs_fim_pcie_ss_shims_pkg::t_tuser_seg rx_sb_aligned_tuser;
    assign rx_sb_aligned_tuser = rx_sb_aligned.tuser_vendor;

    assign rx_sb2ib_in.tvalid = rx_sb_aligned.tvalid;
    assign rx_sb2ib_in.tlast = rx_sb_aligned.tlast;
    assign rx_sb2ib_in.tuser_vendor = { rx_sb_aligned_tuser.hdr, rx_sb_aligned_tuser.vendor };
    assign rx_sb2ib_in.tdata = rx_sb_aligned.tdata;
    assign rx_sb2ib_in.tkeep = rx_sb_aligned.tkeep;
    assign rx_sb_aligned.tready = rx_sb2ib_in.tready;

    ofs_fim_pcie_ss_sb2ib rx_sb2ib
       (
        .stream_in(rx_sb2ib_in),
        .stream_out(rx_ib)
        );

    pcie_ss_axis_if#(.DATA_W(TDATA_WIDTH), .USER_W(HDR_WIDTH+1)) rxreq_sb2ib_in(fim_clk, fim_rst_n);
    pcie_ss_axis_if#(.DATA_W(TDATA_WIDTH), .USER_W(1)) rxreq_ib(fim_clk, fim_rst_n);

    ofs_fim_pcie_ss_shims_pkg::t_tuser_seg rxreq_sb_aligned_tuser;
    assign rxreq_sb_aligned_tuser = rxreq_sb_aligned.tuser_vendor;

    assign rxreq_sb2ib_in.tvalid = rxreq_sb_aligned.tvalid;
    assign rxreq_sb2ib_in.tlast = rxreq_sb_aligned.tlast;
    assign rxreq_sb2ib_in.tuser_vendor = { rxreq_sb_aligned_tuser.hdr, rxreq_sb_aligned_tuser.vendor };
    assign rxreq_sb2ib_in.tdata = rxreq_sb_aligned.tdata;
    assign rxreq_sb2ib_in.tkeep = rxreq_sb_aligned.tkeep;
    assign rxreq_sb_aligned.tready = rxreq_sb2ib_in.tready;

    ofs_fim_pcie_ss_sb2ib rxreq_sb2ib
       (
        .stream_in(rxreq_sb2ib_in),
        .stream_out(rxreq_ib)
        );


    // Connect to the FIM
    if (CFG_HAS_RXCRDT == 0) begin : no_rxcrdt
        // No RX credit interface
        assign axi_st_rx_if.tvalid = rx_ib.tvalid;
        assign axi_st_rx_if.tlast = rx_ib.tlast;
        assign axi_st_rx_if.tuser_vendor = { '0, rx_ib.tuser_vendor };
        assign axi_st_rx_if.tdata = rx_ib.tdata;
        assign axi_st_rx_if.tkeep = rx_ib.tkeep;
        assign rx_ib.tready = axi_st_rx_if.tready;

        assign axi_st_rxreq_if.tvalid = rxreq_ib.tvalid;
        assign axi_st_rxreq_if.tlast = rxreq_ib.tlast;
        assign axi_st_rxreq_if.tuser_vendor = { '0, rxreq_ib.tuser_vendor };
        assign axi_st_rxreq_if.tdata = rxreq_ib.tdata;
        assign axi_st_rxreq_if.tkeep = rxreq_ib.tkeep;
        assign rxreq_ib.tready = axi_st_rxreq_if.tready;

        assign ss_app_st_rxcrdt_tvalid = 1'b0;
        assign ss_app_st_rxcrdt_tdata = '0;
    end else begin : rxcrdt
        // Generate RX credits as packets are passed to the FIM
        ofs_fim_pcie_ss_rxcrdt
          #(
            .TDATA_WIDTH(TDATA_WIDTH),
            // SB headers at the PCIe SS interface. This affects available
            // credit. The actual rx_ib and rxreq_ib are in-band at this point.
            .BUFFER_SB_HEADERS(1),
            // Depth of the clock crossing buffer above.
            .BUFFER_DEPTH(BUFFER_DEPTH)
            )
          tracker
           (
            .stream_in_cpld(rx_ib),
            .stream_in_req(rxreq_ib),
            .stream_out_cpld(axi_st_rx_if),
            .stream_out_req(axi_st_rxreq_if),

            .rxcrdt_clk(hip_clk),
            .rxcrdt_rst_n(hip_rst_n),
            .rxcrdt_tvalid(ss_app_st_rxcrdt_tvalid),
            .rxcrdt_tdata(ss_app_st_rxcrdt_tdata)
            );
    end

endmodule // ofs_fim_pcie_ss_pipe_rx_sb
