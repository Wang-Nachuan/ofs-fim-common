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
    always @(clk) begin
        rst_n <= stream_in.rst_n;
    end

    localparam TDATA_WIDTH = $bits(stream_out.tdata);
    localparam TKEEP_WIDTH = TDATA_WIDTH/8;
    localparam IN_TUSER_WIDTH = $bits(stream_in.tuser_vendor);
    localparam OUT_TUSER_WIDTH = $bits(stream_out.tuser_vendor);

    localparam SEG_TDATA_WIDTH = TDATA_WIDTH / NUM_OF_SEG;
    localparam SEG_TKEEP_WIDTH = TKEEP_WIDTH / NUM_OF_SEG;

    typedef logic [NUM_OF_SEG-1:0][SEG_TDATA_WIDTH-1:0] t_seg_tdata;
    typedef logic [NUM_OF_SEG-1:0][SEG_TKEEP_WIDTH-1:0] t_seg_tkeep;
    typedef ofs_fim_pcie_ss_shims_pkg::t_tuser_seg [NUM_OF_SEG-1:0] t_seg_tuser;
    typedef ofs_fim_pcie_ss_shims_pkg::t_tuser_seg t_out_tuser;

    typedef struct packed {
        t_seg_tdata tdata;
        t_seg_tkeep tkeep;
        t_seg_tuser tuser;
    } t_seg_bus;

    // synthesis translate_off
    initial
    begin : error_proc
        if (TDATA_WIDTH != $bits(stream_in.tdata))
            $fatal(2, "** ERROR ** %m: TDATA width mismatch (in %0d, out %0d)", $bits(stream_in.tdata), TDATA_WIDTH);
        if ($bits(t_seg_tuser) != IN_TUSER_WIDTH)
            $fatal(2, "** ERROR ** %m: stream_in TUSER width mismatch (%0d, expected %0d)",
                   IN_TUSER_WIDTH, $bits(t_seg_tuser));
        if ($bits(t_out_tuser) != OUT_TUSER_WIDTH)
            $fatal(2, "** ERROR ** %m: stream_out TUSER width mismatch (%0d, expected %0d)",
                   OUT_TUSER_WIDTH, $bits(t_out_tuser));
    end
    // synthesis translate_on


    // ====================================================================
    //
    //  Add a skid buffer on input for timing
    //
    // ====================================================================

    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(IN_TUSER_WIDTH)) source(clk, rst_n);

    ofs_fim_axis_pipeline
      #(
        .TDATA_WIDTH(TDATA_WIDTH),
        .TUSER_WIDTH(IN_TUSER_WIDTH)
        )
      in_skid (.clk, .rst_n, .axis_s(stream_in), .axis_m(source));

    t_seg_bus source_segs;
    assign source_segs.tdata = source.tdata;
    assign source_segs.tkeep = source.tkeep;
    assign source_segs.tuser = source.tuser_vendor;


    // ====================================================================
    //
    //  Pack TLPs densely at the low end of the vector. It will be easier
    //  to pack TLPs across AXI stream messages if the location of valid
    //  data is well known.
    //
    // ====================================================================

    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(IN_TUSER_WIDTH)) dense_map(clk, rst_n);
    t_seg_bus dense_map_segs;
    assign dense_map.tdata = dense_map_segs.tdata;
    assign dense_map.tkeep = dense_map_segs.tkeep;
    assign dense_map.tuser_vendor = dense_map_segs.tuser;
    assign dense_map.tlast = source.tlast;

    logic some_source_slot_valid;
    typedef logic [$clog2(NUM_OF_SEG)-1 : 0] t_in_slot_idx;
    t_in_slot_idx dense_mapper[NUM_OF_SEG];
    t_in_slot_idx num_source_valid;

    // Generate a mapping from the input to the dense mapping by counting
    // the number of valid entries below each position.
    always_comb
    begin
        some_source_slot_valid = 1'b0;
        num_source_valid = '0;

        for (int i = 0; i < NUM_OF_SEG; i = i + 1)
        begin
            // Where should input slot "i" go in the dense mapping?
            dense_mapper[i] = num_source_valid;

            some_source_slot_valid = some_source_slot_valid ||
                                     source_segs.tkeep[i][0] || source_segs.tuser[i].hvalid;
            num_source_valid = num_source_valid +
                               t_in_slot_idx'(source_segs.tkeep[i][0] || source_segs.tuser[i].hvalid);
        end
    end

    // Use the mapping to assign the positions in the dense mapping data vector
    t_in_slot_idx tgt_slot;
    always_comb
    begin
        dense_map_segs = '0;

        // Push TLPs to the low vector slots
        for (int i = 0; i < NUM_OF_SEG; i = i + 1)
        begin
            tgt_slot = dense_mapper[i];

            dense_map_segs.tdata[tgt_slot] = source_segs.tdata[i];
            dense_map_segs.tkeep[tgt_slot] = source_segs.tkeep[i];
            dense_map_segs.tuser[tgt_slot] = source_segs.tuser[i];
        end
    end

    // Write the dense mapping to a register
    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(IN_TUSER_WIDTH)) source_dense(clk, rst_n);
    t_seg_bus source_dense_segs;
    assign source_dense_segs.tdata = source_dense.tdata;
    assign source_dense_segs.tkeep = source_dense.tkeep;
    assign source_dense_segs.tuser = source_dense.tuser_vendor;

    ofs_fim_axis_pipeline
      #(
        .MODE(1),
        .TDATA_WIDTH(TDATA_WIDTH),
        .TUSER_WIDTH(IN_TUSER_WIDTH)
        )
      dense (.clk, .rst_n, .axis_s(dense_map), .axis_m(source_dense));

    assign dense_map.tvalid = source.tvalid && some_source_slot_valid;
    assign source.tready = dense_map.tready;


    // ====================================================================
    //
    //  Transform the source stream to the sink stream, enforcing the
    //  guarantees listed at the top of the module.
    //
    // ====================================================================

    // Shift register to merge flits segments across multiple AXI stream
    // flits.
    localparam NUM_WORK_SEG = NUM_OF_SEG*2 - 1;
    // Leave an extra index bit in order to represent one beyond the last slot.
    typedef logic [$clog2(NUM_WORK_SEG) : 0] t_work_ch_idx;

    struct packed {
        bit [SEG_TDATA_WIDTH-1:0] tdata;
        bit [SEG_TKEEP_WIDTH-1:0] tkeep;
        ofs_fim_pcie_ss_shims_pkg::t_tuser_seg tuser;
    } work_reg[NUM_WORK_SEG];

    // valid/eop/sop bits from work_reg, mapped to dense vectors
    logic [NUM_WORK_SEG-1 : 0] work_valid;
    logic [NUM_WORK_SEG-1 : 0] work_sop;
    logic [NUM_WORK_SEG-1 : 0] work_eop;

    always_comb
    begin
        for (int i = 0; i < NUM_WORK_SEG; i = i + 1)
        begin
            work_valid[i] = work_reg[i].tkeep[0] || work_reg[i].tuser.hvalid;
            work_sop[i] = work_reg[i].tuser.hvalid;
            work_eop[i] = work_reg[i].tuser.last_segment;
        end
    end

    logic work_full, work_empty;
    // Can't add new flits if the sink portion of the work register is full.
    // Valid segments are packed densely, so only the last entry has to be
    // checked.
    assign work_full = work_valid[NUM_OF_SEG-1];
    assign work_empty = !work_valid[0];

    // The outbound work is "valid" only if the vector is full or a packet
    // is terminated.
    logic work_out_valid, work_out_ready;
    assign work_out_valid = &(work_valid[NUM_OF_SEG-1 : 0]) ||
                            |(work_eop[NUM_OF_SEG-1 : 0]);

    // Mask of outbound entries to forward as a group, terminated by EOP.
    logic [NUM_OF_SEG-1 : 0] work_out_valid_mask;
    t_work_ch_idx work_out_num_valid;

    always_comb
    begin
        work_out_num_valid = t_work_ch_idx'(NUM_OF_SEG);
        for (int i = 0; i < NUM_OF_SEG; i = i + 1)
        begin
            if (!work_valid[i])
            begin
                work_out_num_valid = t_work_ch_idx'(i);
                break;
            end
            else if (work_eop[i])
            begin
                work_out_num_valid = t_work_ch_idx'(i + 1);
                break;
            end
        end

        work_out_valid_mask[0] = work_valid[0];
        for (int i = 1; i < NUM_OF_SEG; i = i + 1)
        begin
            work_out_valid_mask[i] = work_valid[i] && work_out_valid_mask[i-1] &&
                                     !work_eop[i-1];
        end
    end

    // Does the work vector have an SOP entry that isn't in the lowest
    // slot? If so, then even if work_out_ready is true there may not
    // be enough space for incoming values.
    logic work_has_blocking_sop;

    always_comb
    begin
        work_has_blocking_sop = 1'b0;
        for (int i = 1; i < NUM_OF_SEG; i = i + 1)
        begin
            work_has_blocking_sop = work_has_blocking_sop ||
                                    (work_valid[i] && work_sop[i]);
        end
    end

    // Index of the currently first invalid segment in the vector
    t_work_ch_idx work_first_invalid;

    always_comb
    begin
        work_first_invalid = t_work_ch_idx'(NUM_WORK_SEG);
        for (int i = 0; i < NUM_WORK_SEG; i = i + 1)
        begin
            if (!work_valid[i])
            begin
                work_first_invalid = t_work_ch_idx'(i);
                break;
            end
        end
    end

    // Next insertion point, taking into account outbound entries
    t_work_ch_idx next_insertion_idx;
    assign next_insertion_idx =
        work_first_invalid -
        ((work_out_valid & work_out_ready) ? work_out_num_valid : '0);

    //
    // Finally, we are ready to update the work vectors.
    //
    assign source_dense.tready = (!work_full ||
                                  (work_out_ready && !work_has_blocking_sop));

    always_ff @(posedge clk)
    begin
        if (work_out_valid && work_out_ready)
        begin
            // Shift work entries not forwarded this cycle
            for (int i = 0; i < NUM_WORK_SEG; i = i + 1)
            begin
                work_reg[i] <= work_reg[i + work_out_num_valid];

                // Clear entries with values shifted out
                if (i >= (NUM_WORK_SEG - work_out_num_valid))
                begin
                    work_reg[i].tkeep <= '0;
                    work_reg[i].tuser.hvalid <= 1'b0;
                    work_reg[i].tuser.last_segment <= 1'b0;
                end
            end
        end

        // Add new entries
        if (source_dense.tvalid && source_dense.tready)
        begin
            for (int i = 0; i < NUM_OF_SEG; i = i + 1)
            begin
                work_reg[i + next_insertion_idx].tdata <= source_dense_segs.tdata[i];
                work_reg[i + next_insertion_idx].tkeep <= source_dense_segs.tkeep[i];
                work_reg[i + next_insertion_idx].tuser <= source_dense_segs.tuser[i];
            end
        end

        if (!rst_n)
        begin
            for (int i = 0; i < NUM_WORK_SEG; i = i + 1)
            begin
                work_reg[i].tkeep <= '0;
                work_reg[i].tuser.hvalid <= 1'b0;
                work_reg[i].tuser.last_segment <= 1'b0;
            end
        end
    end

    // Another instance of the interface just to define a t_payload instance
    // for mapping vector entries.
    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(OUT_TUSER_WIDTH)) work_out(clk, rst_n);
    t_seg_bus work_out_segs;
    assign work_out.tdata = work_out_segs.tdata;
    assign work_out.tkeep = work_out_segs.tkeep;
    assign work_out.tuser_vendor = work_out_segs.tuser[0];
    assign work_out.tvalid = work_out_valid;
    assign work_out_ready = work_out.tready;

    // Final mapping of this cycle's work_reg to a stream interface
    always_comb
    begin
        work_out.tlast = 1'b0;

        for (int i = 0; i < NUM_OF_SEG; i = i + 1)
        begin
            work_out_segs.tdata[i] = work_reg[i].tdata;
            work_out_segs.tkeep[i] =
                (work_reg[i].tkeep[0] && work_out_valid_mask[i]) ? work_reg[i].tkeep : '0;

            work_out_segs.tuser[i] = work_reg[i].tuser;
            work_out_segs.tuser[i].hvalid = work_reg[i].tuser.hvalid && work_out_valid_mask[i];
            work_out_segs.tuser[i].last_segment = work_reg[i].tuser.last_segment && work_out_valid_mask[i];

            work_out.tlast |= work_out_segs.tuser[i].last_segment;
        end
    end

    ofs_fim_axis_pipeline
      #(
        .TDATA_WIDTH(TDATA_WIDTH),
        .TUSER_WIDTH(OUT_TUSER_WIDTH)
        )
      to_sink (.clk, .rst_n, .axis_s(work_out), .axis_m(stream_out));

endmodule // ofs_fim_pcie_ss_rx_seg_align
