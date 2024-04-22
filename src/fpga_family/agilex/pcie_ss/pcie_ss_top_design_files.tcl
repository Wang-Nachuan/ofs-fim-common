# Copyright (C) 2020 Intel Corporation.
# SPDX-License-Identifier: MIT

#

set_global_assignment -name SEARCH_PATH "$::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss"

#--------------------
# Packages
#--------------------
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/ofs_fim_pcie_hdr_def.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/ofs_fim_axis_if.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/shims/ofs_fim_pcie_ss_shims_pkg.sv

#--------------------
# PCIE bridge
#--------------------
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/axis_reg_pcie_txs.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/tx_aligner.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_bridge.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_bridge_cdc.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_rx_bridge_cdc.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_tx_bridge_cdc.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_checker.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_rx_bridge.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_tx_bridge.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_rx_bridge_ptile.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_tx_bridge_ptile.sv

#----------
# PCIE CSR
#----------
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_csr.sv

#----------
# PCIE SS IF
#----------
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_err_checker.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_ss_csr_if.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_ss_if.sv

#----------
# PCIE shims -- PCIe SS edge to OFS mapping
#----------
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/shims/ofs_fim_pcie_ss_cpl_metering.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/shims/ofs_fim_pcie_ss_ib2sb.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/shims/ofs_fim_pcie_ss_msix.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/shims/ofs_fim_pcie_ss_msix_table.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/shims/ofs_fim_pcie_ss_pipe_rx_sb.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/shims/ofs_fim_pcie_ss_pipe_tx_sb.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/shims/ofs_fim_pcie_ss_rx_dual_stream.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/shims/ofs_fim_pcie_ss_rx_seg_align.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/shims/ofs_fim_pcie_ss_rxcrdt.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/shims/ofs_fim_pcie_ss_sb2ib.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/shims/ofs_fim_pcie_ss_tx_merge.sv

#----------
# PCIE top
#----------
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_tx_arbiter.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_flr_resync.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_ss_axis_top.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_ss_dm_top.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/ofs_fim_pcie_ss_tag_mode.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/ofs_fim_pcie_ss_debug_log.sv
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/pcie_wrapper.sv

#----------
# PCIE Adapter
#----------
set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/pcie_ss/axi_s_adapter.sv


#----------
# SDC
#----------

