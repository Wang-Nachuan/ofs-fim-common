// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: MIT

//
// Description
//-----------------------------------------------------------------------------
//
// Local Memory wrapper
//
//-----------------------------------------------------------------------------

`include "ofs_fim_mem_defines.vh"
`include "ofs_ip_cfg_db.vh"

module local_mem_wrapper
   import ofs_fim_mem_if_pkg::*;
#(
   parameter bit [11:0] FEAT_ID         = 12'h00f,
   parameter bit [3:0]  FEAT_VER        = 4'h1,
   parameter bit [23:0] NEXT_DFH_OFFSET = 24'h1000,
   parameter bit        END_OF_LIST     = 1'b0
)(
   input                        clk,
   input                        reset,

   ofs_fim_emif_axi_mm_if.emif  afu_mem_if  [NUM_MEM_CHANNELS-1:0],

`ifdef INCLUDE_DDR4  
   ofs_fim_emif_ddr4_if.emif    ddr4_mem_if [NUM_DDR4_CHANNELS-1:0],
`endif

`ifdef INCLUDE_HPS
   // HPS interfaces
   input  logic [4095:0]        hps2emif,
   input  logic [1:0]           hps2emif_gp,
   output logic [4095:0]        emif2hps,
   output logic                 emif2hps_gp,

`ifdef INCLUDE_DDR4  
   ofs_fim_hps_ddr4_if.emif     ddr4_hps_if,
`endif
`endif

   // CSR interfaces
   input                        clk_csr,
   input                        rst_n_csr,
   ofs_fim_axi_lite_if.slave    csr_lite_if
);

`ifdef INCLUDE_DDR4
   // FM Subsystem
   mem_ss_top #(
      .FEAT_ID         (FEAT_ID),
      .FEAT_VER        (FEAT_VER),
      .NEXT_DFH_OFFSET (NEXT_DFH_OFFSET),
      .END_OF_LIST     (END_OF_LIST)
   ) mem_ss_top (
      .*
   );
`endif
                
endmodule // mem_ss_top

