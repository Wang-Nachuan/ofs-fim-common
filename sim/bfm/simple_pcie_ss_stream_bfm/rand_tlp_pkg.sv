// Copyright 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// BFM for testing modules at the boundary between OFS and the PCIe SS.
//
// rand_tlp is a container for simple TLP packets of 3 flavors: completion,
// request with data and request without data. It is used either as a TLP
// generator, with random values, or to construct a TLP packet from a bus.
//
// rand_tlp_stream generates a stream of TLP packets on a bus. It can
// generate in-band or side-band headers and more than one header per
// cycle. This class is typically used in a pipeline ahead of
// the DUT. See the parameters on rand_tlp_stream.
//
// bus_to_tlp consumes a bus with either in-band or side-band headers
// and maps it to the rand_tlp class. This class is typically used at the
// end of a pipeline, following the DUT.
//

package rand_tlp_pkg;

    //
    // Single random TLP
    //
    class rand_tlp;
        typedef enum { TLP_CPLD, TLP_WITH_DATA, TLP_NO_DATA } tlp_type_e;

        rand tlp_type_e tlp_type;

        // Only one of these headers will be active, depending on tlp_type
        pcie_ss_hdr_pkg::PCIe_PUReqHdr_t req_hdr;
        pcie_ss_hdr_pkg::PCIe_PUCplHdr_t cpl_hdr;

        // Payload (not used with TLP_NO_DATA). Random length, up to 128 DWORDs
        // and random content.
        rand bit [31:0] payload_dw[];
        constraint payload_size_c {payload_dw.size() inside {[1:128]};}

        // Tags are allocated sequentially
        local static bit [9:0] next_tag = 1;

        function new(bit random = 1,
                     bit set_tlp_type = 0, tlp_type_e forced_tlp_type = TLP_CPLD);
            req_hdr = 'x;
            cpl_hdr = 'x;

            // Skip setup if not a random packet
            if (!random)
                return;

            randomize();

            if (set_tlp_type)
                tlp_type = forced_tlp_type;

            // Fill in header details. For the purposes of the test very few
            // fields are required. Tests are generally for packet routing
            // and data integrity.

            if (tlp_type == TLP_CPLD) begin
                cpl_hdr = '0;
                cpl_hdr.fmt_type = pcie_ss_hdr_pkg::DM_CPL;
                { cpl_hdr.tag_h, cpl_hdr.tag_m, cpl_hdr.tag_l } = next_tag++;
                cpl_hdr.length = payload_dw.size();
                cpl_hdr.byte_count = payload_dw.size() * 4;
                cpl_hdr.metadata_l = $urandom();
            end else begin
                req_hdr = '0;
                { req_hdr.tag_h, req_hdr.tag_m, req_hdr.tag_l } = next_tag++;
                req_hdr.host_addr_h[31:2] = $urandom();
                req_hdr.length = payload_dw.size();
                req_hdr.last_dw_be = 4'hf;
                req_hdr.first_dw_be = 4'hf;

                if (tlp_type == TLP_NO_DATA) begin
                    payload_dw.delete();
                    req_hdr.fmt_type = pcie_ss_hdr_pkg::M_RD;
                end else begin
                    req_hdr.fmt_type = pcie_ss_hdr_pkg::M_WR;
                end
            end
        endfunction // new

        // TLP to string
        function automatic string sfmt();
            string s;
            if (tlp_type == TLP_CPLD)
              s = pcie_ss_hdr_pkg::func_hdr_to_string(1, cpl_hdr);
            else
              s = pcie_ss_hdr_pkg::func_hdr_to_string(1, req_hdr);

            if (payload_dw.size() != 0) begin
                s = {s, $sformatf(", payload DW 0x%0h:", payload_dw.size())};
                for (int i = 0; i < payload_dw.size(); i++) begin
                    s = {s, $sformatf(" %h", payload_dw[i])};
                    if (i == 4) begin
                        s = {s, "..."};
                        break;
                    end
                end
            end

            return s;
        endfunction // sprintf

        function void display();
            $display("%0s", this.sfmt());
        endfunction // display

        // Compare this TLP to another reference instance.
        task compare(rand_tlp tlp_ref);
            assert(tlp_type == tlp_ref.tlp_type) else
                $fatal(1, "TLP does not match reference: %0s, expected %0s",
                       tlp_type.name(), tlp_ref.tlp_type.name());

            if (tlp_type == TLP_CPLD)
                assert(cpl_hdr == tlp_ref.cpl_hdr) else
                    $fatal(1, "TLP cpl_hdr does not match reference: %h, expected %h",
                           cpl_hdr, tlp_ref.cpl_hdr);
            else
                assert(req_hdr == tlp_ref.req_hdr) else
                    $fatal(1, "TLP req_hdr does not match reference: %h, expected %h",
                           req_hdr, tlp_ref.req_hdr);

            assert(payload_dw == tlp_ref.payload_dw) else
                $fatal(1, "TLP payload not match reference!");
        endtask // compare
    endclass // rand_tlp

    //
    // A stream of random TLPs, mapped to a bus.
    //
    class rand_tlp_stream
      #(
        parameter DATA_WIDTH = 512,
        parameter NUM_OF_SEG = 1,
        // Non-zero for side-band headers, otherwise in-band
        parameter SB_HEADERS = 0,
        // Limit the number of packets that can start per cycle
        parameter MAX_SOP_PER_CYCLE = NUM_OF_SEG
        );

        localparam HDR_WIDTH = 256;
        localparam SEG_WIDTH = DATA_WIDTH / NUM_OF_SEG;
        // Data width in DWORDs
        localparam DATA_WIDTH_DW = DATA_WIDTH / 32;

        typedef logic [DATA_WIDTH-1:0] t_data;
        typedef logic [DATA_WIDTH/8-1:0] t_keep;
        typedef logic [NUM_OF_SEG-1:0][HDR_WIDTH-1:0] t_user_hdr;

        // Standard PCIe SS AXI-S components
        logic tvalid;
        t_data tdata;
        t_keep tkeep;
        logic tlast;
        logic [NUM_OF_SEG-1:0] tuser_vendor;
        logic [NUM_OF_SEG-1:0] tuser_last_segment;
        logic [NUM_OF_SEG-1:0] tuser_hvalid;
        t_user_hdr tuser_hdr;

        // Outbound queue of the TLP packets generated. These are generally
        // used by a test to compare the incoming TLP stream to the output
        // generated by the DUT.
        rand_tlp tlp_queue[$];

        local rand_tlp tlp;
        // Queue of DWORDs to pass on tdata for current packet
        local bit [31:0] dw_data_stream[$];

        local bit set_fixed_tlp_type;
        local rand_tlp::tlp_type_e fixed_tlp_type;

        local bit force_tag_h;
        local bit tag_h_val;
        local bit allow_empty_cycles;

        // set_tag_h is a way to flag a particular stream, forcing tag_h_val in all TLPs.
        // set_tlp_type is a way to force a particular TLP type for all packets.
        function new(bit set_tag_h = 0, bit tag_h = 0,
                     bit set_tlp_type = 0, rand_tlp::tlp_type_e forced_tlp_type = rand_tlp::TLP_CPLD);
            tvalid = 1'b0;
            tlp = null;
            tuser_vendor = '0;
            tuser_last_segment = '0;
            tuser_hvalid = '0;
            tuser_hdr = '0;

            force_tag_h = set_tag_h;
            tag_h_val = tag_h;

            set_fixed_tlp_type = set_tlp_type;
            fixed_tlp_type = forced_tlp_type;

            allow_empty_cycles = 1'b1;
        endfunction // new

        function disable_empty_cycles();
            allow_empty_cycles = 1'b0;
        endfunction // disable_empty_cycles

        // Fill tdata, starting at start segment. Set tlast as needed.
        // Returns the index of the next available segment.
        local function int fill_tdata_payload(int start_seg);
            // Copy up to a bus width of the packet data
            int i = (start_seg*SEG_WIDTH) / 32;
            while (dw_data_stream.size() != 0) begin
                tdata[i*32 +: 32] = dw_data_stream.pop_front();
                tkeep[i*4 +: 4] = 4'hf;

                if ((i == DATA_WIDTH_DW-1) || (dw_data_stream.size() == 0)) break;
                i += 1;
            end

            // Done with current packet?
            if (dw_data_stream.size() == 0) begin
                tlast = 1'b1;

                // last segment bit isn't set by the SS when SOP is 1
                if (NUM_OF_SEG > 1)
                    tuser_last_segment[(i*32) / SEG_WIDTH] = 1'b1;

                tlp = null;
            end

            // Next segment index
            return 1 + ((i*32) / SEG_WIDTH);
        endfunction // fill_tdata_payload

        // Start a new TLP in segment start_seg
        local function void start_new_tlp(int start_seg);
            logic [HDR_WIDTH-1:0] hdr;

            // Starting a new packet
            tlp = new(1, set_fixed_tlp_type, fixed_tlp_type);

            if (force_tag_h) begin
                if (tlp.tlp_type == tlp.TLP_CPLD)
                    tlp.cpl_hdr.tag_h = tag_h_val;
                else
                    tlp.req_hdr.tag_h = tag_h_val;
            end

            // Queue of TLPs will be used for validation of the DUT's output
            tlp_queue.push_back(tlp);

            hdr = (tlp.tlp_type == tlp.TLP_CPLD ? tlp.cpl_hdr : tlp.req_hdr);
            tuser_hvalid[start_seg] = 1'b1;
            if (SB_HEADERS) begin
                tuser_hdr[start_seg] = hdr;
            end else begin
                // In-band headers go on the data stream
                for (int i = 0; i < HDR_WIDTH/32; i += 1)
                    dw_data_stream.push_back(hdr[i*32 +: 32]);
            end

            foreach (tlp.payload_dw[i])
                dw_data_stream.push_back(tlp.payload_dw[i]);
        endfunction // start_new_tlp

        // Compute tdata state for the next cycle. If "done" is set then
        // don't generate new TLP packets, just drain what is left.
        function void next_cycle(logic done);
            int next_seg = 0;
            int num_sop = 0;

            tvalid = 1'b0;
            tdata = '0;
            tkeep = '0;
            tlast = 1'b0;
            tuser_hdr = '0;
            tuser_hvalid = '0;
            tuser_last_segment = '0;

            if (done && (dw_data_stream.size() == 0)) return;
            // Random empty cycles
            if (allow_empty_cycles && ($urandom() & 4'hf) == 4'hf) return;

            while ((next_seg < NUM_OF_SEG) && (num_sop < MAX_SOP_PER_CYCLE)) begin
                if (dw_data_stream.size() == 0) begin
                    // Need a new packet. Pick a start position with some
                    // probability that the start is outside the range and
                    // some or all of tdata will be unused.
                    next_seg = $urandom_range(NUM_OF_SEG+1, next_seg);
                    if (next_seg >= NUM_OF_SEG) break;

                    start_new_tlp(next_seg);
                    num_sop += 1;
                end

                next_seg = fill_tdata_payload(next_seg);
                tvalid = 1'b1;
            end
        endfunction // next_cycle
    endclass // rand_tlp_stream


    //
    // Consume a data bus stream and generate TLP class instances. This class
    // is used at the end of a pipeline to check the DUT by comparing the
    // source stream to the output.
    //
    class bus_to_tlp
      #(
        parameter DATA_WIDTH = 512,
        parameter NUM_OF_SEG = 1,
        // Non-zero for side-band headers, otherwise in-band
        parameter SB_HEADERS = 0
        );

        localparam HDR_WIDTH = 256;
        localparam SEG_WIDTH = DATA_WIDTH / NUM_OF_SEG;
        // Data width in DWORDs
        localparam DATA_WIDTH_DW = DATA_WIDTH / 32;

        typedef logic [DATA_WIDTH-1:0] t_data;
        typedef logic [DATA_WIDTH/8-1:0] t_keep;

        rand_tlp tlp_queue[$];

        // Incoming data stream for current packet
        local bit [31:0] dw_data_stream[$];
        bit [NUM_OF_SEG-1:0] valid_sop_seg_mask;

        function new(int max_sop_segs = NUM_OF_SEG);
            valid_sop_seg_mask = 0;
            for (int i = 0; i < NUM_OF_SEG; i += NUM_OF_SEG/max_sop_segs)
                valid_sop_seg_mask[i] = 1'b1;
        endfunction // new

        // Calculate the number of DWORDs available on the bus for the region
        // starting at segment start_seg.
        function bit push_payload_dw(
            int start_seg,
            t_data tdata,
            t_keep tkeep,
            logic tlast,
            logic [NUM_OF_SEG-1:0] tuser_last_segment
            );

            // The function returns true if this is the last chunk of a packet.
            // If tlast is set and the scan is starting at the beginning of tdata
            // we can be sure this is the last chunk. Otherwise, tuser_last_segment
            // will have to be checked.
            bit is_last = tlast && (start_seg == 0);

            for (int dw = (start_seg * SEG_WIDTH) / 32; dw < DATA_WIDTH_DW; dw += 1) begin
                int seg_num = dw * 32 / SEG_WIDTH;
                // Assume that the number of DWORDs in a segment is a power of 2.
                // Compute the DWORD index within the segment.
                bit [$clog2(SEG_WIDTH/32)-1 : 0] seg_dw_num = $bits(seg_dw_num)'(dw);

                // Empty data?
                if (!tkeep[dw*4]) begin
                    is_last = 1;
                    break;
                end

                dw_data_stream.push_back(tdata[dw*32 +: 32]);

                // Final DWORD in the segment and segment is marked as last?
                if (&(seg_dw_num) && tuser_last_segment[seg_num]) begin
                    is_last = 1;
                    break;
                end
            end

            return is_last;
        endfunction // payload_num_dw

        // Map data queue to a TLP packet
        function void assemble_tlp();
            rand_tlp tlp = new(0);
            pcie_ss_hdr_pkg::PCIe_PUReqHdr_t hdr;

            // Load the header
            for (int i = 0; i < $bits(tlp.req_hdr)/32; i += 1) begin
                assert(dw_data_stream.size() != 0) else $fatal(1, "Incomplete header!");
                hdr[i*32 +: 32] = dw_data_stream.pop_front();
            end

            if (pcie_ss_hdr_pkg::func_is_completion(hdr.fmt_type)) begin
                tlp.cpl_hdr = hdr;
                tlp.req_hdr = 'x;
                tlp.tlp_type = tlp.TLP_CPLD;
            end
            else begin
                tlp.req_hdr = hdr;
                tlp.cpl_hdr = 'x;
                if (pcie_ss_hdr_pkg::func_has_data(hdr.fmt_type))
                    tlp.tlp_type = tlp.TLP_WITH_DATA;
                else
                    tlp.tlp_type = tlp.TLP_NO_DATA;
            end


            // Add data to the TLP payload
            tlp.payload_dw = new[dw_data_stream.size()];
            for (int i = 0; i < tlp.payload_dw.size(); i += 1) begin
                tlp.payload_dw[i] = dw_data_stream.pop_front();
            end

            if (tlp.tlp_type == tlp.TLP_NO_DATA) begin
                if (tlp.payload_dw.size() > 0) begin
                    $display("Malformed TLP: %0s", tlp.sfmt());
                    $fatal(1, "TLP without data has payload!");
                end
            end else begin
                int len = (tlp.tlp_type == tlp.TLP_CPLD) ? tlp.cpl_hdr.length : tlp.req_hdr.length;
                if (len != tlp.payload_dw.size()) begin
                    $display("Malformed TLP: %0s", tlp.sfmt());
                    $fatal(1, "TLP payload incorrect length: 0x%0h, expected 0x%0h",
                           tlp.payload_dw.size(), len);
                end
            end

            tlp_queue.push_back(tlp);
        endfunction // assemble_tlp

        // Push the current state of the bus, updating the TLP being constructed.
        function void push(
            t_data tdata,
            t_keep tkeep,
            logic tlast,
            logic [NUM_OF_SEG-1:0] tuser_vendor,
            logic [NUM_OF_SEG-1:0] tuser_last_segment,
            logic [NUM_OF_SEG-1:0] tuser_hvalid,
            logic [NUM_OF_SEG-1:0][HDR_WIDTH-1:0] tuser_hdr
            );

            if ((dw_data_stream.size() == 0) && !tuser_hvalid)
                $fatal(1, "Expected TLP header!");

            for (int seg_num = 0; seg_num < NUM_OF_SEG; seg_num += 1) begin
                if ((dw_data_stream.size() != 0) && tuser_hvalid[seg_num])
                    $fatal(1, "Unexpected TLP header!");

                if (tuser_hvalid[seg_num] && !valid_sop_seg_mask[seg_num])
                    $fatal(1, "TLP headers not allowed on segment %0d", seg_num);

                if (SB_HEADERS) begin
                    if (tuser_hvalid[seg_num]) begin
                        // Push header onto the data stream, as though it arrived in-band.
                        // This simplifies assemble_tlp() above.
                        for (int i = 0; i < HDR_WIDTH/32; i += 1) begin
                            dw_data_stream.push_back(tuser_hdr[seg_num][i*32 +: 32]);
                        end

                        // Payloads with no data must also set the last segment bit
                        if (!tkeep[(seg_num*SEG_WIDTH)/8] && !tuser_last_segment[seg_num] && (NUM_OF_SEG > 1))
                            $fatal(1, "Packet header without data is missing tuser_last_segment!");
                    end
                end

                if ((dw_data_stream.size() != 0) || tuser_hvalid[seg_num]) begin
                    // Push data from the bus on the current packet's queue. Return if
                    // the packet is still not complete.
                    if (!push_payload_dw(seg_num, tdata, tkeep, tlast, tuser_last_segment))
                        return;

                    assemble_tlp();
                end
            end
        endfunction // push
    endclass // bus_to_tlp

endpackage // rand_tlp_pkg
