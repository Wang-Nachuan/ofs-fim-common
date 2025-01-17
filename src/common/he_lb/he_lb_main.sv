// Copyright 2021 Intel Corporation
// SPDX-License-Identifier: MIT


`include "ofs_plat_if.vh"

module he_lb_main
  #(
    parameter PF_ID         = 0,
    parameter VF_ID         = 0,
    parameter VF_ACTIVE     = 0,
    parameter EMIF          = 0,
    parameter PU_MEM_REQ    = 0,
    // Clock frequency exposed in CSR, used to compute throughput.
    parameter CLK_MHZ       = `OFS_PLAT_PARAM_CLOCKS_PCLK_FREQ
    )
   (
    input  logic clk,
    // Force 'x to 0
    input  bit   rst_n,

    pcie_ss_axis_if.sink      axi_rx_a_if,
    pcie_ss_axis_if.sink      axi_rx_b_if,
    pcie_ss_axis_if.source    axi_tx_a_if,
    pcie_ss_axis_if.source    axi_tx_b_if,

    ofs_plat_axi_mem_if.to_sink ext_mem_if
    );

    // ====================================================================
    //
    //  Get an AXI-MM host channel connection from the platform.
    //
    // ====================================================================

    // Map the incoming TLP stream interfaces into the PIM's host channel
    // wrapper. This is the first step to getting an AXI-MM interface
    // from the PIM.
    ofs_plat_host_chan_axis_pcie_tlp_if
       #(
         .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
         )
       host_chan();

    map_fim_pcie_ss_to_pim_host_chan
      #(
        .PF_NUM(PF_ID),
        .VF_NUM(VF_ID),
        .VF_ACTIVE(VF_ACTIVE)
        )
      map_host_chan
       (
        .clk(clk),

        .reset_n(rst_n),

        .pcie_ss_tx_a_st(axi_tx_a_if),
        .pcie_ss_tx_b_st(axi_tx_b_if),
        .pcie_ss_rx_a_st(axi_rx_a_if),
        .pcie_ss_rx_b_st(axi_rx_b_if),

        .port(host_chan)
        );

    // Instance of the PIM's standard AXI memory interface.
    ofs_plat_axi_mem_if
      #(
        // The PIM provides parameters for configuring a standard host
        // memory DMA AXI memory interface.
        `HOST_CHAN_AXI_MEM_PARAMS,
        // Log traffic in simulation.
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
      axi_host_mem();

    // Instance of the PIM's AXI memory lite interface, which will be
    // used to implement the AFU's 64-bit CSR space.
    ofs_plat_axi_mem_lite_if
      #(
        `HOST_CHAN_AXI_MMIO_PARAMS(64),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
      axi_mmio64();

    ofs_plat_host_chan_as_axi_mem_with_mmio
      #(
        // Setting these to guarantee sorting, though both are sorted
        // by default either by the PIM or the PCIe SS.
        .SORT_READ_RESPONSES(1),
        .SORT_WRITE_RESPONSES(1)
        )
      primary_axi
       (
        .to_fiu(host_chan),
        .host_mem_to_afu(axi_host_mem),
        .mmio_to_afu(axi_mmio64),

        // These ports would be used if the PIM is told to cross to
        // a different clock. In this case, native clk is used.
        .afu_clk(),
        .afu_reset_n()
        );

    // Finally, use a PIM-provided shim to map the MMIO AXI interface to Avalon
    // memory. AXI's split write address and data channels are harder to manage
    // and HE LB's CSR manager's interface is closer to Avalon.
    //
    // AXI tags are stored in the low bits of the Avalon user/readresponseuser
    // fields.
    ofs_plat_avalon_mem_if
      #(
        `HOST_CHAN_AVALON_MMIO_PARAMS(64),
        .USER_WIDTH(axi_mmio64.USER_WIDTH + axi_mmio64.RID_WIDTH),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
      avmm_mmio64();

    assign avmm_mmio64.clk = axi_mmio64.clk;
    assign avmm_mmio64.reset_n = axi_mmio64.reset_n;
    assign avmm_mmio64.instance_number = axi_mmio64.instance_number;

    ofs_plat_axi_mem_lite_if_to_avalon_if
      #(
        // Clear the AXI user field in responses. It is unused,
        // so forcing it to 0 saves area.
        .PRESERVE_RESPONSE_USER(0),
        // Generate the AXI write response inside the shim.
        .LOCAL_WR_RESPONSE(1)
        )
      mmio_to_avmm
       (
        .axi_source(axi_mmio64),
        .avmm_sink(avmm_mmio64)
        );

    // Tie off unused fields, including flow control. The HE LB CSR manager
    // is always ready and write responses are generated by the shim above.
    assign avmm_mmio64.waitrequest = 1'b0;
    assign avmm_mmio64.writeresponsevalid = 1'b0;
    assign avmm_mmio64.writeresponse = '0;
    assign avmm_mmio64.writeresponseuser = '0;


    // ====================================================================
    //
    //  Instantiate the HE LB CSR manager
    //
    // ====================================================================

    // Use the PIM-generated AVMM interface for CSRs.

    // Connections to the CSR manager
    he_lb_pkg::he_csr_req  csr_req;
    he_lb_pkg::he_csr_dout csr_dout;
    he_lb_pkg::he_csr2eng  csr2eng;
    he_lb_pkg::he_eng2csr  eng2csr;

    assign csr_req.wen    = avmm_mmio64.write;
    assign csr_req.ren    = avmm_mmio64.read;
    // CSR manager addresses are to 32 bit chunks. The AVMM interface
    // addresses are to 64 bit chunks. For writes, if the first data byte
    // is unused then infer a 32 bit address in the high half of the 64
    // bit location. For reads, the HE LB CSR manager always expects
    // requests aligned to 64 bits.
    assign csr_req.addr   = he_lb_pkg::CSR_AW'({ avmm_mmio64.address,
                                                 avmm_mmio64.write & ~avmm_mmio64.byteenable[0] });
    assign csr_req.din    = avmm_mmio64.writedata;

    // Infer that a request is 64 bits when the first byte of
    // both 32 bit halves of a read or write or valid.
    assign csr_req.len    = avmm_mmio64.byteenable[4] & avmm_mmio64.byteenable[0];

    assign csr_req.tag    = he_lb_pkg::CSR_TAG_W'(avmm_mmio64.user);

    // Read responses from the CSR manager back to the AVMM interface
    assign avmm_mmio64.readdatavalid    = csr_dout.valid;
    assign avmm_mmio64.readdata         = csr_dout.data;
    assign avmm_mmio64.response         = '0;
    assign avmm_mmio64.readresponseuser = csr_dout.tag;


    // Finally, the HE LB CSR manager
    he_lb_csr
      #(
        .CLK_MHZ(CLK_MHZ),
        .HE_MEM_DATA_WIDTH(EMIF ? ext_mem_if.DATA_WIDTH : 0)
        )
      he_lb_csr
       (
        .clk,
        .rst_n,

        .csr_req,
        .csr_dout,

        .csr2eng,
        .eng2csr
        );



    // ====================================================================
    //
    //  Instantiate the HE LB Engines
    //
    // ====================================================================

    he_lb_engines
      #(
        .EMIF(EMIF)
        )
      engines
       (
        .clk,
        .rst_n,
        .csr2eng,
        .eng2csr,
        .axi_host_mem,
        .emif_if(ext_mem_if)
        );


    // ====================================================================
    //
    //  Display Debug Messages
    //
    // ====================================================================

    //
    // The remainder of the code below is a logger of all PCIe traffic.
    // It is a duplicate of the transactions already logged by the PIM
    // host channel. The log here holds only transactions for a
    // single HE LB instance.
    //

    // synthesis translate_off

    logic axi_tx_a_if_sop;
    logic axi_rx_a_if_sop;
    logic axi_tx_b_if_sop;
    logic axi_rx_b_if_sop;

    always_ff @(posedge clk)
    begin
        if (axi_tx_a_if.tvalid & axi_tx_a_if.tready)
            axi_tx_a_if_sop <= axi_tx_a_if.tlast;

        if (axi_rx_a_if.tvalid & axi_rx_a_if.tready)
            axi_rx_a_if_sop <= axi_rx_a_if.tlast;
  
        if (axi_tx_b_if.tvalid & axi_tx_b_if.tready)
            axi_tx_b_if_sop <= axi_tx_b_if.tlast;

        if (axi_rx_b_if.tvalid & axi_rx_b_if.tready)
            axi_rx_b_if_sop <= axi_rx_b_if.tlast;
  
        if (!rst_n)
        begin
            axi_tx_a_if_sop <= 1'b1;
            axi_rx_a_if_sop <= 1'b1;
            axi_tx_b_if_sop <= 1'b1;
            axi_rx_b_if_sop <= 1'b1;
        end
    end

    // Log all inbound and outbound PCIe traffic to a file.
    initial
    begin : log
        // Open a log file with a unique name for this PF/VF (use VF only if VF_ACTIVE)
        static string fname = $sformatf("log_he_lb_top_pf%0d%s.tsv", PF_ID,
                                        (VF_ACTIVE ? $sformatf("_vf%0d", VF_ID) : ""));
        static int log_fd = $fopen(fname, "w");

        // Write module hierarchy to the top of the log
        $fwrite(log_fd, "he_lb_top.sv: %m (EMIF = %0d)\n\n", EMIF);

        forever @(posedge clk)
        begin
            if(rst_n && axi_rx_a_if.tvalid && axi_rx_a_if.tready)
            begin
                $fwrite(log_fd, "RX_A: %s\n",
                        pcie_ss_pkg::func_pcie_ss_flit_to_string(
                            axi_rx_a_if_sop, axi_rx_a_if.tlast,
                            pcie_ss_hdr_pkg::func_hdr_is_pu_mode(axi_rx_a_if.tuser_vendor),
                            axi_rx_a_if.tdata, axi_rx_a_if.tkeep));
                $fflush(log_fd);
            end

            if(rst_n && axi_tx_a_if.tvalid && axi_tx_a_if.tready)
            begin
                $fwrite(log_fd, "TX_A: %s\n",
                        pcie_ss_pkg::func_pcie_ss_flit_to_string(
                            axi_tx_a_if_sop, axi_tx_a_if.tlast,
                            pcie_ss_hdr_pkg::func_hdr_is_pu_mode(axi_tx_a_if.tuser_vendor),
                            axi_tx_a_if.tdata, axi_tx_a_if.tkeep));
                $fflush(log_fd);
            end

            if(rst_n && axi_rx_b_if.tvalid && axi_rx_b_if.tready)
            begin
                $fwrite(log_fd, "RX_B: %s\n",
                        pcie_ss_pkg::func_pcie_ss_flit_to_string(
                            axi_rx_b_if_sop, axi_rx_b_if.tlast,
                            pcie_ss_hdr_pkg::func_hdr_is_pu_mode(axi_rx_b_if.tuser_vendor),
                            axi_rx_b_if.tdata, axi_rx_b_if.tkeep));
                $fflush(log_fd);
            end

            if(rst_n && axi_tx_b_if.tvalid && axi_tx_b_if.tready)
            begin
                $fwrite(log_fd, "TX_B: %s\n",
                        pcie_ss_pkg::func_pcie_ss_flit_to_string(
                            axi_tx_b_if_sop, axi_tx_b_if.tlast,
                            pcie_ss_hdr_pkg::func_hdr_is_pu_mode(axi_tx_b_if.tuser_vendor),
                            axi_tx_b_if.tdata, axi_tx_b_if.tkeep));
                $fflush(log_fd);
            end
        end
    end

    // synthesis translate_on

endmodule // he_lb_main
