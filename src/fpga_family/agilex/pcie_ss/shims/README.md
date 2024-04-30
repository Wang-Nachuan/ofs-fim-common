# PCIe AXI-S Shims

The modules here are composed to form pipelines that connect OFS to native TLP streams from the AXI Streaming IP for PCIe. OFS implements a pair of TLP streams in each direction: RXREQ (MMIO and other requests), RX (completions inbound to the FPGA), TXREQ (host memory reads from the FPGA) and TX (all other outbound traffic from the FPGA). PCIe hard IP (HIP) encoding is platform-dependent. Headers may be in-band on the data bus or side-band, packets may start at one or more segment boundaries and data bus widths may vary. The shims map between OFS streams and HIP instances.

Modules here named ofs_fim_pcie_ss_pipe_\* form pipelines that compose shim modules into full transformations.

* [ofs_fim_pcie_ss_pipe_rx_sb.sv](ofs_fim_pcie_ss_pipe_rx_sb.sv) and [ofs_fim_pcie_ss_pipe_tx_sb.sv](ofs_fim_pcie_ss_pipe_tx_sb.sv) form RX and TX pipelines for HIPs with side-band header encoding.
* [ofs_fim_pcie_ss_cpl_metering.sv](ofs_fim_pcie_ss_cpl_metering.sv) tracks outstanding FPGA read requests, ensuring that HIP completion buffer space is available for all responses. 
* [ofs_fim_pcie_ss_ib2sb.sv](ofs_fim_pcie_ss_ib2sb.sv) transforms a stream with in-band headers to the equivalent with side-band headers.
* [ofs_fim_pcie_ss_msix.sv](ofs_fim_pcie_ss_msix.sv) and [ofs_fim_pcie_ss_msix_table.sv](ofs_fim_pcie_ss_msix_table.sv) implement an MSI-X table and map AFU interrupt requests to host writes. AFU interrupt requests are encoded using the Data Mover representation of interrupts.
* [ofs_fim_pcie_ss_rxcrdt.sv](ofs_fim_pcie_ss_rxcrdt.sv) manages credits between the HIP and the FIM for RX traffic. The module is used only with HIP variants that expose a credit interface instead of a simple tready wire on the RX stream.
* [ofs_fim_pcie_ss_rx_dual_stream.sv](ofs_fim_pcie_ss_rx_dual_stream.sv) splits the inbound RX stream into separate RX and RXREQ streams by TLP type.
* [ofs_fim_pcie_ss_rx_seg_align.sv](ofs_fim_pcie_ss_rx_seg_align.sv) transforms an incoming RX stream with headers in multiple segments into a stream with a single segment and at most one header per cycle.
* [ofs_fim_pcie_ss_sb2ib.sv](ofs_fim_pcie_ss_sb2ib.sv) maps a stream with side-band headers to the equivalent stream with in-band headers.
* [ofs_fim_pcie_ss_tx_merge.sv](ofs_fim_pcie_ss_tx_merge.sv) combines the outbound TX and TXREQ streams into a single stream. Depending on the HIP, the resulting stream may transmit portions of more than one packet in a single cycle.

Most of the modules share a single unit test wrapper named "pcie_ss_axis_components".