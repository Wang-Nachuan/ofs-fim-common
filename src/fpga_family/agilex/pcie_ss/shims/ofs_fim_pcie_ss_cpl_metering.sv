// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

module ofs_fim_pcie_ss_cpl_metering
  #(
    parameter SB_HEADERS = 1,
    parameter NUM_OF_SEG = 1,

    parameter TILE            = "P-TILE",
    parameter PORT_ID         = 0,
    parameter ENTRY_SIZE      = PORT_ID==0 ? (TILE=="R-TILE" ? 32 : 16) : (PORT_ID==1 ? (TILE=="R-TILE" ? 32 : 16) : (TILE=="R-TILE" ? 16 : 8)),
    parameter TAG_WIDTH       = 10,
    parameter MPS             = 512,
    parameter MRRS            = 4096,
    parameter RCB             = 64,
    parameter MAX_HDR_ENTRY   = MRRS/RCB + 1,
    parameter MAX_DATA_ENTRY  = MRRS/ENTRY_SIZE + 1
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

    wire clk = axi_st_tx_out.clk;
    wire rst_n = axi_st_tx_out.rst_n;

    ofs_fim_pcie_ss_shims_pkg::t_tuser_seg [NUM_OF_SEG-1:0] txreq_tuser;
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t txreq_hdr;
    assign txreq_tuser = axi_st_txreq_in.tuser_vendor;
    assign txreq_hdr = SB_HEADERS ? txreq_tuser[0] : axi_st_txreq_in.tdata[$bits(txreq_hdr)-1:0];

    ofs_fim_pcie_ss_shims_pkg::t_tuser_seg [NUM_OF_SEG-1:0] tx_tuser;
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t tx_hdr;
    assign tx_tuser = axi_st_tx_in.tuser_vendor;
    assign tx_hdr = SB_HEADERS ? tx_tuser[0] : axi_st_tx_in.tdata[$bits(tx_hdr)-1:0];

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
        // Completion slot granted? Clear the is_rd flag even if the request
        // can't be forwarded yet since the buffer credit has been allocated.
        if (rd_req_grant[0])
            rd_req_valid[0] <= 1'b0;

        if (axi_st_txreq_in.tready) begin
            axi_txreq.tvalid <= axi_st_txreq_in.tvalid;
            axi_txreq.tdata <= axi_st_txreq_in.tdata;
            axi_txreq.tkeep <= axi_st_txreq_in.tkeep;
            axi_txreq.tuser_vendor <= axi_st_txreq_in.tuser_vendor;
            axi_txreq.tlast <= axi_st_txreq_in.tlast;

            rd_req_valid[0] <= axi_st_txreq_in.tvalid &&
                               txreq_tuser[0].hvalid &&
                               pcie_ss_hdr_pkg::func_is_mrd_req(txreq_hdr.fmt_type);
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
        // Completion slot granted? Clear the is_rd flag even if the request
        // can't be forwarded yet since the buffer credit has been allocated.
        if (rd_req_grant[1])
            rd_req_valid[1] <= 1'b0;

        if (axi_st_tx_in.tready) begin
            axi_tx.tvalid <= axi_st_tx_in.tvalid;
            axi_tx.tdata <= axi_st_tx_in.tdata;
            axi_tx.tkeep <= axi_st_tx_in.tkeep;
            axi_tx.tuser_vendor <= axi_st_tx_in.tuser_vendor;
            axi_tx.tlast <= axi_st_tx_in.tlast;

            rd_req_valid[1] <= axi_st_tx_in.tvalid &&
                               tx_tuser[0].hvalid &&
                               (pcie_ss_hdr_pkg::func_is_mrd_req(tx_hdr.fmt_type) ||
                                pcie_ss_hdr_pkg::func_is_atomic_req(tx_hdr.fmt_type));
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
        .TILE(TILE),
        .PORT_ID(PORT_ID)
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
    parameter TILE            = "P-TILE",
    parameter PORT_ID         = 0,
    parameter ENTRY_SIZE      = PORT_ID==0 ? (TILE=="R-TILE" ? 32 : 16) : (PORT_ID==1 ? (TILE=="R-TILE" ? 32 : 16) : (TILE=="R-TILE" ? 16 : 8)),
    parameter TAG_WIDTH       = 10,
    parameter MPS             = 512,
    parameter MRRS            = 4096,
    parameter RCB             = 64,
    parameter MAX_HDR_ENTRY   = MRRS/RCB + 1,
    parameter MAX_DATA_ENTRY  = MRRS/ENTRY_SIZE + 1
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

    localparam CPL_HDR_ENTRY_P_F  = PORT_ID==0 ? 1144 : (PORT_ID==1 ? 572 : 286);
    localparam CPL_HDR_ENTRY_R    = PORT_ID==0 ? 1444 : (PORT_ID==1 ? 1144 : 572);
    localparam CPL_HDR_ENTRY      = (TILE=="R-TILE") ? CPL_HDR_ENTRY_R : CPL_HDR_ENTRY_P_F;
    localparam CPL_DATA_ENTRY     = PORT_ID==0 ? (TILE=="R-TILE" ? 2016*2 : 1444*2) : (TILE=="R-TILE" ? 2016 : 1444);

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

    assign c2h_grant[0] = c2h_req_arb_valid[0] & ((|data_entry_count[$clog2(CPL_DATA_ENTRY)-1:$clog2(MAX_DATA_ENTRY)]) | data_entry_count[$clog2(MAX_DATA_ENTRY)-1:0]>=c2h_req_data_entries[0]) &
                          ((|hdr_entry_count[$clog2(CPL_HDR_ENTRY)-1:$clog2(MAX_HDR_ENTRY)]) | hdr_entry_count[$clog2(MAX_HDR_ENTRY)-1:0]>=c2h_req_hdr_entries[0]);
    assign c2h_grant[1] = c2h_req_arb_valid[1] & ((|data_entry_count[$clog2(CPL_DATA_ENTRY)-1:$clog2(MAX_DATA_ENTRY)]) | data_entry_count[$clog2(MAX_DATA_ENTRY)-1:0]>=c2h_req_data_entries[1]) &
                          ((|hdr_entry_count[$clog2(CPL_HDR_ENTRY)-1:$clog2(MAX_HDR_ENTRY)]) | hdr_entry_count[$clog2(MAX_HDR_ENTRY)-1:0]>=c2h_req_hdr_entries[1]);

    always_ff @(posedge clk) begin
        if (c2h_grant[0])
            arb_prev_winner <= 1'b0;
        if (c2h_grant[1])
            arb_prev_winner <= 1'b1;

        if (!rst_n)
            arb_prev_winner <= 1'b0;
    end

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            waddr_a  <= 0;
            wren_a   <= 0;
            wdata_a  <= 0;
        end
        else begin
            unique case (1'b1)
              c2h_grant[0]: begin
                waddr_a <= c2h_req_tag[0];
                wren_a  <= 1'b1;
                wdata_a <= {c2h_req_hdr_entries[0], c2h_req_data_entries[0]};
                end
              c2h_grant[1]: begin
                waddr_a <= c2h_req_tag[1];
                wren_a  <= 1'b1;
                wdata_a <= {c2h_req_hdr_entries[1], c2h_req_data_entries[1]};
                end
              default: begin
                waddr_a <= 0;
                wren_a  <= 0;
                wdata_a <= 0;
                end
            endcase // unique case (1'b1)
        end
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

    assign cpl_actual_byte_cnt   = cpl_hdr_valid ? ({cpl_length[$clog2(MPS)-2:0],2'b00}-cpl_lower_addr) : 0;
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

    always_ff @(posedge clk) begin
        if (~rst_n) begin
            waddr_b <= 0;
            wren_b <= 0;
            wdata_b <= 0;
            data_entry_count_incr0 <= 0;
            hdr_entry_count_incr0 <= 0;
        end
        else begin
            if (cpl_valid[1]) begin
                waddr_b <= cpl_tag_d[1];
                wren_b <= 1'b1;
                if (last_cpl[1]) begin
                    wdata_b <= 0;
                    data_entry_count_incr0 <= (cpl_tag_d[1]==prev_cpl_tag & prev_cpl_tag_valid) ? wdata_b[$clog2(MAX_DATA_ENTRY)-1:0] : rdata_b[$clog2(MAX_DATA_ENTRY)-1:0];
                    hdr_entry_count_incr0 <= (cpl_tag_d[1]==prev_cpl_tag & prev_cpl_tag_valid) ? wdata_b[$clog2(MAX_DATA_ENTRY)+:$clog2(MAX_HDR_ENTRY)] : rdata_b[$clog2(MAX_DATA_ENTRY)+:$clog2(MAX_HDR_ENTRY)];
                end
                else begin
                    wdata_b <= (cpl_tag_d[1]==prev_cpl_tag & prev_cpl_tag_valid) ? {(wdata_b[$clog2(MAX_DATA_ENTRY)+:$clog2(MAX_HDR_ENTRY)] - 1'b1), (wdata_b[$clog2(MAX_DATA_ENTRY)-1:0] - cpl_data_entry_return_d[1])} : 
                               {(rdata_b[$clog2(MAX_DATA_ENTRY)+:$clog2(MAX_HDR_ENTRY)] - 1'b1), (rdata_b[$clog2(MAX_DATA_ENTRY)-1:0] - cpl_data_entry_return_d[1])};

                    data_entry_count_incr0 <= cpl_data_entry_return_d[1];
                    hdr_entry_count_incr0 <= 1'b1;
                end
            end
            else begin
                waddr_b <= 0;
                wren_b <= 0;
                wdata_b <= 0;
                data_entry_count_incr0 <= 0;
                hdr_entry_count_incr0 <= 0;
            end
        end
    end

    always_ff @(posedge clk) begin
        data_entry_count_incr <= data_entry_count_incr0 + data_entry_count_incr1;
        hdr_entry_count_incr <= hdr_entry_count_incr0 + hdr_entry_count_incr1;
    end

    always_comb begin
        data_entry_count_no_decr = data_entry_count + data_entry_count_incr;
        hdr_entry_count_no_decr  = hdr_entry_count + hdr_entry_count_incr;

        data_entry_count_decr_req[0] = data_entry_count - c2h_req_data_entries[0] + data_entry_count_incr;
        hdr_entry_count_decr_req[0]  = hdr_entry_count - c2h_req_hdr_entries[0] + hdr_entry_count_incr;

        data_entry_count_decr_req[1] = data_entry_count - c2h_req_data_entries[1] + data_entry_count_incr;
        hdr_entry_count_decr_req[1]  = hdr_entry_count - c2h_req_hdr_entries[1] + hdr_entry_count_incr;
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

    fim_ram_2r2w
      #(
        .DWIDTH($clog2(MAX_HDR_ENTRY)+$clog2(MAX_DATA_ENTRY)),
        .AWIDTH(TAG_WIDTH),
        .READ_DURING_WRITE("NEW_DATA_B")
        )
      u_hdr_data_alloc_mem
       (
        .clk,
        .reset_n(rst_n),
        .*
        );

endmodule // ofs_fim_pcie_ss_cpl_metering_impl
