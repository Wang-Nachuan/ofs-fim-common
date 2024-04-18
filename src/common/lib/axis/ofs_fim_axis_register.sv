// Copyright 2020 Intel Corporation
// SPDX-License-Identifier: MIT

// Description
//-----------------------------------------------------------------------------
//
// AXIS pipeline register 
//
//-----------------------------------------------------------------------------

`timescale 1 ps / 1 ps
module ofs_fim_axis_register
#( 
    parameter MODE                 = 0, // 0: skid buffer 1: simple buffer 2: simple buffer (bubble) 3: bypass
    parameter TREADY_RST_VAL       = 0, // 0: tready deasserted during reset 
                                        // 1: tready asserted during reset
    parameter ENABLE_TKEEP         = 1,
    parameter ENABLE_TLAST         = 1,
    parameter ENABLE_TID           = 0,
    parameter ENABLE_TDEST         = 0,
    parameter ENABLE_TUSER         = 0,
   
    parameter TDATA_WIDTH          = 32,
    parameter TID_WIDTH            = 8,
    parameter TDEST_WIDTH          = 8,
    parameter TUSER_WIDTH          = 1,

    // Preserve registers for crossing a PR boundary? Set to "RX" for flow
    // into a PR region and "TX" for flow out of a PR region.
    parameter PRESERVE_REG         = "OFF",

    // In MODE 0 (skid buffer), setting REG_IN to 1 adds a third register.
    // When REG_IN is 0 (default), there is no input register and inbound
    // traffic flows to either of the two skid registers. When REG_IN is 1,
    // all inbound traffic flows only to an input register. The input
    // register feeds the two skid registers. The extra pipeline register
    // can improve the fit for complex flow control such as the PF/VF MUX
    // and for crossing PR boundaries.
    parameter REG_IN               = 0,

    // --------------------------------------
    // Derived parameters
    // --------------------------------------
    parameter TKEEP_WIDTH = TDATA_WIDTH / 8
)(
    input  logic                       clk,
    input  logic                       rst_n,

    output logic                       s_tready,
    input  logic                       s_tvalid,
    input  logic [TDATA_WIDTH-1:0]     s_tdata,
    input  logic [TKEEP_WIDTH-1:0]     s_tkeep, 
    input  logic                       s_tlast, 
    input  logic [TID_WIDTH-1:0]       s_tid, 
    input  logic [TDEST_WIDTH-1:0]     s_tdest, 
    input  logic [TUSER_WIDTH-1:0]     s_tuser, 
    
    input  logic                       m_tready,
    output logic                       m_tvalid,
    output logic [TDATA_WIDTH-1:0]     m_tdata,
    output logic [TKEEP_WIDTH-1:0]     m_tkeep, 
    output logic                       m_tlast, 
    output logic [TID_WIDTH-1:0]       m_tid, 
    output logic [TDEST_WIDTH-1:0]     m_tdest, 
    output logic [TUSER_WIDTH-1:0]     m_tuser 
);

    //
    // Flags for preserving registers that cross a PR boundary. They are
    // off by default. When PRESERVE_REG is set to either "RX" or "TX",
    // flags are set to ensure that the full registers are available in
    // subsequent PR builds.
    //

    // Preservation parameters depend on a signal's direction across the
    // PR boundary. Apply PRESERVE_FANOUT_FREE_NODE to PR input registers
    // and PRESERVE_REGISTER_SYN_ONLY to PR output registers.
    localparam PRESERVE_ATTR_M = (PRESERVE_REG == "RX") ? "PRESERVE_FANOUT_FREE_NODE " :
                                                          "PRESERVE_REGISTER_SYN_ONLY ";
    localparam PRESERVE_ATTR_S = (PRESERVE_REG == "RX") ? "PRESERVE_REGISTER_SYN_ONLY " :
                                                          "PRESERVE_FANOUT_FREE_NODE ";

    localparam PRESERVE_ON_OFF = (PRESERVE_REG == "OFF") ? "OFF" : "ON";

    (* altera_attribute = {"-name ", PRESERVE_ATTR_S, PRESERVE_ON_OFF} *)
    logic                          s_tready_reg;

    (* altera_attribute = {"-name ", PRESERVE_ATTR_M, PRESERVE_ON_OFF} *)
    logic                          m_tvalid_reg;
    (* altera_attribute = {"-name ", PRESERVE_ATTR_M, PRESERVE_ON_OFF} *)
    logic [TDATA_WIDTH-1:0]        m_tdata_reg;
    (* altera_attribute = {"-name ", PRESERVE_ATTR_M, PRESERVE_ON_OFF} *)
    logic [TKEEP_WIDTH-1:0]        m_tkeep_reg;
    (* altera_attribute = {"-name ", PRESERVE_ATTR_M, PRESERVE_ON_OFF} *)
    logic                          m_tlast_reg; 
    (* altera_attribute = {"-name ", PRESERVE_ATTR_M, PRESERVE_ON_OFF} *)
    logic [TID_WIDTH-1:0]          m_tid_reg;  
    (* altera_attribute = {"-name ", PRESERVE_ATTR_M, PRESERVE_ON_OFF} *)
    logic [TDEST_WIDTH-1:0]        m_tdest_reg;  
    (* altera_attribute = {"-name ", PRESERVE_ATTR_M, PRESERVE_ON_OFF} *)
    logic [TUSER_WIDTH-1:0]        m_tuser_reg;

generate
if (MODE == 0) begin
    // --------------------------------------
    // skid buffer
    // --------------------------------------
    
    // Input registers, used when REG_IN is set
    logic                          in_tvalid, in_tvalid_reg;
    logic [TDATA_WIDTH-1:0]        in_tdata, in_tdata_reg;
    logic [TKEEP_WIDTH-1:0]        in_tkeep, in_tkeep_reg;
    logic                          in_tlast, in_tlast_reg;
    logic [TID_WIDTH-1:0]          in_tid, in_tid_reg;
    logic [TDEST_WIDTH-1:0]        in_tdest, in_tdest_reg;
    logic [TUSER_WIDTH-1:0]        in_tuser, in_tuser_reg;
    logic                          in_tready_reg;

    // Registers & signals
    logic                          s_tvalid_reg; 
    logic [TDATA_WIDTH-1:0]        s_tdata_reg;
    logic [TKEEP_WIDTH-1:0]        s_tkeep_reg;
    logic                          s_tlast_reg; 
    logic [TID_WIDTH-1:0]          s_tid_reg;  
    logic [TDEST_WIDTH-1:0]        s_tdest_reg;  
    logic [TUSER_WIDTH-1:0]        s_tuser_reg;

    logic                          s_tready_pre;
    logic                          s_tready_reg_dup;
    logic                          use_reg;

    logic                          m_tvalid_pre; 
    logic [TDATA_WIDTH-1:0]        m_tdata_pre;
    logic [TKEEP_WIDTH-1:0]        m_tkeep_pre;
    logic                          m_tlast_pre; 
    logic [TID_WIDTH-1:0]          m_tid_pre;  
    logic [TDEST_WIDTH-1:0]        m_tdest_pre;  
    logic [TUSER_WIDTH-1:0]        m_tuser_pre;

    // These input registers will be consumed only when REG_IN is set.
    always_ff @(posedge clk) begin
       if (in_tready_reg) begin
          in_tvalid_reg <= s_tvalid;
          in_tdata_reg  <= s_tdata;
          in_tkeep_reg  <= s_tkeep;
          in_tlast_reg  <= s_tlast;
          in_tid_reg    <= s_tid;
          in_tdest_reg  <= s_tdest;
          in_tuser_reg  <= s_tuser;
       end

       // Input register ready (including skid buffer). Same as s_tready_reg
       // but add a clause that checks the state of in_tvalid_reg.
       in_tready_reg <= s_tready_pre || (~use_reg && ~in_tvalid) ||
                        (in_tready_reg ? ~s_tvalid : ~in_tvalid_reg);

       if (~rst_n) begin
          in_tvalid_reg <= 1'b0;
          in_tready_reg <= (TREADY_RST_VAL == 0) ? 1'b0 : 1'b1;
       end
    end

    // Feed the skid buffer from the incoming wires (REG_IN == 0)
    // or from the input registers.
    assign in_tvalid = REG_IN ? in_tvalid_reg : s_tvalid;
    assign in_tdata  = REG_IN ? in_tdata_reg  : s_tdata;
    assign in_tkeep  = REG_IN ? in_tkeep_reg  : s_tkeep;
    assign in_tlast  = REG_IN ? in_tlast_reg  : s_tlast;
    assign in_tid    = REG_IN ? in_tid_reg    : s_tid;
    assign in_tdest  = REG_IN ? in_tdest_reg  : s_tdest;
    assign in_tuser  = REG_IN ? in_tuser_reg  : s_tuser;

    assign s_tready_pre = (m_tready || ~m_tvalid);
 
    always_ff @(posedge clk) begin
      if (~rst_n) begin
        s_tready_reg     <= (TREADY_RST_VAL == 0) ? 1'b0 : 1'b1;
        s_tready_reg_dup <= (TREADY_RST_VAL == 0) ? 1'b0 : 1'b1;
      end else begin
        s_tready_reg     <= s_tready_pre || (~use_reg && ~in_tvalid);
        s_tready_reg_dup <= s_tready_pre || (~use_reg && ~in_tvalid);
      end
    end
    
    // --------------------------------------
    // On the first cycle after reset, the pass-through
    // must not be used or downstream logic may sample
    // the same command twice because of the delay in
    // transmitting a rising tready.
    // --------------------------------------			    
    always_ff @(posedge clk) begin
       if (~rst_n) begin
          use_reg <= 1'b1;
       end else if (s_tready_pre) begin
          // stop using the buffer when s_tready_pre is high (m_tready=1 or m_tvalid=0)
          use_reg <= 1'b0;
       end else if (s_tready_reg) begin
          use_reg <= ~s_tready_pre && in_tvalid;
       end
    end
    
    always_ff @(posedge clk) begin
       if (~rst_n) begin
          s_tvalid_reg <= 1'b0;
       end else if (s_tready_reg_dup) begin
          s_tvalid_reg <= in_tvalid;
       end
    end

    always_ff @(posedge clk) begin
       if (s_tready_reg_dup) begin
          s_tdata_reg  <= in_tdata;
          s_tkeep_reg  <= in_tkeep;
          s_tlast_reg  <= in_tlast;
          s_tid_reg    <= in_tid;
          s_tdest_reg  <= in_tdest;
          s_tuser_reg  <= in_tuser;
       end
    end
     
    always_comb begin
       if (use_reg) begin
          m_tvalid_pre = s_tvalid_reg;
          m_tdata_pre  = s_tdata_reg;
          m_tkeep_pre  = s_tkeep_reg;
          m_tlast_pre  = s_tlast_reg;
          m_tid_pre    = s_tid_reg; 
          m_tdest_pre  = s_tdest_reg;
          m_tuser_pre  = s_tuser_reg;
       end else begin
          m_tvalid_pre = in_tvalid;
          m_tdata_pre  = in_tdata;
          m_tkeep_pre  = in_tkeep;
          m_tlast_pre  = in_tlast;
          m_tid_pre    = in_tid;
          m_tdest_pre  = in_tdest;
          m_tuser_pre  = in_tuser;
       end
    end
     
    // --------------------------------------
    // Master-Slave Signal Pipeline Stage 
    // --------------------------------------
    always_ff @(posedge clk) begin
       if (~rst_n) begin
          m_tvalid_reg <= 1'b0;
       end else if (s_tready_pre) begin
          m_tvalid_reg <= m_tvalid_pre;
       end
    end
    
    always_ff @(posedge clk) begin
       if (s_tready_pre) begin
          m_tdata_reg  <= m_tdata_pre;
          m_tkeep_reg  <= m_tkeep_pre;
          m_tlast_reg  <= m_tlast_pre;
          m_tid_reg    <= m_tid_pre;
          m_tdest_reg  <= m_tdest_pre;
          m_tuser_reg  <= m_tuser_pre;
       end
    end

    // Output assignment
    assign m_tvalid = m_tvalid_reg;
    assign m_tdata  = m_tdata_reg;
    assign m_tkeep  = ENABLE_TKEEP ? m_tkeep_reg : '0;
    assign m_tlast  = ENABLE_TLAST ? m_tlast_reg : 1'b0;
    assign m_tid    = ENABLE_TID   ? m_tid_reg   : '0;
    assign m_tdest  = ENABLE_TDEST ? m_tdest_reg : '0;
    assign m_tuser  = ENABLE_TUSER ? m_tuser_reg : '0;
    assign s_tready = REG_IN ? in_tready_reg : s_tready_reg;

end else if (MODE == 1) begin 
   // --------------------------------------
   // Simple pipeline register 
   // --------------------------------------
   logic                          s_tready_pre;

   assign s_tready_pre = (~m_tvalid || m_tready);

   always_ff @(posedge clk) begin
      if (s_tready_pre) begin
         m_tvalid_reg <= s_tvalid;
         m_tdata_reg  <= s_tdata;
         m_tkeep_reg  <= s_tkeep;
         m_tlast_reg  <= s_tlast;
         m_tid_reg    <= s_tid;
         m_tdest_reg  <= s_tdest;
         m_tuser_reg  <= s_tuser;
      end

      if (~rst_n) begin
         m_tvalid_reg <= 1'b0;
      end
   end

   // Output assignment
   assign m_tvalid = m_tvalid_reg;
   assign m_tdata  = m_tdata_reg;
   assign m_tkeep  = ENABLE_TKEEP ? m_tkeep_reg : '0;
   assign m_tlast  = ENABLE_TLAST ? m_tlast_reg : 1'b0;
   assign m_tid    = ENABLE_TID   ? m_tid_reg   : '0;
   assign m_tdest  = ENABLE_TDEST ? m_tdest_reg : '0;
   assign m_tuser  = ENABLE_TUSER ? m_tuser_reg : '0;
   assign s_tready = s_tready_pre;

end else if (MODE == 2) begin 
   // --------------------------------------
   // Simple pipeline register with bubble cycle
   // --------------------------------------

   always_ff @(posedge clk) begin
      if (~rst_n) begin
         s_tready_reg <= 1'b0;
         m_tvalid_reg <= 1'b0;
      end else begin
        if (s_tready_reg && s_tvalid) begin
           s_tready_reg <= 1'b0;
           m_tvalid_reg <= 1'b1;
        end else if (~s_tready_reg && (m_tready || ~m_tvalid)) begin
           s_tready_reg <= 1'b1;
           m_tvalid_reg <= 1'b0;
        end
      end
   end

   always_ff @(posedge clk) begin
      if (s_tready_reg) begin
         m_tdata_reg  <= s_tdata;
         m_tkeep_reg  <= s_tkeep;
         m_tlast_reg  <= s_tlast;
         m_tid_reg    <= s_tid;
         m_tdest_reg  <= s_tdest;
         m_tuser_reg  <= s_tuser;
      end
   end
 
    // Output assignment
    assign m_tvalid = m_tvalid_reg;
    assign m_tdata  = m_tdata_reg;
    assign m_tkeep  = ENABLE_TKEEP ? m_tkeep_reg : '0;
    assign m_tlast  = ENABLE_TLAST ? m_tlast_reg : 1'b0;
    assign m_tid    = ENABLE_TID   ? m_tid_reg   : '0;
    assign m_tdest  = ENABLE_TDEST ? m_tdest_reg : '0;
    assign m_tuser  = ENABLE_TUSER ? m_tuser_reg : '0;
    assign s_tready = s_tready_reg;

end else begin 

   // --------------------------------------
   // bypass mode
   // --------------------------------------
   assign m_tvalid = s_tvalid;
   assign m_tdata  = s_tdata;
   assign m_tkeep  = ENABLE_TKEEP ? s_tkeep : '0;
   assign m_tlast  = ENABLE_TLAST ? s_tlast : 1'b0;
   assign m_tid    = ENABLE_TID   ? s_tid   : '0;
   assign m_tdest  = ENABLE_TDEST ? s_tdest : '0;
   assign m_tuser  = ENABLE_TUSER ? s_tuser : '0;
   assign s_tready = m_tready;
end
endgenerate

endmodule
