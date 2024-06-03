## Copyright (C) 2024 Intel Corporation
## SPDX-License-Identifier: MIT

##
## Force slightly tighter timing constraints during FIM fitting to add a bit
## of extra slack for later PR builds. AFUs in the PR region may have small
## effects on timing in the fixed region, especially for clock crossings.
##

# Is this the fitter stage?
if { $::quartus(nameofexecutable) == "quartus_fit" } {

    # Is this a base FIM build? REVISION_TYPE is PR_IMPL in PR partitions.
    set part_revision_type PR_BASE
    catch { set part_revision_type [get_global_assignment -name REVISION_TYPE] }
    if { $part_revision_type != "PR_IMPL" } {

        # Is a PR region defined?
        set include_pr 0
        foreach_in_collection m [get_all_global_assignments -name VERILOG_MACRO] {
            if { [string equal "INCLUDE_PR" [lindex $m 2]] } {
               set include_pr 1
               break
            }
        }

        if { $include_pr } {
            post_message "Adding extra slack to base iopll clock crossings..."

            set_clock_uncertainty -from [get_clocks {sys_pll|iopll_0_refclk}]   -to [get_clocks {sys_pll|iopll_0_clk_100m}] -add 0.008
            set_clock_uncertainty -from [get_clocks {sys_pll|iopll_0_clk_100m}] -to [get_clocks {sys_pll|iopll_0_refclk}]   -add 0.008

            set_clock_uncertainty -from [get_clocks {sys_pll|iopll_0_clk_100m}] -to [get_clocks {sys_pll|iopll_0_clk_50m}]  -add 0.008
            set_clock_uncertainty -from [get_clocks {sys_pll|iopll_0_clk_50m}]  -to [get_clocks {sys_pll|iopll_0_clk_100m}] -add 0.008
        }
    }
}
