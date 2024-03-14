// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Platform-specific afu_main() wrapper for emulation with ASE. When the PCIe SS
// is present, ASE provides PCIe SS emulation as an input.
//

// OPAE_PLATFORM_GEN is set when a script is generating the PR build environment
// used with OPAE SDK tools. When set, afu_main acts as a simple template that
// defines the module but doesn't include an actual AFU.
`ifndef OPAE_PLATFORM_GEN

`include "ofs_plat_if.vh"
`include "ofs_ip_cfg_db.vh"

module ase_afu_main_emul
  #(
    parameter PG_NUM_PORTS = 1
    )
   (
    input  logic pClk,
    input  logic pClkDiv2,
    input  logic pClkDiv4,
    input  logic uClk_usr,
    input  logic uClk_usrDiv2,
    input  logic softReset,

    // Emulation of the PCIe SS is provided by ASE core services
    pcie_ss_axis_if.source        afu_axi_tx_a_if,
    pcie_ss_axis_if.sink          afu_axi_rx_a_if,
    pcie_ss_axis_if.source        afu_axi_tx_b_if,
    pcie_ss_axis_if.sink          afu_axi_rx_b_if
    );

    // ====================================================================
    //
    //  PCIe
    //
    // ====================================================================

    // ASE currently supports only one link, independent of the emulated
    // platform. On multi-link platforms, ASE represents the full array
    // of ports as independent VF numbers. VF numbering in ASE does not
    // match VF numbering in Quartus builds.
    localparam PG_NUM_LINKS = 1;

`ifdef OFS_FIM_IP_CFG_PCIE_SS_NUM_LINKS
    // Actual number of PCIe links on the platform
    localparam PLATFORM_NUM_LINKS = `OFS_FIM_IP_CFG_PCIE_SS_NUM_LINKS;
`else
    localparam PLATFORM_NUM_LINKS = 1;
`endif

    // Map the PF/VF association of AFU ports to the parameters that will be
    // passed to the port gasket.
    typedef pcie_ss_hdr_pkg::ReqHdr_pf_vf_info_t[PG_NUM_PORTS-1:0] t_afu_pf_vf_info;
    function automatic t_afu_pf_vf_info gen_afu_pf_vf_info();
        t_afu_pf_vf_info info;

        // For simulation, we just pick a collection of VFs associated with a PF.
        for (int p = 0; p < PG_NUM_PORTS; p = p + 1) begin
            info[p].pf_num = 0;
            info[p].vf_num = p;
            info[p].vf_active = 1'b1;
            // Despite ASE not supporting multiple links and requiring
            // unique vf_nums for each port, map ports to the link numbers
            // that would be used on the platform. This way, AFUs that
            // walk the ports looking for link numbers will get the same
            // result in ASE.
            info[p].link_num = p / (PG_NUM_PORTS / PLATFORM_NUM_LINKS);
        end

        return info;
    endfunction // gen_afu_pf_vf_info

    localparam t_afu_pf_vf_info PORT_PF_VF_INFO = gen_afu_pf_vf_info();

    typedef pf_vf_mux_pkg::t_pfvf_rtable_entry[PG_NUM_PORTS-1:0] t_afu_pf_vf_rtable;
    function automatic t_afu_pf_vf_rtable gen_afu_pf_vf_rtable();
        t_afu_pf_vf_rtable rtable;

        // For simulation, we just pick a collection of VFs associated with a PF.
        for (int p = 0; p < PG_NUM_PORTS; p = p + 1) begin
            rtable[p].pfvf_port = p;
            rtable[p].pf = 0;
            rtable[p].vf = p;
            rtable[p].vf_active = 1'b1;
        end

        return rtable;
    endfunction // gen_afu_pf_vf_rtable

    parameter t_afu_pf_vf_rtable PG_PFVF_ROUTING_TABLE = gen_afu_pf_vf_rtable();


    // ====================================================================
    //
    //  Local memory
    //
    // ====================================================================

    //
    // Local RAM emulation. ASE provides a module to instantiate an AXI
    // memory emulator, though the interface is the PIM's generic AXI-MM.
    // The PIM AXI-MM is transformed to the FIM's interface below.
    //
`ifndef OFS_PLAT_PARAM_LOCAL_MEM_NUM_BANKS
    localparam NUM_LOCAL_MEM_BANKS = 0;
`else
    localparam NUM_LOCAL_MEM_BANKS = `OFS_PLAT_PARAM_LOCAL_MEM_NUM_BANKS;

    // FIM version of each local memory bank
    ofs_fim_emif_axi_mm_if ext_mem_if[NUM_LOCAL_MEM_BANKS-1:0]();
    logic local_mem_clk[NUM_LOCAL_MEM_BANKS];

    // PIM version of each local memory bank
    ofs_plat_axi_mem_if
      #(
        .ADDR_WIDTH(ofs_fim_mem_if_pkg::AXI_MEM_ADDR_WIDTH),
        .DATA_WIDTH(ofs_fim_mem_if_pkg::AXI_MEM_WDATA_WIDTH),
        .BURST_CNT_WIDTH(ofs_fim_mem_if_pkg::AXI_MEM_BURST_LEN_WIDTH),
        .USER_WIDTH(ofs_fim_mem_if_pkg::AXI_MEM_USER_WIDTH),
        .RID_WIDTH(ofs_fim_mem_if_pkg::AXI_MEM_ID_WIDTH),
        .WID_WIDTH(ofs_fim_mem_if_pkg::AXI_MEM_ID_WIDTH)
        )
        local_mem[NUM_LOCAL_MEM_BANKS]();

    // Instantiate emulators for each local memory bank (PIM version)
    ase_sim_local_mem_ofs_axi
      #(
        .NUM_BANKS(NUM_LOCAL_MEM_BANKS),
        // The emulator expects ADDR_WIDTH in Avalon terms (line index, not byte)
        .ADDR_WIDTH(ofs_fim_mem_if_pkg::AXI_MEM_ADDR_WIDTH - $clog2(ofs_fim_mem_if_pkg::AXI_MEM_WDATA_WIDTH/8)),
        .DATA_WIDTH(ofs_fim_mem_if_pkg::AXI_MEM_WDATA_WIDTH),
        .BURST_CNT_WIDTH(ofs_fim_mem_if_pkg::AXI_MEM_BURST_LEN_WIDTH),
        .USER_WIDTH(ofs_fim_mem_if_pkg::AXI_MEM_USER_WIDTH),
        .RID_WIDTH(ofs_fim_mem_if_pkg::AXI_MEM_ID_WIDTH),
        .WID_WIDTH(ofs_fim_mem_if_pkg::AXI_MEM_ID_WIDTH)
        )
      local_mem_model
       (
        .local_mem(local_mem),
        .clks(local_mem_clk)
        );

    // Map PIM memory bank wires to the FIM interface
    generate
        for (genvar b = 0; b < NUM_LOCAL_MEM_BANKS; b = b + 1)
        begin : mb
            map_local_mem_to_fim_emif_axi_mm
              #(
                .INSTANCE_NUMBER(b)
                )
              map_local_mem
               (
                .clk(local_mem_clk[b]),
                .reset_n(~softReset),
                .pim_mem_bank(local_mem[b]),
                .fim_mem_bank(ext_mem_if[b])
                );
        end
    endgenerate
`endif


    // ====================================================================
    //
    //  HSSI
    //
    // ====================================================================

    localparam NUM_ETH_CH = ofs_fim_eth_plat_if_pkg::MAX_NUM_ETH_CHANNELS;

`ifdef INCLUDE_HSSI

    ofs_fim_hssi_ss_tx_axis_if hssi_ss_st_tx[NUM_ETH_CH-1:0]();
    ofs_fim_hssi_ss_rx_axis_if hssi_ss_st_rx[NUM_ETH_CH-1:0]();
    ofs_fim_hssi_fc_if hssi_fc[NUM_ETH_CH-1:0]();
    logic [NUM_ETH_CH-1:0] i_hssi_clk_pll;
    logic [NUM_ETH_CH-1:0] i_hssi_rst_n = {NUM_ETH_CH{1'b0}};

    // Clocks and tie offs.
    generate
        for (genvar c = 0; c < NUM_ETH_CH; c = c + 1)
        begin : hssi_clk
            assign hssi_ss_st_tx[c].clk = i_hssi_clk_pll[c];
            assign hssi_ss_st_tx[c].rst_n = i_hssi_rst_n[c];
            assign hssi_ss_st_rx[c].clk = i_hssi_clk_pll[c];
            assign hssi_ss_st_rx[c].rst_n = i_hssi_rst_n[c];

          `ifdef ENABLE_HSSI_SIM
            ase_hssi_emulator #(
                .CHANNEL_ID(c)
              ) ase_hssi_emulator (
                .data_rx (hssi_ss_st_rx[c]),
                .data_tx (hssi_ss_st_tx[c]),
                .fc      (hssi_fc[c])
                );
          `else
            //
            // HSSI simulation is not enabled. Compiling for HSSI is slow, so AFUs
            // that need HSSI simulation must declare it in their JSON files with:
            //
            //   "afu-top-interface":
            //      {
            //         "class": "ofs_plat_afu",
            //         "enable-hssi-sim": 1
            //      },
            //
            assign hssi_ss_st_rx[c].rx = '0;
            assign hssi_ss_st_tx[c].tready = 1'b1;

            assign hssi_fc[c].rx_pause = 0;
            assign hssi_fc[c].rx_pfc = 0;

            always_ff @(negedge i_hssi_clk_pll[c])
            begin
                if (hssi_ss_st_tx[c].tx.tvalid)
                begin
                    $fatal(2,
                           { "\nHSSI traffic present on TX channel %0d but HSSI emulation is disabled!\n",
                             "To enable HSSI emulation, update the afu-top-interface section of the AFU's json file:\n",
                             "  \"afu-top-interface\":\n",
                             "      {\n",
                             "        \"class\": \"ofs_plat_afu\",\n",
                             "        \"enable-hssi-sim\": 1\n",
                             "      }\n" }, c);
                end
            end
          `endif

            // Frequency isn't chosen particularly carefully.
            initial
            begin
                i_hssi_clk_pll[c] = 0;
                forever begin
                    #(1200 + c);
                    i_hssi_clk_pll[c] = ~i_hssi_clk_pll[c];
                end
            end

            always @(posedge i_hssi_clk_pll[c])
            begin
                i_hssi_rst_n[c] <= ~softReset;
            end
        end
    endgenerate

`endif //  `ifdef INCLUDE_HSSI


    // ====================================================================
    //
    //  Dummy JTAG
    //
    // ====================================================================

    ofs_jtag_if remote_stp_jtag_if();
    assign remote_stp_jtag_if.tck = 0;
    assign remote_stp_jtag_if.tdi = '0;


    // ====================================================================
    //
    // Instantiate the user's afu_main()
    //
    // ====================================================================

    localparam TDATA_WIDTH = pcie_ss_axis_pkg::TDATA_WIDTH;
    localparam TUSER_WIDTH = pcie_ss_axis_pkg::TUSER_WIDTH;

    logic [PG_NUM_PORTS-1:0] port_rst_n[PG_NUM_LINKS-1:0];
    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(TUSER_WIDTH)) link_tx_a_if [PG_NUM_LINKS-1:0](.clk(pClk),.rst_n(~softReset));
    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(TUSER_WIDTH)) link_rx_a_if [PG_NUM_LINKS-1:0](.clk(pClk),.rst_n(~softReset));
    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(TUSER_WIDTH)) link_tx_b_if [PG_NUM_LINKS-1:0](.clk(pClk),.rst_n(~softReset));
    pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(TUSER_WIDTH)) link_rx_b_if [PG_NUM_LINKS-1:0](.clk(pClk),.rst_n(~softReset));

    for (genvar link = 0; link < PG_NUM_LINKS; link = link + 1) begin: rst_link
        ofs_fim_axis_pipeline #(.PL_DEPTH(0)) conn_tx_a (.clk(pClk), .rst_n(~softReset), .axis_s(link_tx_a_if[link]), .axis_m(afu_axi_tx_a_if));
        ofs_fim_axis_pipeline #(.PL_DEPTH(0)) conn_rx_a (.clk(pClk), .rst_n(~softReset), .axis_s(afu_axi_rx_a_if), .axis_m(link_rx_a_if[link]));
        ofs_fim_axis_pipeline #(.PL_DEPTH(0)) conn_tx_b (.clk(pClk), .rst_n(~softReset), .axis_s(link_tx_b_if[link]), .axis_m(afu_axi_tx_b_if));
        ofs_fim_axis_pipeline #(.PL_DEPTH(0)) conn_rx_b (.clk(pClk), .rst_n(~softReset), .axis_s(afu_axi_rx_b_if), .axis_m(link_rx_b_if[link]));
        for (genvar p = 0; p < PG_NUM_PORTS; p = p + 1) begin: rst_p
            assign port_rst_n[link][p] = ~softReset;
        end
    end

    afu_main #(
        .PG_NUM_PORTS(PG_NUM_PORTS),
        .PORT_PF_VF_INFO(PORT_PF_VF_INFO),
        .NUM_MEM_CH(NUM_LOCAL_MEM_BANKS),
        .MAX_ETH_CH(NUM_ETH_CH),

        .PG_NUM_RTABLE_ENTRIES(PG_NUM_PORTS),
        .PG_PFVF_ROUTING_TABLE(PG_PFVF_ROUTING_TABLE),
        .LINK_NUM_FROM_PORT_INFO(1)
      ) afu_main (
        .clk(pClk),
        .clk_div2(pClkDiv2),
        .clk_div4(pClkDiv4),
        .uclk_usr(uClk_usr),
        .uclk_usr_div2(uClk_usrDiv2),

        .rst_n(~softReset),
        .port_rst_n(port_rst_n),

        .afu_axi_tx_a_if(link_tx_a_if),
        .afu_axi_rx_a_if(link_rx_a_if),
        .afu_axi_tx_b_if(link_tx_b_if),
        .afu_axi_rx_b_if(link_rx_b_if),

        `ifdef INCLUDE_LOCAL_MEM
            // Local memory
            .ext_mem_if,
        `endif

        `ifdef INCLUDE_HSSI
            .hssi_ss_st_tx,
            .hssi_ss_st_rx,
            .hssi_fc,
            .i_hssi_clk_pll,
        `endif

        // JTAG interface for PR region debug (dummy, since simulating)
        .remote_stp_jtag_if
        );
endmodule // ase_top_ofs_plat

`endif //  `ifndef OPAE_PLATFORM_GEN
