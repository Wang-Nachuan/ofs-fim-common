// Copyright (C) 2023 Intel Corporation.
// SPDX-License-Identifier: MIT

//
// Description
//-----------------------------------------------------------------------------
//
// Common package for memory interface parameters. 
//
//-----------------------------------------------------------------------------

`ifndef __OFS_FIM_MEM_IF_PKG__
`define __OFS_FIM_MEM_IF_PKG__

// IP configuration database, generated by OFS script ofs_ip_cfg_db.tcl after
// IP generation.
`include "ofs_ip_cfg_db.vh"

package ofs_fim_mem_if_pkg;

   // FIM MEMORY PARAMS
   
   // Local memory interface bus width parameters:
   //
   // If no Memory Subsystem is present in the design or a type of memory interface isn't present in the subsystem component
   // then fallback values are selected for the parameters below.
   // The fallback values do not provide a functional mapping to IP interfaces. They are only defined for compilation
   // units included within common design files.

   // AXI-MM PARAMS
`ifdef OFS_FIM_IP_CFG_MEM_SS_DEFINES_USER_AXI
   localparam NUM_MEM_CHANNELS        = `OFS_FIM_IP_CFG_MEM_SS_NUM_AXI_CHANNELS;
   localparam AXI_MEM_RDATA_WIDTH     = `OFS_FIM_IP_CFG_MEM_SS_AXI_RDATA_WIDTH;
   localparam AXI_MEM_WDATA_WIDTH     = `OFS_FIM_IP_CFG_MEM_SS_AXI_WDATA_WIDTH;
   localparam AXI_MEM_ADDR_WIDTH      = `OFS_FIM_IP_CFG_MEM_SS_AXI_ADDR_WIDTH;
   localparam AXI_MEM_ID_WIDTH        = `OFS_FIM_IP_CFG_MEM_SS_AXI_ID_WIDTH;
   localparam AXI_MEM_USER_WIDTH      = `OFS_FIM_IP_CFG_MEM_SS_AXI_USER_WIDTH;
   localparam AXI_MEM_BUSER_WIDTH     = `OFS_FIM_IP_CFG_MEM_SS_AXI_BUSER_WIDTH;
   localparam AXI_MEM_BURST_LEN_WIDTH = `OFS_FIM_IP_CFG_MEM_SS_AXI_LEN_WIDTH;
`else 
   localparam NUM_MEM_CHANNELS        = 1;
   localparam AXI_MEM_RDATA_WIDTH     = 512;
   localparam AXI_MEM_WDATA_WIDTH     = 512;
   localparam AXI_MEM_ADDR_WIDTH      = 32;
   localparam AXI_MEM_ID_WIDTH        = 9;
   localparam AXI_MEM_USER_WIDTH      = 1;
   localparam AXI_MEM_BUSER_WIDTH     = 1;
   localparam AXI_MEM_BURST_LEN_WIDTH = 8;
`endif

   // DDR4 PARAMS
`ifdef OFS_FIM_IP_CFG_MEM_SS_DEFINES_EMIF_DDR4
   localparam NUM_DDR4_CHANNELS       = `OFS_FIM_IP_CFG_MEM_SS_NUM_DDR4_CHANNELS;
   localparam DDR4_A_WIDTH            = `OFS_FIM_IP_CFG_MEM_SS_DDR4_A_WIDTH;
   localparam DDR4_BA_WIDTH           = `OFS_FIM_IP_CFG_MEM_SS_DDR4_BA_WIDTH;
   localparam DDR4_BG_WIDTH           = `OFS_FIM_IP_CFG_MEM_SS_DDR4_BG_WIDTH;
   localparam DDR4_CK_WIDTH           = `OFS_FIM_IP_CFG_MEM_SS_DDR4_CK_WIDTH;
   localparam DDR4_CKE_WIDTH          = `OFS_FIM_IP_CFG_MEM_SS_DDR4_CKE_WIDTH;
   localparam DDR4_CS_WIDTH           = `OFS_FIM_IP_CFG_MEM_SS_DDR4_CS_N_WIDTH;
   localparam DDR4_ODT_WIDTH          = `OFS_FIM_IP_CFG_MEM_SS_DDR4_ODT_WIDTH;
   localparam DDR4_DQ_WIDTH           = `OFS_FIM_IP_CFG_MEM_SS_DDR4_DQ_WIDTH;
`else
   localparam NUM_DDR4_CHANNELS       = 1;
   localparam DDR4_A_WIDTH            = 17;
   localparam DDR4_BA_WIDTH           = 2;
   localparam DDR4_BG_WIDTH           = 1;
   localparam DDR4_CK_WIDTH           = 1;
   localparam DDR4_CKE_WIDTH          = 1;
   localparam DDR4_CS_WIDTH           = 2;
   localparam DDR4_ODT_WIDTH          = 1;
   localparam DDR4_DQ_WIDTH           = 32;
`endif
   localparam DDR4_DQS_WIDTH          = DDR4_DQ_WIDTH/8;
   
`ifdef OFS_FIM_IP_CFG_MEM_SS_DEFINES_HPS_DDR4
   localparam HPS_A_WIDTH            = `OFS_FIM_IP_CFG_MEM_SS_HPS_A_WIDTH;
   localparam HPS_BA_WIDTH           = `OFS_FIM_IP_CFG_MEM_SS_HPS_BA_WIDTH;
   localparam HPS_BG_WIDTH           = `OFS_FIM_IP_CFG_MEM_SS_HPS_BG_WIDTH;
   localparam HPS_CK_WIDTH           = `OFS_FIM_IP_CFG_MEM_SS_HPS_CK_WIDTH;
   localparam HPS_CKE_WIDTH          = `OFS_FIM_IP_CFG_MEM_SS_HPS_CKE_WIDTH;
   localparam HPS_CS_WIDTH           = `OFS_FIM_IP_CFG_MEM_SS_HPS_CS_N_WIDTH;
   localparam HPS_ODT_WIDTH          = `OFS_FIM_IP_CFG_MEM_SS_HPS_ODT_WIDTH;
   localparam HPS_DQ_WIDTH           = `OFS_FIM_IP_CFG_MEM_SS_HPS_DQ_WIDTH;
`else
   localparam NUM_HPS_CHANNELS       = 1;
   localparam HPS_A_WIDTH            = 17;
   localparam HPS_BA_WIDTH           = 2;
   localparam HPS_BG_WIDTH           = 1;
   localparam HPS_CK_WIDTH           = 1;
   localparam HPS_CKE_WIDTH          = 1;
   localparam HPS_CS_WIDTH           = 2;
   localparam HPS_ODT_WIDTH          = 1;
   localparam HPS_DQ_WIDTH           = 32;
`endif
   localparam HPS_DQS_WIDTH          = HPS_DQ_WIDTH/8;
   
endpackage : ofs_fim_mem_if_pkg

`endif //  `ifndef __OFS_FIM_MEM_IF_PKG__
   
