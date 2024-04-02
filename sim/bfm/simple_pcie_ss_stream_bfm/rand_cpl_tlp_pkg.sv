// Copyright 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// BFM for testing modules at the boundary between OFS and the PCIe SS.
//
// Given a read TLP from rand_tlp_pkg::rand_tlp, this class generates
// one or more completions for the read.
//

package rand_cpl_tlp_pkg;

    import rand_tlp_pkg::*;

    class cpl_response;
        localparam HDR_WIDTH = 256;
        localparam MPS = 512;
        localparam RCB = 64;
        localparam RCB_ALIGNED_MASK = ~(RCB-1);

        rand_tlp gen_cpl_queue[$];

        function new();
        endfunction // new

        // Convert a read into one or more completions
        function void push_new_read(rand_tlp rd);
            int dw_rem = rd.req_hdr.length;
            int start_addr = rd.req_hdr.host_addr_h;
            int end_addr = start_addr + dw_rem * 4;

            while (dw_rem != 0) begin
                int cpl_end_addr;
                rand_tlp cpl = new(0);

                if ((end_addr & RCB_ALIGNED_MASK) == (start_addr & RCB_ALIGNED_MASK)) begin
                    // Start and end are in the same boundary. Finish the completion.
                    cpl_end_addr = end_addr;
                end else begin
                    // Pick a random end address for one of the read's completions,
                    // aligned to the read completion boundary.
                    if (end_addr - start_addr <= MPS)
                        cpl_end_addr = $urandom_range(end_addr, start_addr + 4);
                    else
                        cpl_end_addr = $urandom_range(start_addr + MPS, start_addr + 4);

                    cpl_end_addr = (cpl_end_addr + RCB - 1) & RCB_ALIGNED_MASK;
                    if (cpl_end_addr > end_addr)
                        cpl_end_addr = end_addr;
                end

                cpl.tlp_type = rand_tlp::TLP_CPLD;
                cpl.cpl_hdr = '0;
                cpl.cpl_hdr.fmt_type = pcie_ss_hdr_pkg::DM_CPL;
                { cpl.cpl_hdr.tag_h, cpl.cpl_hdr.tag_m, cpl.cpl_hdr.tag_l } =
                    { rd.req_hdr.tag_h, rd.req_hdr.tag_m, rd.req_hdr.tag_l };
                cpl.cpl_hdr.length = (cpl_end_addr - start_addr) / 4;
                cpl.cpl_hdr.low_addr = 7'(start_addr);
                cpl.cpl_hdr.byte_count = end_addr - start_addr;
                cpl.cpl_hdr.metadata_l = rd.req_hdr.metadata_l;

                cpl.payload_dw = new[cpl.cpl_hdr.length];
                for (int i = 0; i < cpl.payload_dw.size(); i++)
                    cpl.payload_dw[i] = $urandom();

                // Queue of TLPs will be used for validation of the DUT's output
                gen_cpl_queue.push_back(cpl);

                dw_rem -= cpl.cpl_hdr.length;
                start_addr += cpl.cpl_hdr.length * 4;
            end
        endfunction // push_new_read
    endclass // cpl_response

endpackage // rand_cpl_tlp_pkg
