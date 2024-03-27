## Copyright (C) 2023 Intel Corporation
## SPDX-License-Identifier: MIT
#--------------------
# Option to disable user clock
#--------------------
set vlog_macros [get_all_global_assignments -name VERILOG_MACRO]
set include_user_clk 0

foreach_in_collection m $vlog_macros {
    if { [string equal "INCLUDE_USER_CLK" [lindex $m 2]] } {
        set include_user_clk 1
    }
}

if {$include_user_clk == 1} {
    #--------------------
    # User Clock Filelist 
    #--------------------
    set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/user_clock/user_clock.sv
    set_global_assignment -name SYSTEMVERILOG_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/user_clock/qph_user_clk.sv
    set_global_assignment -name IP_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/user_clock/qph_user_clk_iopll_RF100M.ip
    set_global_assignment -name IP_FILE $::env(BUILD_ROOT_REL)/ofs-common/src/fpga_family/agilex/user_clock/qph_user_clk_iopll_reconfig.ip
}
