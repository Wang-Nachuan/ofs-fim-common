# PF/VF MUX

The PF/VF MUX maps multiplexed TLP streams that carry traffic for multiple functions into separate ports. By default, OFS creates a PF/VF MUX to expose each PCIe function as a separate port. The routing table passed to the MUX may also be used to assign multiple functions to the same port.

### [pf_vf_mux_tree.sv](pf_vf_mux_tree.sv)

The MUX tree module is instantiated as the top-level of a hierarchical multiplexer tree. It constructs a routing tree recursively, avoiding excessive fanout at each level. Intermediate routing nodes are binary, with half of the target ports mapped to a "left" output and half to the "right".

Note that arbitration is currently round-robin at each level in the tree. Some workload patterns with unbalanced traffic across the ports could suffer QoS problems. Since QoS is an application-dependent problem, managing more complex arbitration is left to the user.

### [pf_vf_mux_w_params.sv](pf_vf_mux_w_params.sv)

This module is a leaf node in the MUX tree. It implements a single switch that connects a multiplexed port to multiple demultiplexed ports. Arbitration is round-robin.

## Debugging

In simulation, each node in a PF/VF MUX tree creates a log file. By default, OFS names the log files "log_pf_vf_mux_*.tsv", with the wildcard containing "PG" for a MUX within the PR port gasket and "SR" within the FIM's static region. A hierarchical tree generates log files for each level in the routing tree, including intermediate binary nodes. Traffic is logged as it passes through each level. Within the tree hierarchy, "_L" and "_R" are appended to the log file names indicating traversal down the left or right ports of intermediate tree nodes.

Each log file begins with its instantiation path and routing table.