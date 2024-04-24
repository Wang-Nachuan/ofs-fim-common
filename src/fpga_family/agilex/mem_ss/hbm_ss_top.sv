// Copyright (C) 2020 Intel Corporation.
// SPDX-License-Identifier: MIT

//
// Description
//-----------------------------------------------------------------------------
//
// Memory Subsystem FIM wrapper
//
//-----------------------------------------------------------------------------

`include "ofs_fim_mem_defines.vh"
`include "ofs_ip_cfg_db.vh"

module hbm_ss_top
   import ofs_fim_mem_if_pkg::*;
#(
   parameter bit [11:0] FEAT_ID         = 12'h00f,
   parameter bit [3:0]  FEAT_VER        = 4'h1,
   parameter bit [23:0] NEXT_DFH_OFFSET = 24'h1000,
   parameter bit        END_OF_LIST     = 1'b0
)(
   input       reset,

   input       uib_refclk      [NUM_HBM_DEVICES-1:0],
   input       fab_clk         [NUM_HBM_DEVICES-1:0],
   input       noc_ctrl_refclk [NUM_HBM_DEVICES-1:0],

   input       hbm_cattrip [NUM_HBM_DEVICES-1:0],
   input [2:0] hbm_temp    [NUM_HBM_DEVICES-1:0],

   ofs_fim_emif_axi_mm_if.emif afu_mem_if [NUM_MEM_CHANNELS-1:0],

   input       clk_csr,
   input       rst_n_csr,
   ofs_fim_axi_lite_if.slave    csr_lite_if

);

`ifndef __OFS_FIM_IP_CFG_LOCAL_MEM__
   $error("OFS HBM Subsystem configuration is undefined, but the subsystem has been instantiated in the design!");
`endif

   logic [NUM_HBM_DEVICES-1:0] hbm_cal_fail;
   logic [NUM_HBM_DEVICES-1:0] hbm_cal_success;

   logic [NUM_HBM_DEVICES-1:0] csr_cal_fail;
   logic [NUM_HBM_DEVICES-1:0] csr_cal_success;

   ofs_fim_axi_lite_if #(.AWADDR_WIDTH(11), .ARADDR_WIDTH(11), .WDATA_WIDTH(64)) emif_dfh_if();

fim_resync #(
   .SYNC_CHAIN_LENGTH(3),
   .WIDTH(NUM_MEM_CHANNELS),
   .INIT_VALUE(0),
   .NO_CUT(0)
) mem_ss_cal_success_resync (
   .clk   (clk_csr),
   .reset (!rst_n_csr),
   .d     (hbm_cal_success),
   .q     (csr_cal_success)
);

fim_resync #(
   .SYNC_CHAIN_LENGTH(3),
   .WIDTH(NUM_MEM_CHANNELS),
   .INIT_VALUE(0),
   .NO_CUT(0)
) mem_ss_cal_fail_resync (
   .clk   (clk_csr),
   .reset (!rst_n_csr),
   .d     (hbm_cal_fail),
   .q     (csr_cal_fail)
);

mem_ss_csr #(
   .FEAT_ID          (FEAT_ID),
   .FEAT_VER         (FEAT_VER),
   .NEXT_DFH_OFFSET  (NEXT_DFH_OFFSET),
   .END_OF_LIST      (END_OF_LIST),
   .NUM_MEM_DEVICES  (NUM_HBM_DEVICES)
) mem_ss_csr_inst (
   .clk              (clk_csr),
   .rst_n            (rst_n_csr),
   .csr_lite_if      (csr_lite_if),
   .cal_fail         (csr_cal_fail),
   .cal_success      (csr_cal_success)
);

// AXI-MM application channel connections
// Macros are used to declare and connect the OFS interface types
// to wires which are implicitly connected to the PD component ports

// Connect clock/reset
generate for(genvar ch = 0; ch < NUM_MEM_CHANNELS; ch++) begin : mem_clk_rst
   always_comb begin
      afu_mem_if[ch].clk   = fab_clk[0];
      afu_mem_if[ch].rst_n = ~reset;
   end
end
endgenerate

`DECLARE_OFS_FIM_AXI_MM_WIRES(i0_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i1_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i2_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i3_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i4_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i5_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i6_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i7_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i8_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i9_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i10_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i11_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i12_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i13_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i14_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i15_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i16_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i17_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i18_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i19_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i20_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i21_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i22_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i23_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i24_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i25_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i26_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i27_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i28_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i29_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i30_app, ofs_fim_mem_if_pkg::AXI_MEM)
`DECLARE_OFS_FIM_AXI_MM_WIRES(i31_app, ofs_fim_mem_if_pkg::AXI_MEM)

generate
   `CONNECT_OFS_FIM_AXI_MM_WIRES(i0_app, afu_mem_if[0])
   if(NUM_MEM_CHANNELS > 1) begin : i1_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i1_app, afu_mem_if[1])
   end
   if(NUM_MEM_CHANNELS > 2) begin : i2_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i2_app, afu_mem_if[2])
   end
   if(NUM_MEM_CHANNELS > 3) begin : i3_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i3_app, afu_mem_if[3])
   end
   if(NUM_MEM_CHANNELS > 4) begin : i4_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i4_app, afu_mem_if[4])
   end
   if(NUM_MEM_CHANNELS > 5) begin : i5_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i5_app, afu_mem_if[5])
   end
   if(NUM_MEM_CHANNELS > 6) begin : i6_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i6_app, afu_mem_if[6])
   end
   if(NUM_MEM_CHANNELS > 7) begin : i7_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i7_app, afu_mem_if[7])
   end
   if(NUM_MEM_CHANNELS > 8) begin : i8_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i8_app, afu_mem_if[8])
   end
   if(NUM_MEM_CHANNELS > 9) begin : i9_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i9_app, afu_mem_if[9])
   end
   if(NUM_MEM_CHANNELS > 10) begin : i10_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i10_app, afu_mem_if[10])
   end
   if(NUM_MEM_CHANNELS > 11) begin : i11_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i11_app, afu_mem_if[11])
   end
   if(NUM_MEM_CHANNELS > 12) begin : i12_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i12_app, afu_mem_if[12])
   end
   if(NUM_MEM_CHANNELS > 13) begin : i13_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i13_app, afu_mem_if[13])
   end
   if(NUM_MEM_CHANNELS > 14) begin : i14_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i14_app, afu_mem_if[14])
   end
   if(NUM_MEM_CHANNELS > 15) begin : i15_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i15_app, afu_mem_if[15])
   end
   if(NUM_MEM_CHANNELS > 16) begin : i16_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i16_app, afu_mem_if[16])
   end
   if(NUM_MEM_CHANNELS > 17) begin : i17_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i17_app, afu_mem_if[17])
   end
   if(NUM_MEM_CHANNELS > 18) begin : i18_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i18_app, afu_mem_if[18])
   end
   if(NUM_MEM_CHANNELS > 19) begin : i19_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i19_app, afu_mem_if[19])
   end
   if(NUM_MEM_CHANNELS > 20) begin : i20_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i20_app, afu_mem_if[20])
   end
   if(NUM_MEM_CHANNELS > 21) begin : i21_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i21_app, afu_mem_if[21])
   end
   if(NUM_MEM_CHANNELS > 22) begin : i22_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i22_app, afu_mem_if[22])
   end
   if(NUM_MEM_CHANNELS > 23) begin : i23_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i23_app, afu_mem_if[23])
   end
   if(NUM_MEM_CHANNELS > 24) begin : i24_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i24_app, afu_mem_if[24])
   end
   if(NUM_MEM_CHANNELS > 25) begin : i25_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i25_app, afu_mem_if[25])
   end
   if(NUM_MEM_CHANNELS > 26) begin : i26_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i26_app, afu_mem_if[26])
   end
   if(NUM_MEM_CHANNELS > 27) begin : i27_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i27_app, afu_mem_if[27])
   end
   if(NUM_MEM_CHANNELS > 28) begin : i28_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i28_app, afu_mem_if[28])
   end
   if(NUM_MEM_CHANNELS > 29) begin : i29_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i29_app, afu_mem_if[29])
   end
   if(NUM_MEM_CHANNELS > 30) begin : i30_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i30_app, afu_mem_if[30])
   end
   if(NUM_MEM_CHANNELS > 31) begin : i31_app_conn
      `CONNECT_OFS_FIM_AXI_MM_WIRES(i31_app, afu_mem_if[31])
   end
endgenerate

   // HBM/NoC signals
   logic        hbm_0_fab_clk_clk, hbm_1_fab_clk_clk;
   logic        hbm_0_rst_n_reset_n, hbm_1_rst_n_reset_n;
   logic        hbm_0_cattrip_conduit, hbm_1_cattrip_conduit;
   logic [2:0]  hbm_0_temp_conduit, hbm_1_temp_conduit;
   logic        hbm_0_local_cal_success_local_cal_success, hbm_1_local_cal_success_local_cal_success;
   logic        hbm_0_local_cal_fail_local_cal_fail, hbm_1_local_cal_fail_local_cal_fail;
   logic        hbm_0_uib_clk_clk, hbm_1_uib_clk_clk;
   logic        noc_0_ctrl_clk, noc_1_ctrl_clk;

generate
   always_comb begin
      hbm_0_fab_clk_clk     = fab_clk[0];
      hbm_0_rst_n_reset_n   = ~reset;
      hbm_0_cattrip_conduit = hbm_cattrip[0];
      hbm_0_temp_conduit    = hbm_temp[0];
      hbm_0_uib_clk_clk     = uib_refclk[0];
      hbm_cal_success[0]    = hbm_0_local_cal_success_local_cal_success;
      hbm_cal_fail[0]       = hbm_0_local_cal_fail_local_cal_fail;
      noc_0_ctrl_clk        = noc_ctrl_refclk[0];
   end

if(NUM_HBM_DEVICES > 1) begin : hbm_1
   always_comb begin
      hbm_1_fab_clk_clk     = fab_clk[1];
      hbm_1_rst_n_reset_n   = ~reset;
      hbm_1_cattrip_conduit = hbm_cattrip[1];
      hbm_1_temp_conduit    = hbm_temp[1];
      hbm_1_uib_clk_clk     = uib_refclk[1];
      hbm_cal_success[1]    = hbm_1_local_cal_success_local_cal_success;
      hbm_cal_fail[1]       = hbm_1_local_cal_fail_local_cal_fail;
      noc_1_ctrl_clk        = noc_ctrl_refclk[1];
   end
end
endgenerate

   // Use implicit connections
   hbm_ss hbm_inst ( .* );


endmodule // mem_ss_top
