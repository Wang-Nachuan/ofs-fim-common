// Copyright (C) 2020 Intel Corporation.
// SPDX-License-Identifier: MIT

//
// Description
//-----------------------------------------------------------------------------
//
// Top level module of PCIe subsystem.
//
//-----------------------------------------------------------------------------

`include "fpga_defines.vh"
`include "ofs_ip_cfg_db.vh"


module pcie_wrapper 
import ofs_fim_cfg_pkg::*;
import pcie_ss_axis_pkg::*;
import ofs_fim_pcie_hdr_def::*;
#(
   parameter            PCIE_LANES      = 16,
   parameter            PCIE_NUM_LINKS  = 1,
   parameter            MM_ADDR_WIDTH   = 19,
   parameter            MM_DATA_WIDTH   = 64,
   parameter bit [11:0] FEAT_ID         = 12'h0,
   parameter bit [3:0]  FEAT_VER        = 4'h0,
   parameter bit [23:0] NEXT_DFH_OFFSET = 24'h1000,
   parameter bit        END_OF_LIST     = 1'b0,
   parameter            SOC_ATTACH      = 0
)(
   input  logic                         fim_clk,
   input  logic [PCIE_NUM_LINKS-1:0]    fim_rst_n,

   input  logic                         csr_clk,
   input  logic [PCIE_NUM_LINKS-1:0]    csr_rst_n,

   input  logic                         ninit_done,
   output logic [PCIE_NUM_LINKS-1:0]    reset_status,

   input  logic [PCIE_NUM_LINKS-1:0]    subsystem_cold_rst_n,    
   input  logic [PCIE_NUM_LINKS-1:0]    subsystem_warm_rst_n,    
   output logic [PCIE_NUM_LINKS-1:0]    subsystem_cold_rst_ack_n,
   output logic [PCIE_NUM_LINKS-1:0]    subsystem_warm_rst_ack_n,
   
   // PCIe pins
   input  logic                     pin_pcie_refclk0_p,
   input  logic                     pin_pcie_refclk1_p,
   input  logic                     pin_pcie_in_perst_n,   // connected to HIP
   input  logic [PCIE_LANES-1:0]    pin_pcie_rx_p,
   input  logic [PCIE_LANES-1:0]    pin_pcie_rx_n,
   output logic [PCIE_LANES-1:0]    pin_pcie_tx_p,
   output logic [PCIE_LANES-1:0]    pin_pcie_tx_n,

   // Ctrl Shadow ports
   output logic [PCIE_NUM_LINKS-1:0]                     ss_app_st_ctrlshadow_tvalid,
   output logic [PCIE_NUM_LINKS-1:0] [39:0]              ss_app_st_ctrlshadow_tdata,

   // AXI-S data interfaces
   pcie_ss_axis_if.source           axi_st_rxreq_if[PCIE_NUM_LINKS-1:0],   // MMIO (when PCIe SS completions are sorted)
   pcie_ss_axis_if.source           axi_st_rx_if[PCIE_NUM_LINKS-1:0],      // Host memory read completions
   pcie_ss_axis_if.sink             axi_st_tx_if[PCIE_NUM_LINKS-1:0],      // Any FPGA to host command or completion
   pcie_ss_axis_if.sink             axi_st_txreq_if[PCIE_NUM_LINKS-1:0],   // DM-encoded reads or interrupts

   // AXI4-lite CSR interface
   ofs_fim_axi_lite_if.slave        csr_lite_if[PCIE_NUM_LINKS-1:0],
  
   // Completion Timeout Interface
   output pcie_ss_axis_pkg::t_axis_pcie_cplto axis_cpl_timeout[PCIE_NUM_LINKS-1:0],
 
   output pcie_ss_axis_pkg::t_pcie_tag_mode tag_mode[PCIE_NUM_LINKS-1:0],

   // FLR 
   output pcie_ss_axis_pkg::t_axis_pcie_flr    axi_st_flr_req[PCIE_NUM_LINKS-1:0],
   input  pcie_ss_axis_pkg::t_axis_pcie_flr    axi_st_flr_rsp[PCIE_NUM_LINKS-1:0]
);  


// Link[0] has access to CSR space
t_axis_pcie         axis_tx[PCIE_NUM_LINKS-1:0];
logic [PCIE_NUM_LINKS-1:0]   axis_tx_tready;

logic [PCIE_NUM_LINKS-1:0]   pcie_linkup;
logic [31:0]        pcie_rx_err_code[PCIE_NUM_LINKS-1:0];

pcie_ss_axis_if #(
            .DATA_W(ofs_fim_cfg_pkg::PCIE_TDATA_WIDTH),
            .USER_W(ofs_fim_cfg_pkg::PCIE_TUSER_WIDTH)
    ) rxreq_in[PCIE_NUM_LINKS-1:0](.clk(fim_clk));

       
pcie_ss_axis_if #(
            .DATA_W(ofs_fim_cfg_pkg::PCIE_TDATA_WIDTH),
            .USER_W(ofs_fim_cfg_pkg::PCIE_TUSER_WIDTH)
    ) axi_st_tx_committed[PCIE_NUM_LINKS-1:0](.clk(fim_clk));


ofs_fim_axi_lite_if #(.AWADDR_WIDTH(20), .ARADDR_WIDTH(20), .WDATA_WIDTH(32), .RDATA_WIDTH(32)) ss_csr_lite_if[PCIE_NUM_LINKS-1:0]();

import ofs_fim_if_pkg::*;
t_sideband_from_pcie   pcie_p2c_sideband[PCIE_NUM_LINKS-1:0];

generate
    for (genvar j=0; j<PCIE_NUM_LINKS; j++) begin : PCIE_LINKS
 
        pcie_ss_axis_if #(
            .DATA_W(ofs_fim_cfg_pkg::PCIE_TDATA_WIDTH),
            .USER_W(ofs_fim_cfg_pkg::PCIE_TUSER_WIDTH)
            ) rxreq_arb_in[2](.clk(fim_clk), .rst_n(fim_rst_n[j]));

       
        always_comb 
        begin
            // axis tx intf
            axis_tx[j].tvalid = axi_st_tx_if[j].tvalid;
            axis_tx[j].tdata  = axi_st_tx_if[j].tdata;
            axis_tx[j].tkeep  = axi_st_tx_if[j].tkeep;
            axis_tx[j].tlast  = axi_st_tx_if[j].tlast;
            axis_tx[j].tuser  = axi_st_tx_if[j].tuser_vendor;

            axis_tx_tready[j] = axi_st_tx_if[j].tready;

            // clk & rst of links
            //axi_st_tx_committed[j].clk   = fim_clk;
            //axi_st_tx_committed[j].rst_n = fim_rst_n[j];

            //rxreq_in[j].clk              = fim_clk;
            //rxreq_in[j].rst_n            = fim_rst_n[j];
            
            // rx to arb
            rxreq_arb_in[0].tvalid             = rxreq_in[j].tvalid;  
            rxreq_arb_in[0].tdata              = rxreq_in[j].tdata;  
            rxreq_arb_in[0].tkeep              = rxreq_in[j].tkeep;  
            rxreq_arb_in[0].tlast              = rxreq_in[j].tlast;  
            rxreq_arb_in[0].tuser_vendor       = rxreq_in[j].tuser_vendor;  

            rxreq_in[j].tready                 = rxreq_arb_in[0].tready;

        end

        // Assign rst_n for the link
        assign rxreq_in[j].rst_n = fim_rst_n[j];
        assign axi_st_tx_committed[j].rst_n = fim_rst_n[j];

        pcie_ss_if #(
            .MM_ADDR_WIDTH   (MM_ADDR_WIDTH), 
            .MM_DATA_WIDTH   (MM_DATA_WIDTH),
            .FEAT_ID         (FEAT_ID),
            .FEAT_VER        (FEAT_VER),
            .NEXT_DFH_OFFSET (NEXT_DFH_OFFSET),
            .END_OF_LIST     (END_OF_LIST)   
        ) pcie_ss_if (
            .fim_clk            (fim_clk),
            .fim_rst_n          (fim_rst_n[j]),
            
            .csr_clk            (csr_clk),
            .csr_rst_n          (csr_rst_n[j]),
            
            .i_axis_tx          (axis_tx[j]),
            .i_axis_tx_tready   (axis_tx_tready[j]),
            
            .i_axis_cpl_timeout (axis_cpl_timeout[j]),
            
            .i_pcie_linkup      (pcie_linkup[j]),
            .i_rx_err_code      (pcie_rx_err_code[j]),
            
            .csr_lite_if        (csr_lite_if[j]),
            .ss_csr_lite_if     (ss_csr_lite_if[j])
        );


        // OFS does not guarantee the relative order of write requests on TX and read requests
        // on TXREQ until this point, where requests enter the PCIe SS. Here, a completion
        // without data is returned to the AFU as a write request commits, indicating that
        // the future reads will see the committed write data.
        //

        // Generate write commits on the commit port. The TX stream toward the PCIe SS
        // is on the source port.
        pcie_arb_local_commit local_commit
        (
            .clk    ( fim_clk       ),
            .rst_n  ( fim_rst_n     ),
            .sink   ( axi_st_tx_if[j]  ),
            .source ( axi_st_tx_committed[j] ),
            .commit ( rxreq_arb_in[1] )
        );

        // Combine the write commit stream and RXREQ toward the AFU.
        pcie_ss_axis_mux #(
            .NUM_CH ( 2 )
        ) ho2mx_rxreq_mux (
            .clk    ( fim_clk       ),
            .rst_n  ( fim_rst_n[j]  ),
            .sink   ( rxreq_arb_in  ),
            .source ( axi_st_rxreq_if[j] )
        );

        ofs_fim_pcie_ss_tag_mode ofs_fim_pcie_ss_tag_mode (
           .fim_clk                        (fim_clk),
           .fim_rst_n                      (fim_rst_n[j]),
           .csr_clk                        (csr_clk),
           .csr_rst_n                      (csr_rst_n[j]),
           .p0_ss_app_st_ctrlshadow_tvalid (ss_app_st_ctrlshadow_tvalid[j] ),
           .p0_ss_app_st_ctrlshadow_tdata  (ss_app_st_ctrlshadow_tdata[j]  ),
           .tag_mode                       (tag_mode[j])
        );
        
        ofs_fim_pcie_ss_debug_log ofs_fim_pcie_ss_debug_log (
           .fim_clk                    (fim_clk),
           .fim_rst_n                  (fim_rst_n[j]),
           .axi_st_rxreq_if            (axi_st_rxreq_if[j]), 
           .axi_st_rx_if               (axi_st_rx_if[j]),    
           .axi_st_tx_if               (axi_st_tx_if[j]),    
           .axi_st_txreq_if            (axi_st_txreq_if[j]) 
        
        );

        assign pcie_linkup[j] = pcie_p2c_sideband[j].pcie_linkup;
        assign pcie_rx_err_code[j] = pcie_p2c_sideband[j].pcie_chk_rx_err_code;
    end // PCIE_LINKS
endgenerate


   pcie_ss_dm_top #(
      .PCIE_LANES       (ofs_fim_cfg_pkg::PCIE_LANES),
      .PCIE_NUM_LINKS   (PCIE_NUM_LINKS),
      .SOC_ATTACH       (SOC_ATTACH)
   ) pcie_ss_top (
      .fim_clk                     (fim_clk),
      .fim_rst_n                   (fim_rst_n),
      .csr_clk                     (csr_clk),
      .csr_rst_n                   (csr_rst_n),
      .ninit_done                  (ninit_done),
      .subsystem_cold_rst_n        (subsystem_cold_rst_n),
      .subsystem_warm_rst_n        (subsystem_warm_rst_n),
      .subsystem_cold_rst_ack_n    (subsystem_cold_rst_ack_n),
      .subsystem_warm_rst_ack_n    (subsystem_warm_rst_ack_n),
      .pin_pcie_refclk0_p          (pin_pcie_refclk0_p),
      .pin_pcie_refclk1_p          (pin_pcie_refclk1_p),
      .pin_pcie_in_perst_n         (pin_pcie_in_perst_n),
      .pin_pcie_rx_p               (pin_pcie_rx_p),
      .pin_pcie_rx_n               (pin_pcie_rx_n),
      .axi_st_txreq_if             (axi_st_txreq_if),
      .axi_st_rxreq_if             (rxreq_in),
      .ss_app_st_ctrlshadow_tvalid (ss_app_st_ctrlshadow_tvalid),
      .ss_app_st_ctrlshadow_tdata  (ss_app_st_ctrlshadow_tdata),
      .axi_st_rx_if                (axi_st_rx_if),
      .axi_st_tx_if                (axi_st_tx_committed),
      .ss_csr_lite_if              (ss_csr_lite_if),
      .flr_req_if                  (axi_st_flr_req),
      .flr_rsp_if                  (axi_st_flr_rsp),
      .reset_status                (reset_status),
      .pin_pcie_tx_p               (pin_pcie_tx_p),
      .pin_pcie_tx_n               (pin_pcie_tx_n),
      .cpl_timeout_if              (axis_cpl_timeout),
      
      .pcie_p2c_sideband           (pcie_p2c_sideband)
);


endmodule : pcie_wrapper
