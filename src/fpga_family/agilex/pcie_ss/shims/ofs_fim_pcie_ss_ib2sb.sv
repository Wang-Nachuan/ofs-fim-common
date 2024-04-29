// Copyright 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Transform the source PCIe SS TLP stream with in-band headers to a
// stream with side-band headers.
//
// The module works only with headers at bit 0.
//
// Side-band headers are emitted in the high bits of stream_out.
//

module ofs_fim_pcie_ss_ib2sb
  #(
    )
   (
    // Input stream with in-band headers.
    pcie_ss_axis_if.sink stream_in,

    // Output stream with side-band headers. Headers will be added at
    // the high end of tuser_vendor.
    pcie_ss_axis_if.source stream_out
    );

    logic clk;
    assign clk = stream_in.clk;
    logic rst_n;
    assign rst_n = stream_in.rst_n;

    localparam TDATA_WIDTH = $bits(stream_out.tdata);
    localparam TKEEP_WIDTH = TDATA_WIDTH/8;
    localparam IN_TUSER_WIDTH = $bits(stream_in.tuser_vendor);
    localparam OUT_TUSER_WIDTH = $bits(stream_out.tuser_vendor);

    // Size of a header. All header types are the same size.
    localparam HDR_WIDTH = $bits(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t);
    localparam HDR_TKEEP_WIDTH = HDR_WIDTH / 8;

    // Size of the data portion when a header that starts at tdata[0] is also present.
    localparam DATA_AFTER_HDR_WIDTH = TDATA_WIDTH - HDR_WIDTH;
    localparam DATA_AFTER_HDR_TKEEP_WIDTH = DATA_AFTER_HDR_WIDTH / 8;

    // synthesis translate_off
    initial
    begin : error_proc
        if (TDATA_WIDTH != $bits(stream_in.tdata))
            $fatal(2, "** ERROR ** %m: TDATA width mismatch (in %0d, out %0d)", $bits(stream_in.tdata), TDATA_WIDTH);
        if (IN_TUSER_WIDTH + HDR_WIDTH != OUT_TUSER_WIDTH) begin
            $fatal(2, "** ERROR ** %m: TUSER width mismatch (in %0d, out %0d+%0d)", OUT_TUSER_WIDTH,
                   IN_TUSER_WIDTH, HDR_WIDTH);
        end
    end
    // synthesis translate_on


    // ====================================================================
    //
    //  Add a skid buffer on input for timing
    //
    // ====================================================================

    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(IN_TUSER_WIDTH)) source_skid(clk, rst_n);
    ofs_fim_axis_pipeline
        conn_source_skid (.clk, .rst_n, .axis_s(stream_in), .axis_m(source_skid));

    logic source_skid_sop;
    always_ff @(posedge clk)
    begin
        if (source_skid.tready && source_skid.tvalid)
            source_skid_sop <= source_skid.tlast;

        if (!rst_n)
            source_skid_sop <= 1'b1;
    end


    // ====================================================================
    //
    //  Split the headers and data streams
    //
    // ====================================================================

    pcie_ss_axis_if #(.DATA_W(HDR_WIDTH), .USER_W(IN_TUSER_WIDTH)) hdr_stream(clk, rst_n);
    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(IN_TUSER_WIDTH)) data_stream(clk, rst_n);

    logic prev_must_drain;

    // New message available and there is somewhere to put it?
    wire process_msg = source_skid.tvalid && source_skid.tready;
    wire process_drain = prev_must_drain && data_stream.tready;

    assign source_skid.tready = hdr_stream.tready && data_stream.tready;

    //
    // Requirements:
    //  - There is at most one header per beat in the incoming tdata stream.
    //  - All headers begin at tdata[0].
    //

    // Header - only when SOP in the incoming stream
    assign hdr_stream.tvalid = process_msg && source_skid_sop;
    assign hdr_stream.tdata = source_skid.tdata[$bits(pcie_ss_hdr_pkg::PCIe_CplHdr_t)-1 : 0];
    assign hdr_stream.tuser_vendor = source_skid.tuser_vendor;
    assign hdr_stream.tkeep = 64'((65'h1 << ($bits(pcie_ss_hdr_pkg::PCIe_CplHdr_t)) / 8) - 1);
    assign hdr_stream.tlast = 1'b1;


    // Data - either directly from the stream for short messages or
    // by combining the current and previous messages.

    // Record the previous data in case it is needed later.
    logic [TDATA_WIDTH-1:0] prev_payload;
    logic [(TDATA_WIDTH/8)-1:0] prev_keep;
    always_ff @(posedge clk)
    begin
        if (process_drain)
        begin
            prev_must_drain <= 1'b0;
        end
        if (process_msg)
        begin
            prev_payload <= source_skid.tdata;
            prev_keep <= source_skid.tkeep;
            // Either there is data that won't fit in this beat or the data+header
            // is a single beat.
            prev_must_drain <= source_skid.tlast &&
                               (source_skid.tkeep[HDR_TKEEP_WIDTH] || source_skid_sop);
        end

        if (!rst_n)
        begin
            prev_must_drain <= 1'b0;
        end
    end

    // Continuation of multi-cycle data?
    logic payload_is_pure_data;
    assign payload_is_pure_data = !source_skid_sop;

    assign data_stream.tvalid = (process_msg && payload_is_pure_data) || process_drain;

    always_comb
    begin
        data_stream.tlast = (source_skid.tlast && !source_skid.tkeep[HDR_TKEEP_WIDTH]) ||
                            prev_must_drain;
        data_stream.tuser_vendor = '0;

        // Realign data - low part from previous flit, high part from current
        data_stream.tdata =
            { source_skid.tdata[0 +: HDR_WIDTH],
              prev_payload[HDR_WIDTH +: DATA_AFTER_HDR_WIDTH] };
        data_stream.tkeep =
            { source_skid.tkeep[0 +: HDR_TKEEP_WIDTH],
              prev_keep[HDR_TKEEP_WIDTH +: DATA_AFTER_HDR_TKEEP_WIDTH] };

        if (prev_must_drain)
        begin
            data_stream.tdata[DATA_AFTER_HDR_WIDTH +: HDR_WIDTH] = '0;
            data_stream.tkeep[DATA_AFTER_HDR_TKEEP_WIDTH +: HDR_TKEEP_WIDTH] = '0;
        end
    end


    // ====================================================================
    //
    //  Outbound buffers
    //
    // ====================================================================
    
    // Header must be a skid buffer to avoid deadlocks, as headers may arrive
    // before the payload.
    pcie_ss_axis_if #(.DATA_W(HDR_WIDTH), .USER_W(IN_TUSER_WIDTH)) hdr_stream_sink(clk, rst_n);
    ofs_fim_axis_pipeline
        conn_hdr_skid (.clk, .rst_n, .axis_s(hdr_stream), .axis_m(hdr_stream_sink));

    // Just a register
    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(IN_TUSER_WIDTH)) data_stream_sink(clk, rst_n);
    ofs_fim_axis_pipeline #(.MODE(1))
        conn_data_skid (.clk, .rst_n, .axis_s(data_stream), .axis_m(data_stream_sink));

    // Map data and header to a single interface
    logic out_sop;
    assign stream_out.tvalid = data_stream_sink.tvalid && (!out_sop || hdr_stream_sink.tvalid);
    assign stream_out.tdata = data_stream_sink.tdata;
    assign stream_out.tkeep = data_stream_sink.tkeep;
    assign stream_out.tlast = data_stream_sink.tlast;
    assign stream_out.tuser_vendor =
               out_sop ? { hdr_stream_sink.tdata, hdr_stream_sink.tuser_vendor } : '0;
                                     
    assign data_stream_sink.tready = stream_out.tready && (!out_sop || hdr_stream_sink.tvalid);
    assign hdr_stream_sink.tready = stream_out.tready && out_sop && data_stream_sink.tvalid;

    always_ff @(posedge clk)
    begin
        if (stream_out.tvalid && stream_out.tready)
            out_sop <= stream_out.tlast;

        if (!rst_n)
            out_sop <= 1'b1;
    end

endmodule // ofs_fim_pcie_ss_ib2sb
