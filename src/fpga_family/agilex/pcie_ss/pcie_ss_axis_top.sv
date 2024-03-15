// Copyright (C) 2024 Intel Corporation.
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

import ofs_fim_cfg_pkg::*;
import ofs_fim_if_pkg::*;
import pcie_ss_axis_pkg::*;

module pcie_ss_axis_top # (
   parameter PCIE_LANES = 16,
   parameter PCIE_NUM_LINKS = 1,
   parameter SOC_ATTACH = 0
)(

   input  logic                     fim_clk,
   input  logic                     csr_clk,
   input  logic                     ninit_done,
   output logic [PCIE_NUM_LINKS-1:0] reset_status,

   input  logic [PCIE_NUM_LINKS-1:0] fim_rst_n,
   input  logic [PCIE_NUM_LINKS-1:0] csr_rst_n,
   input  logic [PCIE_NUM_LINKS-1:0] subsystem_cold_rst_n,  
   input  logic [PCIE_NUM_LINKS-1:0] subsystem_warm_rst_n,    
   output logic [PCIE_NUM_LINKS-1:0] subsystem_cold_rst_ack_n,
   output logic [PCIE_NUM_LINKS-1:0] subsystem_warm_rst_ack_n,

   // PCIe pins
   input  logic                     pin_pcie_refclk0_p,
   input  logic                     pin_pcie_refclk1_p,
   input  logic                     pin_pcie_in_perst_n,   // connected to HIP
   input  logic [PCIE_LANES-1:0]    pin_pcie_rx_p,
   input  logic [PCIE_LANES-1:0]    pin_pcie_rx_n,
   output logic [PCIE_LANES-1:0]    pin_pcie_tx_p,
   output logic [PCIE_LANES-1:0]    pin_pcie_tx_n,

   //TXREQ ports
   pcie_ss_axis_if.sink             axi_st_txreq_if[PCIE_NUM_LINKS-1:0],

   //Ctrl Shadow ports
   output logic [PCIE_NUM_LINKS-1:0]         ss_app_st_ctrlshadow_tvalid,
   output logic [PCIE_NUM_LINKS-1:0][39:0]   ss_app_st_ctrlshadow_tdata,

   // Application to FPGA request port (MMIO/VDM)
   pcie_ss_axis_if.source           axi_st_rxreq_if[PCIE_NUM_LINKS-1:0],

   // FPGA to application request/response ports (DM req/rsp, MMIO rsp)
   pcie_ss_axis_if.source           axi_st_rx_if[PCIE_NUM_LINKS-1:0],
   pcie_ss_axis_if.sink             axi_st_tx_if[PCIE_NUM_LINKS-1:0],
   
   ofs_fim_axi_lite_if.slave        ss_csr_lite_if[PCIE_NUM_LINKS-1:0],
 
   // FLR interface
   output t_axis_pcie_flr           flr_req_if[PCIE_NUM_LINKS-1:0],
   input  t_axis_pcie_flr           flr_rsp_if[PCIE_NUM_LINKS-1:0],

   // Completion Timeout interface
   output t_axis_pcie_cplto         cpl_timeout_if[PCIE_NUM_LINKS-1:0],

   output t_sideband_from_pcie      pcie_p2c_sideband[PCIE_NUM_LINKS-1:0]
);

endmodule // pcie_ss_axis_top
