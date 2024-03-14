// Copyright 2001-2023 Intel Corporation
// SPDX-License-Identifier: MIT


`timescale 1ps/1ps

// DESCRIPTION
// 7 input XOR gate.  Latency 1.
// Generated by one of Gregg's toys.   Share And Enjoy.

module alt_e2550_xor7t1_hn #(
//    parameter SIM_EMULATE = 1'b0
) (
    input clk,
    input [6:0] din,
    output dout
);

wire [1:0] leaf;

alt_e2550_xor4t1_hn c0 (
    .clk(clk),
    .din(din[3:0]),
    .dout(leaf[0])
);
//defparam c0 .SIM_EMULATE = SIM_EMULATE;

alt_e2550_xor3t1_hn c1 (
    .clk(clk),
    .din(din[6:4]),
    .dout(leaf[1])
);
//defparam c1 .SIM_EMULATE = SIM_EMULATE;

alt_e2550_xor2t0_hn c2 (
    .din(leaf),
    .dout(dout)
);
//defparam c2 .SIM_EMULATE = SIM_EMULATE;

endmodule

