// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Convert PCIe SS side-band header to in-band. SOP is only supported
// at bit 0. The AXI-S must first be mapped to one request per cycle,
// with requests starting at bit 0, before the module here can be used.
//
// Pass side-band headers at the end of stream_in.tuser_vendor.
//

module ofs_fim_pcie_ss_sb2ib
  #(
    // Allow control of inbound pipeline mode to save area. Default to
    // skid buffer.
    parameter PL_MODE_IN = 0
    )
   (
    // Input stream with side-band headers. Put the header at the end of
    // tuser_vendor.
    pcie_ss_axis_if.sink stream_in,

    // Output stream. tuser_vendor must be reduced by the size of a header.
    pcie_ss_axis_if.source stream_out
    );

    logic clk;
    assign clk = stream_out.clk;
    logic rst_n;
    assign rst_n = stream_out.rst_n;

    localparam TDATA_WIDTH = $bits(stream_out.tdata);
    localparam TKEEP_WIDTH = TDATA_WIDTH/8;
    localparam OUT_TUSER_WIDTH = $bits(stream_out.tuser_vendor);
    localparam IN_TUSER_WIDTH = $bits(stream_in.tuser_vendor);

    // Size of a header. All header types are the same size.
    localparam HDR_WIDTH = $bits(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t);
    localparam HDR_TKEEP_WIDTH = HDR_WIDTH / 8;
    localparam HDR_START_BIT = OUT_TUSER_WIDTH;

    // Size of the data portion when a header that starts at tdata[0] is also present.
    localparam DATA_AFTER_HDR_WIDTH = TDATA_WIDTH - HDR_WIDTH;
    localparam DATA_AFTER_HDR_TKEEP_WIDTH = DATA_AFTER_HDR_WIDTH / 8;

    // synthesis translate_off
    initial
    begin : error_proc
        if (TDATA_WIDTH != $bits(stream_in.tdata))
            $fatal(2, "** ERROR ** %m: TDATA width mismatch (in %0d, out %0d)", $bits(stream_in.tdata), TDATA_WIDTH);
        if (OUT_TUSER_WIDTH + HDR_WIDTH != IN_TUSER_WIDTH) begin
            $fatal(2, "** ERROR ** %m: TUSER width mismatch (in %0d, out %0d+%0d)", IN_TUSER_WIDTH,
                   OUT_TUSER_WIDTH, HDR_WIDTH);
        end
    end
    // synthesis translate_on


    // ====================================================================
    //
    //  Register input for timing
    //
    // ====================================================================

    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(IN_TUSER_WIDTH)) source(clk, rst_n);

    ofs_fim_axis_pipeline
      #(
        .MODE(PL_MODE_IN),
        .TDATA_WIDTH(TDATA_WIDTH),
        .TUSER_WIDTH(IN_TUSER_WIDTH)
        )
      in_skid (.clk, .rst_n, .axis_s(stream_in), .axis_m(source));


    // ====================================================================
    //
    //  Merge the headers and data streams
    //
    // ====================================================================

    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(OUT_TUSER_WIDTH)) sink_skid(clk, rst_n);

    //
    // Track EOP/SOP of the outgoing stream in order to handle
    // hdr and data messages in order.
    //
    logic source_is_sop;

    always_ff @(posedge clk)
    begin
        if (source.tready && source.tvalid)
        begin
            source_is_sop <= source.tlast;
        end

        if (!rst_n)
        begin
            source_is_sop <= 1'b1;
        end
    end

    //
    // This is a very simple case:
    //  - There is at most one header (SOP) in the incoming tdata stream.
    //  - All headers begin at tdata[0].
    //

    // Track data remaining from the previous cycle
    logic prev_data_valid;
    logic [TDATA_WIDTH-1:0] prev_data;
    logic [(TDATA_WIDTH/8)-1:0] prev_data_keep;

    pcie_ss_hdr_pkg::PCIe_CplHdr_t hdr_source;
    assign hdr_source = pcie_ss_hdr_pkg::PCIe_CplHdr_t'(source.tuser_vendor[HDR_START_BIT +: HDR_WIDTH]);

    wire source_is_single_beat =
        !pcie_ss_hdr_pkg::func_has_data(hdr_source.fmt_type) ||
        !source.tkeep[DATA_AFTER_HDR_TKEEP_WIDTH];

    always_ff @(posedge clk)
    begin
        if (sink_skid.tvalid && sink_skid.tready)
        begin
            if (source.tready)
            begin
                // Does the current cycle's source data fit completely in the
                // sink data vector? If this isn't the SOP beat then the
                // last beat fits if it is shorter than the injected header.
                // If this is an SOP beat then there will be previous data
                // if the message doesn't fit in a single beat.
                prev_data_valid <= ((!source_is_sop && source.tkeep[DATA_AFTER_HDR_TKEEP_WIDTH]) ||
                                    (source_is_sop && !source_is_single_beat));
            end
            else
            begin
                // Must have written out prev_data to sink_skid this cycle, since
                // a message was passed to sink_skid but nothing was consumed
                // from source.
                prev_data_valid <= 1'b0;
            end
        end

        if (!rst_n)
        begin
            prev_data_valid <= 1'b0;
        end
    end

    // Update the stored data
    always_ff @(posedge clk)
    begin
        // As long as something is written to the outbound stream it is safe
        // to update the stored data. If the input data stream is unconsumed
        // this cycle then the stored data is being flushed out with nothing
        // new to replace it. (prev_data_valid will be 0.)
        if (sink_skid.tvalid && sink_skid.tready)
        begin
            // Stored data is always shifted by the same amount: the size
            // of the TLP header.
            prev_data <= { '0, source.tdata[DATA_AFTER_HDR_WIDTH +: HDR_WIDTH] };
            prev_data_keep <= { '0, source.tkeep[DATA_AFTER_HDR_TKEEP_WIDTH +: HDR_TKEEP_WIDTH] };
        end
    end

    // Consume incoming data? If SOP, then only if all previous
    // data has been emitted. If not SOP, then yes as long
    // as the outbound stream is ready.
    assign source.tready = source.tvalid && sink_skid.tready &&
                           (!source_is_sop || !prev_data_valid);

    // Write outbound TLP traffic? Yes if consuming incoming data or if
    // the previous packet is complete and data from it remains.
    assign sink_skid.tvalid = source.tready ||
                              (source_is_sop && prev_data_valid);

    // Generate the outbound payload
    always_comb
    begin
        if (source_is_sop && source.tready)
        begin
            // SOP: payload is first portion of data + header
            sink_skid.tdata = { source.tdata[0 +: DATA_AFTER_HDR_WIDTH], hdr_source };
            sink_skid.tkeep = { source.tkeep[0 +: DATA_AFTER_HDR_TKEEP_WIDTH],
                                {(HDR_TKEEP_WIDTH){1'b1}} };
            sink_skid.tlast = source_is_single_beat;
            sink_skid.tuser_vendor = source.tuser_vendor[OUT_TUSER_WIDTH-1 : 0];
        end
        else
        begin
            sink_skid.tdata = { source.tdata[0 +: DATA_AFTER_HDR_WIDTH],
                                prev_data[0 +: HDR_WIDTH] };
            sink_skid.tkeep = { source.tkeep[0 +: DATA_AFTER_HDR_TKEEP_WIDTH],
                                prev_data_keep[0 +: HDR_TKEEP_WIDTH] };
            if (source_is_sop)
            begin
                // New data isn't being being consumed -- only the prev_data is
                // valid.
                sink_skid.tdata[HDR_WIDTH +: DATA_AFTER_HDR_WIDTH] = '0;
                sink_skid.tkeep[HDR_TKEEP_WIDTH +: DATA_AFTER_HDR_TKEEP_WIDTH] = '0;
            end

            sink_skid.tlast = source_is_sop || !source.tkeep[DATA_AFTER_HDR_TKEEP_WIDTH];
            sink_skid.tuser_vendor = '0;
        end
    end


    // ====================================================================
    //
    //  Outbound skid buffers
    //
    // ====================================================================

    ofs_fim_axis_pipeline
      #(
        .TDATA_WIDTH(TDATA_WIDTH),
        .TUSER_WIDTH(OUT_TUSER_WIDTH)
        )
      conn_sink_skid (.clk, .rst_n, .axis_s(sink_skid), .axis_m(stream_out));

endmodule // ofs_fim_pcie_ss_sb2ib
