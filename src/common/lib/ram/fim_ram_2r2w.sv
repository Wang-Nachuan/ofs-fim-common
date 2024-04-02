// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Quad port RAM. Writing to the same location on both ports in a single cycle
// generates undefined results.
//
// At most one write port may be configured to return new data when reading the
// same address in a cycle on either port. Set READ_DURING_WRITE to either
// "NEW_DATA_A" or "NEW_DATA_B".
//

module fim_ram_2r2w
#(
  parameter DWIDTH            = 32,
  parameter AWIDTH            = 4,
  parameter READ_DURING_WRITE = "OLD_DATA"   
) (

  input                    clk,
  input                    reset_n,

  input                    wren_a,
  input                    wren_b,
  input                    rden_a,
  input                    rden_b,
  input  [DWIDTH-1:0]      wdata_a,
  input  [DWIDTH-1:0]      wdata_b,
  input  [AWIDTH-1:0]      raddr_a,
  input  [AWIDTH-1:0]      raddr_b,
  input  [AWIDTH-1:0]      waddr_a,
  input  [AWIDTH-1:0]      waddr_b,
  output [DWIDTH-1:0]      rdata_a,
  output [DWIDTH-1:0]      rdata_b
);

  wire [DWIDTH-1:0]        BRAM0_0_rdata_a;
  wire [DWIDTH-1:0]        BRAM0_1_rdata_b;
  wire [DWIDTH-1:0]        BRAM1_0_rdata_a;
  wire [DWIDTH-1:0]        BRAM1_1_rdata_b;

  reg [2**AWIDTH-1:0]      lvt;
  reg                      lvt_a;
  reg                      lvt_b;

  reg [DWIDTH-1:0]         wdata_a_d;
  reg [DWIDTH-1:0]         wdata_b_d;
  reg                      read_during_write_a;
  reg                      read_during_write_b;

  generate
  if (READ_DURING_WRITE=="NEW_DATA_A") begin
    always @(posedge clk or negedge reset_n)
    begin
      if (~reset_n) begin
        read_during_write_a <= 0;
        read_during_write_b <= 0;
      end
      else begin
        read_during_write_a <= wren_a & rden_a & waddr_a==raddr_a;
        read_during_write_b <= wren_a & rden_b & waddr_a==raddr_b;
      end
    end
  end
  else if (READ_DURING_WRITE=="NEW_DATA_B") begin
    always @(posedge clk or negedge reset_n)
    begin
      if (~reset_n) begin
        read_during_write_a <= 0;
        read_during_write_b <= 0;
      end
      else begin
        read_during_write_a <= wren_b & rden_a & waddr_b==raddr_a;
        read_during_write_b <= wren_b & rden_b & waddr_b==raddr_b;
      end
    end
  end
  else begin
    always @*
    begin
      read_during_write_a = 0;
      read_during_write_b = 0;
    end
  end
  endgenerate

  always @(posedge clk or negedge reset_n)
  begin
    if (~reset_n) begin
      wdata_a_d <= 0;
      wdata_b_d <= 0;
    end
    else begin
      wdata_a_d <= wdata_a;
      wdata_b_d <= wdata_b;
    end
  end

  always @(posedge clk or negedge reset_n)
  begin
    if (~reset_n)
      lvt <= 0;
    else begin
      if (wren_a)
        lvt[waddr_a] <= 1'b0;

      if (wren_b & ((wren_a & waddr_a!=waddr_b) | ~wren_a))
        lvt[waddr_b] <= 1'b1;
    end
  end

  always @(posedge clk or negedge reset_n)
  begin
    if (~reset_n) begin
      lvt_a     <= 0;
      lvt_b     <= 0;
    end
    else begin
      lvt_a     <= lvt[raddr_a];
      lvt_b     <= lvt[raddr_b];
    end
  end

  generate
  if (READ_DURING_WRITE=="NEW_DATA_A") begin
    assign rdata_a = read_during_write_a ? wdata_a_d : (lvt_a ? BRAM1_0_rdata_a : BRAM0_0_rdata_a);
    assign rdata_b = read_during_write_b ? wdata_a_d : (lvt_b ? BRAM1_1_rdata_b : BRAM0_1_rdata_b);
  end
  else if (READ_DURING_WRITE=="NEW_DATA_B") begin
    assign rdata_a = read_during_write_a ? wdata_b_d : (lvt_a ? BRAM1_0_rdata_a : BRAM0_0_rdata_a);
    assign rdata_b = read_during_write_b ? wdata_b_d : (lvt_b ? BRAM1_1_rdata_b : BRAM0_1_rdata_b);
  end
  else begin
    assign rdata_a = lvt_a ? BRAM1_0_rdata_a : BRAM0_0_rdata_a;
    assign rdata_b = lvt_b ? BRAM1_1_rdata_b : BRAM0_1_rdata_b;
  end
  endgenerate

  altera_syncram #(
  .width_a                              ( DWIDTH                    ),
  .widthad_a                            ( AWIDTH                    ),
  .widthad2_a                           ( AWIDTH                    ),
  .numwords_a                           ( 2**AWIDTH                 ),
  .outdata_reg_a                        ( "CLOCK0"                  ),
  .address_aclr_a                       ( "NONE"                    ),
  .outdata_aclr_a                       ( "NONE"                    ),
  .width_byteena_a                      ( 1                         ),

  .width_b                              ( DWIDTH                    ),
  .widthad_b                            ( AWIDTH                    ),
  .widthad2_b                           ( AWIDTH                    ),
  .numwords_b                           ( 2**AWIDTH                 ),
  .rdcontrol_reg_b                      ( "CLOCK0"                  ),
  .address_reg_b                        ( "CLOCK0"                  ),
  .outdata_reg_b                        ( "UNREGISTERED"            ),
  .outdata_aclr_b                       ( "CLEAR0"                  ),
  .indata_reg_b                         ( "CLOCK0"                  ),
  .byteena_reg_b                        ( "CLOCK0"                  ),
  .address_aclr_b                       ( "NONE"                    ),
  .width_byteena_b                      ( 1                         ),

  .clock_enable_input_a                 ( "BYPASS"                  ),
  .clock_enable_output_a                ( "BYPASS"                  ),
  .clock_enable_input_b                 ( "BYPASS"                  ),
  .clock_enable_output_b                ( "BYPASS"                  ),
  .clock_enable_core_a                  ( "BYPASS"                  ),
  .clock_enable_core_b                  ( "BYPASS"                  ),

  .operation_mode                       ( "DUAL_PORT"               ),
  .optimization_option                  ( "AUTO"                    ),
  .ram_block_type                       ( "AUTO"                    ),
`ifdef DEVICE_FAMILY
  .intended_device_family               ( `FAMILY                   ),
`endif
  .read_during_write_mode_port_b        ( "OLD_DATA"                ),
  .read_during_write_mode_mixed_ports   ( "OLD_DATA"                )
  ) u_BRAM0_0 (
  .wren_a                               ( wren_a                    ),
  .wren_b                               ( 1'b0                      ),
  .rden_a                               ( 1'b0                      ),
  .rden_b                               ( rden_a                    ),
  .data_a                               ( wdata_a                   ),
  .data_b                               ( {DWIDTH{1'b0}}            ),
  .address_a                            ( waddr_a                   ),
  .address_b                            ( raddr_a                   ),
  .clock0                               ( clk                       ),
  .clock1                               ( 1'b1                      ),
  .clocken0                             ( 1'b1                      ),
  .clocken1                             ( 1'b1                      ),
  .clocken2                             ( 1'b1                      ),
  .clocken3                             ( 1'b1                      ),
  .aclr0                                ( ~reset_n                  ),
  .aclr1                                ( 1'b0                      ),
  .byteena_a                            ( 1'b1                      ),
  .byteena_b                            ( 1'b1                      ),
  .addressstall_a                       ( 1'b0                      ),
  .addressstall_b                       ( 1'b0                      ),
  .sclr                                 ( 1'b0                      ),
  .eccencbypass                         ( 1'b0                      ),
  .eccencparity                         ( 8'b0                      ),
  .eccstatus                            (                           ),
  .address2_a                           ( {AWIDTH{1'b1}}            ),
  .address2_b                           ( {AWIDTH{1'b1}}            ),
  .q_a                                  (                           ),
  .q_b                                  ( BRAM0_0_rdata_a           )
  );

  altera_syncram #(
  .width_a                              ( DWIDTH                    ),
  .widthad_a                            ( AWIDTH                    ),
  .widthad2_a                           ( AWIDTH                    ),
  .numwords_a                           ( 2**AWIDTH                 ),
  .outdata_reg_a                        ( "CLOCK0"                  ),
  .address_aclr_a                       ( "NONE"                    ),
  .outdata_aclr_a                       ( "NONE"                    ),
  .width_byteena_a                      ( 1                         ),

  .width_b                              ( DWIDTH                    ),
  .widthad_b                            ( AWIDTH                    ),
  .widthad2_b                           ( AWIDTH                    ),
  .numwords_b                           ( 2**AWIDTH                 ),
  .rdcontrol_reg_b                      ( "CLOCK0"                  ),
  .address_reg_b                        ( "CLOCK0"                  ),
  .outdata_reg_b                        ( "UNREGISTERED"            ),
  .outdata_aclr_b                       ( "CLEAR0"                  ),
  .indata_reg_b                         ( "CLOCK0"                  ),
  .byteena_reg_b                        ( "CLOCK0"                  ),
  .address_aclr_b                       ( "NONE"                    ),
  .width_byteena_b                      ( 1                         ),

  .clock_enable_input_a                 ( "BYPASS"                  ),
  .clock_enable_output_a                ( "BYPASS"                  ),
  .clock_enable_input_b                 ( "BYPASS"                  ),
  .clock_enable_output_b                ( "BYPASS"                  ),
  .clock_enable_core_a                  ( "BYPASS"                  ),
  .clock_enable_core_b                  ( "BYPASS"                  ),

  .operation_mode                       ( "DUAL_PORT"               ),
  .optimization_option                  ( "AUTO"                    ),
  .ram_block_type                       ( "AUTO"                    ),
`ifdef DEVICE_FAMILY
  .intended_device_family               ( `FAMILY                   ),
`endif
  .read_during_write_mode_port_b        ( "OLD_DATA"                ),
  .read_during_write_mode_mixed_ports   ( "OLD_DATA"                )
  ) u_BRAM0_1 (
  .wren_a                               ( wren_a                    ),
  .wren_b                               ( 1'b0                      ),
  .rden_a                               ( 1'b0                      ),
  .rden_b                               ( rden_b                    ),
  .data_a                               ( wdata_a                   ),
  .data_b                               ( {DWIDTH{1'b0}}            ),
  .address_a                            ( waddr_a                   ),
  .address_b                            ( raddr_b                   ),
  .clock0                               ( clk                       ),
  .clock1                               ( 1'b1                      ),
  .clocken0                             ( 1'b1                      ),
  .clocken1                             ( 1'b1                      ),
  .clocken2                             ( 1'b1                      ),
  .clocken3                             ( 1'b1                      ),
  .aclr0                                ( ~reset_n                  ),
  .aclr1                                ( 1'b0                      ),
  .byteena_a                            ( 1'b1                      ),
  .byteena_b                            ( 1'b1                      ),
  .addressstall_a                       ( 1'b0                      ),
  .addressstall_b                       ( 1'b0                      ),
  .sclr                                 ( 1'b0                      ),
  .eccencbypass                         ( 1'b0                      ),
  .eccencparity                         ( 8'b0                      ),
  .eccstatus                            (                           ),
  .address2_a                           ( {AWIDTH{1'b1}}            ),
  .address2_b                           ( {AWIDTH{1'b1}}            ),
  .q_a                                  (                           ),
  .q_b                                  ( BRAM0_1_rdata_b           )
  );

  altera_syncram #(
  .width_a                              ( DWIDTH                    ),
  .widthad_a                            ( AWIDTH                    ),
  .widthad2_a                           ( AWIDTH                    ),
  .numwords_a                           ( 2**AWIDTH                 ),
  .outdata_reg_a                        ( "CLOCK0"                  ),
  .address_aclr_a                       ( "NONE"                    ),
  .outdata_aclr_a                       ( "NONE"                    ),
  .width_byteena_a                      ( 1                         ),

  .width_b                              ( DWIDTH                    ),
  .widthad_b                            ( AWIDTH                    ),
  .widthad2_b                           ( AWIDTH                    ),
  .numwords_b                           ( 2**AWIDTH                 ),
  .rdcontrol_reg_b                      ( "CLOCK0"                  ),
  .address_reg_b                        ( "CLOCK0"                  ),
  .outdata_reg_b                        ( "UNREGISTERED"            ),
  .outdata_aclr_b                       ( "CLEAR0"                  ),
  .indata_reg_b                         ( "CLOCK0"                  ),
  .byteena_reg_b                        ( "CLOCK0"                  ),
  .address_aclr_b                       ( "NONE"                    ),
  .width_byteena_b                      ( 1                         ),

  .clock_enable_input_a                 ( "BYPASS"                  ),
  .clock_enable_output_a                ( "BYPASS"                  ),
  .clock_enable_input_b                 ( "BYPASS"                  ),
  .clock_enable_output_b                ( "BYPASS"                  ),
  .clock_enable_core_a                  ( "BYPASS"                  ),
  .clock_enable_core_b                  ( "BYPASS"                  ),

  .operation_mode                       ( "DUAL_PORT"               ),
  .optimization_option                  ( "AUTO"                    ),
  .ram_block_type                       ( "AUTO"                    ),
`ifdef DEVICE_FAMILY
  .intended_device_family               ( `FAMILY                   ),
`endif
  .read_during_write_mode_port_b        ( "OLD_DATA"                ),
  .read_during_write_mode_mixed_ports   ( "OLD_DATA"                )
  ) u_BRAM1_0 (
  .wren_a                               ( wren_b                    ),
  .wren_b                               ( 1'b0                      ),
  .rden_a                               ( 1'b0                      ),
  .rden_b                               ( rden_a                    ),
  .data_a                               ( wdata_b                   ),
  .data_b                               ( {DWIDTH{1'b0}}            ),
  .address_a                            ( waddr_b                   ),
  .address_b                            ( raddr_a                   ),
  .clock0                               ( clk                       ),
  .clock1                               ( 1'b1                      ),
  .clocken0                             ( 1'b1                      ),
  .clocken1                             ( 1'b1                      ),
  .clocken2                             ( 1'b1                      ),
  .clocken3                             ( 1'b1                      ),
  .aclr0                                ( ~reset_n                  ),
  .aclr1                                ( 1'b0                      ),
  .byteena_a                            ( 1'b1                      ),
  .byteena_b                            ( 1'b1                      ),
  .addressstall_a                       ( 1'b0                      ),
  .addressstall_b                       ( 1'b0                      ),
  .sclr                                 ( 1'b0                      ),
  .eccencbypass                         ( 1'b0                      ),
  .eccencparity                         ( 8'b0                      ),
  .eccstatus                            (                           ),
  .address2_a                           ( {AWIDTH{1'b1}}            ),
  .address2_b                           ( {AWIDTH{1'b1}}            ),
  .q_a                                  (                           ),
  .q_b                                  ( BRAM1_0_rdata_a           )
  );

  altera_syncram #(
  .width_a                              ( DWIDTH                    ),
  .widthad_a                            ( AWIDTH                    ),
  .widthad2_a                           ( AWIDTH                    ),
  .numwords_a                           ( 2**AWIDTH                 ),
  .outdata_reg_a                        ( "CLOCK0"                  ),
  .address_aclr_a                       ( "NONE"                    ),
  .outdata_aclr_a                       ( "NONE"                    ),
  .width_byteena_a                      ( 1                         ),

  .width_b                              ( DWIDTH                    ),
  .widthad_b                            ( AWIDTH                    ),
  .widthad2_b                           ( AWIDTH                    ),
  .numwords_b                           ( 2**AWIDTH                 ),
  .rdcontrol_reg_b                      ( "CLOCK0"                  ),
  .address_reg_b                        ( "CLOCK0"                  ),
  .outdata_reg_b                        ( "UNREGISTERED"            ),
  .outdata_aclr_b                       ( "CLEAR0"                  ),
  .indata_reg_b                         ( "CLOCK0"                  ),
  .byteena_reg_b                        ( "CLOCK0"                  ),
  .address_aclr_b                       ( "NONE"                    ),
  .width_byteena_b                      ( 1                         ),

  .clock_enable_input_a                 ( "BYPASS"                  ),
  .clock_enable_output_a                ( "BYPASS"                  ),
  .clock_enable_input_b                 ( "BYPASS"                  ),
  .clock_enable_output_b                ( "BYPASS"                  ),
  .clock_enable_core_a                  ( "BYPASS"                  ),
  .clock_enable_core_b                  ( "BYPASS"                  ),

  .operation_mode                       ( "DUAL_PORT"               ),
  .optimization_option                  ( "AUTO"                    ),
  .ram_block_type                       ( "AUTO"                    ),
`ifdef DEVICE_FAMILY
  .intended_device_family               ( `FAMILY                   ),
`endif
  .read_during_write_mode_port_b        ( "OLD_DATA"                ),
  .read_during_write_mode_mixed_ports   ( "OLD_DATA"                )
  ) u_BRAM1_1 (
  .wren_a                               ( wren_b                    ),
  .wren_b                               ( 1'b0                      ),
  .rden_a                               ( 1'b0                      ),
  .rden_b                               ( rden_b                    ),
  .data_a                               ( wdata_b                   ),
  .data_b                               ( {DWIDTH{1'b0}}            ),
  .address_a                            ( waddr_b                   ),
  .address_b                            ( raddr_b                   ),
  .clock0                               ( clk                       ),
  .clock1                               ( 1'b1                      ),
  .clocken0                             ( 1'b1                      ),
  .clocken1                             ( 1'b1                      ),
  .clocken2                             ( 1'b1                      ),
  .clocken3                             ( 1'b1                      ),
  .aclr0                                ( ~reset_n                  ),
  .aclr1                                ( 1'b0                      ),
  .byteena_a                            ( 1'b1                      ),
  .byteena_b                            ( 1'b1                      ),
  .addressstall_a                       ( 1'b0                      ),
  .addressstall_b                       ( 1'b0                      ),
  .sclr                                 ( 1'b0                      ),
  .eccencbypass                         ( 1'b0                      ),
  .eccencparity                         ( 8'b0                      ),
  .eccstatus                            (                           ),
  .address2_a                           ( {AWIDTH{1'b1}}            ),
  .address2_b                           ( {AWIDTH{1'b1}}            ),
  .q_a                                  (                           ),
  .q_b                                  ( BRAM1_1_rdata_b           )
  );

endmodule
