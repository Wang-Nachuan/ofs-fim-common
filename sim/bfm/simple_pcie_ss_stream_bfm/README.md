# BFM for PCIe SS AXI-S Edge Shims

The normal ofs_axis_bfm (not this BFM) attaches to the OFS pcie_wrapper above the lowest layer of OFS connections to the PCIe SS. The small BFM here generates and checks traffic that matches the AXI Streaming PCIe IP interface. It can be used to check shims that map platform-specific details of a PCIe SS configuration to the OFS pcie_wrapper.

The BFM is configurable and can generate random patterns of:

* Side-band headers
* In-band headers
* Multiple headers (NUM_OF_SEG > 1)

A corresponding checker consumes the same patterns. The generator and checker can be configured independently, so a side-band to in-band shim can be checked.

Unit tests should include the BFM by adding:

```
-F $OFS_ROOTDIR/ofs-common/sim/bfm/simple_pcie_ss_stream_bfm/filelist.txt
```

to TB_SRC within a test's set_params.sh script.

For example:

```bash
TB_SRC="-F $OFS_ROOTDIR/ofs-common/sim/bfm/simple_pcie_ss_stream_bfm/filelist.txt \
 $TEST_BASE_DIR/test.sv \
 $TEST_BASE_DIR/top_tb.sv"
```

Key classes within the BFM package:

* rand_tlp_stream generates random TLP packets and maps them to a data bus. The data width, number of segments where headers may start, side-band vs. in-band and the maximum number of headers per cycle are all configurable.
* bus_to_tlp reverses the mapping, generating a TLP packet from a data bus.
* The rand_tlp base class defines a TLP and includes a function to compare two packets.
