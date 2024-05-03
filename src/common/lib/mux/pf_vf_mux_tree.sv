// Copyright 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Construct a PF/VF MUX tree -- a hierarchy of pf_vf_mux_w_params instances.
// The lower-level pf_vf_mux_w_params creates a single-level switch. The
// tree module here avoids excessive fanout by turning the routing table
// into a binary tree with the target ports routed at the leaves.
//

module pf_vf_mux_tree
  #(
    parameter string MUX_NAME = "" ,      // Name for logging in a multi-PF/VF MUX system
    parameter string LOG_FILE_NAME = "" , // Override the default log name if specified

    parameter int NUM_RTABLE_ENTRIES,     // Number of entries in the routing table
    // Routing table
    parameter pf_vf_mux_pkg::t_pfvf_rtable_entry[NUM_RTABLE_ENTRIES-1:0] PFVF_ROUTING_TABLE = {NUM_RTABLE_ENTRIES{pf_vf_mux_pkg::t_pfvf_rtable_entry'(0)}},

    parameter NUM_PORT                    // Number of AFU-side ports
    )
   (
    input  logic clk,
    input  logic rst_n,

    pcie_ss_axis_if.sink ho2mx_rx_port,                 // RX from host (1 multiplexed port)
    pcie_ss_axis_if.source mx2ho_tx_port,               // TX to host (1 multiplexed port)
    pcie_ss_axis_if.source mx2fn_rx_port[NUM_PORT-1:0], // Demultiplexed RX to AFUs
    pcie_ss_axis_if.sink fn2mx_tx_port[NUM_PORT-1:0],   // Demultiplexed TX from AFUs

    output logic out_fifo_err,                          // output fifo error?
    output logic out_fifo_perr                          // output fifo parity error?
    );

    localparam TDATA_WIDTH = ho2mx_rx_port.DATA_W;
    localparam TUSER_WIDTH = ho2mx_rx_port.USER_W;

    // synthesis translate_off
    initial begin
        assert (TDATA_WIDTH == mx2ho_tx_port.DATA_W) else
          $fatal(2, "Error %m: DATA WIDTH mismatch ho2mx_rx_port (%0d) vs. mx2ho_tx_port (%0d)", ho2mx_rx_port.DATA_W, mx2ho_tx_port.DATA_W);
        assert (TUSER_WIDTH == mx2ho_tx_port.USER_W) else
          $fatal(2, "Error %m: USER WIDTH mismatch ho2mx_rx_port (%0d) vs. mx2ho_tx_port (%0d)", ho2mx_rx_port.USER_W, mx2ho_tx_port.USER_W);

        assert (TDATA_WIDTH == mx2fn_rx_port[0].DATA_W) else
          $fatal(2, "Error %m: DATA WIDTH mismatch ho2mx_rx_port (%0d) vs. mx2fn_rx_port (%0d)", ho2mx_rx_port.DATA_W, mx2fn_rx_port[0].DATA_W);
        assert (TUSER_WIDTH == mx2fn_rx_port[0].USER_W) else
          $fatal(2, "Error %m: USER WIDTH mismatch ho2mx_rx_port (%0d) vs. mx2fn_rx_port (%0d)", ho2mx_rx_port.USER_W, mx2fn_rx_port[0].USER_W);

        assert (TDATA_WIDTH == fn2mx_tx_port[0].DATA_W) else
          $fatal(2, "Error %m: DATA WIDTH mismatch ho2mx_rx_port (%0d) vs. fn2mx_tx_port (%0d)", ho2mx_rx_port.DATA_W, fn2mx_tx_port[0].DATA_W);
        assert (TUSER_WIDTH == fn2mx_tx_port[0].USER_W) else
          $fatal(2, "Error %m: USER WIDTH mismatch ho2mx_rx_port (%0d) vs. fn2mx_tx_port (%0d)", ho2mx_rx_port.USER_W, fn2mx_tx_port[0].USER_W);
    end
    // synthesis translate_on


    // ====================================================================
    //
    //  Functions and parameters for generating intermediate routing
    //  nodes. They are all used only in the "tree" case below -- the
    //  final section of the if/else clause. SystemVerilog doesn't
    //  permit them to declared inside the internal block, so they
    //  are here at top level.
    //
    // ====================================================================

    // When adding an intermediate binary switch the routing table
    // is split in half. How many entries in the new routing table target
    // the left port? All target ports below right_start_idx go left.
    function automatic int num_left_port_entries(int right_start_idx);
        int n = 0;

        for (int i = 0; i < NUM_RTABLE_ENTRIES; i += 1) begin
            if (PFVF_ROUTING_TABLE[i].pfvf_port < right_start_idx)
              n += 1;
        end

        return n;
    endfunction // num_left_port_entries


    // Half the output ports to right
    localparam RIGHT_START_IDX = NUM_PORT / 2;
    // Number of original routing table entries that target left ports
    localparam N_LEFT_ENTRIES = num_left_port_entries(RIGHT_START_IDX);
    // Number of original routing table entries that target right ports
    localparam N_RIGHT_ENTRIES = NUM_RTABLE_ENTRIES - N_LEFT_ENTRIES;

    // Size of an intermediate binary node routing table. It must hold
    // table entries for the left port plus two wildcard entries to
    // route the rest right -- one with vf_active and one without.
    localparam N_BINARY_TABLE_ENTRIES = N_LEFT_ENTRIES + 2;


    // Generate a routing table for the new intermediate binary tree node.
    // All the original entries targeting left ports are copied to the
    // new table and wildcard entries for right.
    function automatic pf_vf_mux_pkg::t_pfvf_rtable_entry[N_BINARY_TABLE_ENTRIES-1:0] gen_tree_routing_table(int right_start_idx);
        pf_vf_mux_pkg::t_pfvf_rtable_entry[N_BINARY_TABLE_ENTRIES-1:0] tbl;
        int n = 0;

        for (int i = 0; i < NUM_RTABLE_ENTRIES; i += 1) begin
            if (PFVF_ROUTING_TABLE[i].pfvf_port < right_start_idx) begin
                tbl[n] = PFVF_ROUTING_TABLE[i];
                tbl[n].pfvf_port = 0;

                n += 1;
            end
        end

        // Wildcard route anything not going left to the right port
        tbl[N_LEFT_ENTRIES].pfvf_port = 1;
        tbl[N_LEFT_ENTRIES].pf = -1;
        tbl[N_LEFT_ENTRIES].vf = -1;
        tbl[N_LEFT_ENTRIES].vf_active = 0;

        tbl[N_LEFT_ENTRIES+1].pfvf_port = 1;
        tbl[N_LEFT_ENTRIES+1].pf = -1;
        tbl[N_LEFT_ENTRIES+1].vf = -1;
        tbl[N_LEFT_ENTRIES+1].vf_active = 1;

        return tbl;
    endfunction // gen_tree_routing_table


    // Generate the routing tree to pass down recursively for the
    // left path. Original table entries for ports mapped to the
    // left are copied to the new sub-table.
    function automatic pf_vf_mux_pkg::t_pfvf_rtable_entry[N_LEFT_ENTRIES-1:0] gen_left_routing_table(int right_start_idx);
        pf_vf_mux_pkg::t_pfvf_rtable_entry[N_LEFT_ENTRIES-1:0] tbl;
        int n = 0;

        for (int i = 0; i < NUM_RTABLE_ENTRIES; i += 1) begin
            if (PFVF_ROUTING_TABLE[i].pfvf_port < right_start_idx) begin
                tbl[n] = PFVF_ROUTING_TABLE[i];
                n += 1;
            end
        end

        return tbl;
    endfunction // gen_left_routing_table


    // Generate the routing tree to pass down recursively for the
    // right path. It is similar to the left table, except that the
    // pfvf_port offset has to be rebased to 0.
    function automatic pf_vf_mux_pkg::t_pfvf_rtable_entry[N_RIGHT_ENTRIES-1:0] gen_right_routing_table(int right_start_idx);
        pf_vf_mux_pkg::t_pfvf_rtable_entry[N_RIGHT_ENTRIES:0] tbl;
        int n = 0;

        for (int i = 0; i < NUM_RTABLE_ENTRIES; i += 1) begin
            if (PFVF_ROUTING_TABLE[i].pfvf_port >= right_start_idx) begin
                tbl[n] = PFVF_ROUTING_TABLE[i];
                tbl[n].pfvf_port -= right_start_idx;
                n += 1;
            end
        end

        return tbl;
    endfunction // gen_right_routing_table


    // ====================================================================
    //
    //  MUX construction.
    //
    // ====================================================================

    if (NUM_PORT == 1) begin : direct

        // Only 1 AFU port! Just wire the inputs to the outputs.
        ofs_fim_axis_pipeline #(.PL_DEPTH(0))
            rx (.clk, .rst_n, .axis_s(ho2mx_rx_port), .axis_m(mx2fn_rx_port[0]));

        ofs_fim_axis_pipeline #(.PL_DEPTH(0))
            tx (.clk, .rst_n, .axis_s(fn2mx_tx_port[0]), .axis_m(mx2ho_tx_port));

    end
    else if ((NUM_PORT == 2) || (TDATA_WIDTH * NUM_PORT <= 2048)) begin : mux

        // Fanout is low enough. Generate the target MUX.
        pf_vf_mux_w_params
          #(
            .MUX_NAME(MUX_NAME),
            .LOG_FILE_NAME(LOG_FILE_NAME),
            .NUM_RTABLE_ENTRIES(NUM_RTABLE_ENTRIES),
            .PFVF_ROUTING_TABLE(PFVF_ROUTING_TABLE),
            .NUM_PORT(NUM_PORT),
            .DATA_WIDTH(TDATA_WIDTH),
            .USER_WIDTH(TUSER_WIDTH)
            )
          m
           (
            .clk,
            .rst_n,
            .ho2mx_rx_port,
            .mx2ho_tx_port,
            .mx2fn_rx_port,
            .fn2mx_tx_port,
            .out_fifo_err,
            .out_fifo_perr
            );

    end
    else begin : tree

        //
        // High fanout case. Add an intermediate binary node that splits
        // the requested routing table in half. Then pass the two halves
        // recursively back to pf_vf_mux_tree.
        //

        // Routing table for the new binary node, splitting the original
        // table in half.
        localparam pf_vf_mux_pkg::t_pfvf_rtable_entry[N_BINARY_TABLE_ENTRIES-1:0] TREE_ROUTING_TABLE =
            gen_tree_routing_table(RIGHT_START_IDX);

        // Intermediate routing ports for the new binary tree node
        pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(TUSER_WIDTH)) rx_ports[1:0] (.clk, .rst_n);
        pcie_ss_axis_if #(.DATA_W(TDATA_WIDTH), .USER_W(TUSER_WIDTH)) tx_ports[1:0] (.clk, .rst_n);

        logic [2:0] fifo_err;
        assign out_fifo_err = |fifo_err;
        logic [2:0] fifo_perr;
        assign out_fifo_perr = |fifo_perr;

        pf_vf_mux_w_params
          #(
            .MUX_NAME(MUX_NAME),
            .LOG_FILE_NAME(LOG_FILE_NAME),
            .NUM_RTABLE_ENTRIES(N_BINARY_TABLE_ENTRIES),
            .PFVF_ROUTING_TABLE(TREE_ROUTING_TABLE),
            .NUM_PORT(2),
            .DATA_WIDTH(TDATA_WIDTH),
            .USER_WIDTH(TUSER_WIDTH)
            )
          t_binary
           (
            .clk,
            .rst_n,
            .ho2mx_rx_port,
            .mx2ho_tx_port,
            .mx2fn_rx_port(rx_ports),
            .fn2mx_tx_port(tx_ports),
            .out_fifo_err(fifo_err[0]),
            .out_fifo_perr(fifo_perr[0])
            );


        //
        // Now we have the original AFU ports split into two groups. Generate
        // new routing tables for each group and invoke pf_vf_mux_tree recursively.
        // It will either generate another node in the binary tree or the terminal
        // MUX.
        //

        pf_vf_mux_tree
          #(
            .MUX_NAME({ MUX_NAME, "_L" }),
            .LOG_FILE_NAME(LOG_FILE_NAME == "" ? "" : { LOG_FILE_NAME, "_L" }),
            .NUM_RTABLE_ENTRIES(N_LEFT_ENTRIES),
            .PFVF_ROUTING_TABLE(gen_left_routing_table(RIGHT_START_IDX)),
            .NUM_PORT(RIGHT_START_IDX)
            )
          left
           (
            .clk,
            .rst_n,
            .ho2mx_rx_port(rx_ports[0]),
            .mx2ho_tx_port(tx_ports[0]),
            .mx2fn_rx_port(mx2fn_rx_port[RIGHT_START_IDX-1:0]),
            .fn2mx_tx_port(fn2mx_tx_port[RIGHT_START_IDX-1:0]),
            .out_fifo_err(fifo_err[1]),
            .out_fifo_perr(fifo_perr[1])
            );

        pf_vf_mux_tree
          #(
            .MUX_NAME({ MUX_NAME, "_R" }),
            .LOG_FILE_NAME(LOG_FILE_NAME == "" ? "" : { LOG_FILE_NAME, "_R" }),
            .NUM_RTABLE_ENTRIES(N_RIGHT_ENTRIES),
            .PFVF_ROUTING_TABLE(gen_right_routing_table(RIGHT_START_IDX)),
            .NUM_PORT(NUM_PORT - RIGHT_START_IDX)
            )
          right
           (
            .clk,
            .rst_n,
            .ho2mx_rx_port(rx_ports[1]),
            .mx2ho_tx_port(tx_ports[1]),
            .mx2fn_rx_port(mx2fn_rx_port[NUM_PORT-1:RIGHT_START_IDX]),
            .fn2mx_tx_port(fn2mx_tx_port[NUM_PORT-1:RIGHT_START_IDX]),
            .out_fifo_err(fifo_err[2]),
            .out_fifo_perr(fifo_perr[2])
            );
    end


    // ====================================================================
    //
    //  Debug logging for the case where there is only one input port and
    //  one output, with no MUX.
    //
    // ====================================================================

    // synthesis translate_off
    static int log_fd;
    static string mux_tag;

    if (NUM_PORT == 1) begin
        initial
        begin : log
            mux_tag = (MUX_NAME == "") ? "" : {"_", MUX_NAME};

            // Open a log file, using a default if the parent didn't specify a name.
            log_fd = $fopen(((LOG_FILE_NAME == "") ? {"log_pf_vf_mux", mux_tag, ".tsv"} : LOG_FILE_NAME), "w");

            // Write module hierarchy to the top of the log
            $fwrite(log_fd, "pf_vf_mux_tree.sv: %m\n\n");

            // Write the routing table to the log
            $fwrite(log_fd, "Single input and output port -- no switch\n");
            for (int p = 0; p < NUM_RTABLE_ENTRIES; p = p + 1) begin
                $fwrite(log_fd, "routing entry %0d: PF %0d, VF %0d, vf_active %0d, port %0d\n",
                        p, PFVF_ROUTING_TABLE[p].pf, PFVF_ROUTING_TABLE[p].vf,
                        PFVF_ROUTING_TABLE[p].vf_active, PFVF_ROUTING_TABLE[p].pfvf_port);
            end
            $fwrite(log_fd, "\n");
        end

        logic ho2mx_sop;
        logic mx2ho_sop;
        always_ff @(posedge clk) begin
            if (ho2mx_rx_port.tvalid && ho2mx_rx_port.tready)
                ho2mx_sop <= ho2mx_rx_port.tlast;
            if (mx2ho_tx_port.tvalid && mx2ho_tx_port.tready)
                mx2ho_sop <= mx2ho_tx_port.tlast;

            if (!rst_n) begin
                ho2mx_sop <= 1'b1;
                mx2ho_sop <= 1'b1;
            end
        end

        always_ff @(posedge clk) begin
            // FIM to MUX (RX)
            if(rst_n && ho2mx_rx_port.tvalid && ho2mx_rx_port.tready)
            begin
                $fwrite(log_fd, "From_FIM:   %s\n",
                        pcie_ss_pkg::func_pcie_ss_flit_to_string(
                            ho2mx_sop, ho2mx_rx_port.tlast,
                            pcie_ss_hdr_pkg::func_hdr_is_pu_mode(ho2mx_rx_port.tuser_vendor),
                            ho2mx_rx_port.tdata, ho2mx_rx_port.tkeep));
                $fflush(log_fd);
            end

            // MUX to FIM (TX)
            if(rst_n && mx2ho_tx_port.tvalid && mx2ho_tx_port.tready)
            begin
                $fwrite(log_fd, "To_FIM:     %s\n",
                        pcie_ss_pkg::func_pcie_ss_flit_to_string(
                            mx2ho_sop, mx2ho_tx_port.tlast,
                            pcie_ss_hdr_pkg::func_hdr_is_pu_mode(mx2ho_tx_port.tuser_vendor),
                            mx2ho_tx_port.tdata, mx2ho_tx_port.tkeep));
                $fflush(log_fd);
            end
        end
    end
    // synthesis translate_on

endmodule // pf_vf_mux_tree
