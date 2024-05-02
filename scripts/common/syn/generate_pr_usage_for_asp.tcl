# Copyright 2020 Intel Corporation
# SPDX-License-Identifier: MIT

##
## Invoke from quartus_sh -t or as a hook at the end of fitter
##
## The ASP needs some parameters from the FIM compile in order to
## run/configure correctly. This script generates the PR resources
## that is available to the ASP and also other miscellaneous things
## like the Quartus version etc.



# OFS script for parsing command line options
package require ::quartus::project
package require ::quartus::report
package require ::quartus::flow
#package require ::quartus::bpps
package require ::quartus::device


# Add tcl_lib subdirectory of this script to package search path
lappend auto_path [file join [pwd] [file dirname [info script]] tcl_lib]
# OFS script for parsing command line options
package require options

#************************************************
# Description: Print the HELP info
#************************************************
proc PrintHelp {} {
   puts "This script emits PR usage and other misc info for  ASP configuration"
   puts "Usage: generate_pr_usage_for_asp.tcl --project=<proj> --revision=<rev> \[--output=fname\]"
   puts ""
   puts "Supported options:"
   puts "    --project=<project>"
   puts "    --revision=<revision>"
   puts "    --output=<output file>   (writes to stdout if not set)"
}


# Entry point when run as the primary script
proc main {} {

    if { [::options::ParseCMDArguments {--project --revision} {--output}] == -1 } {
      PrintHelp
      exit 1
    }

    if [info exists ::options::optionMap(--help)] {
      PrintHelp
      return 0
    }
    set project $::options::optionMap(--project)
    set revision $::options::optionMap(--revision)
    if [info exists ::options::optionMap(--output)] {
      set ofile [open $::options::optionMap(--output) w]
    } else {
      set ofile stdout
    }

    emit_info_for_asp_config $revision $project $ofile


}

# Entry point when run as post module hook
proc emit_info_for_asp_config {revision project of} {

   # qprs file format
    puts $of "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    puts $of "<!--\\"
    puts $of "  Generated by OFS script generate_pr_usage_for_asp.tcl  post-fit"
    puts $of "-->"
    puts $of "<ip>"
    puts $of " <presets version=\"12.1\">"
    puts $of "  <preset"
    puts $of "     name=\"oneapi_asp_preset\""
    puts $of "     kind=\"oneAPI_kernel_wrapper\""
    puts $of "     version=\"All\""
    puts $of "     description=\"\""
    puts $of "     board=\"\""
    puts $of "     preset_category=\"\">"


    #open project and write out qaurtus version
    project_open -revision $revision $project
    set quartus_ver $quartus(version)
    puts $of "   <parameter name=\"OFS_FIM_QUARTUS_VER\" value=\"${quartus_ver}\"/>"
    load_package report
    load_report
    
    #load the post-fit report and parse out details such as 
    # device number/family etc from the fitter summary panel
    set panel {Fitter||Fitter Summary}
    set id    [get_report_panel_id $panel]
    set rname  {Device}
    set rindex [get_report_panel_row_index -id $id $rname]
    set data   [get_report_panel_data -id $id -row $rindex -col 1]
    puts $of "   <parameter name=\"OFS_FIM_DEVICE\" value=\"${data}\"/>"
    puts $of "   <parameter name=\"OFS_FIM_REVISION\" value=\"${revision}\"/>"
    set rname  {Family}
    set rindex [get_report_panel_row_index -id $id $rname]
    set data   [get_report_panel_data -id $id -row $rindex -col 1]
    puts $of "   <parameter name=\"OFS_FIM_FAMILY\" value=\"${data}\"/>"

    #load the post-fit report and parse ALM/register/M20K and DSP 
    # resources available in the PR region for the AFU
    set panel {Fitter||Place Stage||Fitter Partition Statistics}
    set pattern {[0-9]*\.?[0-9]+?}
    set id    [get_report_panel_id $panel]
    set rname  {ALMs needed*}
    set rindex [get_report_panel_row_index -id $id $rname]
    set data   [get_report_panel_data -id $id -row $rindex -col 2]
    set numbers [regexp -all -inline -- $pattern $data]
    set alm [lindex $numbers 1]
    puts $of "   <parameter name=\"OFS_FIM_PR_AVAIL_ALM\" value=\"${alm}\"/>"

    set rname  {Dedicated Logic Registers}
    set rindex [get_report_panel_row_index -id $id $rname]
    set data   [get_report_panel_data -id $id -row $rindex -col 2]
    set numbers [regexp -all -inline -- $pattern $data]
    set reg [lindex $numbers 1]
    puts $of "   <parameter name=\"OFS_FIM_PR_AVAIL_REGISTERS\" value=\"${reg}\"/>"

    set rname  {M20Ks}
    set rindex [get_report_panel_row_index -id $id $rname]
    set data   [get_report_panel_data -id $id -row $rindex -col 2]
    set numbers [regexp -all -inline -- $pattern $data]
    set m20k [lindex $numbers 1]
    puts $of "   <parameter name=\"OFS_FIM_PR_AVAIL_M20K\" value=\"${m20k}\"/>"

    set rname  {DSP Blocks needed*}
    set rindex [get_report_panel_row_index -id $id $rname]
    set data   [get_report_panel_data -id $id -row $rindex -col 2]
    set numbers [regexp -all -inline -- $pattern $data]
    set dsp [lindex $numbers 1]
    puts $of "   <parameter name=\"OFS_FIM_PR_AVAIL_DSP\" value=\"${dsp}\"/>"

    puts $of "  <\/preset>"
    puts $of "<\/preset>"
    puts $of "<\/ip>"

    close $of
}

# Entry point when invoked from another script with a project open
proc from_sta {} {
    set project [get_current_project]
    set revision [get_current_revision]
    if [info exists ::options::optionMap(--output)] {
      set ofile [open $::options::optionMap(--output) w]
    } else {
      set ofile stdout
    }

    post_message "Running OFS generate_pr_usage_for_asp.tcl" \
        -submsgs [list "Project: ${project}" "Revision: ${revision}"]

    emit_info_for_asp_config $revision $project $ofile
}

if { [info script] eq $::argv0 } {
    main
} else {
    from_sta
}
