// Copyright (C) 2024 Intel Corporation.
// SPDX-License-Identifier: MIT

//
// Merge a pair of PCIe TLP streams into a single TX stream for the PCIe SS AXI-S.
//
// tuser fields should be encoded using ofs_fim_pcie_ss_shims_pkg::t_tuser_seg.
//

module ofs_fim_pcie_ss_tx_merge
  #(
    parameter NUM_OF_SEG = 1
    )
   (
    // Data in axi_st_txreq_in is unused. txreq is header only (read requests).
    pcie_ss_axis_if.sink axi_st_txreq_in,
    pcie_ss_axis_if.sink axi_st_tx_in,

    pcie_ss_axis_if.source axi_st_tx_out
    );

    wire clk = axi_st_tx_out.clk;
    wire rst_n = axi_st_tx_out.rst_n;

    localparam TDATA_WIDTH = $bits(axi_st_tx_in.tdata);
    localparam TKEEP_WIDTH = TDATA_WIDTH / 8;
    localparam TUSER_WIDTH = $bits(axi_st_tx_in.tuser_vendor);

    // tdata, tkeep and tuser_vendor segments
    localparam TDATA_SEG_WIDTH = TDATA_WIDTH / NUM_OF_SEG;
    localparam TKEEP_SEG_WIDTH = TKEEP_WIDTH / NUM_OF_SEG;
    localparam TUSER_SEG_WIDTH = TUSER_WIDTH / NUM_OF_SEG;

    // synthesis translate_off
    initial
    begin : error_proc
        if (TUSER_SEG_WIDTH != $bits(ofs_fim_pcie_ss_shims_pkg::t_tuser_seg))
            $fatal(2, "** ERROR ** %m: TUSER must be of type ofs_fim_pcie_ss_shims_pkg::t_tuser_seg");
    end
    // synthesis translate_on

    pcie_ss_axis_if#(.DATA_W(TDATA_WIDTH), .USER_W(TUSER_WIDTH)) tx_out(clk, rst_n);

    typedef logic [NUM_OF_SEG-1:0][TDATA_SEG_WIDTH-1:0] t_seg_tdata;
    typedef logic [NUM_OF_SEG-1:0][TKEEP_SEG_WIDTH-1:0] t_seg_tkeep;
    typedef ofs_fim_pcie_ss_shims_pkg::t_tuser_seg [NUM_OF_SEG-1:0] t_seg_tuser;

    wire t_seg_tdata tx_in_tdata = axi_st_tx_in.tdata;
    wire t_seg_tkeep tx_in_tkeep = axi_st_tx_in.tkeep;
    wire t_seg_tuser tx_in_tuser = axi_st_tx_in.tuser_vendor;

    wire t_seg_tdata txreq_in_tdata = axi_st_txreq_in.tdata;
    wire t_seg_tkeep txreq_in_tkeep = axi_st_txreq_in.tkeep;
    wire t_seg_tuser txreq_in_tuser = axi_st_txreq_in.tuser_vendor;


    // Registers holding the previous state from TX in case only part
    // of the request was transmitted. Segment 0 must already have been
    // forwarded, so start at 1.
    logic [NUM_OF_SEG-1:1][TDATA_SEG_WIDTH-1:0] tx_prev_tdata;
    logic [NUM_OF_SEG-1:1][TKEEP_SEG_WIDTH-1:0] tx_prev_tkeep;
    ofs_fim_pcie_ss_shims_pkg::t_tuser_seg [NUM_OF_SEG-1:1] tx_prev_tuser;
    logic tx_prev_tlast;
    logic tx_prev_tvalid;
    // Index of the first segment that still hasn't been forwarded
    logic [$clog2(NUM_OF_SEG)-1:0] tx_prev_idx;


    // Incoming segments will be picked from 3 possible locations: txreq,
    // tx and the tx_prev register. Tx_prev holds the remainder of an
    // incompletely forwarded tx from the previous cycle.
    typedef enum logic [1:0] {
        LOC_TXREQ = 0,
        LOC_TX = 1,
        LOC_TX_PREV = 2,
        LOC_NONE = 3
    } e_input_loc;

    // Input location and segment index
    typedef struct packed {
        e_input_loc loc;
        logic [$clog2(NUM_OF_SEG)-1:0] idx;
    } t_input_seg;

    // Vector holding mapping of input sources to the merged output segments
    t_input_seg input_seg[NUM_OF_SEG];

    // Arbitration. Was previous request from txreq?
    logic prev_was_txreq, txreq_was_last;
    t_input_seg next_src;
    logic picked_txreq;
    logic picked_tx;

    // Construct this cycle's mapping of inputs to the merged output stream.
    always_comb begin
        picked_txreq = 1'b0;
        picked_tx = 1'b0;
        txreq_was_last = 1'b0;

        if (tx_prev_tvalid) begin
            // Continue unfinished TX
            next_src.loc = LOC_TX_PREV;
            next_src.idx = tx_prev_idx;
        end
        else if (!tx_prev_tlast || (axi_st_tx_in.tvalid && (prev_was_txreq || !axi_st_txreq_in.tvalid))) begin
            // Pick remainder of a TX or new TX if arbitration currently favors it
            next_src.loc = LOC_TX;
            next_src.idx = 0;
        end
        else if (axi_st_txreq_in.tvalid) begin
            next_src.loc = LOC_TXREQ;
            next_src.idx = 0;
        end
        else begin
            next_src.loc = LOC_NONE;
            next_src.idx = 0;
        end

        for (int i = 0; i < NUM_OF_SEG; i += 1) begin
            input_seg[i] = next_src;

            unique case (input_seg[i].loc)
                LOC_TX_PREV: begin
                    if ((next_src.idx != NUM_OF_SEG-1) && !tx_prev_tuser[next_src.idx].last_segment) begin
                        // There is more in the tx_prev register
                        next_src.loc = LOC_TX_PREV;
                        next_src.idx = next_src.idx + 1;
                    end
                    else if (tx_prev_tlast && axi_st_txreq_in.tvalid) begin
                        // Done with TX packet. Switch to TXREQ.
                        next_src.loc = LOC_TXREQ;
                        next_src.idx = 0;
                    end
                    else if (axi_st_tx_in.tvalid) begin
                        // Continue TX packet from input stream or start a new one
                        next_src.loc = LOC_TX;
                        next_src.idx = 0;
                    end
                    else begin
                        next_src.loc = LOC_NONE;
                        next_src.idx = 0;
                    end
                end

                LOC_TX: begin
                    picked_tx = 1'b1;
                    txreq_was_last = 1'b0;

                    if (!tx_in_tuser[next_src.idx].last_segment) begin
                        // There is more in the tx input
                        next_src.loc = LOC_TX;
                        next_src.idx = next_src.idx + 1;
                    end
                    else if (tx_prev_tlast && axi_st_txreq_in.tvalid && !picked_txreq) begin
                        // Done with TX packet. Switch to TXREQ.
                        next_src.loc = LOC_TXREQ;
                        next_src.idx = 0;
                    end
                    else begin
                        next_src.loc = LOC_NONE;
                        next_src.idx = 0;
                    end
                end

                LOC_TXREQ: begin
                    picked_txreq = 1'b1;
                    txreq_was_last = 1'b1;

                    // TXREQ is always one segment. If this is the first segment,
                    // consider the TX input.
                    if (axi_st_tx_in.tvalid && !picked_tx && (i != NUM_OF_SEG-1)) begin
                        next_src.loc = LOC_TX;
                        next_src.idx = 0;
                    end
                    else begin
                        next_src.loc = LOC_NONE;
                        next_src.idx = 0;
                    end
                end

                default: begin
                    // No action
                    next_src.loc = LOC_NONE;
                    next_src.idx = 0;
                end
            endcase // unique case (input_seg[i].loc)
        end
    end

    assign axi_st_txreq_in.tready = tx_out.tready && picked_txreq;
    assign axi_st_tx_in.tready = tx_out.tready && picked_tx;
    assign tx_out.tvalid = (input_seg[0].loc != LOC_NONE);
    assign tx_out.tlast = picked_txreq ||
                          (tx_prev_tvalid && tx_prev_tlast) ||
                          (picked_tx && (next_src.loc != LOC_TX));

    //
    // Record TX in case it is needed next cycle
    //
    always_ff @(posedge clk) begin
        if (tx_out.tready) begin
            tx_prev_tvalid <= 1'b0;
        end

        if (axi_st_tx_in.tvalid && axi_st_tx_in.tready) begin
            tx_prev_tlast <= axi_st_tx_in.tlast;
            tx_prev_tvalid <= picked_tx && (next_src.loc == LOC_TX) && (input_seg[0].loc != LOC_TX);
            tx_prev_idx <= next_src.idx;
        end

        if (!rst_n) begin
            tx_prev_tvalid <= 1'b0;
            tx_prev_tlast <= 1'b1;
        end
    end

    if (NUM_OF_SEG > 1) begin : reg_tx
        always_ff @(posedge clk) begin
            if (axi_st_tx_in.tvalid && axi_st_tx_in.tready) begin
                tx_prev_tdata <= tx_in_tdata[NUM_OF_SEG-1:1];
                tx_prev_tkeep <= tx_in_tkeep[NUM_OF_SEG-1:1];
                tx_prev_tuser <= tx_in_tuser[NUM_OF_SEG-1:1];
            end
        end
    end

    always_ff @(posedge clk) begin
        if (tx_out.tvalid && tx_out.tready) begin
            prev_was_txreq <= txreq_was_last;
        end

        if (!rst_n) begin
            prev_was_txreq <= 1'b0;
        end
    end

    t_seg_tdata tx_out_tdata;
    t_seg_tkeep tx_out_tkeep;
    t_seg_tuser tx_out_tuser;

    always_comb begin
        for (int i = 0; i < NUM_OF_SEG; i += 1) begin
            unique case (input_seg[i].loc)
              LOC_TX_PREV: begin
                    tx_out_tdata[i] = tx_prev_tdata[input_seg[i].idx];
                    tx_out_tkeep[i] = tx_prev_tkeep[input_seg[i].idx];
                    tx_out_tuser[i] = tx_prev_tuser[input_seg[i].idx];
                end
              LOC_TX: begin
                    tx_out_tdata[i] = tx_in_tdata[input_seg[i].idx];
                    tx_out_tkeep[i] = tx_in_tkeep[input_seg[i].idx];
                    tx_out_tuser[i] = tx_in_tuser[input_seg[i].idx];
                end
              LOC_TXREQ: begin
                    // There is only one TXREQ input
                    tx_out_tdata[i] = txreq_in_tdata[0];
                    tx_out_tkeep[i] = txreq_in_tkeep[0];
                    tx_out_tuser[i] = txreq_in_tuser[0];
                end
              default: begin
                    tx_out_tdata[i] = '0;
                    tx_out_tkeep[i] = '0;
                    tx_out_tuser[i] = '0;
                end
            endcase
        end
    end

    assign tx_out.tdata = tx_out_tdata;
    assign tx_out.tkeep = tx_out_tkeep;
    assign tx_out.tuser_vendor = tx_out_tuser;

    assign tx_out.tready = axi_st_tx_out.tready || !axi_st_tx_out.tvalid;

    always_ff @(posedge clk) begin
        if (axi_st_tx_out.tready) begin
            axi_st_tx_out.tvalid <= 1'b0;
        end

        if (tx_out.tvalid && tx_out.tready) begin
            axi_st_tx_out.tvalid <= 1'b1;
            axi_st_tx_out.tdata <= tx_out.tdata;
            axi_st_tx_out.tkeep <= tx_out.tkeep;
            axi_st_tx_out.tuser_vendor <= tx_out.tuser_vendor;
            axi_st_tx_out.tlast <= tx_out.tlast;
        end

        if (!rst_n) begin
            axi_st_tx_out.tvalid <= 1'b0;
        end
    end

endmodule // ofs_fim_pcie_ss_tx_merge
