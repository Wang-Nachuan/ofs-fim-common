// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Return RX credits to the PCIe SS.
//
// The module assumes that the incoming RX streams have already been transformed
// into OFS streams:
//
//  - In-band headers, though the managed upstream buffer may have either
//    side-band headers. This affects the data credit calculation.
//  - SOP may only be at bit 0.
//  - Completions with data are all in a separate stream.
//
// The module also assumes that the streams are in an OFS clock domain. The
// output credit updates are mapped internally to the PCIe SS AXI-S clock.
//

module ofs_fim_pcie_ss_rxcrdt
  #(
    parameter TDATA_WIDTH = 512,
    parameter NUM_OF_SEG = 1,
    parameter SB_HEADERS = 0,
    parameter BUFFER_DEPTH = 512,
    // While this module requires in-band headers in the TLP streams, the
    // upstream buffer for which credits are managed may have side-band
    // headers. When headers are side-band more data credits are available.
    parameter BUFFER_SB_HEADERS = SB_HEADERS,
    parameter HDR_WIDTH = 256,

    // Default initial credits. The defaults assume that there are separate
    // buffers for completions and for P/NP requests. (P/NP requests share a
    // buffer.) Both buffers are assumed to be the same depth.

    // Number of credits per buffer entry for pure data. Each credit corresponds
    // to 4 DWORDs. (Intermediate calculations -- don't override.)
    parameter DATA_CRDT_WITHOUT_HDR = TDATA_WIDTH / (32 * 4),
    // Number of credits per buffer entry when one header is present. Side-band
    // headers take no space away from data.
    parameter DATA_CRDT_WITH_HDR = (TDATA_WIDTH - (BUFFER_SB_HEADERS ? 0 : HDR_WIDTH)) / (32 * 4),

    // Allocate 50% of entries for headers (one per slot)
    parameter CPL_HDR_INIT = BUFFER_DEPTH / 2,
    // Credits for data in header slots plus half of the remaining slots.
    // This is probably conservative and the data-only fraction could be increased
    // if necessary.
    parameter CPL_DATA_INIT = CPL_HDR_INIT * DATA_CRDT_WITH_HDR +
                              (BUFFER_DEPTH / 4) * DATA_CRDT_WITHOUT_HDR,

    // P/NP share a separate buffer. Re-use the CPL calculations, giving more data
    // to posted requests (writes).
    parameter P_HDR_INIT = CPL_HDR_INIT / 2,
    parameter P_DATA_INIT = (CPL_DATA_INIT * 3) / 4,
    parameter NP_HDR_INIT = CPL_HDR_INIT / 2,
    parameter NP_DATA_INIT = CPL_DATA_INIT / 4
    )
   (
    // Input streams with NUM_OF_SEG segments
    pcie_ss_axis_if.sink stream_in_cpld,
    pcie_ss_axis_if.sink stream_in_req,

    // Output streams (wired to the input streams -- no transformation)
    pcie_ss_axis_if.source stream_out_cpld,
    pcie_ss_axis_if.source stream_out_req,

    // Credits returned to the PCIe SS
    input  wire  rxcrdt_clk,
    input  wire  rxcrdt_rst_n,
    output logic rxcrdt_tvalid,
    output logic [18:0] rxcrdt_tdata
    );

    // synthesis translate_off
    initial
    begin : error_proc
        if (NUM_OF_SEG != 1)
            $fatal(2, "** ERROR ** %m: This module only works when NUM_OF_SEG is 1 (currently %0d)", NUM_OF_SEG);
        if (SB_HEADERS != 0)
            $fatal(2, "** ERROR ** %m: This module only works with in-band headers");
        if (TDATA_WIDTH != $bits(stream_in_cpld.tdata))
            $fatal(2, "** ERROR ** %m: TDATA_WIDTH does not match AXI-S configuration (%0d vs. %0d)", TDATA_WIDTH, $bits(stream_in_cpld.tdata));
    end
    // synthesis translate_on

    wire clk = stream_in_cpld.clk;
    bit rst_n = 1'b0;

    // Counters managed in the module are synchronized with the PCIe SS, so
    // use its reset.
    bit rxcrdt_rst_n_in_clk;
    ipm_cdc_async_rst
      #(
        .RST_TYPE("ACTIVE_LOW")
        )
      rst_cdc
       (
        .clk,
        .arst_in(rxcrdt_rst_n),
        .srst_out(rxcrdt_rst_n_in_clk)
        );

    always @(posedge clk) begin
        rst_n <= stream_in_cpld.rst_n & rxcrdt_rst_n_in_clk;
    end

    localparam TUSER_WIDTH = $bits(stream_in_cpld.tuser_vendor);

    typedef enum logic [2:0] {
        PH_IDX   = 3'b000,
        NPH_IDX  = 3'b001,
        CPLH_IDX = 3'b010,
        PD_IDX   = 3'b100,
        NPD_IDX  = 3'b101,
        CPLD_IDX = 3'b110
    } crdt_type_e;

    logic [15:0] crdt_cnt[8];


    //
    // Wire together inputs and outputs. This module just monitors traffic.
    //

    ofs_fim_axis_pipeline #(.PL_DEPTH(0), .TDATA_WIDTH(TDATA_WIDTH), .TUSER_WIDTH(TUSER_WIDTH))
        conn_cpld (.clk, .rst_n, .axis_s(stream_in_cpld), .axis_m(stream_out_cpld));
    ofs_fim_axis_pipeline #(.PL_DEPTH(0), .TDATA_WIDTH(TDATA_WIDTH), .TUSER_WIDTH(TUSER_WIDTH))
        conn_req (.clk, .rst_n, .axis_s(stream_in_req), .axis_m(stream_out_req));


    // ====================================================================
    //
    // Completion monitor
    //
    // ====================================================================

    logic cpld_sop;
    logic cpld_upd_valid;
    logic cpld_upd_h;
    logic [8:0] cpld_upd_d;

    wire pcie_ss_hdr_pkg::PCIe_PUCplHdr_t cpl_hdr =
        $bits(pcie_ss_hdr_pkg::PCIe_PUCplHdr_t)'(stream_in_cpld.tdata);

    always_ff @(posedge clk) begin
        if (stream_in_cpld.tvalid && stream_in_cpld.tready)
            cpld_sop <= stream_in_cpld.tlast;

        if (!rst_n)
            cpld_sop <= 1'b1;
    end

    always_ff @(posedge clk) begin
        cpld_upd_valid <= 1'b0;

        if (stream_in_cpld.tvalid && stream_in_cpld.tready) begin
            if (cpld_sop) begin
                cpld_upd_h <= '0;
                cpld_upd_d <= '0;

                if (pcie_ss_hdr_pkg::func_is_completion(cpl_hdr.fmt_type)) begin
                    cpld_upd_h <= 1'b1;

                    if (pcie_ss_hdr_pkg::func_has_data(cpl_hdr.fmt_type)) begin
                        cpld_upd_d <= (11'(cpl_hdr.length) + 3) >> 2;
                    end
                end
            end

            cpld_upd_valid <= stream_in_cpld.tlast;
        end

        if (!rst_n) begin
            cpld_upd_h <= 1'b0;
            cpld_upd_d <= '0;
            cpld_upd_valid <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (cpld_upd_valid) begin
            crdt_cnt[CPLH_IDX] <= crdt_cnt[CPLH_IDX] + cpld_upd_h;
            crdt_cnt[CPLD_IDX] <= crdt_cnt[CPLD_IDX] + cpld_upd_d;
        end

        if (!rst_n) begin
            crdt_cnt[CPLH_IDX] <= CPL_HDR_INIT;
            crdt_cnt[CPLD_IDX] <= CPL_DATA_INIT;
        end
    end


    // ====================================================================
    //
    // Posted/non-posted request monitor
    //
    // ====================================================================

    logic req_sop;
    logic req_upd_valid;
    logic req_p_upd_h;
    logic [8:0] req_p_upd_d;
    logic req_np_upd_h;
    logic [8:0] req_np_upd_d;

    wire pcie_ss_hdr_pkg::PCIe_PUReqHdr_t req_hdr =
        $bits(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t)'(stream_in_req.tdata);

    always_ff @(posedge clk) begin
        if (stream_in_req.tvalid && stream_in_req.tready)
            req_sop <= stream_in_req.tlast;

        if (!rst_n)
            req_sop <= 1'b1;
    end

    always_ff @(posedge clk) begin
        req_upd_valid <= 1'b0;

        if (stream_in_req.tvalid && stream_in_req.tready) begin
            if (req_sop) begin
                req_p_upd_h <= '0;
                req_p_upd_d <= '0;
                req_np_upd_h <= '0;
                req_np_upd_d <= '0;

                if (pcie_ss_hdr_pkg::func_is_mwr_req(req_hdr.fmt_type) ||
                    pcie_ss_hdr_pkg::func_is_msg(req_hdr.fmt_type))
                begin
                    req_p_upd_h <= 1'b1;

                    if (pcie_ss_hdr_pkg::func_has_data(req_hdr.fmt_type)) begin
                        req_p_upd_d <= (11'(req_hdr.length) + 3) >> 2;
                    end
                end else begin
                    req_np_upd_h <= 1'b1;

                    if (pcie_ss_hdr_pkg::func_has_data(req_hdr.fmt_type)) begin
                        req_np_upd_d <= (11'(req_hdr.length) + 3) >> 2;
                    end
                end
            end

            req_upd_valid <= stream_in_req.tlast;
        end

        if (!rst_n) begin
            req_p_upd_h <= 1'b0;
            req_p_upd_d <= '0;
            req_np_upd_h <= 1'b0;
            req_np_upd_d <= '0;
            req_upd_valid <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (req_upd_valid) begin
            crdt_cnt[PH_IDX] <= crdt_cnt[PH_IDX] + req_p_upd_h;
            crdt_cnt[PD_IDX] <= crdt_cnt[PD_IDX] + req_p_upd_d;
            crdt_cnt[NPH_IDX] <= crdt_cnt[NPH_IDX] + req_np_upd_h;
            crdt_cnt[NPD_IDX] <= crdt_cnt[NPD_IDX] + req_np_upd_d;
        end

        if (!rst_n) begin
            crdt_cnt[PH_IDX] <= P_HDR_INIT;
            crdt_cnt[PD_IDX] <= P_DATA_INIT;
            crdt_cnt[NPH_IDX] <= NP_HDR_INIT;
            crdt_cnt[NPD_IDX] <= NP_DATA_INIT;
        end
    end


    // ====================================================================
    //
    // Stream credit updates over rxcrt outputs, including a clock
    // crossing.
    //
    // ====================================================================

    logic [18:0] crdt_fifo_din;
    logic [18:0] crdt_fifo_dout;
    logic crdt_fifo_full;
    logic crdt_fifo_empty;

    logic [2:0] src_crdt_idx;
    assign crdt_fifo_din = { src_crdt_idx, crdt_cnt[src_crdt_idx] };

    always_ff @(posedge clk) begin
        if (!crdt_fifo_full) begin
            // Index isn't dense. 3'b011 and 3'b111 are unused (reserved).
            src_crdt_idx <= src_crdt_idx + ((src_crdt_idx[1:0] == 2'b10) ? 2 : 1);
        end

        if (!rst_n) begin
            src_crdt_idx <= '0;
        end
    end

    fim_dcfifo
      #(
        .DATA_WIDTH(19),
        .DEPTH_RADIX(3),
        .READ_ACLR_SYNC("ON"),
        .RDSYNC_DELAYPIPE_PARAM(3),
        .WRSYNC_DELAYPIPE_PARAM(3)
        )
      crdt_fifo
       (
        .aclr(~rst_n),
        .data(crdt_fifo_din),
        .rdclk(rxcrdt_clk),
        .rdreq(!crdt_fifo_empty),
        .wrclk(clk),
        .wrreq(!crdt_fifo_full && rst_n),
        .q(crdt_fifo_dout),
        .rdempty(crdt_fifo_empty),
        .rdfull(),
        .rdusedw(),
        .wrempty(),
        .wrfull(crdt_fifo_full),
        .wralmfull(),
        .wrusedw()
        );

    logic crdt_fifo_dout_valid;
    always_ff @(posedge rxcrdt_clk) begin
        crdt_fifo_dout_valid <= !crdt_fifo_empty;

        rxcrdt_tvalid <= 1'b0;
        if (crdt_fifo_dout_valid) begin
            rxcrdt_tdata <= crdt_fifo_dout;
            rxcrdt_tvalid <= rxcrdt_rst_n;
        end
    end

endmodule // ofs_fim_pcie_ss_rxcrdt
