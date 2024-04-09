// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: MIT

//
// Pipeline to map the OFS FIM TX and TXREQ interfaces to the PCIe SS AXI-S
// interface when headers are side-band.
//

`include "ofs_ip_cfg_db.vh"

module ofs_fim_pcie_ss_pipe_tx_sb
  #(
    parameter TILE = "P-TILE",
    parameter PORT_ID = 0,
    parameter TDATA_WIDTH = 512,
    parameter TKEEP_WIDTH = TDATA_WIDTH / 8,
    parameter NUM_OF_SEG = 1
    )
   (
    pcie_ss_axis_if.sink axi_st_txreq_if,
    pcie_ss_axis_if.sink axi_st_tx_if,

    input  logic hip_clk,
    input  logic hip_rst_n,
    input  logic csr_clk,
    input  logic csr_rst_n,

    // st_tx clocked by hip_clk
    output logic app_ss_st_tx_tvalid,
    output logic [TDATA_WIDTH-1:0] app_ss_st_tx_tdata,
    output logic [TKEEP_WIDTH-1:0] app_ss_st_tx_tkeep,
    output logic app_ss_st_tx_tlast,
    output logic [NUM_OF_SEG-1:0] app_ss_st_tx_tuser_vendor,
    output logic [NUM_OF_SEG-1:0] app_ss_st_tx_tuser_last_segment,
    output logic [NUM_OF_SEG-1:0] app_ss_st_tx_tuser_hvalid,
    output logic [NUM_OF_SEG-1:0][255:0] app_ss_st_tx_tuser_hdr,
    input  logic ss_app_st_tx_tready,

    // Completion tracking for metering. Clocked by fim_clk.
    input  logic cpl_hdr_valid,
    input  pcie_ss_hdr_pkg::PCIe_PUReqHdr_t cpl_hdr,

    // Completion timeout. Clocked by csr_clk.
    input  pcie_ss_axis_pkg::t_axis_pcie_cplto cpl_timeout
    );

    localparam HDR_WIDTH = 256;

    wire fim_clk = axi_st_txreq_if.clk;
    bit fim_rst_n = 1'b0;
    always @(posedge fim_clk) begin
        fim_rst_n <= axi_st_txreq_if.rst_n;
    end

    typedef ofs_fim_pcie_ss_shims_pkg::t_tuser_seg [NUM_OF_SEG-1:0] t_tuser_seg_vec;


    //
    // txreq: encode the required tuser fields (read requests)
    //
    t_tuser_seg_vec txreq_enc_tuser;
    pcie_ss_axis_if
      #(
        .DATA_W(8), // Dummy -- txreq has only headers, moved to tuser
        .USER_W($bits(t_tuser_seg_vec))
        )
      txreq_enc(fim_clk, fim_rst_n);

    always_comb begin
        txreq_enc_tuser = '0;
        txreq_enc_tuser[0].vendor = axi_st_txreq_if.tuser_vendor[0];
        txreq_enc_tuser[0].hvalid = 1'b1;
        txreq_enc_tuser[0].hdr = axi_st_txreq_if.tdata[HDR_WIDTH-1:0];
        txreq_enc_tuser[0].last_segment = 1'b1;
    end

    assign txreq_enc.tvalid = axi_st_txreq_if.tvalid;
    assign axi_st_txreq_if.tready = txreq_enc.tready;
    assign txreq_enc.tdata = '0;
    assign txreq_enc.tkeep = '0;
    assign txreq_enc.tlast = 1'b1;
    assign txreq_enc.tuser_vendor = txreq_enc_tuser;


    //
    // tx in-band to side-band mapping
    //
    pcie_ss_axis_if
      #(
        .DATA_W(TDATA_WIDTH),
        .USER_W(HDR_WIDTH+$bits(axi_st_tx_if.tuser_vendor))
        )
      tx_sb(fim_clk, fim_rst_n);

    ofs_fim_pcie_ss_ib2sb ib2sb
       (
        .stream_in(axi_st_tx_if),
        .stream_out(tx_sb)
        );

    logic tx_sb_sop;
    always_ff @(posedge fim_clk) begin
        if (tx_sb.tready && tx_sb.tvalid)
            tx_sb_sop <= tx_sb.tlast;
        if (!fim_rst_n)
            tx_sb_sop <= 1'b1;
    end


    //
    // tx: encode the required tuser fields
    //
    t_tuser_seg_vec tx_enc_tuser;
    pcie_ss_axis_if
      #(
        .DATA_W(TDATA_WIDTH),
        .USER_W($bits(t_tuser_seg_vec))
        )
      tx_enc(fim_clk, fim_rst_n);

    always_comb begin
        tx_enc_tuser = '0;
        tx_enc_tuser[0].vendor = tx_sb.tuser_vendor[0];
        tx_enc_tuser[0].hvalid = tx_sb_sop;
        if (tx_sb_sop)
            tx_enc_tuser[0].hdr = tx_sb.tuser_vendor[$bits(axi_st_tx_if.tuser_vendor) +: HDR_WIDTH];

        // Figure out which segment is last (assuming one is)
        for (int i = NUM_OF_SEG-1; i >= 0; i = i - 1) begin
            if (tx_sb.tkeep[(i * TDATA_WIDTH/NUM_OF_SEG) / 8] || ((i == 0) && tx_sb_sop)) begin
                tx_enc_tuser[i].last_segment = tx_sb.tlast;
                break;
            end
        end
    end

    assign tx_enc.tvalid = tx_sb.tvalid;
    assign tx_sb.tready = tx_enc.tready;
    assign tx_enc.tdata = tx_sb.tdata;
    assign tx_enc.tkeep = tx_sb.tkeep;
    assign tx_enc.tlast = tx_sb.tlast;
    assign tx_enc.tuser_vendor = tx_enc_tuser;


    //
    // tx+txreq: completion metering
    //
    pcie_ss_axis_if
      #(
        .DATA_W($bits(txreq_enc.tdata)),
        .USER_W($bits(txreq_enc.tuser_vendor))
        )
      txreq_cpl_meter(fim_clk, fim_rst_n);

    pcie_ss_axis_if
      #(
        .DATA_W($bits(tx_enc.tdata)),
        .USER_W($bits(tx_enc.tuser_vendor))
        )
      tx_cpl_meter(fim_clk, fim_rst_n);

    ofs_fim_pcie_ss_cpl_metering
      #(
        .TILE(TILE),
        .PORT_ID(PORT_ID),
        .SB_HEADERS(1),
        .NUM_OF_SEG(NUM_OF_SEG)
        )
      cpl_metering
       (
        .axi_st_txreq_in(txreq_enc),
        .axi_st_tx_in(tx_enc),
        .axi_st_txreq_out(txreq_cpl_meter),
        .axi_st_tx_out(tx_cpl_meter),

        .csr_clk,
        .csr_rst_n,

        .ss_cplto_tvalid(cpl_timeout.tvalid),
        .ss_cplto_tdata(cpl_timeout.tdata),

        .cpl_hdr_valid,
        .cpl_hdr
        );


    //
    // txreq: clock crossing FIM -> HIP
    //
    pcie_ss_axis_if
      #(
        .DATA_W($bits(txreq_enc.tdata)),
        .USER_W($bits(txreq_enc.tuser_vendor))
        )
      txreq_hip(hip_clk, hip_rst_n);

    ofs_fim_axis_cdc
      #(
        // Relatively shallow buffer. Extra buffering only makes managing
        // QoS in an AFU harder and doesn't improve throughput.
        .DEPTH_LOG2(4)
        )
      txreq_cdc(.axis_s(txreq_cpl_meter), .axis_m(txreq_hip));


    //
    // tx clock crossing FIM -> HIP
    //
    pcie_ss_axis_if
      #(
        .DATA_W($bits(tx_enc.tdata)),
        .USER_W($bits(tx_enc.tuser_vendor))
        )
      tx_hip(hip_clk, hip_rst_n);

    // Clock crossing buffer must at least be large enough to hold an entire
    // packet since the buffer is also used to ensure that packets are
    // delivered to the HIP without empty cycles.
    //
    // Size the buffer for 4 max. size packets.
    localparam TX_CDC_DEPTH_LOG2 =
        2 + $clog2((8 * ofs_pcie_ss_cfg_pkg::MAX_WR_PAYLOAD_BYTES) / TDATA_WIDTH);

    ofs_fim_axis_cdc
      #(
        .DEPTH_LOG2(TX_CDC_DEPTH_LOG2 > 5 ? TX_CDC_DEPTH_LOG2 : 5),
        // Delay output until full packets are queued
        .DENSE_OUTPUT(1)
        )
      tx_cdc(.axis_s(tx_cpl_meter), .axis_m(tx_hip));


    //
    // Merge tx and txreq streams.
    //
    pcie_ss_axis_if
      #(
        .DATA_W(TDATA_WIDTH),
        .USER_W($bits(t_tuser_seg_vec))
        )
      tx_out(hip_clk, hip_rst_n);

    ofs_fim_pcie_ss_tx_merge
      #(
        .TILE(TILE),
        .PORT_ID(PORT_ID),
        .NUM_OF_SEG(NUM_OF_SEG)
        )
      tx_merge
       (
        .axi_st_txreq_in(txreq_hip),
        .axi_st_tx_in(tx_hip),
        .axi_st_tx_out(tx_out)
        );


    t_tuser_seg_vec tx_out_tuser;
    assign app_ss_st_tx_tvalid = tx_out.tvalid;

    assign tx_out.tready = ss_app_st_tx_tready;
    assign app_ss_st_tx_tdata = tx_out.tdata;
    assign app_ss_st_tx_tkeep = tx_out.tkeep;
    assign app_ss_st_tx_tlast = tx_out.tlast;

    assign tx_out_tuser = tx_out.tuser_vendor;
    for (genvar i = 0; i < NUM_OF_SEG; i += 1) begin
        assign app_ss_st_tx_tuser_vendor[i] = tx_out_tuser[i].vendor;
        assign app_ss_st_tx_tuser_last_segment[i] = tx_out_tuser[i].last_segment;
        assign app_ss_st_tx_tuser_hvalid[i] = tx_out_tuser[i].hvalid;
        assign app_ss_st_tx_tuser_hdr[i] = tx_out_tuser[i].hdr;
    end

endmodule // ofs_fim_pcie_ss_pipe_tx_sb
