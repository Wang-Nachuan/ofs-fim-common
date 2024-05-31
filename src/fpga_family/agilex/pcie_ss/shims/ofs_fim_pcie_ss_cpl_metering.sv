// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Track outstanding host read requests, ensuring that total outstanding
// requests don't exceed the HIP's completion buffers. New read requests
// on axi_st_txreq_in and axi_st_rx_in block until buffer space is
// available.
//

module ofs_fim_pcie_ss_cpl_metering
  #(
    parameter SB_HEADERS = 1,
    parameter NUM_OF_SEG = 1,

    parameter TILE       = "P-TILE",
    parameter PORT_ID    = 0,
    parameter TAG_WIDTH  = 10,
    parameter MPS        = 512,
    parameter MRRS       = 4096,
    parameter RCB        = 64
    )
   (
    // Data in axi_st_txreq_in is unused. txreq is header only (read requests).
    pcie_ss_axis_if.sink axi_st_txreq_in,
    pcie_ss_axis_if.sink axi_st_tx_in,

    pcie_ss_axis_if.source axi_st_txreq_out,
    pcie_ss_axis_if.source axi_st_tx_out,

    input  logic csr_clk,
    input  logic csr_rst_n,

    input  logic ss_cplto_tvalid,
    input  logic [29:0] ss_cplto_tdata,

    input  logic cpl_hdr_valid,
    input  pcie_ss_hdr_pkg::PCIe_PUReqHdr_t cpl_hdr
    );

    // HIP completion buffer data entry size is the smallest allocation unit.
    // A single DWORD consumes this allocation unit. The documented completion
    // buffer space tables often miss this detail.
    function automatic int port_data_entry_bytes();
        if ((TILE == "P-TILE") || (TILE == "F-TILE")) begin
            if (PORT_ID <= 1)
                // Port 0 is 2x the size of port 1, but the entry size is the
                // same. Each port 0 buffer slot has 2 independent entries.
                return 16;
            else
                return 8;
        end else if (TILE == "R-TILE") begin
            if (PORT_ID <= 1)
                // Port 0 is 2x the size of port 1, but the entry size is the
                // same. Each port 0 buffer slot has 2 independent entries.
                return 32;
            else
                return 16;
        end else begin
            return -1;
        end
    endfunction // port_data_entry_size

    // Number of data entry slots in the HIP completion buffer.
    function automatic int port_num_data_entries();
        if ((TILE == "P-TILE") || (TILE == "F-TILE")) begin
            if (PORT_ID == 0)
                // 2 entries per 32 byte group. See the entry size
                // calculation in port_data_entry_bytes().
                return 1444 * 2;
            else
                return 1444;
        end else if (TILE == "R-TILE") begin
            if (PORT_ID == 0)
                // 2 entries per 64 byte group. See the entry size
                // calculation in port_data_entry_bytes().
                return 2016 * 2;
            else
                return 2016;
        end else begin
            return -1;
        end
    endfunction // port_num_data_entries

    function automatic int port_num_hdr_entries();
        if ((TILE == "P-TILE") || (TILE == "F-TILE")) begin
            if (PORT_ID == 0)
                return 1144;
            else if (PORT_ID == 1)
                return 572;
            else
                return 286;
        end else if (TILE == "R-TILE") begin
            if (PORT_ID == 0)
                return 1444;
            else if (PORT_ID == 1)
                return 1144;
            else
                return 572;
        end else begin
            return -1;
        end
    endfunction // port_num_hdr_entries

    // Tile/port-specific completion buffer entry size (bytes). This is the
    // minimum allocation unit.
    localparam ENTRY_SIZE = port_data_entry_bytes();
    localparam CPL_DATA_ENTRY_HIP = port_num_data_entries();
    localparam CPL_HDR_ENTRY_HIP  = port_num_hdr_entries();

    localparam MAX_HDR_ENTRY = MRRS/RCB + 1;
    localparam MAX_DATA_ENTRY = MRRS/ENTRY_SIZE + 1;

    // synthesis translate_off
    initial begin
        if (ENTRY_SIZE <= 0)
            $fatal(2, "Error %m: ENTRY_SIZE undefined for tile %0s port %0d", TILE, PORT_ID);
        if (CPL_DATA_ENTRY_HIP <= 0)
            $fatal(2, "Error %m: CPL_DATA_ENTRY_HIP undefined for tile %0s port %0d", TILE, PORT_ID);
        if (CPL_HDR_ENTRY_HIP <= 0)
            $fatal(2, "Error %m: CPL_HDR_ENTRY_HIP undefined for tile %0s port %0d", TILE, PORT_ID);
    end
    // synthesis translate_on

    wire clk = axi_st_tx_out.clk;
    wire rst_n = axi_st_tx_out.rst_n;

    ofs_fim_pcie_ss_shims_pkg::t_tuser_seg [NUM_OF_SEG-1:0] txreq_tuser;
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t txreq_hdr;
    assign txreq_tuser = axi_st_txreq_in.tuser_vendor;
    if (SB_HEADERS)
        assign txreq_hdr = txreq_tuser[0].hdr;
    else
        assign txreq_hdr = axi_st_txreq_in.tdata[$bits(txreq_hdr)-1:0];

    ofs_fim_pcie_ss_shims_pkg::t_tuser_seg [NUM_OF_SEG-1:0] tx_tuser;
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t tx_hdr;
    assign tx_tuser = axi_st_tx_in.tuser_vendor;
    if (SB_HEADERS)
        assign tx_hdr = tx_tuser[0];
    else
        assign tx_hdr = axi_st_tx_in.tdata[$bits(tx_hdr)-1:0];

    pcie_ss_axis_if
      #(
        .DATA_W($bits(axi_st_txreq_in.tdata)),
        .USER_W($bits(axi_st_txreq_in.tuser_vendor))
        )
      axi_txreq(clk, rst_n);

    pcie_ss_axis_if
      #(
        .DATA_W($bits(axi_st_tx_in.tdata)),
        .USER_W($bits(axi_st_tx_in.tuser_vendor))
        )
      axi_tx(clk, rst_n);

    function automatic logic [$clog2(MAX_HDR_ENTRY)-1:0] num_hdr_entries(
        input pcie_ss_hdr_pkg::PCIe_PUReqHdr_t hdr
        );
        logic non_rcbaligned = pcie_ss_hdr_pkg::func_is_addr64(hdr.fmt_type) ?
                                   |(hdr.host_addr_l[$clog2(RCB)-3:0]) :
                                   |(hdr.host_addr_h[$clog2(RCB)-1:2]);

        return hdr.length[9:$clog2(RCB)-2] +
               |(hdr.length[$clog2(RCB)-3:0]) +
               non_rcbaligned;
    endfunction

    function automatic logic [$clog2(MAX_DATA_ENTRY)-1:0] num_data_entries(
        input pcie_ss_hdr_pkg::PCIe_PUReqHdr_t hdr
        );
        logic non_rcbaligned = pcie_ss_hdr_pkg::func_is_addr64(hdr.fmt_type) ?
                                   |(hdr.host_addr_l[$clog2(RCB)-3:0]) :
                                   |(hdr.host_addr_h[$clog2(RCB)-1:2]);

        return hdr.length[9:$clog2(ENTRY_SIZE)-2] +
               |(hdr.length[$clog2(ENTRY_SIZE)-3:0]) +
               non_rcbaligned;
    endfunction

    logic rd_req_valid[2];
    logic [TAG_WIDTH-1:0] rd_req_tag[2];
    logic [$clog2(MAX_HDR_ENTRY)-1:0] rd_req_hdr_entries[2];
    logic [$clog2(MAX_DATA_ENTRY)-1:0] rd_req_data_entries[2];
    logic rd_req_grant[2];

    always_ff @(posedge clk) begin
        // Read request pending if a new one arrives or an
        // old one remains unprocessed.
        rd_req_valid[0] <= (axi_st_txreq_in.tready &&
                            axi_st_txreq_in.tvalid &&
                            txreq_tuser[0].hvalid &&
                            pcie_ss_hdr_pkg::func_is_mrd_req(txreq_hdr.fmt_type)) ||
                           (rd_req_valid[0] && !rd_req_grant[0]);

        if (axi_st_txreq_in.tready) begin
            axi_txreq.tvalid <= axi_st_txreq_in.tvalid;
            axi_txreq.tdata <= axi_st_txreq_in.tdata;
            axi_txreq.tkeep <= axi_st_txreq_in.tkeep;
            axi_txreq.tuser_vendor <= axi_st_txreq_in.tuser_vendor;
            axi_txreq.tlast <= axi_st_txreq_in.tlast;

            rd_req_tag[0] <= { txreq_hdr.tag_h, txreq_hdr.tag_m, txreq_hdr.tag_l };
            rd_req_hdr_entries[0] <= num_hdr_entries(txreq_hdr);
            rd_req_data_entries[0] <= num_data_entries(txreq_hdr);
        end

        if (!rst_n) begin
            axi_txreq.tvalid <= 1'b0;
            rd_req_valid[0] <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        // Similar logic to txreq above for requests with completions on tx.
        rd_req_valid[1] <= (axi_st_tx_in.tready &&
                            axi_st_tx_in.tvalid &&
                            tx_tuser[0].hvalid &&
                            (pcie_ss_hdr_pkg::func_is_mrd_req(tx_hdr.fmt_type) ||
                             pcie_ss_hdr_pkg::func_is_atomic_req(tx_hdr.fmt_type))) ||
                           (rd_req_valid[1] && !rd_req_grant[1]);

        if (axi_st_tx_in.tready) begin
            axi_tx.tvalid <= axi_st_tx_in.tvalid;
            axi_tx.tdata <= axi_st_tx_in.tdata;
            axi_tx.tkeep <= axi_st_tx_in.tkeep;
            axi_tx.tuser_vendor <= axi_st_tx_in.tuser_vendor;
            axi_tx.tlast <= axi_st_tx_in.tlast;

            rd_req_tag[1] <= { tx_hdr.tag_h, tx_hdr.tag_m, tx_hdr.tag_l };
            rd_req_hdr_entries[1] <= num_hdr_entries(tx_hdr);
            rd_req_data_entries[1] <= num_data_entries(tx_hdr);
        end

        if (!rst_n) begin
            axi_tx.tvalid <= 1'b0;
            rd_req_valid[1] <= 1'b0;
        end
    end

    assign axi_st_txreq_in.tready = axi_st_txreq_out.tready && (!rd_req_valid[0] || rd_req_grant[0]);
    assign axi_st_tx_in.tready = axi_st_tx_out.tready && (!rd_req_valid[1] || rd_req_grant[1]);

    assign axi_st_txreq_out.tvalid = axi_txreq.tvalid && (!rd_req_valid[0] || rd_req_grant[0]);
    assign axi_txreq.tready = axi_st_txreq_out.tready;
    assign axi_st_txreq_out.tdata = axi_txreq.tdata;
    assign axi_st_txreq_out.tkeep = axi_txreq.tkeep;
    assign axi_st_txreq_out.tuser_vendor = axi_txreq.tuser_vendor;
    assign axi_st_txreq_out.tlast = axi_txreq.tlast;

    assign axi_st_tx_out.tvalid = axi_tx.tvalid && (!rd_req_valid[1] || rd_req_grant[1]);
    assign axi_tx.tready = axi_st_tx_out.tready;
    assign axi_st_tx_out.tdata = axi_tx.tdata;
    assign axi_st_tx_out.tkeep = axi_tx.tkeep;
    assign axi_st_tx_out.tuser_vendor = axi_tx.tuser_vendor;
    assign axi_st_tx_out.tlast = axi_tx.tlast;

    ofs_fim_pcie_ss_cpl_metering_impl
      #(
        .ENTRY_SIZE(ENTRY_SIZE),
        .TAG_WIDTH(TAG_WIDTH),
        .CPL_HDR_ENTRY_HIP(CPL_HDR_ENTRY_HIP),
        .CPL_DATA_ENTRY_HIP(CPL_DATA_ENTRY_HIP),
        .MPS(MPS),
        .MRRS(MRRS),
        .RCB(RCB),
        .MAX_HDR_ENTRY(MAX_HDR_ENTRY),
        .MAX_DATA_ENTRY(MAX_DATA_ENTRY)
        )
      impl
       (
        .clk,
        .rst_n,
        .csr_clk,
        .csr_rst_n,

        .ss_cplto_tvalid,
        .ss_cplto_tdata,

        .cpl_hdr_valid,
        .cpl_hdr,

        .c2h_req_valid(rd_req_valid),
        .c2h_req_tag(rd_req_tag),
        .c2h_req_data_entries(rd_req_data_entries),
        .c2h_req_hdr_entries(rd_req_hdr_entries),
        .c2h_grant(rd_req_grant)
        );

endmodule // ofs_fim_pcie_ss_cpl_metering

module ofs_fim_pcie_ss_cpl_metering_impl
  #(
    parameter ENTRY_SIZE,
    parameter TAG_WIDTH,
    parameter CPL_HDR_ENTRY_HIP,
    parameter CPL_DATA_ENTRY_HIP,
    parameter MPS,
    parameter MRRS,
    parameter RCB,
    parameter MAX_HDR_ENTRY,
    parameter MAX_DATA_ENTRY
    )
   (
    input  logic clk,
    input  logic rst_n,

    input  logic csr_clk,
    input  logic csr_rst_n,

    input  logic ss_cplto_tvalid,
    input  logic [29:0] ss_cplto_tdata,

    input  logic cpl_hdr_valid,
    input  logic [255:0] cpl_hdr,

    input  logic c2h_req_valid[2],
    input  logic [TAG_WIDTH-1: 0] c2h_req_tag[2],
    input  logic [$clog2(MAX_DATA_ENTRY)-1:0] c2h_req_data_entries[2],
    input  logic [$clog2(MAX_HDR_ENTRY)-1:0] c2h_req_hdr_entries[2],
    output logic c2h_grant[2]
    );

    localparam MAX_CPL_DATA_ENTRY = MPS/ENTRY_SIZE;

    // CPL_HDR_ENTRY and CPL_DATA_ENTRY would normally just be equal
    // to the HIP values. A simplifcation is made for timing. See
    // the comment below that begins "For timing, the grant calculation".
    localparam CPL_HDR_ENTRY      = CPL_HDR_ENTRY_HIP + MAX_HDR_ENTRY;
    localparam CPL_DATA_ENTRY     = CPL_DATA_ENTRY_HIP + MAX_DATA_ENTRY;

    logic [29:0] st_cplto_tdata_sync;
    logic        st_cplto_tvalid_sync;
    logic [1:0]           cplto;
    logic [TAG_WIDTH-1:0] cplto_tag;

    logic [$clog2(CPL_DATA_ENTRY)-1:0] data_entry_count;
    logic [$clog2(CPL_HDR_ENTRY)-1:0]  hdr_entry_count;

    logic [$clog2(CPL_DATA_ENTRY)-1:0] data_entry_count_no_decr;
    logic [$clog2(CPL_HDR_ENTRY)-1:0]  hdr_entry_count_no_decr;
    logic [$clog2(CPL_DATA_ENTRY)-1:0] data_entry_count_decr_req[2];
    logic [$clog2(CPL_HDR_ENTRY)-1:0]  hdr_entry_count_decr_req[2];

    logic [$clog2(CPL_DATA_ENTRY)-1:0] data_entry_count_incr_pending;
    logic [$clog2(CPL_HDR_ENTRY)-1:0]  hdr_entry_count_incr_pending;
    logic [$clog2(MAX_DATA_ENTRY)-1:0] data_entry_count_incr;
    logic [$clog2(MAX_DATA_ENTRY)-1:0] data_entry_count_incr0;
    logic [$clog2(MAX_DATA_ENTRY)-1:0] data_entry_count_incr1;
    logic [$clog2(MAX_HDR_ENTRY)-1:0]  hdr_entry_count_incr;
    logic [$clog2(MAX_HDR_ENTRY)-1:0]  hdr_entry_count_incr0;
    logic [$clog2(MAX_HDR_ENTRY)-1:0]  hdr_entry_count_incr1;

    logic wren_a;
    logic wren_b;
    logic rden_a;
    logic rden_b;
    logic [TAG_WIDTH-1:0] waddr_a;
    logic [TAG_WIDTH-1:0] waddr_b;
    logic [TAG_WIDTH-1:0] raddr_a;
    logic [TAG_WIDTH-1:0] raddr_b;

    logic [$clog2(MAX_HDR_ENTRY)+$clog2(MAX_DATA_ENTRY)-1:0] wdata_a;
    logic [$clog2(MAX_HDR_ENTRY)+$clog2(MAX_DATA_ENTRY)-1:0] wdata_b;
    logic [$clog2(MAX_HDR_ENTRY)+$clog2(MAX_DATA_ENTRY)-1:0] prev_wdata_b;
    logic [$clog2(MAX_HDR_ENTRY)+$clog2(MAX_DATA_ENTRY)-1:0] rdata_a;
    logic [$clog2(MAX_HDR_ENTRY)+$clog2(MAX_DATA_ENTRY)-1:0] rdata_b;

    logic [10-1:0]                       cpl_hdr_tag;
    logic [12:0]                         cpl_byte_cnt;
    logic [10:0]                         cpl_length;
    logic [1:0]                          cpl_lower_addr;
    logic [$clog2(MPS):0]                cpl_actual_byte_cnt;
    logic                                cpl_success;
    logic [$clog2(MAX_CPL_DATA_ENTRY):0] cpl_data_entry_return;

    logic [1:0]           cpl_valid;
    logic [1:0]           last_cpl;
    logic [$clog2(MAX_CPL_DATA_ENTRY):0] cpl_data_entry_return_d[1:0];
    logic [TAG_WIDTH-1:0] cpl_tag;
    logic [TAG_WIDTH-1:0] cpl_tag_d[1:0];
    logic                 cpl_tag_valid_d[1:0];

    logic [TAG_WIDTH-1:0] prev_cpl_tag;
    logic                 prev_cpl_tag_valid;


    logic arb_prev_winner;
    logic c2h_req_arb_valid[2];

    assign c2h_req_arb_valid[0] = c2h_req_valid[0] && (arb_prev_winner || !c2h_req_valid[1]);
    assign c2h_req_arb_valid[1] = c2h_req_valid[1] && (!arb_prev_winner || !c2h_req_valid[0]);

    //
    // For timing, the grant calculation simplifies the counters. A normal calculation
    // would check that either the entry count is larger than the max. request size or that
    // the actual request size is smaller than the number of available slots. For example:
    //
    //   assign c2h_grant[1] = c2h_req_arb_valid[1] & ((|data_entry_count[$clog2(CPL_DATA_ENTRY)-1:$clog2(MAX_DATA_ENTRY)]) | data_entry_count[$clog2(MAX_DATA_ENTRY)-1:0]>=c2h_req_data_entries[1]) &
    //                         ((|hdr_entry_count[$clog2(CPL_HDR_ENTRY)-1:$clog2(MAX_HDR_ENTRY)]) | hdr_entry_count[$clog2(MAX_HDR_ENTRY)-1:0]>=c2h_req_hdr_entries[1]);
    //
    // Instead we add MAX_HDR_ENTRY and MAX_DATA_ENTRY to CPL_HDR_ENTRY and CPL_DATA_ENTRY,
    // which oversubscribes the buffers. The check comparing against the actual request size,
    // which requires addition, becomes unnecessary. With the max. request size added, we
    // no longer need to check the low bits for buffer space.
    //
    // The FIM provides at least as much receive buffering as this oversubscription.
    // In addition, the FIM instantiates this metering on the FIM side of clock
    // crossing buffers. Fewer requests are in flight inside the HIP than the metering
    // calculation computes.
    //

    wire hip_cpl_buffer_avail = |data_entry_count[$clog2(CPL_DATA_ENTRY)-1:$clog2(MAX_DATA_ENTRY)] &
                                |hdr_entry_count[$clog2(CPL_HDR_ENTRY)-1:$clog2(MAX_HDR_ENTRY)];
    // The A and B logical write ports share the same RAM port. Only use
    // A when B is not busy.
    assign c2h_grant[0] = c2h_req_arb_valid[0] & hip_cpl_buffer_avail & !wren_b;
    assign c2h_grant[1] = c2h_req_arb_valid[1] & hip_cpl_buffer_avail & !wren_b;

    always_ff @(posedge clk) begin
        if (c2h_grant[0])
            arb_prev_winner <= 1'b0;
        if (c2h_grant[1])
            arb_prev_winner <= 1'b1;

        if (!rst_n)
            arb_prev_winner <= 1'b0;
    end

    // Write request will be written to a register when merging the A
    // and B requests into a single RAM port.
    always_comb begin
        unique case (1'b1)
          c2h_grant[0]: begin
            waddr_a = c2h_req_tag[0];
            wren_a  = 1'b1;
            wdata_a = {c2h_req_hdr_entries[0], c2h_req_data_entries[0]};
            end
          c2h_grant[1]: begin
            waddr_a = c2h_req_tag[1];
            wren_a  = 1'b1;
            wdata_a = {c2h_req_hdr_entries[1], c2h_req_data_entries[1]};
            end
          default: begin
            waddr_a = 0;
            wren_a  = 0;
            wdata_a = 0;
            end
        endcase // unique case (1'b1)
    end 

    pciess_vecsync_handshake
      #(
        .DWIDTH(30)
        )
      u_hia_dm_st_cplto_sync
       (
        .wr_clk(csr_clk),
        .wr_rst_n(csr_rst_n),
        .rd_clk(clk),
        .rd_rst_n(rst_n),
        .data_in(ss_cplto_tdata),
        .load_data_in(ss_cplto_tvalid),
        .data_in_rdy2ld(),
        .data_out(st_cplto_tdata_sync),
        .data_out_vld(st_cplto_tvalid_sync),
        .ack_data_out(1'b1)
        );

    assign cplto_tag = st_cplto_tdata_sync[10-1:0];

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            cplto   <= 0;
            raddr_a <= 0;
            rden_a  <= 0;
        end
        else begin
            cplto <= st_cplto_tvalid_sync ? {cplto[0],1'b1} : {cplto[0],1'b0};

            if (st_cplto_tvalid_sync) begin
                raddr_a <= cplto_tag;
                rden_a  <= 1'b1;
            end
            else begin
                raddr_a <= 0;
                rden_a  <= 0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            data_entry_count_incr1 <= 0;
            hdr_entry_count_incr1  <= 0;
        end
        else begin
            data_entry_count_incr1 <= cplto[1] ? rdata_a[$clog2(MAX_DATA_ENTRY)-1:0] : 0;
            hdr_entry_count_incr1  <= cplto[1] ? rdata_a[$clog2(MAX_DATA_ENTRY)+:$clog2(MAX_HDR_ENTRY)] : 0;
        end
    end

    assign cpl_hdr_tag        = cpl_hdr_valid ? {cpl_hdr[23], cpl_hdr[19], cpl_hdr[79:72]} : 0;
    assign cpl_byte_cnt[11:0] = cpl_hdr_valid ? cpl_hdr[43:32] : 12'h0;
    assign cpl_byte_cnt[12]   = (cpl_hdr_valid & cpl_hdr[43:32]==0) ? 1 : 0;
    assign cpl_length[9:0]    = cpl_hdr_valid ? cpl_hdr[9:0] : 10'h0;
    assign cpl_length[10]     = (cpl_hdr_valid & cpl_hdr[9:0]==0) ? 1 : 0;
    assign cpl_lower_addr     = cpl_hdr_valid ? cpl_hdr[65:64] : 2'b00;
    assign cpl_success        = cpl_hdr_valid ? cpl_hdr[47:45]==3'b000 : 0;

    assign cpl_actual_byte_cnt   = cpl_hdr_valid ? ({cpl_length[$clog2(MPS)-2:0],2'b00}-cpl_lower_addr) : '0;
    assign cpl_data_entry_return = cpl_actual_byte_cnt[$clog2(MPS):$clog2(ENTRY_SIZE)] + |cpl_actual_byte_cnt[$clog2(ENTRY_SIZE)-1:0];

    assign cpl_tag = cpl_hdr_tag;

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            cpl_valid <= 0;
            last_cpl <= 0;
            raddr_b <= 0;
            rden_b <= 0;
            for (int i=0; i<2; i++)
              cpl_data_entry_return_d[i] <= 0;
        end
        else begin
            if (cpl_hdr_valid) begin
                cpl_valid <= {cpl_valid[0],1'b1};
                last_cpl <= {last_cpl[0],(cpl_byte_cnt<={cpl_length,2'b00} | ~cpl_success)};
                cpl_data_entry_return_d <= {cpl_data_entry_return_d[0],cpl_data_entry_return};
                raddr_b <= cpl_tag;
                rden_b <= 1'b1;
            end
            else begin
                cpl_valid <= {cpl_valid[0],1'b0};
                last_cpl <= {last_cpl[0],1'b0};
                cpl_data_entry_return_d <= {cpl_data_entry_return_d[0],{($clog2(MAX_CPL_DATA_ENTRY)+1){1'b0}}};
                raddr_b <= 0;
                rden_b <= 0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            for (int i=0; i<2; i++) begin
                cpl_tag_d[i] <= 0;
                cpl_tag_valid_d[i] <= 0;
            end
            prev_cpl_tag <= 0;
            prev_cpl_tag_valid <= 0;
        end
        else begin
            cpl_tag_d <= {cpl_tag_d[0],cpl_tag};
            cpl_tag_valid_d <= {cpl_tag_valid_d[0],cpl_hdr_valid};
            prev_cpl_tag <= cpl_tag_d[1];
            prev_cpl_tag_valid <= cpl_tag_valid_d[1];
        end
    end

    always_comb begin
        wren_b = cpl_valid[1] & !last_cpl[1];
        waddr_b = cpl_tag_d[1];
        wdata_b = (cpl_tag_d[1]==prev_cpl_tag & prev_cpl_tag_valid) ? {(prev_wdata_b[$clog2(MAX_DATA_ENTRY)+:$clog2(MAX_HDR_ENTRY)] - 1'b1), (prev_wdata_b[$clog2(MAX_DATA_ENTRY)-1:0] - cpl_data_entry_return_d[1])} : 
                  {(rdata_b[$clog2(MAX_DATA_ENTRY)+:$clog2(MAX_HDR_ENTRY)] - 1'b1), (rdata_b[$clog2(MAX_DATA_ENTRY)-1:0] - cpl_data_entry_return_d[1])};
    end

    always_ff @(posedge clk) begin
        prev_wdata_b <= wdata_b;
    end

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            data_entry_count_incr0 <= 0;
            hdr_entry_count_incr0 <= 0;
        end
        else begin
            if (cpl_valid[1]) begin
                if (last_cpl[1]) begin
                    data_entry_count_incr0 <= (cpl_tag_d[1]==prev_cpl_tag & prev_cpl_tag_valid) ? prev_wdata_b[$clog2(MAX_DATA_ENTRY)-1:0] : rdata_b[$clog2(MAX_DATA_ENTRY)-1:0];
                    hdr_entry_count_incr0 <= (cpl_tag_d[1]==prev_cpl_tag & prev_cpl_tag_valid) ? prev_wdata_b[$clog2(MAX_DATA_ENTRY)+:$clog2(MAX_HDR_ENTRY)] : rdata_b[$clog2(MAX_DATA_ENTRY)+:$clog2(MAX_HDR_ENTRY)];
                end
                else begin
                    data_entry_count_incr0 <= cpl_data_entry_return_d[1];
                    hdr_entry_count_incr0 <= 1'b1;
                end
            end
            else begin
                data_entry_count_incr0 <= 0;
                hdr_entry_count_incr0 <= 0;
            end
        end
    end

    // Track credit increments from arriving completions. Unlike decrements
    // from new requests, credit increments can be delayed. The only cost
    // is the possibility of requests being held back.
    always_ff @(posedge clk) begin
        // New credit arriving this cycle
        data_entry_count_incr <= data_entry_count_incr0 + data_entry_count_incr1;
        hdr_entry_count_incr <= hdr_entry_count_incr0 + hdr_entry_count_incr1;

        // Updating data_entry_count and hdr_entry_count requires
        // two additions: one to subtract credit consumed by requests
        // and one to add credit returned by completions. A pair of
        // additions in a single cycle would put the update on the
        // critical path. Instead, we delay increments until a cycle
        // when there are no new requests. In theory this might delay
        // issuing new read requests. In practice, grants are much
        // less frequent than every cycle. Long read request rates
        // are limited by completions. The system bandwidth of short
        // reads is less than the available bus bandwidth.
        if (c2h_grant[0] || c2h_grant[1]) begin
            // New request issued this cycle. Tracking incoming increment
            // credits until they can be added to the main counters.
            data_entry_count_incr_pending <= data_entry_count_incr_pending + data_entry_count_incr;
            hdr_entry_count_incr_pending <= hdr_entry_count_incr_pending + hdr_entry_count_incr;
        end
        else begin
            // Pending increments were applied to the main counters.
            // Only note new incoming updates.
            data_entry_count_incr_pending <= data_entry_count_incr;
            hdr_entry_count_incr_pending <= hdr_entry_count_incr;
        end
    end

    // Only one of the groups of updates will be applied per cycle.
    always_comb begin
        data_entry_count_no_decr = data_entry_count + data_entry_count_incr_pending;
        hdr_entry_count_no_decr  = hdr_entry_count + hdr_entry_count_incr_pending;

        data_entry_count_decr_req[0] = data_entry_count - c2h_req_data_entries[0];
        hdr_entry_count_decr_req[0]  = hdr_entry_count - c2h_req_hdr_entries[0];

        data_entry_count_decr_req[1] = data_entry_count - c2h_req_data_entries[1];
        hdr_entry_count_decr_req[1]  = hdr_entry_count - c2h_req_hdr_entries[1];
    end 

    always_ff @(posedge clk) begin
        unique case (1'b1)
          c2h_grant[0]: begin
            data_entry_count <= data_entry_count_decr_req[0];
            hdr_entry_count <= hdr_entry_count_decr_req[0];
            end
          c2h_grant[1]: begin
            data_entry_count <= data_entry_count_decr_req[1];
            hdr_entry_count <= hdr_entry_count_decr_req[1];
            end
          default: begin
            data_entry_count <= data_entry_count_no_decr;
            hdr_entry_count <= hdr_entry_count_no_decr;
            end
        endcase // unique case (1'b1)

        if (~rst_n) begin
            data_entry_count <= CPL_DATA_ENTRY;
            hdr_entry_count <= CPL_HDR_ENTRY;
        end
    end

    localparam RAM_DATA_WIDTH = $clog2(MAX_HDR_ENTRY)+$clog2(MAX_DATA_ENTRY);

    logic wren;
    logic [TAG_WIDTH-1:0] waddr;
    logic [RAM_DATA_WIDTH-1:0] wdata;

    // synthesis translate_off
    always_ff @(negedge clk) begin
        // Arbitration above must prevent attempted writes to both A and B
        assert (~wren_a | ~wren_b | ~rst_n) else
            $fatal(2, "Error %m: RAM write arbitration failure!");
    end
    // synthesis translate_on

    always_ff @(posedge clk) begin
        wren <= wren_a | wren_b;
        if (wren_b) begin
            waddr <= waddr_b;
            wdata <= wdata_b;
        end else begin
            waddr <= waddr_a;
            wdata <= wdata_a;
        end
    end

    fim_ram_1r1w
      #(
        .WIDTH(RAM_DATA_WIDTH),
        .DEPTH(TAG_WIDTH),
        .GRAM_MODE(1)
        )
      u_hdr_data_alloc_mem_a
       (
        .clk,
        .perr(),

        .we(wren),
        .waddr(waddr),
        .din(wdata),

        .re(rden_a),
        .raddr(raddr_a),
        .dout(rdata_a)
        );


    // Make RAM-B return new data for simultaneous read/write to the same
    // address by monitoring the read/write traffic here.
    logic [RAM_DATA_WIDTH-1 : 0] wdata_reg;
    logic [RAM_DATA_WIDTH-1 : 0] rdata_ram_b;
    logic rd_during_write_b;

    fim_ram_1r1w
      #(
        .WIDTH(RAM_DATA_WIDTH),
        .DEPTH(TAG_WIDTH),
        .GRAM_MODE(1)
        )
      u_hdr_data_alloc_mem_b
       (
        .clk,
        .perr(),

        .we(wren),
        .waddr(waddr),
        .din(wdata),

        .re(rden_b),
        .raddr(raddr_b),
        .dout(rdata_ram_b)
        );

    assign rdata_b = rd_during_write_b ? wdata_reg : rdata_ram_b;

    always_ff @(posedge clk) begin
        rd_during_write_b <= wren & rden_b & (waddr == raddr_b);

        if (wren)
            wdata_reg <= wdata;
    end

endmodule // ofs_fim_pcie_ss_cpl_metering_impl
