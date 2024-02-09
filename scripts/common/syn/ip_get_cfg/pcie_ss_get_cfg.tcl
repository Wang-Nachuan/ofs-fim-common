## Copyright (C) 2023 Intel Corporation
## SPDX-License-Identifier: MIT

##
## Script for dumping state from a PCIe SS IP file with qsys-script for
## use by the OFS FIM.
##
## Do not use the --script argument. Instead, invoke qsys-script with a
## project and system-file, adding:
##
##     --cmd="source <path to this script>; emit_ip_cfg <generated .vh file name> <subsystem name>"
## e.g.:
##     --cmd="source pcie_ss_get_cfg.tcl; emit_ip_cfg pcie_ss_cfg.vh PCIE_SS"
##
## The subsystem name is included in each symbol written to the .vh file"
##

package require qsys

proc emit_ip_cfg {ofile_name ip_name} {
    set of [open $ofile_name w]

    puts $of "//"
    puts $of "// Generated by OFS script pcie_ss_get_cfg.tcl using qsys-script"
    puts $of "//"
    puts $of ""

    puts $of "`ifndef __OFS_FIM_IP_CFG_${ip_name}__"
    puts $of "`define __OFS_FIM_IP_CFG_${ip_name}__ 1"
    puts $of ""

    # Find the instance name in the IP's namespace (expecting "pcie_ss")
    set instances [get_instances]
    if { [llength $instances] != 1 } {
        send_message ERROR "Expected one instance in PCIe SS IP"
        exit 1
    }
    set inst [lindex $instances 0]

    # Figure out which PCIe width is active. Only one instance of
    # "core<width>_pf0_pci_type0_device_id_hwtcl" is expected to have a non-zero value.
    set width 0
    foreach p [get_instance_parameters $inst] {
        if { [regexp {core([0-9]+)_pf0_pci_type0_device_id_hwtcl} $p key w] } {
            if { [get_instance_parameter_value $inst "core${w}_pf0_pci_type0_device_id_hwtcl"] != 0 } {
                # Found an instance with a non-zero device ID
                set width $w
                send_message INFO "PCIe x${width} is active"
                break
            }
        }
    }

    if { $width == 0 } {
        send_message ERROR "Did not find an active PCIe width"
        exit 1
    }

    set interfaces [get_interfaces]

    # Create an associative array of all the active core's parameters. It's easier
    # to manipulate the array than to probe the IP repeatedly. After this, the
    # script will just use the $core() array. The "core<width>_" prefix is dropped
    # to simplify name matching.
    foreach p [get_instance_parameters $inst] {
        if { [string equal $p "top_topology_hwtcl"] } {
            # Change value to upper case and remove space
            set top_topology [string toupper [get_instance_parameter_value $inst $p]]
            regsub -all { +} $top_topology {_} top_topology

            # Extract the number of links from top topology (GenA_LXW)
            if { [regsub -all {.*_+([0-9]+)X.*} $top_topology {\1} topology_num_links] == 0 } {
                # Pattern match failed. Assume 1.
                set topology_num_links 1
            }
        }

        # Tile name
        if { [string equal $p "TILE"] } {
            set tile_name [get_instance_parameter_value $inst $p]
            set tile_name_macro [string map {- _} [string toupper $tile_name]]
        }

        # Native endpoint mode?
        if { [string equal $p "virtual_rp_ep_mode_hwtcl"] } {
            set m [get_instance_parameter_value $inst $p]
            if { [string first "Native Endpoint" $m] != -1 } {
                set pcie_ss_rp_ep_mode "NATIVE_EP"
            }
        }

        # Functional mode, original PCIe SS ("AXI-ST Data Mover" or "Power User")
        if { [string equal $p "pcie_ss_func_mode_hwtcl"] } {
            set fm [get_instance_parameter_value $inst $p]
            if { [string first "Data Mover" $fm] != -1 } {
                set pcie_ss_func_mode "DM"
            } elseif { [string first "Power User" $fm] != -1 } {
                set pcie_ss_func_mode "PU"
            }
        }

        if { [regexp "^core${width}_(.*)" $p match key] } {
            set core($key) [get_instance_parameter_value $inst $p]
        }
    }

    puts $of "`define OFS_FIM_IP_CFG_${ip_name}_IS_${tile_name_macro} 1"
    puts $of "`define OFS_FIM_IP_CFG_${ip_name}_TILE_NAME \"${tile_name}\""
    puts $of ""

    puts $of "// PCIe SS Topology"
    puts $of "`define OFS_FIM_IP_CFG_${ip_name}_${top_topology} 1"
    puts $of "`define OFS_FIM_IP_CFG_${ip_name}_NUM_LINKS ${topology_num_links}"
    puts $of ""

    puts $of "// PCIe SS Interface"
    puts $of "`define OFS_FIM_IP_CFG_${ip_name}_FUNC_MODE \"${pcie_ss_func_mode}\""
    puts $of "`define OFS_FIM_IP_CFG_${ip_name}_FUNC_MODE_IS_${pcie_ss_func_mode} 1"
    if { ${pcie_ss_func_mode} != "DM" } {
        puts $of "`define OFS_FIM_IP_CFG_${ip_name}_PORT_MODE \"${pcie_ss_rp_ep_mode}\""
        puts $of "`define OFS_FIM_IP_CFG_${ip_name}_PORT_MODE_IS_${pcie_ss_rp_ep_mode} 1"
    }

    if { [info exists core(header_scheme_hwtcl)] } {
        set hdr [string map {- _} [string toupper $core(header_scheme_hwtcl)]]
        puts $of "`define OFS_FIM_IP_CFG_${ip_name}_HDR_SCHEME \"${hdr}\""
        puts $of "`define OFS_FIM_IP_CFG_${ip_name}_HDR_SCHEME_IS_${hdr} 1"
    }
    if { [info exists core(dwidth_byte_hwtcl)] } {
        puts $of "`define OFS_FIM_IP_CFG_${ip_name}_DWIDTH_BYTE $core(dwidth_byte_hwtcl)"
    }
    if { [info exists core(num_seg_hwtcl)] } {
        puts $of "`define OFS_FIM_IP_CFG_${ip_name}_NUM_SEG $core(num_seg_hwtcl)"
    } else {
        # Assume 1 if not set
        puts $of "`define OFS_FIM_IP_CFG_${ip_name}_NUM_SEG 1"
    }

    # Is there an RX credit interface?
    if { [lsearch -glob $interfaces "*_st_rxcrdt"] != -1 } {
        puts $of "`define OFS_FIM_IP_CFG_${ip_name}_HAS_RXCRDT 1"
    } else {
        puts $of "// No rxcrdt interface (OFS_FIM_IP_CFG_${ip_name}_HAS_RXCRDT not set)"
    }

    # Does the RX interface have tready?
    set st_rx_idx [lsearch -glob $interfaces "*_st_rx"]
    if { $st_rx_idx != -1 } {
        set st_rx_ifc [lindex $interfaces $st_rx_idx]
        if { [lsearch -glob [get_interface_ports $st_rx_ifc] "*_tready"] != -1 } {
            puts $of "`define OFS_FIM_IP_CFG_${ip_name}_ST_RX_HAS_TREADY 1"
        } else {
            puts $of "// No tready in st_rx (OFS_FIM_IP_CFG_${ip_name}_ST_RX_HAS_TREADY not set)"
        }
    }

    # Does the FLR completion interface have a tready output?
    set flrcmpl_idx [lsearch -glob $interfaces "*_st_flrcmpl"]
    if { $flrcmpl_idx != -1 } {
        set flrcmpl_ifc [lindex $interfaces $flrcmpl_idx]
        if { [lsearch -glob [get_interface_ports $flrcmpl_ifc] "*_tready"] != -1 } {
            puts $of "`define OFS_FIM_IP_CFG_${ip_name}_FLRCMPL_HAS_TREADY 1"
        } else {
            puts $of "// No tready in flrcmpl (OFS_FIM_IP_CFG_${ip_name}_FLRCMPL_HAS_TREADY not set)"
        }
    }

    # Sorted completions? Meaningful only in DM mode.
    if { [info exists core(cpl_reordering_en_hwtcl)] && $core(cpl_reordering_en_hwtcl) } {
        puts $of "`define OFS_FIM_IP_CFG_${ip_name}_HAS_CPL_REORDER 1"
    } else {
        puts $of "// No completion reordering (OFS_FIM_IP_CFG_${ip_name}_HAS_CPL_REORDER not set)"
    }

    puts $of ""

    # Look for active PFs and VFs
    puts $of "//"
    puts $of "// The OFS_FIM_IP_CFG_<ip_name>_PF<n>_ACTIVE macro will be defined iff the"
    puts $of "// PF is active. The value does not have to be tested."
    puts $of "//"
    puts $of "// For each active PF<n>, OFS_FIM_IP_CFG_<ip_name>_PF<n>_NUM_VFS will be"
    puts $of "// defined iff there are VFs associated with the PF."
    puts $of "//"
    puts $of ""

    set num_pfs 0
    set max_pf_num 0
    set total_num_vfs 0
    set max_vfs_per_pf 0

    # Construct two arrays. pf_active_arr entries are 0 or 1, indicating whether
    # the PF number is enabled. num_vfs_arr is the number of VFs associated with
    # a PF index.
    set pf_active_arr(0) 0
    set num_vfs_arr(0) 0

    set ats_cap_enabled 0
    set prs_cap_enabled 0
    set pasid_cap_enabled 0

    # Loop through all PFs. This loop is set up to support sparse PF numbering,
    # though the PCIe SS configuration forces dense PF numbering.
    for { set pf_num 0 } { $pf_num < $core(total_pf_count_hwtcl) } { incr pf_num } {
        set pf_active_arr($pf_num) 0
        set num_vfs_arr($pf_num) 0

        # PF active?
        if { $core(pf${pf_num}_pci_type0_device_id_hwtcl) > 0 } {
            set pf_active_arr($pf_num) 1
            set max_pf_num $pf_num
            incr num_pfs 1
            puts $of "`define OFS_FIM_IP_CFG_${ip_name}_PF${pf_num}_ACTIVE 1"
            puts $of "`define OFS_FIM_IP_CFG_${ip_name}_PF${pf_num}_BAR0_ADDR_WIDTH $core(pf${pf_num}_bar0_address_width_hwtcl)"

            # Define capability macros only when enabled
            if { $core(virtual_pf${pf_num}_ats_cap_enable_hwtcl) > 0 } {
                puts $of "`define OFS_FIM_IP_CFG_${ip_name}_PF${pf_num}_ATS_CAP 1"
                set ats_cap_enabled 1
            }
            if { $core(virtual_pf${pf_num}_prs_ext_cap_enable_hwtcl) > 0 } {
                puts $of "`define OFS_FIM_IP_CFG_${ip_name}_PF${pf_num}_PRS_CAP 1"
                set prs_cap_enabled 1
            }
            if { $core(virtual_pf${pf_num}_pasid_cap_enable_hwtcl) > 0 } {
                puts $of "`define OFS_FIM_IP_CFG_${ip_name}_PF${pf_num}_PASID_CAP 1"
                set pasid_cap_enabled 1
            }

            # VFs active?
            set num_vfs $core(pf${pf_num}_vf_count_hwtcl)
            if { $num_vfs > 0 } {
                set num_vfs_arr($pf_num) $num_vfs
                puts $of "`define OFS_FIM_IP_CFG_${ip_name}_PF${pf_num}_NUM_VFS ${num_vfs}"
                puts $of "`define OFS_FIM_IP_CFG_${ip_name}_PF${pf_num}_VF_BAR0_ADDR_WIDTH $core(pf${pf_num}_sriov_vf_bar0_address_width_hwtcl)"
                incr total_num_vfs $num_vfs
                if { $num_vfs > $max_vfs_per_pf } {
                    set max_vfs_per_pf $num_vfs
                }

                if { $core(pf${pf_num}_vf_ats_cap_enable_hwtcl) > 0 } {
                    puts $of "`define OFS_FIM_IP_CFG_${ip_name}_PF${pf_num}_VF_ATS_CAP 1"
                }
            }

            puts $of ""
        }
    }

    puts $of ""
    puts $of "//"
    puts $of "// The macros below represent the raw PF/VF configuration above in"
    puts $of "// ways that are easier to process in SystemVerilog loops."
    puts $of "//"
    puts $of ""
    
    puts $of "// Total number of PFs, not necessarily dense (see MAX_PF_NUM)"
    puts $of "`define OFS_FIM_IP_CFG_${ip_name}_NUM_PFS ${num_pfs}"
    puts $of "// Total number of VFs across all PFs"
    puts $of "`define OFS_FIM_IP_CFG_${ip_name}_TOTAL_NUM_VFS ${total_num_vfs}"
    puts $of "// Largest active PF number"
    puts $of "`define OFS_FIM_IP_CFG_${ip_name}_MAX_PF_NUM ${max_pf_num}"
    puts $of "// Largest number of VFs associated with a single PF"
    puts $of "`define OFS_FIM_IP_CFG_${ip_name}_MAX_VFS_PER_PF ${max_vfs_per_pf}"
    puts $of ""

    puts $of "// Vector indicating enabled PFs (1 if enabled) with"
    puts $of "// index range 0 to OFS_FIM_IP_CFG_${ip_name}_MAX_PF_NUM"
    puts -nonewline $of "`define OFS_FIM_IP_CFG_${ip_name}_PF_ENABLED_VEC "
    for { set i 0 } { $i <= $max_pf_num } { incr i } {
        if { $i > 0 } { puts -nonewline $of ", " }
        puts -nonewline $of $pf_active_arr($i)
    }
    puts $of ""

    puts $of "// Vector with the number of VFs indexed by PF"
    puts -nonewline $of "`define OFS_FIM_IP_CFG_${ip_name}_NUM_VFS_VEC "
    for { set i 0 } { $i <= $max_pf_num } { incr i } {
        if { $i > 0 } { puts -nonewline $of ", " }
        puts -nonewline $of $num_vfs_arr($i)
    }
    puts $of ""

    puts $of ""
    puts $of "// If ATS, PRS or PASID is enabled on at least one PF the following"
    puts $of "// macros will be defined here, one per feature:"
    puts $of "//   OFS_FIM_IP_CFG_${ip_name}_ATS_CAP"
    puts $of "//   OFS_FIM_IP_CFG_${ip_name}_PRS_CAP"
    puts $of "//   OFS_FIM_IP_CFG_${ip_name}_PASID_CAP"
    if { $ats_cap_enabled > 0 } {
        puts $of "`define OFS_FIM_IP_CFG_${ip_name}_ATS_CAP 1"
    }
    if { $prs_cap_enabled > 0 } {
        puts $of "`define OFS_FIM_IP_CFG_${ip_name}_PRS_CAP 1"
    }
    if { $pasid_cap_enabled > 0 } {
        puts $of "`define OFS_FIM_IP_CFG_${ip_name}_PASID_CAP 1"
    }

    # Emit ATS/PRS/PASID configuration as vectors, indexed by PF. These may
    # be used by modules that operate on multiplexed TLP streams and maintain
    # per-function state.
    puts $of ""
    puts $of "// Vector indicating whether ATS is enabled, indexed by PF"
    puts -nonewline $of "`define OFS_FIM_IP_CFG_${ip_name}_ATS_CAP_VEC "
    puts $of [join [get_cfg_enable_pf_vec core $max_pf_num virtual_pf _ats_cap_enable_hwtcl] ", "]

    puts $of "// Vector indicating whether ATS is enabled for VFs, indexed by PF"
    puts -nonewline $of "`define OFS_FIM_IP_CFG_${ip_name}_VF_ATS_CAP_VEC "
    # Entries in the ATS VF vector are true if VFs and ATS are enabled
    set vf_ena [get_cfg_enable_pf_vec core $max_pf_num pf _vf_count_hwtcl]
    set vf_ats [get_cfg_enable_pf_vec core $max_pf_num pf _vf_ats_cap_enable_hwtcl]
    set v {}
    foreach {ena} $vf_ena {ats} $vf_ats {
        lappend v [expr {$ena && $ats}]
    }
    puts $of [join $v ", "]

    puts $of "// Vector indicating whether PRS is enabled, indexed by PF"
    puts -nonewline $of "`define OFS_FIM_IP_CFG_${ip_name}_PRS_CAP_VEC "
    puts $of [join [get_cfg_enable_pf_vec core $max_pf_num virtual_pf _prs_ext_cap_enable_hwtcl] ", "]

    puts $of "// Vector indicating whether PASID is enabled, indexed by PF"
    puts -nonewline $of "`define OFS_FIM_IP_CFG_${ip_name}_PASID_CAP_VEC "
    puts $of [join [get_cfg_enable_pf_vec core $max_pf_num virtual_pf _pasid_cap_enable_hwtcl] ", "]

    puts $of ""
    puts $of "`endif // `ifndef __OFS_FIM_IP_CFG_${ip_name}__"

    close $of
}


##
## Return a list with one entry per PF. Entries in the returned list are
## either 0 or 1 depending on whether the key ${name_prefix}<pf_num>${name_suffix}
## has a non-zero value in $core()..
##
proc get_cfg_enable_pf_vec {coreRef max_pf_num name_prefix name_suffix} {
    upvar $coreRef core
    set v {}

    for { set pf_num 0 } { $pf_num <= $max_pf_num } { incr pf_num } {
        lappend v [expr ($core(${name_prefix}${pf_num}${name_suffix}) > 0)]
    }

    return $v
}
