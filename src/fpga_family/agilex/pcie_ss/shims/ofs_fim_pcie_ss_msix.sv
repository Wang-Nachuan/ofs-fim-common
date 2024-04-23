// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

module ofs_fim_pcie_ss_msix
  #(
    // No parameter defaults. They must be set to proper values by the parent.
    parameter int NUM_PFS,
    parameter int TOTAL_NUM_VFS,
    parameter int VFS_COUNT_PER_PF[NUM_PFS],

    // MSIX PF table properties, indexed by PF
    parameter int MSIX_PF_TABLE_SIZE[8],
    parameter int MSIX_PF_TABLE_OFFSET[8],
    parameter int MSIX_PF_TABLE_BAR[8],
    parameter int MSIX_PF_TABLE_BAR_LOG2_SIZE[8],
    parameter int MSIX_PF_PBA_OFFSET[8],
    parameter int MSIX_PF_PBA_BAR[8],

    // MSIX VF table properties, indexed by PF
    parameter int MSIX_VF_TABLE_SIZE[8],
    parameter int MSIX_VF_TABLE_OFFSET[8],
    parameter int MSIX_VF_TABLE_BAR[8],
    parameter int MSIX_VF_TABLE_BAR_LOG2_SIZE[8],
    parameter int MSIX_VF_PBA_OFFSET[8],
    parameter int MSIX_VF_PBA_BAR[8]
    )
   (
    // RX from the host. MMIO traffic directed at the MSI-X will be handled
    // in this module. 
    pcie_ss_axis_if.sink axi_st_rxreq_in,
    // RX that isn't MSI-X traffic flows out here toward the FIM.
    pcie_ss_axis_if.source axi_st_rxreq_out,

    // TX incoming from FIM. DM-encoded interrupt requests will be mapped to writes.
    pcie_ss_axis_if.sink axi_st_tx_in,
    // TX toward the host: everything from tx_in that isn't an interrupt plus
    // interrupt writes and completions for MSI-X reads from rxreq_in.
    pcie_ss_axis_if.source axi_st_tx_out,

    input  logic csr_clk,
    input  logic csr_rst_n,

    input  logic ctrlshadow_tvalid,
    input  logic [39:0] ctrlshadow_tdata,

    input  pcie_ss_axis_pkg::t_axis_pcie_flr flr_req_if,
    output pcie_ss_axis_pkg::t_axis_pcie_flr flr_rsp_if,
    input  logic flr_rsp_tready
    );

    wire clk = axi_st_tx_out.clk;
    wire rst_n = axi_st_tx_out.rst_n;

    // Find a representative PF that is configured with an MSI-X table.
    // The table implementation requires that all functions with MSI-X
    // enabled must have identical configurations.
    function automatic int find_msix_enabled_pf();
        for (int f = 0; f < 8; f += 1) begin
            if (MSIX_PF_TABLE_SIZE[f] != 0) return f;
        end

        return -1;
    endfunction // find_msix_enabled_pf

    // Use the representative PF to set MSI-X BAR and address configuration.
    localparam MIDX = find_msix_enabled_pf();
    localparam MSIX_TABLE_SIZE = MSIX_PF_TABLE_SIZE[MIDX];
    // Byte offset of the MSI-X table in MSIX_BAR
    localparam MSIX_TABLE_OFFSET = MSIX_PF_TABLE_OFFSET[MIDX];
    localparam MSIX_BAR = MSIX_PF_TABLE_BAR[MIDX];
    localparam MSIX_BAR_LOG2_SIZE = MSIX_PF_TABLE_BAR_LOG2_SIZE[MIDX];
    localparam MSIX_PBA_OFFSET = MSIX_PF_PBA_OFFSET[MIDX];
    localparam MSIX_PBA_BAR = MSIX_PF_PBA_BAR[MIDX];

    // First byte offset beyond both the table and PBA in MSIX_BAR
    localparam MSIX_TABLE_END = MSIX_TABLE_OFFSET + 16 * MSIX_TABLE_SIZE +
                                // PBA bit vector size rounded up to 16 byte granularity
                                ((MSIX_TABLE_SIZE + 127) / 128) * 16;

    // synthesis translate_off
    initial begin
        //
        // Validation of MSI-X configuration. These are all restrictions
        // imposed by the implementation in ofs_fim_pcie_ss_msix_table:
        //
        //  - The representative PF must be fully specified.
        //  - The PBA bit vector offset must be immediately at the end
        //    of the MSI-X table. Namely, MSIX_PBA_OFFSET must be
        //    MSIX_TABLE_OFFSET + 16*MSIX_TABLE_SIZE. (Each table entry
        //    is 16 bytes.)
        //  - All functions configured for MSI-X must specify the same
        //    table size, offset, bar and bar size.
        //
        if (MIDX == -1) $fatal(2, "%m error: no PF with MSI-X found!");
        if (MSIX_TABLE_SIZE == 0) $fatal(2, "%m error: MSIX_TABLE_SIZE is 0!");
        if (MSIX_TABLE_OFFSET == 0) $fatal(2, "%m error: MSIX_TABLE_OFFSET is 0!");
        if (MSIX_BAR_LOG2_SIZE == 0) $fatal(2, "%m error: MSIX_BAR_LOG2_SIZE is 0!");
        if (MSIX_BAR != MSIX_PBA_BAR) $fatal(2, "%m error: MSIX_BAR and MSIX_PBA_BAR must be the same!");
        if (MSIX_PBA_OFFSET != MSIX_TABLE_OFFSET + 16 * MSIX_TABLE_SIZE)
            $fatal(2, "%m error: MSIX PBA must be immediately after the MSI-X table!");

        // Confirm that all functions are configured identically. Accept
        // either 0 (MSI-X not enabled on function) or matching configurations.
        for (int f = 0; f < 8; f += 1) begin
            if ((MSIX_PF_TABLE_SIZE[f] != 0) && (MSIX_PF_TABLE_SIZE[f] != MSIX_TABLE_SIZE))
                $fatal(2, "%m error: PF%0d table size is %0d, expected %0d!", f, MSIX_PF_TABLE_SIZE[f], MSIX_TABLE_SIZE);
            if ((MSIX_PF_TABLE_OFFSET[f] != 0) && (MSIX_PF_TABLE_OFFSET[f] != MSIX_TABLE_OFFSET))
                $fatal(2, "%m error: PF%0d table offset is 0x%0h, expected 0x%0h!", f, MSIX_PF_TABLE_OFFSET[f], MSIX_TABLE_OFFSET);
            if ((MSIX_PF_TABLE_BAR_LOG2_SIZE[f] != 0) && (MSIX_PF_TABLE_BAR_LOG2_SIZE[f] != MSIX_BAR_LOG2_SIZE))
                $fatal(2, "%m error: PF%0d BAR log2 size is %0d, expected %0d!", f, MSIX_PF_TABLE_BAR_LOG2_SIZE[f], MSIX_BAR_LOG2_SIZE);
            if ((MSIX_PF_TABLE_BAR[f] != 0) && (MSIX_PF_TABLE_BAR[f] != MSIX_BAR))
                $fatal(2, "%m error: PF%0d BAR is %0d, expected %0d!", f, MSIX_PF_TABLE_BAR[f], MSIX_BAR);
            if ((MSIX_PF_PBA_OFFSET[f] != 0) && (MSIX_PF_PBA_OFFSET[f] != MSIX_PBA_OFFSET))
                $fatal(2, "%m error: PF%0d PBA offset is 0x%0h, expected 0x%0h!", f, MSIX_PF_PBA_OFFSET[f], MSIX_PBA_OFFSET);
            if ((MSIX_PF_PBA_BAR[f] != 0) && (MSIX_PF_PBA_BAR[f] != MSIX_PBA_BAR))
                $fatal(2, "%m error: PF%0d PBA BAR is %0d, expected %0d!", f, MSIX_PF_PBA_BAR[f], MSIX_PBA_BAR);

            if ((MSIX_VF_TABLE_SIZE[f] != 0) && (MSIX_VF_TABLE_SIZE[f] != MSIX_TABLE_SIZE))
                $fatal(2, "%m error: PF%0d VF table size is %0d, expected %0d!", f, MSIX_VF_TABLE_SIZE[f], MSIX_TABLE_SIZE);
            if ((MSIX_VF_TABLE_OFFSET[f] != 0) && (MSIX_VF_TABLE_OFFSET[f] != MSIX_TABLE_OFFSET))
                $fatal(2, "%m error: PF%0d VF table offset is 0x%0h, expected 0x%0h!", f, MSIX_VF_TABLE_OFFSET[f], MSIX_TABLE_OFFSET);
            if ((MSIX_VF_TABLE_BAR_LOG2_SIZE[f] != 0) && (MSIX_VF_TABLE_BAR_LOG2_SIZE[f] != MSIX_BAR_LOG2_SIZE))
                $fatal(2, "%m error: PF%0d VF BAR log2 size is %0d, expected %0d!", f, MSIX_VF_TABLE_BAR_LOG2_SIZE[f], MSIX_BAR_LOG2_SIZE);
            if ((MSIX_VF_TABLE_BAR[f] != 0) && (MSIX_VF_TABLE_BAR[f] != MSIX_BAR))
                $fatal(2, "%m error: PF%0d VF BAR is %0d, expected %0d!", f, MSIX_VF_TABLE_BAR[f], MSIX_BAR);
            if ((MSIX_VF_PBA_OFFSET[f] != 0) && (MSIX_VF_PBA_OFFSET[f] != MSIX_PBA_OFFSET))
                $fatal(2, "%m error: PF%0d VF PBA offset is 0x%0h, expected 0x%0h!", f, MSIX_VF_PBA_OFFSET[f], MSIX_PBA_OFFSET);
            if ((MSIX_VF_PBA_BAR[f] != 0) && (MSIX_VF_PBA_BAR[f] != MSIX_PBA_BAR))
                $fatal(2, "%m error: PF%0d VF PBA BAR is %0d, expected %0d!", f, MSIX_VF_PBA_BAR[f], MSIX_PBA_BAR);
        end
    end
    // synthesis translate_on


    logic msix_rst_req;
    logic msix_rst_done;
    logic msix_ready;


    // ====================================================================
    //
    //  RXREQ -- route normal requests to axi_st_rxreq_out. Split out
    //  requests for the MSI-X table.
    //
    // ====================================================================

    logic rxreq_sop;
    logic intc_rx_st_ready;

    always_ff @(posedge clk) begin
        if (axi_st_rxreq_in.tvalid && axi_st_rxreq_in.tready)
            rxreq_sop <= axi_st_rxreq_in.tlast;

        if (!rst_n)
            rxreq_sop <= 1'b1;
    end

    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t rxreq_hdr;
    assign rxreq_hdr = pcie_ss_hdr_pkg::PCIe_PUReqHdr_t'(axi_st_rxreq_in.tdata);
    // Address when request is 32 bit mode
    wire [MSIX_BAR_LOG2_SIZE-1:0] rxreq_addr32 = MSIX_BAR_LOG2_SIZE'(rxreq_hdr.host_addr_h);
    // Address when request is 64 bit mode
    wire [MSIX_BAR_LOG2_SIZE-1:0] rxreq_addr64 = MSIX_BAR_LOG2_SIZE'({ rxreq_hdr.host_addr_h, rxreq_hdr.host_addr_l, 2'b0 });

    wire rxreq_addr32_is_msix =
           (rxreq_addr32[MSIX_BAR_LOG2_SIZE-1:4] >= MSIX_TABLE_OFFSET[MSIX_BAR_LOG2_SIZE-1:4]) &&
           (rxreq_addr32[MSIX_BAR_LOG2_SIZE-1:4] < MSIX_TABLE_END[MSIX_BAR_LOG2_SIZE-1:4]);
    wire rxreq_addr64_is_msix =
           (rxreq_addr64[MSIX_BAR_LOG2_SIZE-1:4] >= MSIX_TABLE_OFFSET[MSIX_BAR_LOG2_SIZE-1:4]) &&
           (rxreq_addr64[MSIX_BAR_LOG2_SIZE-1:4] < MSIX_TABLE_END[MSIX_BAR_LOG2_SIZE-1:4]);
    wire rxreq_addr_is_msix =
           pcie_ss_hdr_pkg::func_is_addr32(rxreq_hdr.fmt_type) ? rxreq_addr32_is_msix :
                                                                 rxreq_addr64_is_msix;

    wire rxreq_hdr_is_msix =
           rxreq_sop &&
           pcie_ss_hdr_pkg::func_is_mem_req(rxreq_hdr.fmt_type) &&
           // MSI-X enabled for function?
           (rxreq_hdr.vf_active ? (MSIX_VF_TABLE_SIZE[rxreq_hdr.pf_num] != 0) : (MSIX_PF_TABLE_SIZE[rxreq_hdr.pf_num] != 0)) &&
           (MSIX_BAR == rxreq_hdr.bar_number) &&
           rxreq_addr_is_msix;

    // Not an MSI-X request. For MSI-X requests, see the intc_rx_st_* ports below.
    assign axi_st_rxreq_out.tvalid = axi_st_rxreq_in.tvalid && !rxreq_hdr_is_msix;
    assign axi_st_rxreq_out.tlast = axi_st_rxreq_in.tlast;
    assign axi_st_rxreq_out.tuser_vendor = axi_st_rxreq_in.tuser_vendor;
    assign axi_st_rxreq_out.tdata = axi_st_rxreq_in.tdata;
    assign axi_st_rxreq_out.tkeep = axi_st_rxreq_in.tkeep;

    assign axi_st_rxreq_in.tready = rxreq_hdr_is_msix ? intc_rx_st_ready && msix_ready :
                                                        axi_st_rxreq_out.tready;


    // ====================================================================
    //
    //  TX stream, mostly forwarded to the host. Interrupt requests to
    //  the MSIX-table.
    //
    // ====================================================================

    pcie_ss_hdr_pkg::PCIe_IntrHdr_t tx_hdr;
    assign tx_hdr = pcie_ss_hdr_pkg::PCIe_IntrHdr_t'(axi_st_tx_in.tdata);

    logic tx_sop;
    logic msix_st_tx_tready;

    always_ff @(posedge clk) begin
        if (axi_st_tx_in.tvalid && axi_st_tx_in.tready)
            tx_sop <= axi_st_tx_in.tlast;

        if (!rst_n)
            tx_sop <= 1'b1;
    end

    wire tx_hdr_is_interrupt =
           tx_sop &&
           pcie_ss_hdr_pkg::func_is_interrupt_req(tx_hdr.fmt_type) &&
           pcie_ss_hdr_pkg::func_hdr_is_dm_mode(axi_st_tx_in.tuser_vendor);

    // Multiplex FIM TX traffic and MSI-X completions/interrupts
    pcie_ss_axis_if #(.DATA_W(axi_st_tx_out.DATA_W), .USER_W(axi_st_tx_out.USER_W))
        tx_mux_in[2](.clk, .rst_n);
    
    assign tx_mux_in[0].tvalid = axi_st_tx_in.tvalid && !tx_hdr_is_interrupt;
    assign tx_mux_in[0].tlast = axi_st_tx_in.tlast;
    assign tx_mux_in[0].tuser_vendor = axi_st_tx_in.tuser_vendor;
    assign tx_mux_in[0].tdata = axi_st_tx_in.tdata;
    assign tx_mux_in[0].tkeep = axi_st_tx_in.tkeep;

    assign axi_st_tx_in.tready = tx_hdr_is_interrupt ? msix_st_tx_tready && msix_ready :
                                                       tx_mux_in[0].tready;

    pcie_ss_axis_mux
      #(
        .NUM_CH(2),
        .PL_DEPTH({ 1, 0 }),
        .TDATA_WIDTH(axi_st_tx_out.DATA_W),
        .TUSER_WIDTH(axi_st_tx_out.USER_W)
        )
      tx_mux
       (
        .clk,
        .rst_n,
        .sink(tx_mux_in),
        .source(axi_st_tx_out)
        );


    // ====================================================================
    //
    //  Multiplex the FIM TX stream and MSI-X table TX traffic.
    //
    // ====================================================================

    // Both generated interrupts (intc_st_tx_*) and MMIO completions
    // (intc_st_cpl_tx_*) are routed through these.
    logic msix_tx_tvalid;
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t msix_tx_hdr;
    logic [63:0] msix_tx_data;

    logic intc_st_cpl_tx_tvalid;
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t intc_st_cpl_tx_hdr;
    logic [63:0] intc_st_cpl_tx_data;
    wire intc_st_cpl_tx_tready = !msix_tx_tvalid;

    logic intc_st_tx_tvalid;
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t intc_st_tx_hdr;
    logic [63:0] intc_st_tx_data;
    wire intc_st_tx_tready = !msix_tx_tvalid && !intc_st_cpl_tx_tvalid;

    assign tx_mux_in[1].tvalid = msix_tx_tvalid;
    assign tx_mux_in[1].tlast = 1'b1;
    assign tx_mux_in[1].tuser_vendor = '0;
    assign tx_mux_in[1].tdata = { msix_tx_data, msix_tx_hdr };
    assign tx_mux_in[1].tkeep = { '0, {8{1'b1}}, {($bits(msix_tx_hdr)/8){1'b1}} };

    always_ff @(posedge clk) begin
        if (msix_tx_tvalid) begin
            // Existing message transmitted?
            msix_tx_tvalid <= !tx_mux_in[1].tready;
        end else begin
            // New TX message from MSI-X table?
            msix_tx_tvalid <= intc_st_cpl_tx_tvalid || intc_st_tx_tvalid;
            if (intc_st_cpl_tx_tvalid) begin
                msix_tx_hdr <= intc_st_cpl_tx_hdr;
                msix_tx_data <= intc_st_cpl_tx_data;
            end else begin
                msix_tx_hdr <= intc_st_tx_hdr;
                msix_tx_data <= intc_st_tx_data;
            end
        end

        if (!rst_n) begin
            msix_tx_tvalid <= 1'b0;
        end
    end


    // ====================================================================
    //
    //  MSI-X table
    //
    // ====================================================================

    // Reset the MSI-X table. Reset request is held until the table responds "done".
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            msix_rst_req <= 1'b1;
            msix_ready <= 1'b0;
        end else if (msix_rst_done) begin
            msix_rst_req <= 1'b0;
            msix_ready <= 1'b1;
        end
    end

    ofs_fim_pcie_ss_msix_table
      #(
        .MSIX_TABLE_SIZE(MSIX_TABLE_SIZE),
        .MSIX_BIR(MSIX_BAR),
        .MSIX_BAR_OFFSET(MSIX_TABLE_OFFSET),

        .total_pf_count(NUM_PFS),
        .total_vf_count(TOTAL_NUM_VFS),
        .pf0_vf_count((NUM_PFS > 0) ? VFS_COUNT_PER_PF[0] : 0),
        .pf1_vf_count((NUM_PFS > 1) ? VFS_COUNT_PER_PF[1] : 0),
        .pf2_vf_count((NUM_PFS > 2) ? VFS_COUNT_PER_PF[2] : 0),
        .pf3_vf_count((NUM_PFS > 3) ? VFS_COUNT_PER_PF[3] : 0),
        .pf4_vf_count((NUM_PFS > 4) ? VFS_COUNT_PER_PF[4] : 0),
        .pf5_vf_count((NUM_PFS > 5) ? VFS_COUNT_PER_PF[5] : 0),
        .pf6_vf_count((NUM_PFS > 6) ? VFS_COUNT_PER_PF[6] : 0),
        .pf7_vf_count((NUM_PFS > 7) ? VFS_COUNT_PER_PF[7] : 0),

        .DWIDTH(64)
        )
      msix_table
       (
        .axi_lite_clk(csr_clk),
        .lite_areset_n(csr_rst_n),
        .axi_st_clk(clk),
        .st_areset_n(rst_n),

        .subsystem_rst_req(msix_rst_req),
        .subsystem_rst_rdy(msix_rst_done),

        // Host MMIO requests
        .intc_rx_st_ready,
        .intc_rx_st_valid(axi_st_rxreq_in.tvalid && rxreq_hdr_is_msix && msix_ready),
        .intc_rx_st_msix_size_valid((rxreq_hdr.length == 1) || (rxreq_hdr.length == 2)),
        .intc_rx_st_sop(1'b1),
        .intc_rx_st_data(axi_st_rxreq_in.tdata[$bits(rxreq_hdr) +: 64]),
        .intc_rx_st_hdr(128'(rxreq_hdr)),
        .intc_rx_st_pvalid(rxreq_hdr.pref_present),
        .intc_rx_st_prefix({ '0, rxreq_hdr.pref_present, rxreq_hdr.pref_type, rxreq_hdr.pref }),
        .intc_rx_st_bar_num(rxreq_hdr.bar_number),
        .intc_rx_st_slot_num(rxreq_hdr.slot_num),
        .intc_rx_st_pf_num(rxreq_hdr.pf_num),
        .intc_rx_st_vf_num(rxreq_hdr.vf_num),
        .intc_rx_st_vf_active(rxreq_hdr.vf_active),
        .intc_rx_st_unmapped_hdr_addr(pcie_ss_hdr_pkg::func_is_addr32(rxreq_hdr.fmt_type) ? { '0, rxreq_addr32 } : rxreq_addr64),

        // CSR write interface not used by OFS
        .lite_csr_awvalid(1'b0),
        .lite_csr_awready(),
        .lite_csr_awaddr('0),
        .lite_csr_wvalid(1'b0),
        .lite_csr_wready(),
        .lite_csr_wdata('0),
        .lite_csr_wstrb('0),
        .lite_csr_bvalid(),
        .lite_csr_bready(1'b1),
        .lite_csr_bresp(),

        // CSR read interface not used by OFS
        .lite_csr_arvalid(1'b0),
        .lite_csr_arready(),
        .lite_csr_araddr('0),
        .lite_csr_rvalid(),
        .lite_csr_rready(1'b1),
        .lite_csr_rdata(),
        .lite_csr_rresp(),

        .ctrlshadow_tvalid,
        .ctrlshadow_tdata,

        .flrrcvd_tvalid(flr_req_if.tvalid),
        .flrrcvd_tdata(flr_req_if.tdata),

        .flrif_flrcmpl_tready(flr_rsp_tready),
        .intc_flrcmpl_tvalid(flr_rsp_if.tvalid),
        .intc_flrcmpl_tdata(flr_rsp_if.tdata),

        // AFU interrupts on TXREQ stream not used by OFS
        .st_txreq_tready(),
        .st_txreq_tvalid(1'b0),
        .st_txreq_tdata('0),

        // AFU interrupts on TX stream
        .st_tx_tdata(axi_st_tx_in.tdata[255:0]),
        .st_tx_tvalid(axi_st_tx_in.tvalid && tx_hdr_is_interrupt && msix_ready),
        .st_tx_tready(msix_st_tx_tready),

        // Host MMIO read response
        .intc_st_cpl_tx_hdr,
        .intc_st_cpl_tx_data,
        .intc_st_cpl_tx_tvalid,
        .intc_st_cpl_tx_tready,

        // Size request not used by OFS
        .h2c_msix_size(),
        .h2c_size_req_valid(1'b0),
        .h2c_slot_num('0),
        .h2c_pf_num('0),
        .h2c_vf_num('0),
        .h2c_vf_active(1'b0),

        // Error CSRs not used by OFS
        .intc_err_gen_ctrl_trig_req(),
        .intc_err_gen_ctrl_trig_done(1'b1),
        .intc_err_gen_ctrl_logh(),
        .intc_err_gen_ctrl_logp(),
        .intc_err_gen_ctrl_vf_active(),
        .intc_err_gen_ctrl_pf_num(),
        .intc_err_gen_ctrl_vf_num(),
        .intc_err_gen_ctrl_slot_num(),
        .intc_err_gen_attr(),
        .intc_err_gen_hdr_dw0(),
        .intc_err_gen_hdr_dw1(),
        .intc_err_gen_hdr_dw2(),
        .intc_err_gen_hdr_dw3(),
        .intc_err_gen_prfx(),

        .intc_vf_err_vf_num(),
        .intc_vf_err_func_num(),
        .intc_vf_err_slot_num(),
        .intc_vf_err_tvalid(),
        .intc_vf_err_tready(1'b1),

        // AFU TX interrupts mapped to host writes
        .intc_st_tx_hdr,
        .intc_st_tx_data,
        .intc_st_tx_tvalid,
        .intc_st_tx_tready
        );

endmodule // ofs_fim_pcie_ss_msix
