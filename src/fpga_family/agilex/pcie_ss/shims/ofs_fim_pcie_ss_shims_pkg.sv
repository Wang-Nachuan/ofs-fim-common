// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

package ofs_fim_pcie_ss_shims_pkg;

    localparam HDR_WIDTH = 256;

    // Per-segment tuser state, packed so it can be passed through the
    // normal OFS tuser_vendor in pcie_ss_axis_if.
    typedef struct packed {
        logic vendor;
        logic last_segment;
        logic hvalid;
        // The hdr field is left in here, even in configurations with
        // in-band headers. This generally simplifies the code. Quartus
        // will not waste resources on headers that are driven with
        // constant 0 or are unconsumed.
        logic [HDR_WIDTH-1:0] hdr;
    } t_tuser_seg;

endpackage // ofs_fim_pcie_ss_shims_pkg
