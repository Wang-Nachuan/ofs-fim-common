// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Accept stream_in -- a packet stream where there may be multiple headers
// and empty segments in a cycle.
//
// Both in-band and side-band headers are supported. 
//
// The output in stream_out guarantees:
//  1. At most one SOP is set. That SOP will always be in slot 0.
//  2. Entries beyond an EOP are empty. (A consequence of #1.)
//
// The tuser_vendor field in stream_in must be a [NUM_OF_SEG-1:0] array
// of ofs_fim_pcie_ss_shims_pkg::t_tuser_seg, holding all tuser
// information. When in-band headers are used, the t_user_seg hdr field
// will be unused.
//
// Since the output of the module has a single packet, the tuser_vendor
// field in stream_out is a single instance of
// ofs_fim_pcie_ss_shims_pkg::t_tuser_seg.
//

module ofs_fim_pcie_ss_rx_seg_align
  #(
    parameter NUM_OF_SEG = 2
    )
   (
    // Input stream with NUM_OF_SEG segments
    pcie_ss_axis_if.sink stream_in,

    // Output stream, mapped to one SOP at 0.
    pcie_ss_axis_if.source stream_out
    );

    wire clk = stream_in.clk;
    bit rst_n = 1'b0;
    always @(posedge clk) begin
        rst_n <= stream_in.rst_n;
    end

    localparam TDATA_WIDTH = $bits(stream_out.tdata);
    localparam TKEEP_WIDTH = TDATA_WIDTH/8;
    localparam IN_TUSER_WIDTH = $bits(stream_in.tuser_vendor);
    localparam OUT_TUSER_WIDTH = $bits(stream_out.tuser_vendor);

    localparam SEG_TDATA_WIDTH = TDATA_WIDTH / NUM_OF_SEG;
    localparam SEG_TKEEP_WIDTH = TKEEP_WIDTH / NUM_OF_SEG;

    // synthesis translate_off
    initial begin : error_proc
        if (TDATA_WIDTH != $bits(stream_in.tdata))
            $fatal(2, "** ERROR ** %m: TDATA width mismatch (in %0d, out %0d)", $bits(stream_in.tdata), TDATA_WIDTH);
        if (NUM_OF_SEG * $bits(ofs_fim_pcie_ss_shims_pkg::t_tuser_seg) != IN_TUSER_WIDTH)
            $fatal(2, "** ERROR ** %m: stream_in TUSER width mismatch (%0d, expected %0d)",
                   IN_TUSER_WIDTH, NUM_OF_SEG * $bits(ofs_fim_pcie_ss_shims_pkg::t_tuser_seg));
        if ($bits(ofs_fim_pcie_ss_shims_pkg::t_tuser_seg) != OUT_TUSER_WIDTH)
            $fatal(2, "** ERROR ** %m: stream_out TUSER width mismatch (%0d, expected %0d)",
                   OUT_TUSER_WIDTH, $bits(ofs_fim_pcie_ss_shims_pkg::t_tuser_seg));
    end
    // synthesis translate_on


    // ====================================================================
    //
    //  Transform the source stream to the sink stream, enforcing the
    //  guarantees listed at the top of the module.
    //
    // ====================================================================

    // The work bus is 2 instances of the incoming bus.
    localparam NUM_WORK_SEG = NUM_OF_SEG * 2;

    struct packed {
        logic [NUM_WORK_SEG-1:0][SEG_TDATA_WIDTH-1:0] tdata;
        logic [NUM_WORK_SEG-1:0][SEG_TKEEP_WIDTH-1:0] tkeep;
        ofs_fim_pcie_ss_shims_pkg::t_tuser_seg [NUM_WORK_SEG-1:0] tuser;
    } work_bus;

    // Segment index into full work bus
    typedef logic [$clog2(NUM_WORK_SEG)-1 : 0] t_work_seg_idx;
    // Segment index into low half of work bus
    typedef logic [$clog2(NUM_OF_SEG)-1 : 0] t_work_low_seg_idx;

    // valid/eop/sop bits from work_bus, mapped to dense vectors
    logic [NUM_WORK_SEG-1 : 0] work_valid;
    logic [NUM_WORK_SEG-1 : 0] work_sop;
    logic [NUM_WORK_SEG-1 : 0] work_eop;

    for (genvar i = 0; i < NUM_WORK_SEG; i = i + 1) begin : v
        assign work_valid[i] = work_bus.tkeep[i][0] || work_bus.tuser[i].hvalid;
        assign work_sop[i] = work_bus.tuser[i].hvalid;
        assign work_eop[i] = work_bus.tuser[i].last_segment;
    end

    // Pick a contiguous group of segments to emit as the next output cycle.
    // The group must start in the low half of the work bus but may include
    // some segments from the high half.
    logic work_out_valid;
    logic work_out_ready;
    t_work_low_seg_idx work_out_start_idx;
    // Mask of segments chosen this cycle in the work bus
    logic [NUM_WORK_SEG-1 : 0] work_out_seg_mask;
    // Mask of segments in the output bus. The number of bits set will always be
    // the same as work_out_seg_mask, but the first bit set will always be bit 0.
    logic [NUM_OF_SEG-1 : 0] out_seg_mask;

    always_comb begin
        work_out_valid = 1'b0;
        work_out_start_idx = 0;
        work_out_seg_mask = '0;
        out_seg_mask = '0;

        for (int i = 0; i < NUM_OF_SEG; i += 1) begin
            if (work_valid[i]) begin
                work_out_valid = &work_valid[i +: NUM_OF_SEG] || |work_eop[i +: NUM_OF_SEG];
                work_out_start_idx = i;

                // Generate a mask for the chosen output segments
                work_out_seg_mask[i] = 1'b1;
                out_seg_mask[0] = 1'b1;
                for (int j = 1; j < NUM_OF_SEG; j += 1) begin
                    // Stop at next SOP
                    if (work_sop[i + j]) break;
                    work_out_seg_mask[i + j] = 1'b1;
                    out_seg_mask[j] = 1'b1;
                end

                break;
            end
        end
    end

    // Update the work bus

    // Work bus will shift high half to low half if the low half is empty or
    // complete.
    wire shift_work_bus = ~|work_valid[0 +: NUM_OF_SEG] ||
                          (work_out_valid && work_out_ready && work_out_seg_mask[NUM_OF_SEG-1]);

    assign stream_in.tready = shift_work_bus || ~|work_valid[NUM_OF_SEG +: NUM_OF_SEG];

    always_ff @(posedge clk)
    begin
        // Mark emitted low segments invalid in case there is another SOP in the
        // low half of the work bus. These will be overwritten if the high half
        // is shifted into the low half.
        for (int i = 0; i < NUM_OF_SEG; i += 1) begin
            if (work_out_valid && work_out_ready && work_out_seg_mask[i]) begin
                work_bus.tkeep[i][0] <= '0;
                work_bus.tuser[i].hvalid <= 1'b0;
                work_bus.tuser[i].last_segment <= 1'b0;
            end
        end

        // Shift high half to low half if the low half is or will become empty.
        if (shift_work_bus) begin
            work_bus.tdata[0 +: NUM_OF_SEG] <= work_bus.tdata[NUM_OF_SEG +: NUM_OF_SEG];
            work_bus.tkeep[0 +: NUM_OF_SEG] <= work_bus.tkeep[NUM_OF_SEG +: NUM_OF_SEG];
            work_bus.tuser[0 +: NUM_OF_SEG] <= work_bus.tuser[NUM_OF_SEG +: NUM_OF_SEG];

            // Clear the high half. These will be overwritten if new data arrives.
            for (int i = NUM_OF_SEG; i < 2 * NUM_OF_SEG; i += 1) begin
                work_bus.tkeep[i][0] <= '0;
                work_bus.tuser[i].hvalid <= 1'b0;
                work_bus.tuser[i].last_segment <= 1'b0;
            end

            // Clear the entries from the high half, now in the low half, that were
            // just emitted this cycle. The loop terminates 1 cycle before the end
            // of the low segment because it's impossible to emit the last entry of
            // the high segment.
            for (int i = 0; i < NUM_OF_SEG-1; i += 1) begin
                if (work_out_seg_mask[i + NUM_OF_SEG]) begin
                    work_bus.tkeep[i][0] <= '0;
                    work_bus.tuser[i].hvalid <= 1'b0;
                    work_bus.tuser[i].last_segment <= 1'b0;
                end
            end
        end

        // Add new data if the high half of the work bus is available.
        if (stream_in.tready && stream_in.tvalid) begin
            work_bus.tdata[NUM_OF_SEG +: NUM_OF_SEG] <= stream_in.tdata;
            work_bus.tkeep[NUM_OF_SEG +: NUM_OF_SEG] <= stream_in.tkeep;
            work_bus.tuser[NUM_OF_SEG +: NUM_OF_SEG] <= stream_in.tuser_vendor;
        end

        if (!rst_n)
        begin
            for (int i = 0; i < NUM_WORK_SEG; i = i + 1)
            begin
                work_bus.tkeep[i][0] <= '0;
                work_bus.tuser[i].hvalid <= 1'b0;
                work_bus.tuser[i].last_segment <= 1'b0;
            end
        end
    end


    // ====================================================================
    //
    //  Map chosen work bus region to output.
    //
    // ====================================================================

    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(OUT_TUSER_WIDTH)) work_out(clk, rst_n);

    logic [NUM_OF_SEG-1:0][SEG_TKEEP_WIDTH-1:0] work_out_tkeep;

    assign work_out.tvalid = work_out_valid;
    assign work_out_ready = work_out.tready;
    assign work_out.tdata = work_bus.tdata[work_out_start_idx +: NUM_OF_SEG];
    assign work_out.tkeep = work_out_tkeep;
    assign work_out.tuser_vendor = work_bus.tuser[work_out_start_idx];

    // Final mapping of this cycle's work_bus to a stream interface
    always_comb
    begin
        // Segment 0 must be set or work_out_valid will be false
        work_out_tkeep[0] = work_bus.tkeep[work_out_start_idx];
        work_out.tlast = work_bus.tuser[work_out_start_idx].last_segment;

        for (int i = 1; i < NUM_OF_SEG; i = i + 1)
        begin
            if (out_seg_mask[i]) begin
                work_out_tkeep[i] = work_bus.tkeep[work_out_start_idx + i];
                work_out.tlast |= work_bus.tuser[work_out_start_idx + i].last_segment;
            end else begin
                work_out_tkeep[i] = '0;
            end
        end
    end

    ofs_fim_axis_pipeline
      to_sink (.clk, .rst_n, .axis_s(work_out), .axis_m(stream_out));

endmodule // ofs_fim_pcie_ss_rx_seg_align
