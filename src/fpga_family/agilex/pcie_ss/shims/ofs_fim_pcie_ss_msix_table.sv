// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Taken from DM MSI-X table implementation
//

`include "fpga_defines.vh"

module ofs_fim_pcie_ss_msix_table
# (

  parameter    MSIX_TABLE                     = "Enable",
  parameter    MSIX_TABLE_SIZE                = 4096,
  parameter    MSIX_BIR                       = 5,
  parameter    MSIX_BAR_OFFSET                = 0,
  parameter    MSIX_VECTOR_ALLOC              = "Static",

  parameter    total_pf_count                 = 1,
  parameter    total_vf_count                 = 0,
  parameter    pf0_vf_count                   = 0,
  parameter    pf1_vf_count                   = 0,
  parameter    pf2_vf_count                   = 0,
  parameter    pf3_vf_count                   = 0,
  parameter    pf4_vf_count                   = 0,
  parameter    pf5_vf_count                   = 0,
  parameter    pf6_vf_count                   = 0,
  parameter    pf7_vf_count                   = 0,

  parameter    SS_PWIDTH      = 32,

  parameter    LITESLVAWD     = 18,
  parameter    LITESLVDWD     = 32,
  parameter    DWIDTH         = 512
  ) (

  input                          axi_lite_clk,
  input                          lite_areset_n,
  input                          axi_st_clk,
  input                          st_areset_n,

  input                          subsystem_rst_req,
  output                         subsystem_rst_rdy,

  // Host MMIO requests
  output logic                   intc_rx_st_ready,
  input                          intc_rx_st_valid,
  input                          intc_rx_st_msix_size_valid,
  input                          intc_rx_st_sop,
  input  [64 - 1: 0]             intc_rx_st_data,
  input  [127:0]                 intc_rx_st_hdr,
  input                          intc_rx_st_pvalid,
  input  [SS_PWIDTH - 1:0]       intc_rx_st_prefix,
  input  [2:0]                   intc_rx_st_bar_num,
  input  [4:0]                   intc_rx_st_slot_num,
  input  [2:0]                   intc_rx_st_pf_num,
  input  [10:0]                  intc_rx_st_vf_num,
  input                          intc_rx_st_vf_active,
  input  [64 - 1: 0]             intc_rx_st_unmapped_hdr_addr,

  // CSR write interface not used by OFS
  input                          lite_csr_awvalid,
  output  logic                  lite_csr_awready,
  input   [LITESLVAWD-1:0]       lite_csr_awaddr,
  input                          lite_csr_wvalid,
  output  logic                  lite_csr_wready,
  input   [LITESLVDWD-1:0]       lite_csr_wdata,
  input   [LITESLVDWD/8-1:0]     lite_csr_wstrb,
  output logic                   lite_csr_bvalid,
  input                          lite_csr_bready,
  output logic [1:0]             lite_csr_bresp,

  // CSR read interface not used by OFS
  input                          lite_csr_arvalid,
  output  logic                  lite_csr_arready,
  input   [LITESLVAWD-1:0]       lite_csr_araddr,
  output  logic                  lite_csr_rvalid,
  input                          lite_csr_rready,
  output  logic [LITESLVDWD-1:0] lite_csr_rdata,
  output  logic [1:0]            lite_csr_rresp,

  input                          ctrlshadow_tvalid,
  input    [39:0]                ctrlshadow_tdata,

  input                          flrrcvd_tvalid,
  input  [19:0]                  flrrcvd_tdata,

  input                          flrif_flrcmpl_tready,
  output  logic                  intc_flrcmpl_tvalid,
  output  logic [19:0]           intc_flrcmpl_tdata,

  // AFU interrupts on TXREQ stream not used by OFS
  output logic                   st_txreq_tready,
  input                          st_txreq_tvalid,
  input [255:0]                  st_txreq_tdata,

  // AFU interrupts on TX stream
  input  logic  [255:0]          st_tx_tdata,
  input  logic                   st_tx_tvalid,
  output                         st_tx_tready,

  // Host MMIO read response
  output  logic  [255:0]         intc_st_cpl_tx_hdr,
  output  logic  [DWIDTH-1:0]    intc_st_cpl_tx_data,
  output  logic                  intc_st_cpl_tx_tvalid,
  input                          intc_st_cpl_tx_tready,

  // Size request not used by OFS
  output  logic [11:0]           h2c_msix_size,
  input                          h2c_size_req_valid,
  input  [4:0]                   h2c_slot_num,
  input  [2:0]                   h2c_pf_num,
  input  [10:0]                  h2c_vf_num,
  input                          h2c_vf_active,

  // Error CSRs not used by OFS
  output reg                     intc_err_gen_ctrl_trig_req,
  input                          intc_err_gen_ctrl_trig_done,
  output reg                     intc_err_gen_ctrl_logh,
  output reg                     intc_err_gen_ctrl_logp,
  output reg                     intc_err_gen_ctrl_vf_active,
  output reg [4:0]               intc_err_gen_ctrl_pf_num,
  output reg [10:0]              intc_err_gen_ctrl_vf_num,
  output reg [4:0]               intc_err_gen_ctrl_slot_num,
  output reg [13:0]              intc_err_gen_attr,
  output reg [31:0]              intc_err_gen_hdr_dw0,
  output reg [31:0]              intc_err_gen_hdr_dw1,
  output reg [31:0]              intc_err_gen_hdr_dw2,
  output reg [31:0]              intc_err_gen_hdr_dw3,
  output reg [31:0]              intc_err_gen_prfx,

  output reg [10:0]              intc_vf_err_vf_num,
  output reg [2:0]               intc_vf_err_func_num,
  output reg [4:0]               intc_vf_err_slot_num,
  output reg                     intc_vf_err_tvalid,
  input                          intc_vf_err_tready,

  // AFU TX interrupts mapped to host writes
  output  logic [255:0]          intc_st_tx_hdr,
  output  logic [DWIDTH-1:0]     intc_st_tx_data,
  output  logic                  intc_st_tx_tvalid,
  input                          intc_st_tx_tready

  );

`ifdef DEVICE_FAMILY
  localparam DEVICE_FAMILY = `DEVICE_FAMILY;
`else
  localparam DEVICE_FAMILY = "Agilex";
`endif

  localparam MAX_TOTAL_MSIX_TABLE_SIZE = 4096;
  localparam MSIX_TABLE_DEPTH          = MSIX_VECTOR_ALLOC=="Static" ? MSIX_TABLE_SIZE*(total_pf_count+total_vf_count) :
                                                                      ((total_pf_count==1 & total_vf_count==0) ? 2048 : 4096);
  localparam MSIX_TABLE_DEPTH_PER_FUNC = 2048;

  localparam MSIX_TABLE_ADDR_WIDTH     = $clog2(MSIX_TABLE_DEPTH) == 0 ? 1 : $clog2(MSIX_TABLE_DEPTH);
  localparam PF_NUM_WIDTH              = $clog2(total_pf_count) == 0 ? 1 : $clog2(total_pf_count);
  localparam VF_NUM_WIDTH              = $clog2(total_vf_count) == 0 ? 1 : $clog2(total_vf_count);

  localparam PBA_SIZE = (MSIX_TABLE_DEPTH%64) == 0 ? MSIX_TABLE_DEPTH/64 : (MSIX_TABLE_DEPTH/64)+1;
  localparam PBA_DEPTH = $clog2(PBA_SIZE)==0 ? 1 : $clog2(PBA_SIZE);

  localparam CTRLSHADOW_DEPTH      = total_pf_count+total_vf_count;
  localparam CTRLSHADOW_ADDR_WIDTH = $clog2(CTRLSHADOW_DEPTH) == 0 ? 1 : $clog2(CTRLSHADOW_DEPTH);

  localparam PFIFO_WIDTH = MSIX_TABLE_ADDR_WIDTH + PF_NUM_WIDTH + VF_NUM_WIDTH + CTRLSHADOW_ADDR_WIDTH + 1 + SS_PWIDTH;
  localparam PFIFO_DEPTH = MSIX_TABLE_DEPTH < 4 ? 4 : MSIX_TABLE_DEPTH+2;

  localparam FLRFIFO_WIDTH = 3 + 11 + 1;
  localparam FLRFIFO_DEPTH = $clog2(total_pf_count+total_vf_count)==0 ? 1 : $clog2(total_pf_count+total_vf_count);

  localparam MAX_PF_COUNT = 8;
  localparam MAX_VF_COUNT = 2048;

  localparam SIZE_REG_DEPTH      = total_pf_count+total_vf_count;
  localparam SIZE_REG_ADDR_WIDTH = $clog2(SIZE_REG_DEPTH) == 0 ? 1 : $clog2(SIZE_REG_DEPTH);

  enum {LITE_WAIT4BRDY, LITE_WAIT4BRESP, LITE_WAIT4WDATA, LITE_WIDLE} lite_wstate;
  enum {LITE_WAIT4RRDY, LITE_WAIT4RRESP, LITE_RIDLE} lite_rstate;
  typedef enum {REQ, INTC, HOST, NONE, FLR} mstr_arb;
  mstr_arb access, access_d;
  enum {CPL_DONE, CPL_WAIT4SB, CPL_HOLD, CPL_OUT, FORM_DATA2, FORM_DATA, WAIT4DATA, WAIT4OFFSET, IDLE} Host_cpl_state;
  enum {ERR_DONE, ERR_WAIT4CPL, ERR_WAIT4DONE, ERR_RPT, ERR_IDLE} Err_rpt_state;
  enum {VF_ERR_WAIT4CPL, VF_ERR_WAIT4RDY, VF_ERR_RPT, VF_ERR_IDLE} VF_Err_rpt_state;
  enum {LITERD, LITE, TXREQ, TX, NOREQ} req_access;
  enum {GEN_DROP, GEN_REQ, GEN_DECODE, GEN_IDLE} GenCtrl_state;
  enum {PBA_END, PBA_WR, PBA_WAIT4DATA, PBA_RD, PBA_RD_INIT, PBA_VEC_CAL, PBA_RANGE_CHK, PBA_WAIT4OFFSET, PBA_WAIT4GRANT2, PBA_WAIT4GRANT, PBA_WAIT4REQGRANT, PBA_IDLE} pba_state;
  enum {MSIX_END, MSIX_WAIT4DATA, MSIX_RD, MSIX_WAIT4GRANT, MSIX_WAIT4REQGRANT, MSIX_IDLE} msix_state;
  enum {INTC_HOLD, INTC_INT_OUT, INTC_WR, INTC_WAIT4DATA, INTC_WAIT4GRANT, INTC_CAPTURE, INTC_IDLE} Intc_state;
  enum {FLR_HOLD, FLR_CMPL, FLR_WAIT4VFCMPL, FLR_INIT_VF, FLR_WAIT4VFOFFSET, FLR_GETVFOFFSET, FLR_WAIT4CMPL, FLR_WAIT4OFFSET, FLR_WAIT4GRANT, FLR_VECNUMCALC, FLR_IDLE} Flr_state;
  enum {FLR_MSIX_HOLD, FLR_MSIX_CLEAR, FLR_MSIX_IDLE} Flr_msix_state;
  enum {FLR_PBA_HOLD, FLR_PBA_CLEAR, FLR_PBA_INITIATE, FLR_PBA_IDLE} Flr_pba_state;

  enum {SIZE_WR_ACCESS2, SIZE_WR_ACCESS, SIZE_WR_DECODE, SIZE_WR_IDLE} Size_wr_state;
  enum {SIZE_RD_DONE, SIZE_RD_WAIT4DATA2, SIZE_RD_WAIT4DATA, SIZE_RD_CONFLICT2, SIZE_RD_CONFLICT, SIZE_RD_ACCESS2, SIZE_RD_ACCESS, SIZE_RD_DECODE, SIZE_RD_IDLE} Size_rd_state;
  enum {OFFSET_WR_POPULATE, OFFSET_WR_INIT, OFFSET_WR_PRE_INIT, OFFSET_WR_IDLE} Offset_wr_state;
  enum {HOST_OFFSET_DONE, HOST_OFFSET_CHK_DONE, HOST_OFFSET_DECODE3, HOST_OFFSET_DECODE2, HOST_OFFSET_DECODE1, HOST_OFFSET_WAIT4DATA, HOST_OFFSET_IDLE} Host_offset_state;

  localparam HDR_WIDTH           = 128;
  localparam DATA_WIDTH          = 64;
  localparam PRFX_VALID_WIDTH    = 1;
  localparam BAR_NUM_WIDTH       = 3;
  localparam SLOT_NUM_WIDTH      = 5;
  localparam PFNUM_WIDTH         = 3;
  localparam VFNUM_WIDTH         = 11;
  localparam VF_ACTIVE_WIDTH     = 1;
  localparam UNMAPPED_ADDR_WIDTH = 64;
  localparam SOP_WIDTH           = 1;
  localparam MSIX_SZ_VALID_WIDTH = 1;

  localparam PF0_VF_BASE = total_pf_count;
  localparam PF1_VF_BASE = pf0_vf_count + PF0_VF_BASE;
  localparam PF2_VF_BASE = pf1_vf_count + PF1_VF_BASE;
  localparam PF3_VF_BASE = pf2_vf_count + PF2_VF_BASE;
  localparam PF4_VF_BASE = pf3_vf_count + PF3_VF_BASE;
  localparam PF5_VF_BASE = pf4_vf_count + PF4_VF_BASE;
  localparam PF6_VF_BASE = pf5_vf_count + PF5_VF_BASE;
  localparam PF7_VF_BASE = pf6_vf_count + PF6_VF_BASE;

  localparam PF0_VF_OFFSET = 0;
  localparam PF1_VF_OFFSET = PF0_VF_OFFSET + pf0_vf_count;
  localparam PF2_VF_OFFSET = PF1_VF_OFFSET + pf1_vf_count;
  localparam PF3_VF_OFFSET = PF2_VF_OFFSET + pf2_vf_count;
  localparam PF4_VF_OFFSET = PF3_VF_OFFSET + pf3_vf_count;
  localparam PF5_VF_OFFSET = PF4_VF_OFFSET + pf4_vf_count;
  localparam PF6_VF_OFFSET = PF5_VF_OFFSET + pf5_vf_count;
  localparam PF7_VF_OFFSET = PF6_VF_OFFSET + pf6_vf_count;


  wire [HDR_WIDTH+DATA_WIDTH+PRFX_VALID_WIDTH+SS_PWIDTH+BAR_NUM_WIDTH+SLOT_NUM_WIDTH+PFNUM_WIDTH+VFNUM_WIDTH+VF_ACTIVE_WIDTH+UNMAPPED_ADDR_WIDTH+SOP_WIDTH+MSIX_SZ_VALID_WIDTH-1:0] st_rx_data_pipe;
  wire                                                                                                                                                          st_rx_valid_pipe;
  wire                                                                                                                                                          st_rx_ready;
  reg                                                                                                                                                           st_rx_valid;
  wire                                                                                                                                                          st_rx_sop_pipe;

  reg [HDR_WIDTH-1:0]                          st_rx_hdr;
  reg [31:0]                                   st_rx_hdr_addr;
  reg [DATA_WIDTH-1:0]                         st_rx_data;
  reg                                          st_rx_pvalid;
  reg [SS_PWIDTH-1:0]                          st_rx_prefix;
  reg [BAR_NUM_WIDTH-1:0]                      st_rx_bar_num;
  reg [SLOT_NUM_WIDTH-1:0]                     st_rx_slot_num;
  reg [PFNUM_WIDTH-1:0]                        st_rx_pf_num;
  reg [VFNUM_WIDTH-1:0]                        st_rx_vf_num;
  reg                                          st_rx_vf_active;
  reg [UNMAPPED_ADDR_WIDTH-1:0]                st_rx_unmapped_hdr_addr;
  reg                                          st_rx_msix_size_valid;

  reg  [VFNUM_WIDTH+PFNUM_WIDTH-1:0]           cumulative_st_rx_vf_num;

  reg  [$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:0] vf_pba_bit_offset;
  reg  [$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:0] vf_pba_end_bit;
  reg  [$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:0] pf_pba_bit_offset;
  reg  [$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:0] pf_pba_end_bit;
  reg  [6:0]                                   pba_valid_bit;


  reg                                          msix_wren [3:0];
  reg                                          msix_rden, msix_rden_d;
  reg [31:0]                                   msix_wdata[3:0];
  reg [31:0]                                   msix_rdata[3:0];
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]              msix_waddr;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]              msix_raddr;

  reg                                          pba_wren [1:0];
  reg                                          pba_rden, pba_rden_d;
  reg [31:0]                                   pba_wdata[1:0];
  reg [31:0]                                   pba_rdata[1:0];
  reg [PBA_DEPTH-1:0]                          pba_waddr;
  reg [PBA_DEPTH-1:0]                          pba_raddr;

  reg [63:0]                                   pba_pending_bit;
  reg [31:0]                                   pba_pending[1:0];
  reg                                          pba_bit_set;
  reg                                          pba_in_progress;
  reg [PF_NUM_WIDTH-1:0]                       pba_pf_num;
  reg [VF_NUM_WIDTH-1:0]                       pba_vf_num;
  reg [CTRLSHADOW_ADDR_WIDTH-1:0]              pba_cumulative_vf_num;
  reg                                          pba_vf_active;
  reg [SS_PWIDTH-1:0]                          pba_prefix;
  reg [$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:0]  pba_vec_num;
  reg [1:0]                                    pba_cycle_cnt;
  reg [1:0]                                    pba_offset_cycle_cnt;
  reg                                          pba_requester;
  reg                                          pba_chk_offset_valid;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]              pba_chk_offset_range;

  reg  [PFIFO_WIDTH-1:0]                       pfifo_wdata;
  reg                                          pfifo_wrreq;
  reg                                          pfifo_rdreq;
  wire [PFIFO_WIDTH-1:0]                       pfifo_rdata;
  wire                                         pfifo_full;
  wire                                         pfifo_empty;
  wire                                         pfifo_almost_full;
  reg                                          intc_valid;

  reg  [$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:0] intc_vec_num;
  wire                                         intc_bme;
  wire                                         intc_msix_en;
  wire                                         intc_msix_mask;
  wire [CTRLSHADOW_ADDR_WIDTH-1:0]             intc_ctrlshadow_addr;
  reg  [63:0]                                  intc_pending_bit;
  reg  [63:0]                                  intc_pba_wdata;
  reg  [63:0]                                  intc_pba_bit_clr;
  reg                                          intc_in_progress;
  reg  [2:0]                                   intc_cycle_cnt;
  reg                                          intc_rd_en;

  reg                                          host_pba_1st_access;
  reg                                          mem_data_sel;
  reg [63:0]                                   mem_data;

  reg [MSIX_TABLE_ADDR_WIDTH-1:0]              rst_req_msix_waddr;
  reg [PBA_DEPTH-1:0]                          rst_req_pba_waddr;
  reg [SIZE_REG_ADDR_WIDTH-1:0]                rst_req_size_waddr;

  reg                                          flrfifo_rdreq;
  wire                                         flrfifo_empty;
  wire [FLRFIFO_WIDTH-1:0]                     flrfifo_rdata;
  reg                                          flr_valid;

  logic                                        flrcmpl_fifo_tready;
  logic                                        flrcmpl_fifo_tvalid;
  logic [19:0]                                 flrcmpl_fifo_tdata;

  reg [MSIX_TABLE_ADDR_WIDTH-1:0]              flr_pf_vec_num_start;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]              flr_pf_vec_num_end;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]              flr_vf_vec_num_start;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]              flr_vf_vec_num_end;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]              flr_pf_vf_vec_num_start;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]              flr_pf_vf_vec_num_end;
  reg [11-1:0]                                 flr_pf_vf_count;
  reg [$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:0]  flr_vec_num_start;
  reg [$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:0]  flr_vec_num_end;
  reg                                          flr_vf_vec_num_valid;
  reg [2:0]                                    flr_pf_num;
  reg [11-1:0]                                 flr_vf_num;
  reg                                          flr_vf_active;
  reg                                          flr_cycle_cnt;

  reg                                          flr_pba_initiate;
  reg                                          flr_pba_completed;
  reg [PBA_DEPTH-1:0]                          flr_pba_raddr;
  reg [PBA_DEPTH-1:0]                          flr_pba_raddr_d1, flr_pba_raddr_d2, flr_pba_raddr_d3;
  reg                                          flr_pba_rden;
  reg [PBA_DEPTH-1:0]                          flr_pba_waddr;
  reg                                          flr_pba_wren;
  reg [63:0]                                   flr_pba_wdata;
  reg [1:0]                                    flr_pba_cycle_cnt;

  reg                                          flr_msix_initiate;
  reg                                          flr_msix_completed;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]              flr_msix_waddr;
  reg                                          flr_msix_wren;

  reg                                          size_wren;
  reg [SIZE_REG_ADDR_WIDTH-1:0]                size_waddr;
  reg [11:0]                                   size_wdata;
  reg                                          size_rden;
  reg [SIZE_REG_ADDR_WIDTH-1:0]                size_raddr;
  reg [11:0]                                   size_rdata;

  reg                                          offset_size_rden;
  reg [SIZE_REG_ADDR_WIDTH-1:0]                offset_size_raddr, offset_size_raddr_d1, offset_size_raddr_d2, offset_size_raddr_d3;
  reg [2:0]                                    h2c_size_req_pf;
  reg [SIZE_REG_ADDR_WIDTH-1:0]                h2c_size_req_vf;
  reg                                          host_size_rden;
  reg [SIZE_REG_ADDR_WIDTH-1:0]                host_size_raddr;
  reg [1:0]                                    host_size_rd_valid;
  reg                                          lite_size_rden;
  reg [SIZE_REG_ADDR_WIDTH-1:0]                lite_size_raddr;
  reg [1:0]                                    lite_rd_wait4data_cycle;

  reg [MSIX_TABLE_ADDR_WIDTH*2-1+1:0]          offset_wdata;
  reg                                          offset_wren;
  reg [SIZE_REG_ADDR_WIDTH-1:0]                offset_waddr;
  reg [1:0]                                    offset_wr_cycle_cnt;
  reg                                          offset_rden;
  reg [SIZE_REG_ADDR_WIDTH-1:0]                offset_raddr;
  reg [MSIX_TABLE_ADDR_WIDTH*2-1+1:0]          offset_rdata;

  reg                                          host_offset_rden;
  reg [SIZE_REG_ADDR_WIDTH-1:0]                host_offset_raddr;
  reg [SIZE_REG_ADDR_WIDTH-1:0]                tx_offset_raddr;
  reg [SIZE_REG_ADDR_WIDTH-1:0]                txreq_offset_raddr;
  reg                                          req_offset_rden;
  reg [SIZE_REG_ADDR_WIDTH-1:0]                req_offset_raddr;
  reg                                          flr_offset_rden;
  reg [SIZE_REG_ADDR_WIDTH-1:0]                flr_offset_raddr;

  reg [VFNUM_WIDTH+PFNUM_WIDTH-1:0]            cumulative_flr_vf_num;
  reg [1:0]                                    flr_offset_cycle_cnt;
  reg [11-1:0]                                 flr_pf_vf_start;
  reg [11-1:0]                                 flr_pf_vf_end;
  reg [11-1:0]                                 flr_pf_vf_offset;

  wire                                         stclk_rst_n_1;
  wire                                         stclk_rst_n_2;
  wire                                         stclk_rst_n_3;

  wire                                         liteclk_rst_n_1;

  altera_std_synchronizer u_rst_stclk_sync1 (.clk(axi_st_clk), .reset_n(st_areset_n), .din(1'b1), .dout(stclk_rst_n_1));
  altera_std_synchronizer u_rst_stclk_sync2 (.clk(axi_st_clk), .reset_n(st_areset_n), .din(1'b1), .dout(stclk_rst_n_2));
  altera_std_synchronizer u_rst_stclk_sync3 (.clk(axi_st_clk), .reset_n(st_areset_n), .din(1'b1), .dout(stclk_rst_n_3));

  altera_std_synchronizer u_rst_liteclk_sync1 (.clk(axi_lite_clk), .reset_n(lite_areset_n), .din(1'b1), .dout(liteclk_rst_n_1));

  /*--------------- Ctrlshadow -----------------*/

  reg [CTRLSHADOW_ADDR_WIDTH-1:0] ctrlshadow_cumulative_vf_num;
  always @* begin
    case (ctrlshadow_tdata[2:0])
    3'b000 : ctrlshadow_cumulative_vf_num = PF0_VF_BASE + ctrlshadow_tdata[13:3];
    3'b001 : ctrlshadow_cumulative_vf_num = PF1_VF_BASE + ctrlshadow_tdata[13:3];
    3'b010 : ctrlshadow_cumulative_vf_num = PF2_VF_BASE + ctrlshadow_tdata[13:3];
    3'b011 : ctrlshadow_cumulative_vf_num = PF3_VF_BASE + ctrlshadow_tdata[13:3];
    3'b100 : ctrlshadow_cumulative_vf_num = PF4_VF_BASE + ctrlshadow_tdata[13:3];
    3'b101 : ctrlshadow_cumulative_vf_num = PF5_VF_BASE + ctrlshadow_tdata[13:3];
    3'b110 : ctrlshadow_cumulative_vf_num = PF6_VF_BASE + ctrlshadow_tdata[13:3];
    3'b111 : ctrlshadow_cumulative_vf_num = PF7_VF_BASE + ctrlshadow_tdata[13:3];
    endcase
  end

  localparam CTRLSHADOW_SYNC_WIDTH = 1+1+1+1+CTRLSHADOW_ADDR_WIDTH+3;
  localparam CTRLSHADOW_SYNC_DEPTH = 2;
  wire [CTRLSHADOW_SYNC_WIDTH-1:0]  ctrlshadow_tdata_in = {ctrlshadow_tdata[22:20],ctrlshadow_tdata[14],ctrlshadow_cumulative_vf_num,ctrlshadow_tdata[2:0]};
  wire [CTRLSHADOW_SYNC_WIDTH-1:0]  ctrlshadow_tdata_sync;
  reg                               ctrlshadow_tvalid_sync;
  wire                              ctrlshadow_fifo_empty;

  dcfifo #(
  .lpm_width                ( CTRLSHADOW_SYNC_WIDTH                                               ),
  .lpm_widthu               ( CTRLSHADOW_SYNC_DEPTH                                               ),
  .lpm_numwords             ( 2**CTRLSHADOW_SYNC_DEPTH                                            ),
  .overflow_checking        ( "OFF"                                                               ),
  .underflow_checking       ( "OFF"                                                               ),
  .ram_block_type           ( "AUTO"                                                              )
  ) u_ctrlshadow_dcfifo (
  .aclr                     ( ~stclk_rst_n_2                                                      ),
  .wrclk                    ( axi_lite_clk                                                        ),
  .data                     ( ctrlshadow_tdata_in                                                 ),
  .wrreq                    ( ctrlshadow_tvalid                                                   ),
  .wrusedw                  (                                                                     ),
  .wrempty                  (                                                                     ),
  .wrfull                   (                                                                     ),
  .rdclk                    ( axi_st_clk                                                          ),
  .rdreq                    ( ~ctrlshadow_fifo_empty                                              ),
  .rdfull                   (                                                                     ),
  .rdempty                  ( ctrlshadow_fifo_empty                                               ),
  .rdusedw                  (                                                                     ),
  .q                        ( ctrlshadow_tdata_sync                                               ),
  .eccstatus                (                                                                     )
  );

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1)
      ctrlshadow_tvalid_sync <= 0;
    else
      ctrlshadow_tvalid_sync <= ~ctrlshadow_fifo_empty ? 1'b1 : 1'b0;
  end

  reg                                 ctrlshadow_wren;
  reg [2:0]                           ctrlshadow_wdata;
  reg [CTRLSHADOW_ADDR_WIDTH - 1 : 0] ctrlshadow_waddr;
  reg                                 ctrlshadow_rden;
  reg [CTRLSHADOW_ADDR_WIDTH - 1 : 0] ctrlshadow_raddr;
  wire [2:0]                          ctrlshadow_rdata;

  reg [CTRLSHADOW_ADDR_WIDTH - 1 : 0] rst_req_ctrlshadow_waddr;

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      ctrlshadow_wren  <= 0;
      ctrlshadow_wdata <= 0;
      ctrlshadow_waddr <= 0;
    end
    else begin
      if (ctrlshadow_tvalid_sync) begin
        ctrlshadow_wren <= 1'b1;
        ctrlshadow_wdata <= {ctrlshadow_tdata_sync[3+CTRLSHADOW_ADDR_WIDTH+1 +:3]};
        ctrlshadow_waddr <= ctrlshadow_tdata_sync[3+CTRLSHADOW_ADDR_WIDTH] /*vf_active*/ ? ctrlshadow_tdata_sync[3+:CTRLSHADOW_ADDR_WIDTH] : ctrlshadow_tdata_sync[2:0];
      end
      else
        ctrlshadow_wren <= 1'b0;
    end
  end

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1)
      rst_req_ctrlshadow_waddr  <= 0;
    else
      if (subsystem_rst_req)
        rst_req_ctrlshadow_waddr  <= rst_req_ctrlshadow_waddr==(2**CTRLSHADOW_ADDR_WIDTH-1) ? rst_req_ctrlshadow_waddr : rst_req_ctrlshadow_waddr+1;
  end

  altera_syncram #(
    .width_a                              ( 3                                                                      ),
    .widthad_a                            ( CTRLSHADOW_ADDR_WIDTH                                                  ),
    .widthad2_a                           ( CTRLSHADOW_ADDR_WIDTH                                                  ),
    .numwords_a                           ( 2**CTRLSHADOW_ADDR_WIDTH                                               ),
    .outdata_reg_a                        ( "CLOCK0"                                                               ),
    .address_aclr_a                       ( "NONE"                                                                 ),
    .outdata_aclr_a                       ( "NONE"                                                                 ),
    .width_byteena_a                      ( 1                                                                      ),

    .width_b                              ( 3                                                                      ),
    .widthad_b                            ( CTRLSHADOW_ADDR_WIDTH                                                  ),
    .widthad2_b                           ( CTRLSHADOW_ADDR_WIDTH                                                  ),
    .numwords_b                           ( 2**CTRLSHADOW_ADDR_WIDTH                                               ),
    .rdcontrol_reg_b                      ( "CLOCK0"                                                               ),
    .address_reg_b                        ( "CLOCK0"                                                               ),
    .outdata_reg_b                        ( "CLOCK0"                                                               ),
    .outdata_aclr_b                       ( "CLEAR0"                                                               ),
    .indata_reg_b                         ( "CLOCK0"                                                               ),
    .byteena_reg_b                        ( "CLOCK0"                                                               ),
    .address_aclr_b                       ( "NONE"                                                                 ),
    .width_byteena_b                      ( 1                                                                      ),

    .clock_enable_input_a                 ( "BYPASS"                                                               ),
    .clock_enable_output_a                ( "BYPASS"                                                               ),
    .clock_enable_input_b                 ( "BYPASS"                                                               ),
    .clock_enable_output_b                ( "BYPASS"                                                               ),
    .clock_enable_core_a                  ( "BYPASS"                                                               ),
    .clock_enable_core_b                  ( "BYPASS"                                                               ),

    .operation_mode                       ( "DUAL_PORT"                                                            ),
    .optimization_option                  ( "AUTO"                                                                 ),
    .ram_block_type                       ( "AUTO"                                                                 ),
    .intended_device_family               ( DEVICE_FAMILY                                                          ),
    .read_during_write_mode_port_b        ( "OLD_DATA"                                                             ),
    .read_during_write_mode_mixed_ports   ( "OLD_DATA"                                                             )
    ) u_ctrlshadow (
    .wren_a                               ( subsystem_rst_req ? 1'b1 : ctrlshadow_wren                             ),
    .wren_b                               ( 1'b0                                                                   ),
    .rden_a                               ( 1'b0                                                                   ),
    .rden_b                               ( ctrlshadow_rden                                                        ),
    .data_a                               ( subsystem_rst_req ? 3'b000 : ctrlshadow_wdata                          ),
    .data_b                               ( 3'b000                                                                 ),
    .address_a                            ( subsystem_rst_req ? rst_req_ctrlshadow_waddr : ctrlshadow_waddr        ),
    .address_b                            ( ctrlshadow_raddr                                                       ),
    .clock0                               ( axi_st_clk                                                             ),
    .clock1                               ( 1'b1                                                                   ),
    .clocken0                             ( 1'b1                                                                   ),
    .clocken1                             ( 1'b1                                                                   ),
    .clocken2                             ( 1'b1                                                                   ),
    .clocken3                             ( 1'b1                                                                   ),
    .aclr0                                ( ~stclk_rst_n_1                                                           ),
    .aclr1                                ( 1'b0                                                                   ),
    .byteena_a                            ( 1'b1                                                                   ),
    .byteena_b                            ( 1'b1                                                                   ),
    .addressstall_a                       ( 1'b0                                                                   ),
    .addressstall_b                       ( 1'b0                                                                   ),
    .sclr                                 ( 1'b0                                                                   ),
    .eccencbypass                         ( 1'b0                                                                   ),
    .eccencparity                         ( 8'b0                                                                   ),
    .eccstatus                            (                                                                        ),
    .address2_a                           ( {CTRLSHADOW_ADDR_WIDTH{1'b1}}                                          ),
    .address2_b                           ( {CTRLSHADOW_ADDR_WIDTH{1'b1}}                                          ),
    .q_a                                  (                                                                        ),
    .q_b                                  ( ctrlshadow_rdata                                                       )
    );


  /*--------------- HOST access -----------------*/

  reg                                                 host_valid;
  reg                                                 host_rd;
  reg                                                 host_wr;
  reg [HDR_WIDTH-1:0]                                 host_hdr;
  reg [BAR_NUM_WIDTH-1:0]                             host_bar_num;
  reg [SLOT_NUM_WIDTH-1:0]                            host_slot_num;
  reg [2:0]                                           host_pf_num;
  reg [10:0]                                          host_vf_num;
  reg                                                 host_vf_active;
  reg [31:0]                                          host_hdr_addr;
  reg                                                 host_pvalid;
  reg [SS_PWIDTH-1:0]                                 host_prefix;
  reg [UNMAPPED_ADDR_WIDTH-1:0]                       host_unmapped_hdr_addr;
  reg                                                 host_msix_size_valid;

  reg [DATA_WIDTH-1:0]                                host_wdata;
  reg                                                 host_msix_table_access;
  reg                                                 host_pba_access;
  reg                                                 host_access_err;
  reg [MSIX_TABLE_ADDR_WIDTH-1+4:0]                   host_msix_addr;
  reg [PBA_DEPTH-1:0]                                 host_pba_addr;
  reg                                                 host_pba_2nd_rd;
  reg [11:0]                                          host_pba_bit_offset;
  reg [6:0]                                           host_pba_valid_bit;
  reg                                                 host_sideband_err_rpt_done;
  reg                                                 host_err_rpt_cpl_done;
  reg                                                 host_in_progress;

  reg [MSIX_TABLE_ADDR_WIDTH-1:0]                     host_msix_table_size;
  reg [1:0]                                           host_offset_cycle_cnt;
  reg [$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:0]         host_pba_end_bit;
  reg [31:0]                                          host_access_addr;
  reg [1:0]                                           host_access_length;
  reg [63:0]                                          host_access_wdata;
  reg                                                 host_offset_ready;
  reg                                                 host_access_rd;
  reg                                                 host_access_wr;

  reg                                                 cpl_error;
  reg [HDR_WIDTH-1:0]                                 cpl_hdr;
  reg [BAR_NUM_WIDTH-1:0]                             cpl_bar_num;
  reg [SLOT_NUM_WIDTH-1:0]                            cpl_slot_num;
  reg [2:0]                                           cpl_pf_num;
  reg [10:0]                                          cpl_vf_num;
  reg                                                 cpl_vf_active;
  reg                                                 cpl_msix_size_valid;
  reg [6:0]                                           cpl_lower_addr;
  reg                                                 cpl_length;
  reg [3:0]                                           cpl_byte_addr;
  reg [5:0]                                           cpl_pba_bit_offset;
  reg                                                 cpl_pba_2nd_rd;
  reg [6:0]                                           cpl_pba_valid_bit;
  reg                                                 cpl_cycle_cnt;

  ofs_fim_axis_register #(
  .MODE              ( 2                                            ),
  .ENABLE_TKEEP      ( 0                                            ),
  .ENABLE_TLAST      ( 0                                            ),
  .TDATA_WIDTH       ( HDR_WIDTH+DATA_WIDTH+PRFX_VALID_WIDTH+SS_PWIDTH+BAR_NUM_WIDTH+SLOT_NUM_WIDTH+PFNUM_WIDTH+VFNUM_WIDTH+VF_ACTIVE_WIDTH+UNMAPPED_ADDR_WIDTH+SOP_WIDTH+MSIX_SZ_VALID_WIDTH )
  ) u_st_rx_pipeline (
  .clk               ( axi_st_clk                                   ),
  .rst_n             ( stclk_rst_n_1                                ),

  .s_tready          ( intc_rx_st_ready                             ),
  .s_tvalid          ( intc_rx_st_valid                             ),
  .s_tdata           ( {intc_rx_st_msix_size_valid,intc_rx_st_sop,intc_rx_st_unmapped_hdr_addr,intc_rx_st_vf_active,intc_rx_st_vf_num,intc_rx_st_pf_num,intc_rx_st_slot_num,intc_rx_st_bar_num,intc_rx_st_prefix,intc_rx_st_pvalid,intc_rx_st_data,intc_rx_st_hdr} ),
  .s_tkeep           ( ),
  .s_tlast           ( ),
  .s_tid             ( ),
  .s_tdest           ( ),
  .s_tuser           ( ),

  .m_tready          ( st_rx_ready                                  ),
  .m_tvalid          ( st_rx_valid_pipe                             ),
  .m_tdata           ( st_rx_data_pipe                              ),
  .m_tkeep           ( ),
  .m_tlast           ( ),
  .m_tid             ( ),
  .m_tdest           ( ),
  .m_tuser           ( )
  );

  assign st_rx_sop_pipe = st_rx_data_pipe[0+HDR_WIDTH+DATA_WIDTH+1+SS_PWIDTH+BAR_NUM_WIDTH+SLOT_NUM_WIDTH+PFNUM_WIDTH+VFNUM_WIDTH+1+UNMAPPED_ADDR_WIDTH];

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      st_rx_hdr               <= 0;
      st_rx_hdr_addr          <= 0;
      st_rx_data              <= 0;
      st_rx_pvalid            <= 0;
      st_rx_prefix            <= 0;
      st_rx_bar_num           <= 0;
      st_rx_slot_num          <= 0;
      st_rx_pf_num            <= 0;
      st_rx_vf_num            <= 0;
      st_rx_vf_active         <= 0;
      st_rx_unmapped_hdr_addr <= 0;
      st_rx_msix_size_valid   <= 1;
      st_rx_valid             <= 0;
    end
    else begin
      if (st_rx_valid_pipe & st_rx_sop_pipe & st_rx_ready) begin
        st_rx_hdr               <= st_rx_data_pipe[0+:HDR_WIDTH];
        st_rx_hdr_addr          <= st_rx_data_pipe[29] ? { st_rx_data_pipe[127:98], 2'b0 } : st_rx_data_pipe[95:64];
        st_rx_data              <= st_rx_data_pipe[0+HDR_WIDTH +:DATA_WIDTH];
        st_rx_pvalid            <= st_rx_data_pipe[0+HDR_WIDTH+DATA_WIDTH +:1];
        st_rx_prefix            <= st_rx_data_pipe[0+HDR_WIDTH+DATA_WIDTH+1 +:SS_PWIDTH];
        st_rx_bar_num           <= st_rx_data_pipe[0+HDR_WIDTH+DATA_WIDTH+1+SS_PWIDTH +:BAR_NUM_WIDTH];
        st_rx_slot_num          <= st_rx_data_pipe[0+HDR_WIDTH+DATA_WIDTH+1+SS_PWIDTH+BAR_NUM_WIDTH +:SLOT_NUM_WIDTH];
        st_rx_pf_num            <= st_rx_data_pipe[0+HDR_WIDTH+DATA_WIDTH+1+SS_PWIDTH+BAR_NUM_WIDTH+SLOT_NUM_WIDTH +:PFNUM_WIDTH];
        st_rx_vf_num            <= st_rx_data_pipe[0+HDR_WIDTH+DATA_WIDTH+1+SS_PWIDTH+BAR_NUM_WIDTH+SLOT_NUM_WIDTH+PFNUM_WIDTH +:VFNUM_WIDTH];
        st_rx_vf_active         <= st_rx_data_pipe[0+HDR_WIDTH+DATA_WIDTH+1+SS_PWIDTH+BAR_NUM_WIDTH+SLOT_NUM_WIDTH+PFNUM_WIDTH+VFNUM_WIDTH +:1];
        st_rx_unmapped_hdr_addr <= st_rx_data_pipe[0+HDR_WIDTH+DATA_WIDTH+1+SS_PWIDTH+BAR_NUM_WIDTH+SLOT_NUM_WIDTH+PFNUM_WIDTH+VFNUM_WIDTH+1 +:UNMAPPED_ADDR_WIDTH];
        st_rx_msix_size_valid   <= st_rx_data_pipe[0+HDR_WIDTH+DATA_WIDTH+1+SS_PWIDTH+BAR_NUM_WIDTH+SLOT_NUM_WIDTH+PFNUM_WIDTH+VFNUM_WIDTH+1+UNMAPPED_ADDR_WIDTH +1+:1];
        st_rx_valid             <= 1'b1;
      end
      else
        st_rx_valid             <= st_rx_ready ? 1'b0 : st_rx_valid;
    end
  end

  wire [PFNUM_WIDTH-1:0] st_rx_pf_num_pipe = st_rx_data_pipe[0+HDR_WIDTH+DATA_WIDTH+1+SS_PWIDTH+BAR_NUM_WIDTH+SLOT_NUM_WIDTH +:PFNUM_WIDTH];
  wire [VFNUM_WIDTH-1:0] st_rx_vf_num_pipe = st_rx_data_pipe[0+HDR_WIDTH+DATA_WIDTH+1+SS_PWIDTH+BAR_NUM_WIDTH+SLOT_NUM_WIDTH+PFNUM_WIDTH +:VFNUM_WIDTH];

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1)
      cumulative_st_rx_vf_num <= 0;
    else begin
      if (st_rx_valid_pipe & st_rx_ready) begin
        case (st_rx_pf_num_pipe)
        3'b000 : cumulative_st_rx_vf_num <= PF0_VF_BASE + st_rx_vf_num_pipe;
        3'b001 : cumulative_st_rx_vf_num <= PF1_VF_BASE + st_rx_vf_num_pipe;
        3'b010 : cumulative_st_rx_vf_num <= PF2_VF_BASE + st_rx_vf_num_pipe;
        3'b011 : cumulative_st_rx_vf_num <= PF3_VF_BASE + st_rx_vf_num_pipe;
        3'b100 : cumulative_st_rx_vf_num <= PF4_VF_BASE + st_rx_vf_num_pipe;
        3'b101 : cumulative_st_rx_vf_num <= PF5_VF_BASE + st_rx_vf_num_pipe;
        3'b110 : cumulative_st_rx_vf_num <= PF6_VF_BASE + st_rx_vf_num_pipe;
        3'b111 : cumulative_st_rx_vf_num <= PF7_VF_BASE + st_rx_vf_num_pipe;
      endcase
      end
    end
  end

  generate
  if (MSIX_VECTOR_ALLOC=="Static")
  begin
    wire [6:0] st_rx_pba_addr = st_rx_data_pipe[29] ?
                                  { st_rx_data_pipe[127:98], 2'b0 } - MSIX_TABLE_SIZE*16 :
                                  st_rx_data_pipe[95:64] - MSIX_TABLE_SIZE*16;

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        pf_pba_bit_offset <= 0;
        pf_pba_end_bit    <= 0;
      end
      else begin
        if (st_rx_valid_pipe & st_rx_ready) begin
          pf_pba_bit_offset <= MSIX_TABLE_SIZE*st_rx_pf_num_pipe + {st_rx_pba_addr,3'b000};
          pf_pba_end_bit    <= MSIX_TABLE_SIZE*st_rx_pf_num_pipe + {st_rx_pba_addr,3'b000} +
                              (st_rx_data_pipe[1:0]*32 > (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) ? (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) : st_rx_data_pipe[1:0]*32) - 1;
        end
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        vf_pba_bit_offset <= 0;
      else begin
        if (st_rx_valid_pipe & st_rx_ready) begin
          case (st_rx_pf_num_pipe)
          3'b000 : vf_pba_bit_offset <= MSIX_TABLE_SIZE*(PF0_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000};
          3'b001 : vf_pba_bit_offset <= MSIX_TABLE_SIZE*(PF1_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000};
          3'b010 : vf_pba_bit_offset <= MSIX_TABLE_SIZE*(PF2_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000};
          3'b011 : vf_pba_bit_offset <= MSIX_TABLE_SIZE*(PF3_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000};
          3'b100 : vf_pba_bit_offset <= MSIX_TABLE_SIZE*(PF4_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000};
          3'b101 : vf_pba_bit_offset <= MSIX_TABLE_SIZE*(PF5_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000};
          3'b110 : vf_pba_bit_offset <= MSIX_TABLE_SIZE*(PF6_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000};
          3'b111 : vf_pba_bit_offset <= MSIX_TABLE_SIZE*(PF7_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000};
          endcase
        end
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        vf_pba_end_bit <= 0;
      else begin
        if (st_rx_valid_pipe & st_rx_ready) begin
          case (st_rx_pf_num_pipe)
          3'b000 : vf_pba_end_bit <= MSIX_TABLE_SIZE*(PF0_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000} +
                                    ({st_rx_data_pipe[1:0],5'b00000} > (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) ? (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) : {st_rx_data_pipe[1:0],5'b00000}) - 1;
          3'b001 : vf_pba_end_bit <= MSIX_TABLE_SIZE*(PF1_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000} +
                                    ({st_rx_data_pipe[1:0],5'b00000} > (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) ? (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) : {st_rx_data_pipe[1:0],5'b00000}) - 1;
          3'b010 : vf_pba_end_bit <= MSIX_TABLE_SIZE*(PF2_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000} +
                                    ({st_rx_data_pipe[1:0],5'b00000} > (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) ? (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) : {st_rx_data_pipe[1:0],5'b00000}) - 1;
          3'b011 : vf_pba_end_bit <= MSIX_TABLE_SIZE*(PF3_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000} +
                                    ({st_rx_data_pipe[1:0],5'b00000} > (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) ? (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) : {st_rx_data_pipe[1:0],5'b00000}) - 1;
          3'b100 : vf_pba_end_bit <= MSIX_TABLE_SIZE*(PF4_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000} +
                                    ({st_rx_data_pipe[1:0],5'b00000} > (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) ? (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) : {st_rx_data_pipe[1:0],5'b00000}) - 1;
          3'b101 : vf_pba_end_bit <= MSIX_TABLE_SIZE*(PF5_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000} +
                                    ({st_rx_data_pipe[1:0],5'b00000} > (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) ? (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) : {st_rx_data_pipe[1:0],5'b00000}) - 1;
          3'b110 : vf_pba_end_bit <= MSIX_TABLE_SIZE*(PF6_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000} +
                                    ({st_rx_data_pipe[1:0],5'b00000} > (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) ? (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) : {st_rx_data_pipe[1:0],5'b00000}) - 1;
          3'b111 : vf_pba_end_bit <= MSIX_TABLE_SIZE*(PF7_VF_BASE+st_rx_vf_num_pipe) + {st_rx_pba_addr,3'b000} +
                                    ({st_rx_data_pipe[1:0],5'b00000} > (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) ? (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) : {st_rx_data_pipe[1:0],5'b00000}) - 1;
        endcase
        end
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        pba_valid_bit <= 0;
      else
        if (st_rx_valid_pipe & st_rx_ready)
          pba_valid_bit <= st_rx_data_pipe[1:0]*32 > (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) ? (MSIX_TABLE_SIZE-{st_rx_pba_addr,3'b000}) : st_rx_data_pipe[1:0]*32;
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        host_valid             <= 0;
        host_rd                <= 0;
        host_wr                <= 0;
        host_hdr               <= 0;
        host_bar_num           <= 0;
        host_slot_num          <= 0;
        host_pf_num            <= 0;
        host_vf_num            <= 0;
        host_vf_active         <= 0;
        host_hdr_addr          <= 0;
        host_pvalid            <= 0;
        host_prefix            <= 0;
        host_unmapped_hdr_addr <= 0;
        host_msix_size_valid   <= 1;
        host_wdata             <= 0;
        host_msix_table_access <= 0;
        host_pba_access        <= 0;
        host_access_err        <= 0;
        host_msix_addr         <= 0;
        host_pba_addr          <= 0;
        host_pba_2nd_rd        <= 0;
        host_pba_bit_offset    <= 0;
        host_pba_valid_bit     <= 0;
      end
      else begin
        if (st_rx_valid & st_rx_ready) begin
          host_valid             <= st_rx_hdr[9:0] <= 2;
          host_rd                <= st_rx_hdr[31:30]==00 & st_rx_hdr[28:24]==00;
          host_wr                <= st_rx_hdr[31:30]==01 & st_rx_hdr[28:24]==00;
          host_hdr               <= st_rx_hdr;
          host_bar_num           <= st_rx_bar_num;
          host_slot_num          <= st_rx_slot_num;
          host_pf_num            <= st_rx_pf_num;
          host_vf_num            <= st_rx_vf_num;
          host_vf_active         <= st_rx_vf_active;
          host_hdr_addr          <= st_rx_hdr_addr;
          host_pvalid            <= st_rx_pvalid;
          host_prefix            <= st_rx_prefix;
          host_unmapped_hdr_addr <= st_rx_unmapped_hdr_addr;
          host_msix_size_valid   <= st_rx_msix_size_valid;
          host_wdata             <= st_rx_data;
          host_msix_table_access <= ~(st_rx_hdr_addr[0+:$clog2(MSIX_TABLE_SIZE+MSIX_TABLE_SIZE*16)] >= MSIX_TABLE_SIZE*16);
          host_pba_access        <= st_rx_hdr_addr[0+:$clog2(MSIX_TABLE_SIZE+MSIX_TABLE_SIZE*16)] >= MSIX_TABLE_SIZE*16;
          host_access_err        <= st_rx_hdr[9:0] > 2;
          host_msix_addr         <= st_rx_vf_active ? (MSIX_TABLE_SIZE*cumulative_st_rx_vf_num*16 + st_rx_hdr_addr[0+:$clog2(MSIX_TABLE_SIZE*16)]) :
                                                      (MSIX_TABLE_SIZE*st_rx_pf_num*16 + st_rx_hdr_addr[0+:$clog2(MSIX_TABLE_SIZE*16)]);
          host_pba_addr          <= st_rx_vf_active ? vf_pba_bit_offset[11:6] : pf_pba_bit_offset[11:6];
          host_pba_2nd_rd        <= st_rx_vf_active ? vf_pba_end_bit[11:6]!=vf_pba_bit_offset[11:6] : pf_pba_end_bit[11:6]!=pf_pba_bit_offset[11:6];
          host_pba_bit_offset    <= st_rx_vf_active ? vf_pba_bit_offset[5:0] : pf_pba_bit_offset[5:0];
          host_pba_valid_bit     <= pba_valid_bit;
        end
        else begin
          host_access_err        <= host_access_err&host_rd ? ~host_err_rpt_cpl_done : 0;
          if (access==HOST) begin
            host_valid           <= 0;
            host_pba_2nd_rd      <= 0;
          end
        end
      end
    end

    assign st_rx_ready = ((access==HOST & ~(host_pba_access&host_pba_2nd_rd)) | (~host_valid&~host_access_err)) & Err_rpt_state==ERR_IDLE & VF_Err_rpt_state==VF_ERR_IDLE;

  end
  else begin

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        host_valid             <= 0;
        host_rd                <= 0;
        host_wr                <= 0;
        host_hdr               <= 0;
        host_bar_num           <= 0;
        host_slot_num          <= 0;
        host_pf_num            <= 0;
        host_vf_num            <= 0;
        host_vf_active         <= 0;
        host_hdr_addr          <= 0;
        host_pvalid            <= 0;
        host_prefix            <= 0;
        host_unmapped_hdr_addr <= 0;
        host_msix_size_valid   <= 1;
        host_wdata             <= 0;
        host_access_err        <= 0;
        host_offset_rden       <= 0;
        host_offset_raddr      <= 0;
      end
      else begin
        if (st_rx_valid & st_rx_ready) begin
          host_valid             <= st_rx_hdr[9:0] <= 2;
          host_rd                <= st_rx_hdr[31:30]==00 & st_rx_hdr[28:24]==00;
          host_wr                <= st_rx_hdr[31:30]==01 & st_rx_hdr[28:24]==00;
          host_hdr               <= st_rx_hdr;
          host_bar_num           <= st_rx_bar_num;
          host_slot_num          <= st_rx_slot_num;
          host_pf_num            <= st_rx_pf_num;
          host_vf_num            <= st_rx_vf_num;
          host_vf_active         <= st_rx_vf_active;
          host_hdr_addr          <= st_rx_hdr_addr;
          host_pvalid            <= st_rx_pvalid;
          host_prefix            <= st_rx_prefix;
          host_unmapped_hdr_addr <= st_rx_unmapped_hdr_addr;
          host_msix_size_valid   <= st_rx_msix_size_valid;
          host_wdata             <= st_rx_data;
          host_access_err        <= st_rx_hdr[9:0] > 2;
          host_offset_rden       <= st_rx_hdr[9:0] <= 2;
          host_offset_raddr      <= st_rx_vf_active ? cumulative_st_rx_vf_num : st_rx_pf_num;
        end
        else begin
          host_access_err        <= host_access_err&host_rd ? ~host_err_rpt_cpl_done : 0;
          if (access==HOST) begin
            host_valid           <= 0;
            host_offset_rden     <= 0;
          end
        end
      end
    end

    assign st_rx_ready = ~host_in_progress & (~host_valid&~host_access_err) & Err_rpt_state==ERR_IDLE & VF_Err_rpt_state==VF_ERR_IDLE;

  end
  endgenerate

  generate
  if (MSIX_VECTOR_ALLOC=="Dynamic") begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        host_in_progress <= 0;
      else begin
        if ((host_valid & (host_rd | host_wr)) | (host_access_err & host_rd))
          host_in_progress <= 1'b1;
        else if ((host_wr & host_offset_ready) | (host_rd & Host_cpl_state==IDLE))
          host_in_progress <= 1'b0;
      end
    end
  end
  endgenerate

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      Err_rpt_state               <= ERR_IDLE;
      intc_err_gen_ctrl_trig_req  <= 0;
      intc_err_gen_ctrl_logh      <= 0;
      intc_err_gen_ctrl_logp      <= 0;
      intc_err_gen_ctrl_vf_active <= 0;
      intc_err_gen_ctrl_pf_num    <= 0;
      intc_err_gen_ctrl_vf_num    <= 0;
      intc_err_gen_ctrl_slot_num  <= 0;
      intc_err_gen_attr           <= 0;
      intc_err_gen_hdr_dw0        <= 0;
      intc_err_gen_hdr_dw1        <= 0;
      intc_err_gen_hdr_dw2        <= 0;
      intc_err_gen_hdr_dw3        <= 0;
      intc_err_gen_prfx           <= 0;
      host_sideband_err_rpt_done  <= 0;
    end
    else begin
      case (Err_rpt_state)
      ERR_IDLE : begin
                   intc_err_gen_ctrl_trig_req    <= 1'b0;
                   intc_err_gen_ctrl_logh        <= 0;
                   intc_err_gen_ctrl_logp        <= 0;
                   intc_err_gen_ctrl_vf_active   <= 0;
                   intc_err_gen_ctrl_pf_num      <= 0;
                   intc_err_gen_ctrl_vf_num      <= 0;
                   intc_err_gen_ctrl_slot_num    <= 0;
                   intc_err_gen_attr             <= 0;
                   intc_err_gen_hdr_dw0          <= 0;
                   intc_err_gen_hdr_dw1          <= 0;
                   intc_err_gen_hdr_dw2          <= 0;
                   intc_err_gen_hdr_dw3          <= 0;
                   intc_err_gen_prfx             <= 0;

                   if (host_access_err) begin
                     Err_rpt_state               <= ERR_RPT;
                     host_sideband_err_rpt_done  <= 1'b0;
                   end
                   else
                     host_sideband_err_rpt_done  <= 1'b1;
                 end

      ERR_RPT : begin
                  Err_rpt_state               <= intc_err_gen_ctrl_trig_done & (host_err_rpt_cpl_done|host_wr) ? ERR_IDLE :
                                                                                                            (intc_err_gen_ctrl_trig_done ? ERR_WAIT4CPL :
                                                                                                                                           (host_err_rpt_cpl_done|host_wr) ? ERR_WAIT4DONE : ERR_RPT);
                  intc_err_gen_ctrl_trig_req  <= ~intc_err_gen_ctrl_trig_req ? 1'b1 : ~intc_err_gen_ctrl_trig_done;
                  intc_err_gen_ctrl_logh      <= 1'b1;
                  intc_err_gen_ctrl_logp      <= host_pvalid;
                  intc_err_gen_ctrl_vf_active <= host_vf_active;
                  intc_err_gen_ctrl_pf_num    <= host_pf_num;
                  intc_err_gen_ctrl_vf_num    <= host_vf_num;
                  intc_err_gen_ctrl_slot_num  <= host_slot_num;
                  intc_err_gen_attr[0]        <= host_hdr[31:30]==00 & host_hdr[28:24]==00;
                  intc_err_gen_attr[2]        <= 1'b1;
                  intc_err_gen_hdr_dw0        <= host_hdr[31:0];
                  intc_err_gen_hdr_dw1        <= host_hdr[63:32];
                  intc_err_gen_hdr_dw2        <= host_unmapped_hdr_addr[31:0];
                  intc_err_gen_hdr_dw3        <= host_unmapped_hdr_addr[63:32];
                  intc_err_gen_prfx           <= host_prefix;
                  host_sideband_err_rpt_done  <= intc_err_gen_ctrl_trig_done;
                end

      ERR_WAIT4CPL : Err_rpt_state <= host_err_rpt_cpl_done ? ERR_DONE : ERR_WAIT4CPL;

      ERR_WAIT4DONE : begin
                        if (intc_err_gen_ctrl_trig_done) begin
                          Err_rpt_state              <= ERR_DONE;
                          intc_err_gen_ctrl_trig_req <= 0;
                          host_sideband_err_rpt_done <= 1'b1;
                        end
                      end
      ERR_DONE : Err_rpt_state <= ERR_IDLE;
      endcase
    end
  end

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      VF_Err_rpt_state             <= VF_ERR_IDLE;
      intc_vf_err_vf_num           <= 0;
      intc_vf_err_func_num         <= 0;
      intc_vf_err_slot_num         <= 0;
      intc_vf_err_tvalid           <= 0;
    end
    else begin
      case (VF_Err_rpt_state)
      VF_ERR_IDLE : begin
                      intc_vf_err_tvalid   <= 0;
                      intc_vf_err_vf_num   <= 0;
                      intc_vf_err_func_num <= 0;
                      intc_vf_err_slot_num <= 0;

                      if (host_access_err & host_vf_active)
                        VF_Err_rpt_state  <= VF_ERR_RPT;
                    end
      VF_ERR_RPT  : begin
                      intc_vf_err_vf_num   <= host_vf_num;
                      intc_vf_err_func_num <= host_pf_num;
                      intc_vf_err_slot_num <= host_slot_num;
                      intc_vf_err_tvalid   <= 1'b1;
                      VF_Err_rpt_state     <= (intc_vf_err_tready & (host_err_rpt_cpl_done|host_wr)) ? VF_ERR_IDLE : (intc_vf_err_tready ? VF_ERR_WAIT4CPL : (host_err_rpt_cpl_done|host_wr) ? VF_ERR_WAIT4RDY : VF_ERR_RPT);
                    end
      VF_ERR_WAIT4RDY : begin
                          if (intc_vf_err_tready) begin
                            intc_vf_err_tvalid <= 1'b0;
                            VF_Err_rpt_state   <= VF_ERR_IDLE;
                          end
                        end
      VF_ERR_WAIT4CPL : begin
                          intc_vf_err_tvalid <= 1'b0;
                          VF_Err_rpt_state   <= host_err_rpt_cpl_done ? VF_ERR_IDLE : VF_ERR_WAIT4CPL;
                        end
      endcase
    end
  end


  /*--------------- Host Offset to request decode -----------------*/
  generate
  if (MSIX_VECTOR_ALLOC=="Dynamic")
  begin

    wire [7:0] host_access_pba_addr = host_access_addr-{host_msix_table_size,4'b0000};

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        host_msix_table_size   <= 0;
        host_access_addr       <= 0;
        host_access_length     <= 0;
        host_access_wdata      <= 0;
        host_access_rd         <= 0;
        host_access_wr         <= 0;
        host_msix_table_access <= 0;
        host_pba_access        <= 0;
        host_msix_addr         <= 0;
        host_pba_addr          <= 0;
        host_pba_2nd_rd        <= 0;
        host_pba_bit_offset    <= 0;
        host_pba_end_bit       <= 0;
        host_pba_valid_bit     <= 0;
        host_offset_cycle_cnt  <= 0;
        host_offset_ready      <= 0;
        Host_offset_state      <= HOST_OFFSET_IDLE;
      end
      else begin
        case (Host_offset_state)
        HOST_OFFSET_IDLE      : begin
                                  host_offset_cycle_cnt <= 0;
                                  if (access==HOST & host_offset_rden) begin
                                    Host_offset_state  <= HOST_OFFSET_WAIT4DATA;
                                    host_access_addr   <= host_hdr_addr;
                                    host_access_length <= host_hdr[1:0];
                                    host_access_wdata  <= host_wdata;
                                    host_access_rd     <= host_rd;
                                    host_access_wr     <= host_wr & host_msix_size_valid;
                                  end
                                end
        HOST_OFFSET_WAIT4DATA : begin
                                  host_offset_cycle_cnt <= host_offset_cycle_cnt+1'b1;
                                  if (host_offset_cycle_cnt==2) begin
                                    Host_offset_state    <= HOST_OFFSET_DECODE1;
                                    host_msix_table_size <= offset_rdata[MSIX_TABLE_ADDR_WIDTH+:MSIX_TABLE_ADDR_WIDTH] - offset_rdata[0+:MSIX_TABLE_ADDR_WIDTH] + 1;
                                  end
                                end
        HOST_OFFSET_DECODE1   : begin
                                  Host_offset_state      <= HOST_OFFSET_DECODE2;
                                  host_msix_table_access <= host_access_addr < {host_msix_table_size,4'b0000};
                                  host_pba_access        <= host_access_addr >= {host_msix_table_size,4'b0000};
                                  host_pba_bit_offset    <= offset_rdata[0+:MSIX_TABLE_ADDR_WIDTH] + {host_access_pba_addr, 3'b000};
                                  host_pba_valid_bit     <= cpl_hdr[1:0]*32 > (host_msix_table_size - {host_access_pba_addr, 3'b000}) ? host_msix_table_size - {host_access_pba_addr, 3'b000} :  cpl_hdr[1:0]*32;
                                end
        HOST_OFFSET_DECODE2   : begin
                                  Host_offset_state      <= HOST_OFFSET_DECODE3;
                                  host_pba_end_bit       <= offset_rdata[0+:MSIX_TABLE_ADDR_WIDTH] + {host_access_pba_addr, 3'b000} + host_pba_valid_bit;
                                end
        HOST_OFFSET_DECODE3   : begin
                                  Host_offset_state      <= HOST_OFFSET_CHK_DONE;
                                  host_msix_addr         <= {offset_rdata[0+:MSIX_TABLE_ADDR_WIDTH],4'b000} + host_access_addr;
                                  host_pba_addr          <= host_pba_bit_offset[11:6];
                                  host_pba_2nd_rd        <= host_pba_end_bit[11:6] != host_pba_bit_offset[11:6];
                                  host_offset_ready      <= 1;
                                end
        HOST_OFFSET_CHK_DONE  : begin
                                  if (host_pba_access&host_pba_2nd_rd) begin
                                    host_pba_addr        <= host_pba_addr+1'b1;
                                    Host_offset_state    <= HOST_OFFSET_DONE;
                                  end
                                  else begin
                                    Host_offset_state    <= HOST_OFFSET_IDLE;
                                    host_offset_ready    <= 0;
                                  end
                                end
        HOST_OFFSET_DONE      : begin
                                  Host_offset_state      <= HOST_OFFSET_IDLE;
                                  host_offset_ready      <= 0;
                                end
        endcase
      end
    end

  end
  endgenerate


  /*--------------- Lite access -----------------*/

  reg                     lite_csr_awaddr_valid;
  reg  [LITESLVAWD-1:0]   lite_csr_awaddr_in;
  reg                     lite_csr_wdata_valid;
  reg  [LITESLVDWD-1:0]   lite_csr_wdata_in;
  reg  [LITESLVDWD/8-1:0] lite_csr_wstrb_in;
  wire                    lite_csr_bvalid_out;
  wire [LITESLVAWD-1:0]   axi_lite_csr_awaddr;
  wire                    axi_lite_csr_awvalid;
  wire [LITESLVDWD-1:0]   axi_lite_csr_wdata;
  wire [LITESLVDWD/8-1:0] axi_lite_csr_wstrb;
  wire                    axi_lite_csr_wvalid;
  reg  [1:0]              axi_lite_csr_bresp;
  reg                     axi_lite_csr_bvalid;

  wire [1:0]              lite_csr_bresp_sync;

  reg                     lite_csr_araddr_valid;
  reg  [LITESLVAWD-1:0]   lite_csr_araddr_in;
  wire                    lite_csr_rvalid_out;
  wire [LITESLVAWD-1:0]   axi_lite_csr_araddr;
  wire                    axi_lite_csr_arvalid;
  reg  [LITESLVDWD-1:0]   axi_lite_csr_rdata;
  reg  [1:0]              axi_lite_csr_rresp;
  reg                     axi_lite_csr_rvalid;

  wire [LITESLVDWD-1:0]   lite_csr_rdata_sync;
  wire [1:0]              lite_csr_rresp_sync;

  assign lite_csr_awready = lite_csr_awvalid & lite_wstate==LITE_WIDLE;
  assign lite_csr_wready  = lite_csr_wvalid & (lite_wstate==LITE_WIDLE | lite_wstate==LITE_WAIT4WDATA);

  always @(posedge axi_lite_clk)
  begin
    lite_csr_awaddr_in <= {LITESLVAWD{lite_csr_awvalid}} & lite_csr_awaddr;
    lite_csr_wdata_in  <= {LITESLVDWD{lite_csr_wvalid}} & lite_csr_wdata;
    lite_csr_wstrb_in  <= {LITESLVDWD/8{lite_csr_wvalid}} & lite_csr_wstrb;
    lite_csr_bresp     <= {2{lite_csr_bvalid_out}} & lite_csr_bresp_sync;
  end

  always @(posedge axi_lite_clk or negedge liteclk_rst_n_1)
  begin
    if (~liteclk_rst_n_1) begin
      lite_wstate           <= LITE_WIDLE;
      lite_csr_awaddr_valid <= 1'b0;
      lite_csr_wdata_valid  <= 1'b0;
      lite_csr_bvalid       <= 1'b0;
    end
    else begin
      case (lite_wstate)
      LITE_WIDLE : begin
                     lite_csr_bvalid         <= 1'b0;
                     if (lite_csr_awvalid) begin
                       lite_csr_awaddr_valid <= 1'b1;
                       lite_csr_wdata_valid  <= lite_csr_wvalid ? 1'b1 : 1'b0;
                       lite_wstate           <= lite_csr_wvalid ? LITE_WAIT4BRESP : LITE_WAIT4WDATA;
                     end
                   end
      LITE_WAIT4WDATA : begin
                          lite_csr_awaddr_valid  <= 1'b0;
                          if (lite_csr_wvalid) begin
                            lite_csr_wdata_valid <= 1'b1;
                            lite_wstate          <= LITE_WAIT4BRESP;
                          end
                        end
      LITE_WAIT4BRESP : begin
                          lite_csr_awaddr_valid  <= 1'b0;
                          lite_csr_wdata_valid   <= 1'b0;
                          if (lite_csr_bvalid_out) begin
                            lite_csr_bvalid      <= 1'b1;
                            lite_wstate          <= lite_csr_bready ? LITE_WIDLE : LITE_WAIT4BRDY;
                          end
                        end
      LITE_WAIT4BRDY : if (lite_csr_bready) begin
                         lite_csr_bvalid <= 1'b0;
                         lite_wstate     <= LITE_WIDLE;
                       end
      endcase
    end
  end

  // Lite CSR is not used by OFS. The original clock crossing primitive
  // is replaced with a dummy version that drives 0.
  dummy_msix_vecsync_handshake #(
  .DWIDTH         ( LITESLVAWD                 )
  ) u_lite_csr_awaddr_sync (
  .wr_clk         ( axi_lite_clk               ),
  .wr_rst_n       ( liteclk_rst_n_1            ),
  .rd_clk         ( axi_st_clk                 ),
  .rd_rst_n       ( stclk_rst_n_1              ),
  .data_in        ( lite_csr_awaddr_in         ),
  .load_data_in   ( lite_csr_awaddr_valid      ),
  .data_in_rdy2ld (                            ),
  .data_out       ( axi_lite_csr_awaddr        ),
  .data_out_vld   ( axi_lite_csr_awvalid       ),
  .ack_data_out   ( 1'b1                       )
  );

  dummy_msix_vecsync_handshake #(
  .DWIDTH         ( LITESLVDWD + LITESLVDWD/8               )
  ) u_lite_csr_wdata_sync (
  .wr_clk         ( axi_lite_clk                            ),
  .wr_rst_n       ( liteclk_rst_n_1                         ),
  .rd_clk         ( axi_st_clk                              ),
  .rd_rst_n       ( stclk_rst_n_1                           ),
  .data_in        ( {lite_csr_wdata_in,lite_csr_wstrb_in}   ),
  .load_data_in   ( lite_csr_wdata_valid                    ),
  .data_in_rdy2ld (                                         ),
  .data_out       ( {axi_lite_csr_wdata,axi_lite_csr_wstrb} ),
  .data_out_vld   ( axi_lite_csr_wvalid                     ),
  .ack_data_out   ( 1'b1                                    )
  );

  dummy_msix_vecsync_handshake #(
  .DWIDTH         ( 2                          )
  ) u_lite_csr_bresp_sync (
  .wr_clk         ( axi_st_clk                 ),
  .wr_rst_n       ( stclk_rst_n_1              ),
  .rd_clk         ( axi_lite_clk               ),
  .rd_rst_n       ( liteclk_rst_n_1            ),
  .data_in        ( axi_lite_csr_bresp         ),
  .load_data_in   ( axi_lite_csr_bvalid        ),
  .data_in_rdy2ld (                            ),
  .data_out       ( lite_csr_bresp_sync        ),
  .data_out_vld   ( lite_csr_bvalid_out        ),
  .ack_data_out   ( 1'b1                       )
  );

  assign lite_csr_arready = lite_csr_arvalid & lite_rstate==LITE_RIDLE;

  always @(posedge axi_lite_clk)
    lite_csr_araddr_in <= {LITESLVAWD{lite_csr_arvalid}} & lite_csr_araddr;

  always @(posedge axi_lite_clk or negedge liteclk_rst_n_1)
  begin
    if (~liteclk_rst_n_1) begin
      lite_csr_rvalid       <= 1'b0;
      lite_csr_rdata        <= 0;
      lite_csr_rresp        <= 0;
      lite_rstate           <= LITE_RIDLE;
      lite_csr_araddr_valid <= 1'b0;
    end
    else begin
      case (lite_rstate)
      LITE_RIDLE : begin
                     lite_csr_rvalid         <= 1'b0;
                     lite_csr_rdata          <= 0;
                     lite_csr_rresp          <= 0;
                     if (lite_csr_arvalid) begin
                       lite_csr_araddr_valid <= 1'b1;
                       lite_rstate           <= LITE_WAIT4RRESP;
                     end
                   end
      LITE_WAIT4RRESP : begin
                          lite_csr_araddr_valid  <= 1'b0;
                          if (lite_csr_rvalid_out) begin
                            lite_csr_rvalid      <= 1'b1;
                            lite_csr_rdata       <= lite_csr_rdata_sync;
                            lite_csr_rresp       <= lite_csr_rresp_sync;
                            lite_rstate          <= lite_csr_rready ? LITE_RIDLE : LITE_WAIT4RRDY;
                          end
                        end
      LITE_WAIT4RRDY : if (lite_csr_rready) begin
                         lite_csr_rvalid <= 1'b0;
                         lite_csr_rdata  <= 0;
                         lite_csr_rresp  <= 0;
                         lite_rstate     <= LITE_RIDLE;
                       end
      endcase
    end
  end

  dummy_msix_vecsync_handshake #(
  .DWIDTH         ( LITESLVAWD                 )
  ) u_lite_csr_araddr_sync (
  .wr_clk         ( axi_lite_clk               ),
  .wr_rst_n       ( liteclk_rst_n_1            ),
  .rd_clk         ( axi_st_clk                 ),
  .rd_rst_n       ( stclk_rst_n_1              ),
  .data_in        ( lite_csr_araddr_in         ),
  .load_data_in   ( lite_csr_araddr_valid      ),
  .data_in_rdy2ld (                            ),
  .data_out       ( axi_lite_csr_araddr        ),
  .data_out_vld   ( axi_lite_csr_arvalid       ),
  .ack_data_out   ( 1'b1                       )
  );
  assign lite_csr_araddr_load = lite_csr_arready & lite_csr_arvalid;

  dummy_msix_vecsync_handshake #(
  .DWIDTH         ( LITESLVDWD + 2                            )
  ) u_lite_csr_rresp_sync (
  .wr_clk         ( axi_st_clk                                ),
  .wr_rst_n       ( stclk_rst_n_1                             ),
  .rd_clk         ( axi_lite_clk                              ),
  .rd_rst_n       ( liteclk_rst_n_1                           ),
  .data_in        ( {axi_lite_csr_rdata,axi_lite_csr_rresp}   ),
  .load_data_in   ( axi_lite_csr_rvalid                       ),
  .data_in_rdy2ld (                                           ),
  .data_out       ( {lite_csr_rdata_sync,lite_csr_rresp_sync} ),
  .data_out_vld   ( lite_csr_rvalid_out                       ),
  .ack_data_out   ( 1'b1                                      )
  );

  reg [31:0]                                  msix_gen_ctrl;
  reg                                         lite_gen_ctrl_valid;
  reg                                         lite_gen_ctrl_drop;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]             msix_gen_ctrl_vf_vec_base;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]             msix_gen_ctrl_pf_vec_base;
  reg [VF_NUM_WIDTH-1:0]                      msix_gen_ctrl_vf_offset;
  reg [CTRLSHADOW_ADDR_WIDTH-1:0]             lite_gen_ctrl_ctrlshadow_addr;
  reg [PF_NUM_WIDTH-1:0]                      lite_gen_ctrl_pf_num;
  reg [VF_NUM_WIDTH-1:0]                      lite_gen_ctrl_vf_num;
  reg                                         lite_gen_ctrl_vf_active;
  reg [$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:0] lite_gen_ctrl_vec_num;

  reg                                         lite_wr_msix_gen_ctrl;
  reg                                         lite_wr_msix_pba;
  reg [LITESLVDWD-1:0]                        lite_wr_wdata;
  reg [LITESLVDWD/8-1:0]                      lite_wr_wstrb;
  reg                                         lite_wr_size;
  reg [18:0]                                  lite_wr_size_addr;
  reg                                         lite_wr_size_done;
  reg                                         lite_wr_size_drop;
  reg                                         lite_wr_size_pf_or_vf;
  reg                                         lite_wr_size_pf_oor;
  reg                                         lite_wr_size_vfs_pf_oor;
  reg                                         lite_wr_size_vf_oor;
  reg [2:0]                                   lite_wr_size_pf_num;
  reg [10:0]                                  lite_wr_size_vf_num;

  reg [VFNUM_WIDTH+PFNUM_WIDTH-1:0]           cumulative_lite_gen_ctrl_vf_num;
  reg [SIZE_REG_ADDR_WIDTH-1:0]               lite_gen_ctrl_offset_raddr;

  generate
  if (MSIX_VECTOR_ALLOC=="Static") begin

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        axi_lite_csr_bresp    <= 0;
        axi_lite_csr_bvalid   <= 0;
      end
      else begin
        axi_lite_csr_bresp   <= axi_lite_csr_awaddr[16:12]!=0 ? 2'b10 : 2'b00;
        axi_lite_csr_bvalid  <= ~axi_lite_csr_bvalid ? axi_lite_csr_awvalid : 0;
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        msix_gen_ctrl <= 0;
      else begin
        msix_gen_ctrl[0] <= (axi_lite_csr_wvalid & axi_lite_csr_awaddr[16:12]==0 & ~msix_gen_ctrl[0] & axi_lite_csr_wstrb[0]) ? axi_lite_csr_wdata[0] :
                                                                                                                           ~((req_access==LITE&access==REQ)|lite_gen_ctrl_drop) & msix_gen_ctrl[0];
        if (axi_lite_csr_wvalid & axi_lite_csr_awaddr[16:12]==0) begin
          msix_gen_ctrl[7:1]      <= (axi_lite_csr_wdata[7:1] & {7{axi_lite_csr_wstrb[0]}}) | (~{7{axi_lite_csr_wstrb[0]}} & msix_gen_ctrl[7:1]);
          for (int w=1; w<4; w++)
            msix_gen_ctrl[w*8+:8] <= (axi_lite_csr_wdata[w*8+:8] & {8{axi_lite_csr_wstrb[w]}}) | (~{8{axi_lite_csr_wstrb[w]}} & msix_gen_ctrl[w*8+:8]);
        end
      end
    end
  end
  else begin

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        axi_lite_csr_bresp    <= 0;
        axi_lite_csr_bvalid   <= 0;
      end
      else begin
        axi_lite_csr_bresp   <= lite_wr_msix_pba/*|lite_wr_size_msix_en*/ ? 2'b10 : 2'b00;
        axi_lite_csr_bvalid  <= ~axi_lite_csr_bvalid ? lite_wr_msix_gen_ctrl/*|lite_wr_size_msix_en*/|lite_wr_msix_pba|lite_wr_size_done|lite_wr_size_drop : 0;
      end
    end


    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        lite_wr_msix_gen_ctrl <= 0;
        lite_wr_msix_pba      <= 0;
        lite_wr_wdata         <= 0;
        lite_wr_wstrb         <= 0;
        lite_wr_size          <= 0;
        lite_wr_size_addr     <= 0;
      end
      else begin
        lite_wr_msix_gen_ctrl <= axi_lite_csr_awvalid & axi_lite_csr_awaddr[18:12]==0 & ~lite_wr_msix_gen_ctrl;
        lite_wr_msix_pba      <= axi_lite_csr_awvalid & axi_lite_csr_awaddr[18:17]==0 & |axi_lite_csr_awaddr[16:12] & ~lite_wr_msix_pba;
        lite_wr_wdata         <= axi_lite_csr_wdata;
        lite_wr_wstrb         <= axi_lite_csr_wstrb;
        lite_wr_size          <= axi_lite_csr_awvalid & |axi_lite_csr_awaddr[18:17] /*& all_msix_disabled*/ & ~lite_wr_size;
        lite_wr_size_addr     <= axi_lite_csr_awaddr[18:0];
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        msix_gen_ctrl <= 0;
      else begin
        msix_gen_ctrl[0] <= (lite_wr_msix_gen_ctrl & ~msix_gen_ctrl[0] & lite_wr_wstrb[0]) ? lite_wr_wdata[0] : ~((req_access==LITE&access==REQ)|lite_gen_ctrl_drop) & msix_gen_ctrl[0];
        if (lite_wr_msix_gen_ctrl) begin
          msix_gen_ctrl[7:1]      <= (lite_wr_wdata[7:1] & {7{lite_wr_wstrb[0]}}) | (~{7{lite_wr_wstrb[0]}} & msix_gen_ctrl[7:1]);
          for (int w=1; w<4; w++)
            msix_gen_ctrl[w*8+:8] <= (lite_wr_wdata[w*8+:8] & {8{lite_wr_wstrb[w]}}) | (~{8{lite_wr_wstrb[w]}} & msix_gen_ctrl[w*8+:8]);
        end
      end
    end

    wire [17:0] lite_wr_translated_vf_addr = lite_wr_size_addr-18'h2_0100;

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        size_wren               <= 0;
        size_waddr              <= 0;
        size_wdata              <= 0;
        lite_wr_size_done       <= 0;
        lite_wr_size_drop       <= 0;
        lite_wr_size_pf_or_vf   <= 0;
        lite_wr_size_pf_oor     <= 0;
        lite_wr_size_vfs_pf_oor <= 0;
        lite_wr_size_vf_oor     <= 0;
        lite_wr_size_pf_num     <= 0;
        lite_wr_size_vf_num     <= 0;
        Size_wr_state           <= SIZE_WR_IDLE;
      end
      else begin
        case (Size_wr_state)
        SIZE_WR_IDLE     : begin
                             size_wren               <= 0;
                             size_waddr              <= 0;
                             size_wdata              <= 0;
                             lite_wr_size_done       <= 0;
                             lite_wr_size_drop       <= 0;
                             lite_wr_size_pf_or_vf   <= 0;
                             lite_wr_size_pf_oor     <= 0;
                             lite_wr_size_vfs_pf_oor <= 0;
                             lite_wr_size_vf_oor     <= 0;
                             lite_wr_size_pf_num     <= 0;
                             lite_wr_size_vf_num     <= 0;
                             if (lite_wr_size)
                               Size_wr_state         <= SIZE_WR_DECODE;
                           end
        SIZE_WR_DECODE   : begin
                             Size_wr_state <= SIZE_WR_ACCESS;

                             if (lite_wr_size_addr[18:8]=='h200)
                               lite_wr_size_pf_or_vf <= 0;
                             else
                               lite_wr_size_pf_or_vf <= 1;

                             if (lite_wr_size_addr[7:2]>total_pf_count)
                               lite_wr_size_pf_oor     <= 1;
                             if (lite_wr_translated_vf_addr[17:13]>total_pf_count)
                               lite_wr_size_vfs_pf_oor <= 1;

                             case (lite_wr_translated_vf_addr[15:13])
                             3'b000 : if (lite_wr_translated_vf_addr[12:2] > pf0_vf_count) lite_wr_size_vf_oor <= 1;
                             3'b001 : if (lite_wr_translated_vf_addr[12:2] > pf1_vf_count) lite_wr_size_vf_oor <= 1;
                             3'b010 : if (lite_wr_translated_vf_addr[12:2] > pf2_vf_count) lite_wr_size_vf_oor <= 1;
                             3'b011 : if (lite_wr_translated_vf_addr[12:2] > pf3_vf_count) lite_wr_size_vf_oor <= 1;
                             3'b100 : if (lite_wr_translated_vf_addr[12:2] > pf4_vf_count) lite_wr_size_vf_oor <= 1;
                             3'b101 : if (lite_wr_translated_vf_addr[12:2] > pf5_vf_count) lite_wr_size_vf_oor <= 1;
                             3'b110 : if (lite_wr_translated_vf_addr[12:2] > pf6_vf_count) lite_wr_size_vf_oor <= 1;
                             3'b111 : if (lite_wr_translated_vf_addr[12:2] > pf7_vf_count) lite_wr_size_vf_oor <= 1;
                             endcase

                             lite_wr_size_pf_num   <= lite_wr_size_addr[4:2];

                             case (lite_wr_translated_vf_addr[15:13])
                             3'b000 : lite_wr_size_vf_num   <= PF0_VF_BASE + lite_wr_translated_vf_addr[12:2];
                             3'b001 : lite_wr_size_vf_num   <= PF1_VF_BASE + lite_wr_translated_vf_addr[12:2];
                             3'b010 : lite_wr_size_vf_num   <= PF2_VF_BASE + lite_wr_translated_vf_addr[12:2];
                             3'b011 : lite_wr_size_vf_num   <= PF3_VF_BASE + lite_wr_translated_vf_addr[12:2];
                             3'b100 : lite_wr_size_vf_num   <= PF4_VF_BASE + lite_wr_translated_vf_addr[12:2];
                             3'b101 : lite_wr_size_vf_num   <= PF5_VF_BASE + lite_wr_translated_vf_addr[12:2];
                             3'b110 : lite_wr_size_vf_num   <= PF6_VF_BASE + lite_wr_translated_vf_addr[12:2];
                             3'b111 : lite_wr_size_vf_num   <= PF7_VF_BASE + lite_wr_translated_vf_addr[12:2];
                             endcase

                           end
        SIZE_WR_ACCESS   : begin
                             if ((~lite_wr_size_pf_or_vf&lite_wr_size_pf_oor) | (lite_wr_size_pf_or_vf&(lite_wr_size_vfs_pf_oor|lite_wr_size_vf_oor))) begin
                               lite_wr_size_drop <= 1;
                               Size_wr_state     <= SIZE_WR_IDLE;
                             end
                             else begin
                               size_wren         <= 1;
                               size_waddr        <= LITESLVDWD==32 ? (lite_wr_size_pf_or_vf ? lite_wr_size_vf_num : lite_wr_size_pf_num) : (lite_wr_size_pf_or_vf ? {lite_wr_size_vf_num[10:1],1'b0} : {lite_wr_size_pf_num[2:1],1'b0});
                               size_wdata        <= lite_wr_wdata[11:0];
                               lite_wr_size_done <= LITESLVDWD==32 ? 1 : 0;
                               Size_wr_state     <= LITESLVDWD==32 ? SIZE_WR_IDLE : SIZE_WR_ACCESS2;
                             end
                           end
        SIZE_WR_ACCESS2  : begin
                             Size_wr_state     <= SIZE_WR_IDLE;
                             size_wren         <= 1;
                             size_waddr        <= size_waddr+1;
                             size_wdata        <= lite_wr_wdata[LITESLVDWD/2 +: 12];
                             lite_wr_size_done <= 1;
                           end
        endcase
      end
    end

    reg [11:0]   size_rdata_d;

    always @(posedge axi_st_clk)
      size_rdata_d <= size_rdata;

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        offset_size_raddr_d1 <= 0;
        offset_size_raddr_d2 <= 0;
        offset_size_raddr_d3 <= 0;
      end
      else begin
        offset_size_raddr_d1 <= offset_size_raddr;
        offset_size_raddr_d2 <= offset_size_raddr_d1;
        offset_size_raddr_d3 <= offset_size_raddr_d2;
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        Offset_wr_state     <= OFFSET_WR_IDLE;
        offset_size_rden    <= 0;
        offset_size_raddr   <= 0;
        offset_wren         <= 0;
        offset_waddr        <= 0;
        offset_wdata        <= {1'b0, {(MSIX_TABLE_ADDR_WIDTH*2){1'b1}}};
        offset_wr_cycle_cnt <= 0;
      end
      else begin
        case (Offset_wr_state)
        OFFSET_WR_IDLE     : begin
                               offset_size_rden    <= 0;
                               offset_size_raddr   <= 0;
                               offset_wren         <= 0;
                               offset_waddr        <= 0;
                               offset_wdata        <= {1'b0, {(MSIX_TABLE_ADDR_WIDTH*2){1'b1}}};
                               offset_wr_cycle_cnt <= 0;
                               if (size_wren)
                                 Offset_wr_state   <= OFFSET_WR_PRE_INIT;
                             end
        OFFSET_WR_PRE_INIT : begin
                               Offset_wr_state     <= OFFSET_WR_INIT;
                               offset_size_rden    <= 1;
                               offset_size_raddr   <= 0;

                               offset_wdata        <= {1'b0, {(MSIX_TABLE_ADDR_WIDTH*2){1'b1}}};
                               offset_wr_cycle_cnt <= 0;
                               if (offset_wr_cycle_cnt==2)
                                 Offset_wr_state <= OFFSET_WR_INIT;
                             end
        OFFSET_WR_INIT     : begin
                               if (size_wren) begin
                                 Offset_wr_state   <= OFFSET_WR_PRE_INIT;
                                 offset_size_rden  <= 0;
                               end
                               else begin
                                 offset_size_rden    <= 1;
                                 offset_size_raddr   <= offset_size_raddr+1'b1;
                                 offset_wr_cycle_cnt <= offset_wr_cycle_cnt+1'b1;
                                 if (offset_wr_cycle_cnt==2)
                                   Offset_wr_state <= OFFSET_WR_POPULATE;
                               end
                             end
       OFFSET_WR_POPULATE  : begin
                               if (size_wren) begin
                                 Offset_wr_state   <= OFFSET_WR_PRE_INIT;
                                 offset_size_rden  <= 0;
                               end
                               else begin
                                 offset_size_rden                                           <= 1;
                                 offset_size_raddr                                          <= offset_size_raddr+1'b1;

                                 offset_waddr                                               <= offset_size_raddr_d3;
                                 offset_wdata[0+:MSIX_TABLE_ADDR_WIDTH]                     <= size_rdata_d==0 ? offset_wdata[0+:MSIX_TABLE_ADDR_WIDTH] :
                                                                                                                 offset_wdata[MSIX_TABLE_ADDR_WIDTH+:MSIX_TABLE_ADDR_WIDTH]+1'b1;
                                 offset_wdata[MSIX_TABLE_ADDR_WIDTH+:MSIX_TABLE_ADDR_WIDTH] <= size_rdata_d==0 ? offset_wdata[MSIX_TABLE_ADDR_WIDTH+:MSIX_TABLE_ADDR_WIDTH] :
                                                                                                                 offset_wdata[MSIX_TABLE_ADDR_WIDTH+:MSIX_TABLE_ADDR_WIDTH]+size_rdata_d;
                                 offset_wdata[MSIX_TABLE_ADDR_WIDTH*2]                      <= size_rdata_d==0 ? 1'b1 : 1'b0;
                                 offset_wren                                                <= 1;
                                 Offset_wr_state                                            <= offset_size_raddr_d3==(SIZE_REG_DEPTH-1) ? OFFSET_WR_IDLE : OFFSET_WR_POPULATE;
                               end
                             end
        endcase
      end
    end

  end
  endgenerate

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1)
      msix_gen_ctrl_vf_offset <= 0;
    else begin
      case (msix_gen_ctrl[3:1])
      3'b000 : msix_gen_ctrl_vf_offset <= PF0_VF_OFFSET + msix_gen_ctrl[17:7];
      3'b001 : msix_gen_ctrl_vf_offset <= PF1_VF_OFFSET + msix_gen_ctrl[17:7];
      3'b010 : msix_gen_ctrl_vf_offset <= PF2_VF_OFFSET + msix_gen_ctrl[17:7];
      3'b011 : msix_gen_ctrl_vf_offset <= PF3_VF_OFFSET + msix_gen_ctrl[17:7];
      3'b100 : msix_gen_ctrl_vf_offset <= PF4_VF_OFFSET + msix_gen_ctrl[17:7];
      3'b101 : msix_gen_ctrl_vf_offset <= PF5_VF_OFFSET + msix_gen_ctrl[17:7];
      3'b110 : msix_gen_ctrl_vf_offset <= PF6_VF_OFFSET + msix_gen_ctrl[17:7];
      3'b111 : msix_gen_ctrl_vf_offset <= PF7_VF_OFFSET + msix_gen_ctrl[17:7];
      endcase
    end
  end

  always @* begin
    case (msix_gen_ctrl[3:1])
    3'b000 : cumulative_lite_gen_ctrl_vf_num = PF0_VF_BASE + msix_gen_ctrl[17:7];
    3'b001 : cumulative_lite_gen_ctrl_vf_num = PF1_VF_BASE + msix_gen_ctrl[17:7];
    3'b010 : cumulative_lite_gen_ctrl_vf_num = PF2_VF_BASE + msix_gen_ctrl[17:7];
    3'b011 : cumulative_lite_gen_ctrl_vf_num = PF3_VF_BASE + msix_gen_ctrl[17:7];
    3'b100 : cumulative_lite_gen_ctrl_vf_num = PF4_VF_BASE + msix_gen_ctrl[17:7];
    3'b101 : cumulative_lite_gen_ctrl_vf_num = PF5_VF_BASE + msix_gen_ctrl[17:7];
    3'b110 : cumulative_lite_gen_ctrl_vf_num = PF6_VF_BASE + msix_gen_ctrl[17:7];
    3'b111 : cumulative_lite_gen_ctrl_vf_num = PF7_VF_BASE + msix_gen_ctrl[17:7];
    endcase
  end

  generate
  if (MSIX_VECTOR_ALLOC=="Static") begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        msix_gen_ctrl_pf_vec_base <= 0;
      else
        msix_gen_ctrl_pf_vec_base <= MSIX_TABLE_SIZE*msix_gen_ctrl[5:1];
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        msix_gen_ctrl_vf_vec_base <= 0;
      else begin
        case (msix_gen_ctrl[3:1])
        3'b000 : msix_gen_ctrl_vf_vec_base <= MSIX_TABLE_SIZE*(PF0_VF_BASE + msix_gen_ctrl[17:7]);
        3'b001 : msix_gen_ctrl_vf_vec_base <= MSIX_TABLE_SIZE*(PF1_VF_BASE + msix_gen_ctrl[17:7]);
        3'b010 : msix_gen_ctrl_vf_vec_base <= MSIX_TABLE_SIZE*(PF2_VF_BASE + msix_gen_ctrl[17:7]);
        3'b011 : msix_gen_ctrl_vf_vec_base <= MSIX_TABLE_SIZE*(PF3_VF_BASE + msix_gen_ctrl[17:7]);
        3'b100 : msix_gen_ctrl_vf_vec_base <= MSIX_TABLE_SIZE*(PF4_VF_BASE + msix_gen_ctrl[17:7]);
        3'b101 : msix_gen_ctrl_vf_vec_base <= MSIX_TABLE_SIZE*(PF5_VF_BASE + msix_gen_ctrl[17:7]);
        3'b110 : msix_gen_ctrl_vf_vec_base <= MSIX_TABLE_SIZE*(PF6_VF_BASE + msix_gen_ctrl[17:7]);
        3'b111 : msix_gen_ctrl_vf_vec_base <= MSIX_TABLE_SIZE*(PF7_VF_BASE + msix_gen_ctrl[17:7]);
        endcase
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        lite_gen_ctrl_valid           <= 0;
        lite_gen_ctrl_pf_num          <= 0;
        lite_gen_ctrl_vf_num          <= 0;
        lite_gen_ctrl_vf_active       <= 0;
        lite_gen_ctrl_vec_num         <= 0;
        lite_gen_ctrl_ctrlshadow_addr <= 0;
        lite_gen_ctrl_drop            <= 0;
        GenCtrl_state                 <= GEN_IDLE;
      end
      else begin
        case (GenCtrl_state)
        GEN_IDLE :   begin
                       if (msix_gen_ctrl[0] & req_access!=LITE)
                         GenCtrl_state <= GEN_DECODE;
                     end
        GEN_DECODE : begin
                       lite_gen_ctrl_pf_num          <= msix_gen_ctrl[5:1];
                       lite_gen_ctrl_vf_num          <= msix_gen_ctrl[17:7];
                       lite_gen_ctrl_vf_active       <= msix_gen_ctrl[19];
                       lite_gen_ctrl_vec_num         <= msix_gen_ctrl[19] ? msix_gen_ctrl_vf_vec_base+msix_gen_ctrl[30:20] : msix_gen_ctrl_pf_vec_base+msix_gen_ctrl[30:20];
                       lite_gen_ctrl_ctrlshadow_addr <= msix_gen_ctrl[19] ? cumulative_lite_gen_ctrl_vf_num : msix_gen_ctrl[5:1];
                       if (msix_gen_ctrl[30:20]<MSIX_TABLE_SIZE) begin
                         GenCtrl_state       <= GEN_REQ;
                         lite_gen_ctrl_valid <= 1;
                       end
                       else begin
                         GenCtrl_state       <= GEN_DROP;
                         lite_gen_ctrl_drop  <= 1;
                       end
                     end
        GEN_REQ  :   begin
                       if (req_access==LITE) begin
                         GenCtrl_state       <= GEN_IDLE;
                         lite_gen_ctrl_valid <= 0;
                       end
                     end
        GEN_DROP :   begin
                         GenCtrl_state       <= GEN_IDLE;
                         lite_gen_ctrl_drop  <= 0;
                     end
        endcase
      end
    end
  end
  else begin

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        lite_gen_ctrl_valid           <= 0;
        lite_gen_ctrl_pf_num          <= 0;
        lite_gen_ctrl_vf_num          <= 0;
        lite_gen_ctrl_vf_active       <= 0;
        lite_gen_ctrl_vec_num         <= 0;
        lite_gen_ctrl_ctrlshadow_addr <= 0;
        lite_gen_ctrl_offset_raddr    <= 0;
        lite_gen_ctrl_drop            <= 0;
        GenCtrl_state                 <= GEN_IDLE;
      end
      else begin
        case (GenCtrl_state)
        GEN_IDLE :   begin
                       if (msix_gen_ctrl[0] & req_access!=LITE)
                         GenCtrl_state <= GEN_DECODE;
                     end
        GEN_DECODE : begin
                       lite_gen_ctrl_pf_num          <= msix_gen_ctrl[5:1];
                       lite_gen_ctrl_vf_num          <= msix_gen_ctrl[17:7];
                       lite_gen_ctrl_vf_active       <= msix_gen_ctrl[19];
                       lite_gen_ctrl_vec_num         <= msix_gen_ctrl[30:20];
                       lite_gen_ctrl_offset_raddr    <= msix_gen_ctrl[19] ? cumulative_lite_gen_ctrl_vf_num : msix_gen_ctrl[5:1];
                       lite_gen_ctrl_ctrlshadow_addr <= msix_gen_ctrl[19] ? cumulative_lite_gen_ctrl_vf_num : msix_gen_ctrl[5:1];
                       lite_gen_ctrl_valid           <= 1;
                       GenCtrl_state                 <= GEN_REQ;
                     end
        GEN_REQ  :   begin
                       if (req_access==LITE) begin
                         GenCtrl_state       <= GEN_IDLE;
                         lite_gen_ctrl_valid <= 0;
                       end
                     end
        endcase
      end
    end
  end
  endgenerate

  reg                                lite_rd_msix;
  reg                                lite_rd_pba;
  reg                                lite_rd_genctrl;
  reg                                lite_rd_out_of_range;
  reg [LITESLVDWD-1:0]               lite_rd_data;
  reg                                lite_rdata_valid;
  reg                                lite_rd_valid;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]    lite_rd_msix_addr;
  reg [PBA_DEPTH-1:0]                lite_rd_pba_addr;
  reg                                lite_pending_grant;

  reg [3:2]                          lite_rd_araddr;

  wire                               lite_rd_grant;
  reg                                req_literd_grant, req_literd_grant_d1, req_literd_grant_d2, req_literd_grant_d3;

  reg                                         req_valid;
  reg                                         req_msix_rden;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]             req_msix_raddr;
  reg                                         req_pba_wren [1:0];
  reg [31:0]                                  req_pba_wdata [1:0];
  reg [PBA_DEPTH-1:0]                         req_pba_waddr;
  reg                                         req_pba_rden;
  reg [PBA_DEPTH-1:0]                         req_pba_raddr;
  reg                                         req_mem_sel, req_mem_sel_d1, req_mem_sel_d2;
  reg [PF_NUM_WIDTH-1:0]                      req_pf_num;
  reg [VF_NUM_WIDTH-1:0]                      req_vf_num;
  reg                                         req_vf_active;
  reg [SS_PWIDTH-1:0]                         req_prefix;
  reg [$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:0] req_vec_num;
  reg [CTRLSHADOW_ADDR_WIDTH-1:0]             req_ctrlshadow_addr;

  reg                                         req_rd_msix;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]             req_rd_msix_addr;
  reg                                         req_rd_pba;
  reg [PBA_DEPTH-1:0]                         req_rd_pba_addr;

  reg                                         lite_rd_size;
  reg [18:0]                                  lite_rd_size_addr;
  reg                                         lite_rd_size_done;
  reg                                         lite_rd_size_pf_or_vf;
  reg                                         lite_rd_size_pf_oor;
  reg                                         lite_rd_size_vfs_pf_oor;
  reg                                         lite_rd_size_vf_oor;
  reg [2:0]                                   lite_rd_size_pf_num;
  reg [10:0]                                  lite_rd_size_vf_num;
  reg [LITESLVDWD-1:0]                        lite_rd_size_data;

  reg [1:0]                                   msix_cycle_cnt;
  reg                                         msix_in_progress;
  reg                                         lite_rd_msix_done;
  reg                                         lite_rd_pba_done;

  wire [16:0] lite_csr_msix_raddr = axi_lite_csr_araddr[16:0]-'h1000;

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1)
      lite_rd_araddr <= 0;
    else begin
      if (axi_lite_csr_arvalid)
        lite_rd_araddr <= axi_lite_csr_araddr[3:2];
    end
  end

  generate
  if (MSIX_VECTOR_ALLOC=="Static") begin

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        lite_rd_msix          <= 0;
        lite_rd_pba           <= 0;
        lite_rd_genctrl       <= 0;
        lite_rd_out_of_range  <= 0;
      end
      else begin
        lite_rd_msix          <= axi_lite_csr_arvalid ? |axi_lite_csr_araddr[16:12] & (axi_lite_csr_araddr[16:0]-'h1000)<{MSIX_TABLE_DEPTH,4'b0000} : lite_rd_msix & ~lite_rd_grant;
        lite_rd_pba           <= axi_lite_csr_arvalid ? axi_lite_csr_araddr[16:12]==5'h1_1 & axi_lite_csr_araddr[11:0]< {2**PBA_DEPTH,3'b000} : lite_rd_pba & ~lite_rd_grant;
        lite_rd_genctrl       <= axi_lite_csr_arvalid ? ~|axi_lite_csr_araddr[16:12] : 0;
        lite_rd_out_of_range  <= axi_lite_csr_arvalid ? ((~(axi_lite_csr_araddr[16:12]==5'h1_1) & |axi_lite_csr_araddr[16:12] & (axi_lite_csr_araddr[16:0]-'h1000)>={MSIX_TABLE_DEPTH,4'b0000}) |
                                                          (axi_lite_csr_araddr[16:12]==5'h1_1 & axi_lite_csr_araddr[11:0]>={2**PBA_DEPTH,3'b000})) : 0;
      end
    end

    assign lite_rd_grant = req_literd_grant | lite_rd_genctrl | lite_rd_out_of_range;

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        lite_pending_grant <= 0;
      else
        lite_pending_grant <= ~lite_pending_grant ? lite_rd_valid : ~req_literd_grant;
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        req_mem_sel    <= 0;
        req_mem_sel_d1 <= 0;
        req_mem_sel_d2 <= 0;
      end
      else begin
        req_mem_sel    <= ~(access==REQ & req_msix_rden); /*0-msix, 1-pba*/
        req_mem_sel_d1 <= req_mem_sel;
        req_mem_sel_d2 <= req_mem_sel_d1;
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        lite_rd_data <= 0;
        lite_rdata_valid <= 0;
      end
      else begin
        if (req_literd_grant_d2) begin
          lite_rdata_valid   <= 1'b1;
          case (req_mem_sel_d2)
          1'b1 : lite_rd_data <= LITESLVDWD==64 ? {pba_rdata[1],pba_rdata[0]} : (lite_rd_araddr[2] ? pba_rdata[1] : pba_rdata[0]);
          1'b0 : lite_rd_data <= LITESLVDWD==64 ? (lite_rd_araddr[3] ? {msix_rdata[3],msix_rdata[2]} : {msix_rdata[1],msix_rdata[0]}) :
                               /*LITESLVDWD==32*/ (&lite_rd_araddr[3:2] ? msix_rdata[3] :
                                                                              lite_rd_araddr[3:2]==2'b10 ? msix_rdata[2] :
                                                                                               lite_rd_araddr[3:2]==2'b01 ? msix_rdata[1] : msix_rdata[0]);
          endcase
        end
        else begin
          lite_rd_data <= 0;
          lite_rdata_valid <=0;
        end
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        axi_lite_csr_rvalid   <= 0;
        axi_lite_csr_rdata    <= 0;
        axi_lite_csr_rresp    <= 0;
        lite_rd_valid         <= 0;
        lite_rd_msix_addr     <= 0;
        lite_rd_pba_addr      <= 0;
      end
      else begin
        lite_rd_valid         <= ~lite_rd_valid ? ~lite_pending_grant & (lite_rd_msix|lite_rd_pba) : ~(req_access==LITERD);
        lite_rd_msix_addr     <= lite_csr_msix_raddr[16:4];
        lite_rd_pba_addr      <= axi_lite_csr_araddr[11:3];
        axi_lite_csr_rvalid   <= ~axi_lite_csr_rvalid ? ((req_literd_grant_d3 & lite_rdata_valid) | lite_rd_genctrl | lite_rd_out_of_range) : 0;
        axi_lite_csr_rdata    <= lite_rd_out_of_range ? 0 : (lite_rd_genctrl ? msix_gen_ctrl : lite_rd_data);
      end
    end
  end
  else begin

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        lite_rd_msix          <= 0;
        lite_rd_pba           <= 0;
        lite_rd_genctrl       <= 0;
        lite_rd_out_of_range  <= 0;
        lite_rd_size          <= 0;
        lite_rd_size_addr     <= 0;
      end
      else begin
        lite_rd_msix          <= axi_lite_csr_arvalid ? axi_lite_csr_araddr[18:17]==0 & |axi_lite_csr_araddr[16:12] & (axi_lite_csr_araddr[16:0]-'h1000)<{MSIX_TABLE_DEPTH,4'b0000} :
                                                        lite_rd_msix & ~lite_rd_grant;
        lite_rd_pba           <= axi_lite_csr_arvalid ? axi_lite_csr_araddr[18:17]==0 & axi_lite_csr_araddr[16:12]==5'h1_1 & axi_lite_csr_araddr[11:0]< {2**PBA_DEPTH,3'b000} :
                                                        lite_rd_pba & ~lite_rd_grant;
        lite_rd_genctrl       <= axi_lite_csr_arvalid ? ~|axi_lite_csr_araddr[18:12] : 0;
        lite_rd_out_of_range  <= axi_lite_csr_arvalid ? ((~(axi_lite_csr_araddr[16:12]==5'h1_1) & |axi_lite_csr_araddr[16:12] & (axi_lite_csr_araddr[16:0]-'h1000)>={MSIX_TABLE_DEPTH,4'b0000}) |
                                                          (axi_lite_csr_araddr[16:12]==5'h1_1 & axi_lite_csr_araddr[11:0]>={2**PBA_DEPTH,3'b000})) : 0;
        lite_rd_size          <= axi_lite_csr_arvalid ? |axi_lite_csr_araddr[18:17] : lite_rd_size & ~lite_rd_size_done;
        lite_rd_size_addr     <= axi_lite_csr_araddr[18:0];
      end
    end

    assign lite_rd_grant = req_literd_grant | lite_rd_genctrl | lite_rd_out_of_range | lite_rd_size_done;

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        lite_pending_grant <= 0;
      else
        lite_pending_grant <= ~lite_pending_grant ? lite_rd_valid : ~req_literd_grant;
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        lite_rd_valid         <= 0;
        lite_rd_msix_addr     <= 0;
        lite_rd_pba_addr      <= 0;
      end
      else begin
        lite_rd_valid         <= ~lite_rd_valid ? ~lite_pending_grant & (lite_rd_msix|lite_rd_pba) : ~(req_access==LITERD);
        lite_rd_msix_addr     <= lite_csr_msix_raddr[16:4];
        lite_rd_pba_addr      <= axi_lite_csr_araddr[11:3];
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        req_mem_sel    <= 0;
        req_mem_sel_d1 <= 0;
        req_mem_sel_d2 <= 0;
      end
      else begin
        req_mem_sel    <= ~(access_d ==REQ & msix_state==MSIX_RD); /*0-msix, 1-pba*/
        req_mem_sel_d1 <= req_mem_sel;
        req_mem_sel_d2 <= req_mem_sel_d1;
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        lite_rd_data <= 0;
        lite_rdata_valid <= 0;
      end
      else begin
        if (req_literd_grant_d3) begin
          lite_rdata_valid   <= 1'b1;
          case (req_mem_sel_d2)
          1'b1 : lite_rd_data <= LITESLVDWD==64 ? {pba_rdata[1],pba_rdata[0]} : (lite_rd_araddr[2] ? pba_rdata[1] : pba_rdata[0]);
          1'b0 : lite_rd_data <= LITESLVDWD==64 ? (lite_rd_araddr[3] ? {msix_rdata[3],msix_rdata[2]} : {msix_rdata[1],msix_rdata[0]}) :
                               /*LITESLVDWD==32*/ (&lite_rd_araddr[3:2] ? msix_rdata[3] :
                                                                              lite_rd_araddr[3:2]==2'b10 ? msix_rdata[2] :
                                                                                               lite_rd_araddr[3:2]==2'b01 ? msix_rdata[1] : msix_rdata[0]);
          endcase
        end
        else begin
          lite_rd_data <= 0;
          lite_rdata_valid <=0;
        end
      end
    end

    wire [17:0] lite_rd_translated_vf_addr = lite_rd_size_addr-18'h2_0100;

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        lite_size_rden          <= 0;
        lite_size_raddr         <= 0;
        lite_rd_size_done       <= 0;
        lite_rd_size_pf_or_vf   <= 0;
        lite_rd_size_pf_oor     <= 0;
        lite_rd_size_vfs_pf_oor <= 0;
        lite_rd_size_vf_oor     <= 0;
        lite_rd_size_pf_num     <= 0;
        lite_rd_size_vf_num     <= 0;
        lite_rd_wait4data_cycle <= 0;
        lite_rd_size_data       <= 0;
        Size_rd_state           <= SIZE_RD_IDLE;
      end
      else begin
        case (Size_rd_state)
        SIZE_RD_IDLE      : begin
                              lite_size_rden          <= 0;
                              lite_size_raddr         <= 0;
                              lite_rd_size_done       <= 0;
                              lite_rd_size_pf_or_vf   <= 0;
                              lite_rd_size_pf_oor     <= 0;
                              lite_rd_size_vfs_pf_oor <= 0;
                              lite_rd_size_vf_oor     <= 0;
                              lite_rd_size_pf_num     <= 0;
                              lite_rd_size_vf_num     <= 0;
                              lite_rd_wait4data_cycle <= 0;
                              if (lite_rd_size)
                                Size_rd_state         <= SIZE_RD_DECODE;
                            end
        SIZE_RD_DECODE    : begin
                              Size_rd_state <= SIZE_RD_ACCESS;

                              if (lite_rd_size_addr[18:8]=='h200)
                                lite_rd_size_pf_or_vf <= 0;
                              else
                                lite_rd_size_pf_or_vf <= 1;

                              if (lite_rd_size_addr[7:2]>total_pf_count)
                                lite_rd_size_pf_oor     <= 1;
                              if (lite_rd_translated_vf_addr[17:13]>total_pf_count)
                                lite_rd_size_vfs_pf_oor <= 1;

                              case (lite_rd_translated_vf_addr[15:13])
                              3'b000 : if (lite_rd_translated_vf_addr[12:2] > pf0_vf_count) lite_rd_size_vf_oor <= 1;
                              3'b001 : if (lite_rd_translated_vf_addr[12:2] > pf1_vf_count) lite_rd_size_vf_oor <= 1;
                              3'b010 : if (lite_rd_translated_vf_addr[12:2] > pf2_vf_count) lite_rd_size_vf_oor <= 1;
                              3'b011 : if (lite_rd_translated_vf_addr[12:2] > pf3_vf_count) lite_rd_size_vf_oor <= 1;
                              3'b100 : if (lite_rd_translated_vf_addr[12:2] > pf4_vf_count) lite_rd_size_vf_oor <= 1;
                              3'b101 : if (lite_rd_translated_vf_addr[12:2] > pf5_vf_count) lite_rd_size_vf_oor <= 1;
                              3'b110 : if (lite_rd_translated_vf_addr[12:2] > pf6_vf_count) lite_rd_size_vf_oor <= 1;
                              3'b111 : if (lite_rd_translated_vf_addr[12:2] > pf7_vf_count) lite_rd_size_vf_oor <= 1;
                              endcase

                              lite_rd_size_pf_num   <= LITESLVDWD==64 ? {lite_rd_size_addr[4:3],1'b0} : lite_rd_size_addr[4:2];

                              if (LITESLVDWD==32) begin
                                case (lite_rd_translated_vf_addr[15:13])
                                3'b000 : lite_rd_size_vf_num   <= PF0_VF_BASE + lite_rd_translated_vf_addr[12:2];
                                3'b001 : lite_rd_size_vf_num   <= PF1_VF_BASE + lite_rd_translated_vf_addr[12:2];
                                3'b010 : lite_rd_size_vf_num   <= PF2_VF_BASE + lite_rd_translated_vf_addr[12:2];
                                3'b011 : lite_rd_size_vf_num   <= PF3_VF_BASE + lite_rd_translated_vf_addr[12:2];
                                3'b100 : lite_rd_size_vf_num   <= PF4_VF_BASE + lite_rd_translated_vf_addr[12:2];
                                3'b101 : lite_rd_size_vf_num   <= PF5_VF_BASE + lite_rd_translated_vf_addr[12:2];
                                3'b110 : lite_rd_size_vf_num   <= PF6_VF_BASE + lite_rd_translated_vf_addr[12:2];
                                3'b111 : lite_rd_size_vf_num   <= PF7_VF_BASE + lite_rd_translated_vf_addr[12:2];
                                endcase
                              end
                              else begin
                                case (lite_rd_translated_vf_addr[15:13])
                                3'b000 : lite_rd_size_vf_num   <= PF0_VF_BASE + {lite_rd_translated_vf_addr[12:3],1'b0};
                                3'b001 : lite_rd_size_vf_num   <= PF1_VF_BASE + {lite_rd_translated_vf_addr[12:3],1'b0};
                                3'b010 : lite_rd_size_vf_num   <= PF2_VF_BASE + {lite_rd_translated_vf_addr[12:3],1'b0};
                                3'b011 : lite_rd_size_vf_num   <= PF3_VF_BASE + {lite_rd_translated_vf_addr[12:3],1'b0};
                                3'b100 : lite_rd_size_vf_num   <= PF4_VF_BASE + {lite_rd_translated_vf_addr[12:3],1'b0};
                                3'b101 : lite_rd_size_vf_num   <= PF5_VF_BASE + {lite_rd_translated_vf_addr[12:3],1'b0};
                                3'b110 : lite_rd_size_vf_num   <= PF6_VF_BASE + {lite_rd_translated_vf_addr[12:3],1'b0};
                                3'b111 : lite_rd_size_vf_num   <= PF7_VF_BASE + {lite_rd_translated_vf_addr[12:3],1'b0};
                                endcase
                              end

                            end
        SIZE_RD_ACCESS    : begin
                              if ((~lite_rd_size_pf_or_vf&lite_rd_size_pf_oor) | (lite_rd_size_pf_or_vf&(lite_rd_size_vfs_pf_oor|lite_rd_size_vf_oor))) begin
                                lite_rd_size_done <= 1;
                                lite_rd_size_data <= 0;
                                Size_rd_state     <= SIZE_RD_IDLE;
                              end
                              else begin
                                lite_size_rden    <= ~h2c_size_req_valid & Offset_wr_state==OFFSET_WR_IDLE;
                                lite_size_raddr   <= (~h2c_size_req_valid & Offset_wr_state==OFFSET_WR_IDLE) ? (lite_rd_size_pf_or_vf ? lite_rd_size_vf_num : lite_rd_size_pf_num) : 0;
                                Size_rd_state     <= (~h2c_size_req_valid & Offset_wr_state==OFFSET_WR_IDLE) ? SIZE_RD_CONFLICT : SIZE_RD_ACCESS;
                              end
                            end
        SIZE_RD_CONFLICT  : begin
                              if (~h2c_size_req_valid) begin
                                lite_rd_wait4data_cycle <= lite_rd_wait4data_cycle+1'b1;
                                lite_size_rden          <= 0;
                                lite_size_raddr         <= 0;
                                Size_rd_state           <= SIZE_RD_WAIT4DATA;
                              end
                            end
        SIZE_RD_WAIT4DATA : begin
                              lite_rd_wait4data_cycle <= lite_rd_wait4data_cycle+1'b1;
                              if (lite_rd_wait4data_cycle==2) begin
                                lite_rd_size_data     <= size_rdata;
                                lite_rd_size_done     <= LITESLVDWD==64 ? 0 : 1;
                                Size_rd_state         <= LITESLVDWD==64 ? SIZE_RD_ACCESS2 : SIZE_RD_DONE;
                              end
                            end
        SIZE_RD_ACCESS2   : begin
                              lite_rd_wait4data_cycle <= 0;
                              lite_size_rden          <= ~h2c_size_req_valid & Offset_wr_state==OFFSET_WR_IDLE;
                              lite_size_raddr         <= lite_size_raddr+1'b1;
                              Size_rd_state           <= (~h2c_size_req_valid & Offset_wr_state==OFFSET_WR_IDLE) ? SIZE_RD_WAIT4DATA2 : SIZE_RD_ACCESS2;
                            end
        SIZE_RD_CONFLICT2 : begin
                              if (~h2c_size_req_valid) begin
                                lite_rd_wait4data_cycle <= lite_rd_wait4data_cycle+1'b1;
                                lite_size_rden          <= 0;
                                lite_size_raddr         <= 0;
                                Size_rd_state           <= SIZE_RD_WAIT4DATA2;
                              end
                            end
        SIZE_RD_WAIT4DATA2: begin
                              lite_rd_wait4data_cycle <= lite_rd_wait4data_cycle+1'b1;
                              if (lite_rd_wait4data_cycle==2) begin
                                lite_rd_size_data     <= {size_rdata,lite_rd_size_data[31:0]};
                                lite_rd_size_done     <= 1;
                                Size_rd_state         <= SIZE_RD_DONE;
                              end
                            end
        SIZE_RD_DONE      : begin
                              lite_rd_size_done       <= 0;
                              Size_rd_state           <= SIZE_RD_IDLE;
                            end
        endcase
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        axi_lite_csr_rvalid   <= 0;
        axi_lite_csr_rdata    <= 0;
        axi_lite_csr_rresp    <= 0;
      end
      else begin
        axi_lite_csr_rvalid   <= ~axi_lite_csr_rvalid ? (lite_rd_msix_done | lite_rd_pba_done | (lite_rd_size&lite_rd_size_done) | lite_rd_genctrl | lite_rd_out_of_range) : 0;
        casez ({lite_rd_size,(lite_rd_msix_done|lite_rd_pba_done),lite_rd_genctrl,lite_rd_out_of_range})
        4'b???1 : axi_lite_csr_rdata <= 0;
        4'b??1? : axi_lite_csr_rdata <= msix_gen_ctrl;
        4'b?1?? : axi_lite_csr_rdata <= lite_rd_data;
        4'b1??? : axi_lite_csr_rdata <= lite_rd_size_data;
        default : axi_lite_csr_rdata <= 0;
        endcase
      end
    end

  end
  endgenerate


  /*--------------- Access to Size and Offset register -----------------*/
  generate
  if (MSIX_VECTOR_ALLOC=="Dynamic") begin

    always @*
      h2c_size_req_pf = h2c_pf_num;

    always @* begin
      case (h2c_pf_num)
      3'b000 : h2c_size_req_vf = PF0_VF_BASE + h2c_vf_num;
      3'b001 : h2c_size_req_vf = PF1_VF_BASE + h2c_vf_num;
      3'b010 : h2c_size_req_vf = PF2_VF_BASE + h2c_vf_num;
      3'b011 : h2c_size_req_vf = PF3_VF_BASE + h2c_vf_num;
      3'b100 : h2c_size_req_vf = PF4_VF_BASE + h2c_vf_num;
      3'b101 : h2c_size_req_vf = PF5_VF_BASE + h2c_vf_num;
      3'b110 : h2c_size_req_vf = PF6_VF_BASE + h2c_vf_num;
      3'b111 : h2c_size_req_vf = PF7_VF_BASE + h2c_vf_num;
      endcase
    end
/*
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        host_size_rden  <= 0;
        host_size_raddr <= 0;
      end
      else begin
        host_size_rden  <= h2c_size_req_valid;
        host_size_raddr <= {SIZE_REG_ADDR_WIDTH{h2c_size_req_valid}} & (h2c_vf_active ? h2c_size_req_vf : h2c_size_req_pf);
      end
    end
*/
    always @* begin
      host_size_rden  = h2c_size_req_valid;
      host_size_raddr = {SIZE_REG_ADDR_WIDTH{h2c_size_req_valid}} & (h2c_vf_active ? h2c_size_req_vf : h2c_size_req_pf);
    end

    always @(posedge axi_st_clk)
      host_size_rd_valid <= {host_size_rd_valid[0],host_size_rden};

    assign h2c_msix_size = {12{host_size_rd_valid[1]}} & size_rdata;

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        size_rden        <= 0;
        size_raddr       <= 0;
      end
      else begin
        size_rden        <= offset_size_rden | host_size_rden | lite_size_rden;
        size_raddr       <= offset_size_raddr | host_size_raddr | ({SIZE_REG_ADDR_WIDTH{~h2c_size_req_valid}}&lite_size_raddr);
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        offset_rden       <= 0;
        offset_raddr      <= 0;
      end
      else begin
        case (access)
        HOST : begin
                 offset_rden            <= host_offset_rden;
                 offset_raddr           <= host_offset_raddr;
               end
        REQ  : begin
                 offset_rden            <= req_offset_rden;
                 offset_raddr           <= req_offset_raddr;
               end
        FLR  : begin
                 offset_rden            <= flr_offset_rden;
                 offset_raddr           <= flr_offset_raddr;
               end
        NONE : begin
                 offset_rden            <= 0;
                 offset_raddr           <= 0;
               end
        endcase
      end
    end

  end
  endgenerate

  /*--------------- Mainband access -----------------*/

  wire [SS_PWIDTH-1:0] st_tx_prefix    = st_tx_tdata[159:128];
  wire                 st_tx_vf_active = st_tx_tdata[174];
  wire [11-1:0]        st_tx_vf_num    = st_tx_tdata[173:163];
  wire [2:0]           st_tx_pf_num    = st_tx_tdata[162:160];
  wire [10:0]          st_tx_vec_num   = st_tx_tdata[74:64];

  reg                                         tx_in_valid;
  reg [PF_NUM_WIDTH-1:0]                      tx_in_pf_num;
  reg [VF_NUM_WIDTH-1:0]                      tx_in_vf_num;
  reg                                         tx_in_vf_active;
  reg [SS_PWIDTH-1:0]                         tx_in_prefix;
  reg [$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:0] tx_in_vec_num;
  reg                                         tx_in_in_range;

  reg                                         tx_valid;
  reg [PF_NUM_WIDTH-1:0]                      tx_pf_num;
  reg [VF_NUM_WIDTH-1:0]                      tx_vf_num;
  reg                                         tx_vf_active;
  reg [SS_PWIDTH-1:0]                         tx_prefix;
  reg [$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:0] tx_vec_num;
  reg [CTRLSHADOW_ADDR_WIDTH-1:0]             tx_ctrlshadow_addr;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]             tx_vf_vec_base;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]             tx_pf_vec_base;
  reg [VFNUM_WIDTH+PFNUM_WIDTH-1:0]           cumulative_tx_vf_num;

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1)
      cumulative_tx_vf_num <= 0;
    else begin
      if (st_tx_tvalid & st_tx_tready) begin
        case (st_tx_pf_num)
        3'b000 : cumulative_tx_vf_num <= PF0_VF_BASE + st_tx_vf_num;
        3'b001 : cumulative_tx_vf_num <= PF1_VF_BASE + st_tx_vf_num;
        3'b010 : cumulative_tx_vf_num <= PF2_VF_BASE + st_tx_vf_num;
        3'b011 : cumulative_tx_vf_num <= PF3_VF_BASE + st_tx_vf_num;
        3'b100 : cumulative_tx_vf_num <= PF4_VF_BASE + st_tx_vf_num;
        3'b101 : cumulative_tx_vf_num <= PF5_VF_BASE + st_tx_vf_num;
        3'b110 : cumulative_tx_vf_num <= PF6_VF_BASE + st_tx_vf_num;
        3'b111 : cumulative_tx_vf_num <= PF7_VF_BASE + st_tx_vf_num;
        endcase
      end
    end
  end

  generate
  if (MSIX_VECTOR_ALLOC=="Static") begin
    always @*
      tx_pf_vec_base = MSIX_TABLE_SIZE*st_tx_pf_num;

    always @* begin
      case (st_tx_pf_num)
      3'b000 : tx_vf_vec_base = MSIX_TABLE_SIZE*(PF0_VF_BASE + st_tx_vf_num);
      3'b001 : tx_vf_vec_base = MSIX_TABLE_SIZE*(PF1_VF_BASE + st_tx_vf_num);
      3'b010 : tx_vf_vec_base = MSIX_TABLE_SIZE*(PF2_VF_BASE + st_tx_vf_num);
      3'b011 : tx_vf_vec_base = MSIX_TABLE_SIZE*(PF3_VF_BASE + st_tx_vf_num);
      3'b100 : tx_vf_vec_base = MSIX_TABLE_SIZE*(PF4_VF_BASE + st_tx_vf_num);
      3'b101 : tx_vf_vec_base = MSIX_TABLE_SIZE*(PF5_VF_BASE + st_tx_vf_num);
      3'b110 : tx_vf_vec_base = MSIX_TABLE_SIZE*(PF6_VF_BASE + st_tx_vf_num);
      3'b111 : tx_vf_vec_base = MSIX_TABLE_SIZE*(PF7_VF_BASE + st_tx_vf_num);
      endcase
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        tx_in_valid           <= 0;
        tx_in_pf_num          <= 0;
        tx_in_vf_num          <= 0;
        tx_in_vf_active       <= 0;
        tx_in_prefix          <= 0;
        tx_in_vec_num         <= 0;
        tx_in_in_range        <= 0;
      end
      else begin
        if (st_tx_tvalid & st_tx_tready) begin
          tx_in_valid           <= 1'b1;
          tx_in_vec_num         <= st_tx_vf_active ? tx_vf_vec_base+st_tx_vec_num : tx_pf_vec_base+st_tx_vec_num;
          tx_in_pf_num          <= st_tx_pf_num;
          tx_in_vf_num          <= st_tx_vf_num;
          tx_in_vf_active       <= st_tx_vf_active;
          tx_in_prefix          <= st_tx_prefix;
          tx_in_in_range        <= st_tx_vec_num<MSIX_TABLE_SIZE;
        end
        else
          tx_in_valid   <= st_tx_tready ? 1'b0 : tx_in_valid;
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        tx_valid           <= 0;
        tx_pf_num          <= 0;
        tx_vf_num          <= 0;
        tx_vf_active       <= 0;
        tx_prefix          <= 0;
        tx_vec_num         <= 0;
        tx_ctrlshadow_addr <= 0;
      end
      else begin
        if (tx_in_valid & st_tx_tready) begin
          tx_valid           <= tx_in_in_range;
          tx_pf_num          <= tx_in_pf_num;
          tx_vf_num          <= tx_in_vf_num;
          tx_vf_active       <= tx_in_vf_active;
          tx_prefix          <= tx_in_prefix;
          tx_vec_num         <= tx_in_vec_num;
          tx_ctrlshadow_addr <= tx_in_vf_active ? cumulative_tx_vf_num : tx_in_pf_num;
        end
        else if (req_access==TX)
          tx_valid   <= 0;
      end
    end

  end
  else begin

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        tx_in_valid        <= 0;
        tx_in_pf_num       <= 0;
        tx_in_vf_num       <= 0;
        tx_in_vf_active    <= 0;
        tx_in_prefix       <= 0;
        tx_in_vec_num      <= 0;
      end
      else begin
        if (st_tx_tvalid & st_tx_tready) begin
          tx_in_valid        <= 1'b1;
          tx_in_vec_num      <= st_tx_vec_num;
          tx_in_pf_num       <= st_tx_pf_num;
          tx_in_vf_num       <= st_tx_vf_num;
          tx_in_vf_active    <= st_tx_vf_active;
          tx_in_prefix       <= st_tx_prefix;
        end
        else
          tx_in_valid   <= st_tx_tready ? 1'b0 : tx_in_valid;
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        tx_valid           <= 0;
        tx_pf_num          <= 0;
        tx_vf_num          <= 0;
        tx_vf_active       <= 0;
        tx_prefix          <= 0;
        tx_vec_num         <= 0;
        tx_offset_raddr    <= 0;
        tx_ctrlshadow_addr <= 0;
      end
      else begin
        if (tx_in_valid & st_tx_tready) begin
          tx_valid           <= 1'b1;
          tx_vec_num         <= tx_in_vec_num;
          tx_pf_num          <= tx_in_pf_num;
          tx_vf_num          <= tx_in_vf_num;
          tx_vf_active       <= tx_in_vf_active;
          tx_prefix          <= tx_in_prefix;
          tx_offset_raddr    <= tx_in_vf_active ? cumulative_tx_vf_num : tx_in_pf_num;
          tx_ctrlshadow_addr <= tx_in_vf_active ? cumulative_tx_vf_num : tx_in_pf_num;
        end
        else if (req_access==TX)
          tx_valid   <= 0;
      end
    end
  end
  endgenerate

  assign st_tx_tready = req_access==TX ? access==REQ : ~tx_valid;

  wire [SS_PWIDTH-1:0] st_txreq_prefix    = st_txreq_tdata[159:128];
  wire                 st_txreq_vf_active = st_txreq_tdata[174];
  wire [11-1:0]        st_txreq_vf_num    = st_txreq_tdata[173:163];
  wire [2:0]           st_txreq_pf_num    = st_txreq_tdata[162:160];
  wire [10:0]          st_txreq_vec_num   = st_txreq_tdata[74:64];

  reg                                         txreq_in_valid;
  reg [PF_NUM_WIDTH-1:0]                      txreq_in_pf_num;
  reg [VF_NUM_WIDTH-1:0]                      txreq_in_vf_num;
  reg                                         txreq_in_vf_active;
  reg [SS_PWIDTH-1:0]                         txreq_in_prefix;
  reg [$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:0] txreq_in_vec_num;
  reg                                         txreq_in_in_range;

  reg                                         txreq_valid;
  reg [PF_NUM_WIDTH-1:0]                      txreq_pf_num;
  reg [VF_NUM_WIDTH-1:0]                      txreq_vf_num;
  reg                                         txreq_vf_active;
  reg [SS_PWIDTH-1:0]                         txreq_prefix;
  reg [$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:0] txreq_vec_num;
  reg [CTRLSHADOW_ADDR_WIDTH-1:0]             txreq_ctrlshadow_addr;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]             txreq_vf_vec_base;
  reg [MSIX_TABLE_ADDR_WIDTH-1:0]             txreq_pf_vec_base;
  reg [VFNUM_WIDTH+PFNUM_WIDTH-1:0]           cumulative_txreq_vf_num;

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1)
      cumulative_txreq_vf_num <= 0;
    else begin
      if (st_txreq_tvalid & st_txreq_tready) begin
        case (st_txreq_pf_num)
        3'b000 : cumulative_txreq_vf_num <= PF0_VF_BASE + st_txreq_vf_num;
        3'b001 : cumulative_txreq_vf_num <= PF1_VF_BASE + st_txreq_vf_num;
        3'b010 : cumulative_txreq_vf_num <= PF2_VF_BASE + st_txreq_vf_num;
        3'b011 : cumulative_txreq_vf_num <= PF3_VF_BASE + st_txreq_vf_num;
        3'b100 : cumulative_txreq_vf_num <= PF4_VF_BASE + st_txreq_vf_num;
        3'b101 : cumulative_txreq_vf_num <= PF5_VF_BASE + st_txreq_vf_num;
        3'b110 : cumulative_txreq_vf_num <= PF6_VF_BASE + st_txreq_vf_num;
        3'b111 : cumulative_txreq_vf_num <= PF7_VF_BASE + st_txreq_vf_num;
        endcase
      end
    end
  end

  generate
  if (MSIX_VECTOR_ALLOC=="Static") begin
    always @*
      txreq_pf_vec_base = MSIX_TABLE_SIZE*st_txreq_pf_num;

    always @* begin
      case (st_txreq_pf_num)
      3'b000 : txreq_vf_vec_base = MSIX_TABLE_SIZE*(PF0_VF_BASE + st_txreq_vf_num);
      3'b001 : txreq_vf_vec_base = MSIX_TABLE_SIZE*(PF1_VF_BASE + st_txreq_vf_num);
      3'b010 : txreq_vf_vec_base = MSIX_TABLE_SIZE*(PF2_VF_BASE + st_txreq_vf_num);
      3'b011 : txreq_vf_vec_base = MSIX_TABLE_SIZE*(PF3_VF_BASE + st_txreq_vf_num);
      3'b100 : txreq_vf_vec_base = MSIX_TABLE_SIZE*(PF4_VF_BASE + st_txreq_vf_num);
      3'b101 : txreq_vf_vec_base = MSIX_TABLE_SIZE*(PF5_VF_BASE + st_txreq_vf_num);
      3'b110 : txreq_vf_vec_base = MSIX_TABLE_SIZE*(PF6_VF_BASE + st_txreq_vf_num);
      3'b111 : txreq_vf_vec_base = MSIX_TABLE_SIZE*(PF7_VF_BASE + st_txreq_vf_num);
      endcase
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        txreq_in_valid        <= 0;
        txreq_in_pf_num       <= 0;
        txreq_in_vf_num       <= 0;
        txreq_in_vf_active    <= 0;
        txreq_in_prefix       <= 0;
        txreq_in_vec_num      <= 0;
        txreq_in_in_range     <= 0;
      end
      else begin
        if (st_txreq_tvalid & st_txreq_tready) begin
          txreq_in_valid        <= 1'b1;
          txreq_in_vec_num      <= st_txreq_vf_active ? txreq_vf_vec_base+st_txreq_vec_num : txreq_pf_vec_base+st_txreq_vec_num;
          txreq_in_pf_num       <= st_txreq_pf_num;
          txreq_in_vf_num       <= st_txreq_vf_num;
          txreq_in_vf_active    <= st_txreq_vf_active;
          txreq_in_prefix       <= st_txreq_prefix;
          txreq_in_in_range     <= st_txreq_vec_num<MSIX_TABLE_SIZE;
        end
        else
          txreq_in_valid   <= st_txreq_tready ? 1'b0 : txreq_in_valid;
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        txreq_valid           <= 0;
        txreq_pf_num          <= 0;
        txreq_vf_num          <= 0;
        txreq_vf_active       <= 0;
        txreq_prefix          <= 0;
        txreq_vec_num         <= 0;
        txreq_ctrlshadow_addr <= 0;
      end
      else begin
        if (txreq_in_valid & st_txreq_tready) begin
          txreq_valid           <= txreq_in_in_range;
          txreq_pf_num          <= txreq_in_pf_num;
          txreq_vf_num          <= txreq_in_vf_num;
          txreq_vf_active       <= txreq_in_vf_active;
          txreq_prefix          <= txreq_in_prefix;
          txreq_vec_num         <= txreq_in_vec_num;
          txreq_ctrlshadow_addr <= txreq_in_vf_active ? cumulative_txreq_vf_num : txreq_in_pf_num;
        end
        else if (req_access==TXREQ)
          txreq_valid   <= 0;
      end
    end

  end
  else begin

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        txreq_in_valid        <= 0;
        txreq_in_pf_num       <= 0;
        txreq_in_vf_num       <= 0;
        txreq_in_vf_active    <= 0;
        txreq_in_prefix       <= 0;
        txreq_in_vec_num      <= 0;
      end
      else begin
        if (st_txreq_tvalid & st_txreq_tready) begin
          txreq_in_valid        <= 1'b1;
          txreq_in_vec_num      <= st_txreq_vec_num;
          txreq_in_pf_num       <= st_txreq_pf_num;
          txreq_in_vf_num       <= st_txreq_vf_num;
          txreq_in_vf_active    <= st_txreq_vf_active;
          txreq_in_prefix       <= st_txreq_prefix;
        end
        else
          txreq_in_valid   <= st_txreq_tready ? 1'b0 : txreq_in_valid;
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        txreq_valid           <= 0;
        txreq_pf_num          <= 0;
        txreq_vf_num          <= 0;
        txreq_vf_active       <= 0;
        txreq_prefix          <= 0;
        txreq_vec_num         <= 0;
        txreq_offset_raddr    <= 0;
        txreq_ctrlshadow_addr <= 0;
      end
      else begin
        if (txreq_in_valid & st_txreq_tready) begin
          txreq_valid           <= 1'b1;
          txreq_vec_num         <= txreq_in_vec_num;
          txreq_pf_num          <= txreq_in_pf_num;
          txreq_vf_num          <= txreq_in_vf_num;
          txreq_vf_active       <= txreq_in_vf_active;
          txreq_prefix          <= txreq_in_prefix;
          txreq_offset_raddr    <= txreq_in_vf_active ? cumulative_txreq_vf_num : txreq_in_pf_num;
          txreq_ctrlshadow_addr <= txreq_in_vf_active ? cumulative_txreq_vf_num : txreq_in_pf_num;
        end
        else if (req_access==TXREQ)
          txreq_valid   <= 0;
      end
    end
  end
  endgenerate

  assign st_txreq_tready = req_access==TXREQ ? access==REQ : ~txreq_valid;


  /*--------------- Lite, TXREQ, TX Request Arbitration -----------------*/
  reg [3:0]         req_access_ptr;
  generate
  if (MSIX_VECTOR_ALLOC=="Static") begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        req_access <= NOREQ;
        req_valid  <= 1'b0;
        req_access_ptr <= 4'b1111;
      end
      else begin
        if ((tx_valid & pba_state==PBA_IDLE & msix_state==MSIX_IDLE & (req_access_ptr[0]|(~txreq_valid&~lite_gen_ctrl_valid&~lite_rd_valid)) & ~pfifo_almost_full) | (req_access==TX&access!=REQ)) begin
          req_access <= TX;
          req_valid  <= 1'b1;
          req_access_ptr <= {1'b1,1'b1,1'b1,1'b0};
        end
        else if ((txreq_valid & pba_state==PBA_IDLE & msix_state==MSIX_IDLE & (req_access_ptr[1]|(~tx_valid&~lite_gen_ctrl_valid&~lite_rd_valid)) & ~pfifo_almost_full) | (req_access==TXREQ&access!=REQ)) begin
          req_access <= TXREQ;
          req_valid  <= 1'b1;
          req_access_ptr <= {1'b1,1'b1,1'b0,1'b0};
        end
        else if ((lite_gen_ctrl_valid & pba_state==PBA_IDLE & msix_state==MSIX_IDLE & (req_access_ptr[2]|(~tx_valid&~txreq_valid&~lite_rd_valid)) & ~pfifo_almost_full) | (req_access==LITE&access!=REQ)) begin
          req_access <= LITE;
          req_valid  <= 1'b1;
          req_access_ptr <= {1'b1,1'b0,1'b0,1'b0};
        end
        else if ((lite_rd_valid & pba_state==PBA_IDLE & msix_state==MSIX_IDLE & (req_access_ptr[3]|(~tx_valid&~txreq_valid&~lite_gen_ctrl_valid)|pfifo_almost_full)) | (req_access==LITERD&access!=REQ)) begin
          req_access <= LITERD;
          req_valid  <= 1'b1;
          req_access_ptr <= {1'b0,1'b1,1'b1,1'b1};
        end
        else begin
          req_access       <= NOREQ;
          req_valid        <= 1'b0;
          req_access_ptr   <= {1'b1,1'b1,1'b1,1'b1};
        end
      end
    end
  end
  else begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        req_access <= NOREQ;
        req_valid  <= 1'b0;
        req_access_ptr <= 4'b1111;
        req_offset_rden <= 0;
        req_offset_raddr <= 0;
      end
      else begin
        if ((tx_valid & pba_state==PBA_IDLE & msix_state==MSIX_IDLE & (req_access_ptr[0]|(~txreq_valid&~lite_gen_ctrl_valid&~lite_rd_valid)) & ~pfifo_almost_full) | (req_access==TX&access!=REQ)) begin
          req_access <= TX;
          req_valid  <= 1'b1;
          req_access_ptr <= {1'b1,1'b1,1'b1,1'b0};
          req_offset_rden <= 1'b1;
          req_offset_raddr <= tx_offset_raddr;
        end
        else if ((txreq_valid & pba_state==PBA_IDLE & msix_state==MSIX_IDLE & (req_access_ptr[1]|(~tx_valid&~lite_gen_ctrl_valid&~lite_rd_valid)) & ~pfifo_almost_full) | (req_access==TXREQ&access!=REQ)) begin
          req_access <= TXREQ;
          req_valid  <= 1'b1;
          req_access_ptr <= {1'b1,1'b1,1'b0,1'b0};
          req_offset_rden <= 1'b1;
          req_offset_raddr <= txreq_offset_raddr;
        end
        else if ((lite_gen_ctrl_valid & pba_state==PBA_IDLE & msix_state==MSIX_IDLE & (req_access_ptr[2]|(~tx_valid&~txreq_valid&~lite_rd_valid)) & ~pfifo_almost_full) | (req_access==LITE&access!=REQ)) begin
          req_access <= LITE;
          req_valid  <= 1'b1;
          req_access_ptr <= {1'b1,1'b0,1'b0,1'b0};
          req_offset_rden <= 1'b1;
          req_offset_raddr <= lite_gen_ctrl_offset_raddr;
        end
        else if ((lite_rd_valid & pba_state==PBA_IDLE & msix_state==MSIX_IDLE & (req_access_ptr[3]|(~tx_valid&~txreq_valid&~lite_gen_ctrl_valid)|pfifo_almost_full)) | (req_access==LITERD&access!=REQ)) begin
          req_access <= LITERD;
          req_valid  <= 1'b1;
          req_access_ptr <= {1'b0,1'b1,1'b1,1'b1};
          req_offset_rden  <= 0;
          req_offset_raddr <= 0;
        end
        else begin
          req_access       <= NOREQ;
          req_valid        <= 1'b0;
          req_access_ptr   <= {1'b1,1'b1,1'b1,1'b1};
          req_offset_rden  <= 0;
          req_offset_raddr <= 0;
        end
      end
    end
  end
  endgenerate

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      req_literd_grant    <= 0;
      req_literd_grant_d1 <= 0;
      req_literd_grant_d2 <= 0;
      req_literd_grant_d3 <= 0;
    end
    else begin
      req_literd_grant    <= req_access==LITERD & access==REQ;
      req_literd_grant_d1 <= req_literd_grant;
      req_literd_grant_d2 <= req_literd_grant_d1;
      req_literd_grant_d3 <= req_literd_grant_d2;
    end
  end

  generate
  if (MSIX_VECTOR_ALLOC=="Static") begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        req_msix_rden      <= 0;
        req_msix_raddr     <= 0;
        req_pba_wren[1:0]  <= {0,0};
        req_pba_wdata[1:0] <= {0,0};
        req_pba_waddr      <= 0;
        req_pba_rden       <= 0;
        req_pba_raddr      <= 0;
        req_vec_num        <= 0;
        req_pf_num         <= 0;
        req_vf_num         <= 0;
        req_vf_active      <= 0;
        req_prefix         <= 0;
        req_ctrlshadow_addr <= 0;
      end
      else begin
        case (req_access)
        LITERD : begin
                   req_msix_rden       <= req_valid & lite_rd_msix;
                   req_msix_raddr      <= lite_rd_msix_addr;
                   req_pba_wren[1:0]   <= {0,0};
                   req_pba_wdata[1:0]  <= {0,0};
                   req_pba_waddr       <= 0;
                   req_pba_rden        <= req_valid & lite_rd_pba;
                   req_pba_raddr       <= lite_rd_pba_addr;
                   req_vec_num         <= 0;
                   req_pf_num          <= 0;
                   req_vf_num          <= 0;
                   req_vf_active       <= 0;
                   req_prefix          <= 0;
                   req_ctrlshadow_addr <= 0;
                 end
        LITE   : begin
                   req_msix_rden       <= 0;
                   req_msix_raddr      <= 0;
                   req_pba_wren[1:0]   <= {0,0};
                   req_pba_wdata[1:0]  <= {0,0};
                   req_pba_waddr       <= 0;
                   req_pba_rden        <= req_valid;
                   req_pba_raddr       <= lite_gen_ctrl_vec_num[$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:6];
                   req_vec_num         <= lite_gen_ctrl_vec_num;
                   req_pf_num          <= lite_gen_ctrl_pf_num;
                   req_vf_num          <= lite_gen_ctrl_vf_num;
                   req_vf_active       <= lite_gen_ctrl_vf_active;
                   req_prefix          <= 0;
                   req_ctrlshadow_addr <= lite_gen_ctrl_ctrlshadow_addr;
                 end
        TX     : begin
                   req_msix_rden       <= 0;
                   req_msix_raddr      <= 0;
                   req_pba_wren[1:0]   <= {0,0};
                   req_pba_wdata[1:0]  <= {0,0};
                   req_pba_waddr       <= 0;
                   req_pba_rden        <= req_valid;
                   req_pba_raddr       <= tx_vec_num[$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:6];
                   req_vec_num         <= tx_vec_num;
                   req_pf_num          <= tx_pf_num;
                   req_vf_num          <= tx_vf_num;
                   req_vf_active       <= tx_vf_active;
                   req_prefix          <= tx_prefix;
                   req_ctrlshadow_addr <= tx_ctrlshadow_addr;
                 end
        TXREQ  : begin
                   req_msix_rden       <= 0;
                   req_msix_raddr      <= 0;
                   req_pba_wren[1:0]   <= {0,0};
                   req_pba_wdata[1:0]  <= {0,0};
                   req_pba_waddr       <= 0;
                   req_pba_rden        <= req_valid;
                   req_pba_raddr       <= txreq_vec_num[$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:6];
                   req_vec_num         <= txreq_vec_num;
                   req_pf_num          <= txreq_pf_num;
                   req_vf_num          <= txreq_vf_num;
                   req_vf_active       <= txreq_vf_active;
                   req_prefix          <= txreq_prefix;
                   req_ctrlshadow_addr <= txreq_ctrlshadow_addr;
                 end
        NOREQ  : begin
                   req_msix_rden       <= 0;
                   req_pba_wren[1:0]   <= {0,0};
                   req_pba_rden        <= 0;
                 end
        endcase
      end
    end
  end
  else begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        req_rd_msix         <= 0;
        req_rd_msix_addr    <= 0;
        req_rd_pba          <= 0;
        req_rd_pba_addr     <= 0;

        req_vec_num         <= 0;
        req_pf_num          <= 0;
        req_vf_num          <= 0;
        req_vf_active       <= 0;
        req_prefix          <= 0;
        req_ctrlshadow_addr <= 0;
      end
      else begin
        case (req_access)
        LITERD : begin
                   req_rd_msix         <= req_valid & lite_rd_msix;
                   req_rd_msix_addr    <= lite_rd_msix_addr;
                   req_rd_pba          <= req_valid & lite_rd_pba;
                   req_rd_pba_addr     <= lite_rd_pba_addr;

                   req_vec_num         <= 0;
                   req_pf_num          <= 0;
                   req_vf_num          <= 0;
                   req_vf_active       <= 0;
                   req_prefix          <= 0;
                   req_ctrlshadow_addr <= 0;
                 end
        LITE   : begin
                   req_rd_msix         <= 0;
                   req_rd_msix_addr    <= 0;
                   req_rd_pba          <= 0;
                   req_rd_pba_addr     <= 0;

                   req_vec_num         <= lite_gen_ctrl_vec_num;
                   req_pf_num          <= lite_gen_ctrl_pf_num;
                   req_vf_num          <= lite_gen_ctrl_vf_num;
                   req_vf_active       <= lite_gen_ctrl_vf_active;
                   req_prefix          <= 0;
                   req_ctrlshadow_addr <= lite_gen_ctrl_ctrlshadow_addr;
                 end
        TX     : begin
                   req_rd_msix         <= 0;
                   req_rd_msix_addr    <= 0;
                   req_rd_pba          <= 0;
                   req_rd_pba_addr     <= 0;

                   req_vec_num         <= tx_vec_num;
                   req_pf_num          <= tx_pf_num;
                   req_vf_num          <= tx_vf_num;
                   req_vf_active       <= tx_vf_active;
                   req_prefix          <= tx_prefix;
                   req_ctrlshadow_addr <= tx_ctrlshadow_addr;
                 end
        TXREQ  : begin
                   req_rd_msix         <= 0;
                   req_rd_msix_addr    <= 0;
                   req_rd_pba          <= 0;
                   req_rd_pba_addr     <= 0;

                   req_vec_num         <= txreq_vec_num;
                   req_pf_num          <= txreq_pf_num;
                   req_vf_num          <= txreq_vf_num;
                   req_vf_active       <= txreq_vf_active;
                   req_prefix          <= txreq_prefix;
                   req_ctrlshadow_addr <= txreq_ctrlshadow_addr;
                 end
        NOREQ  : begin
                   req_rd_msix         <= 0;
                   req_rd_pba          <= 0;
                 end
        endcase
      end
    end
  end
  endgenerate


  /*--------------- Arbitration to MSIX TABLE and PBA  -----------------*/
  reg [2:0] access_ptr;

  generate
  if (MSIX_VECTOR_ALLOC=="Static") begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        access     <= NONE;
        access_ptr <= 3'b111;
      end
      else begin
        if ((flr_valid&~intc_in_progress&~pba_in_progress&~msix_in_progress) | (access==FLR&Flr_state!=FLR_IDLE)) begin
          access <= FLR;
        end
        else begin
          if (((host_valid & Host_cpl_state==IDLE & (~(access==HOST)|host_wr)) &
               Err_rpt_state==ERR_IDLE & ~(access==REQ&(pba_in_progress|msix_in_progress)) & ~(access==INTC&intc_in_progress) & (access_ptr[0]|(~req_valid&~intc_valid))) |
               (access==HOST & Host_cpl_state==IDLE & cpl_pba_2nd_rd)) begin
            access <= HOST;
            access_ptr <= {1'b1,1'b1,1'b0};
          end
          else if ((intc_valid & ~(access==REQ&(pba_in_progress|msix_in_progress)) & (access_ptr[1]|(~host_valid&~req_valid)) & ~intc_st_tx_tvalid) | (access==INTC&intc_in_progress)) begin
            access <= INTC;
            access_ptr <= {1'b1,1'b0,1'b0};
          end
          else if ((req_valid & ~(access==INTC&intc_in_progress) & (access_ptr[2]|(~host_valid&~intc_valid))) | (access==REQ&(pba_in_progress|msix_in_progress))) begin
            access <= REQ;
            access_ptr <= {1'b0,1'b1,1'b1};
          end
          else begin
            access <= NONE;
            access_ptr <= {1'b1,1'b1,1'b1};
          end
        end
      end
    end
  end
  else begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        access     <= NONE;
        access_ptr <= 3'b111;
      end
      else begin
        if ((flr_valid&~intc_in_progress&~pba_in_progress&~msix_in_progress) | (access==FLR&Flr_state!=FLR_IDLE)) begin
          access <= FLR;
        end
        else begin
          if ((host_valid & Err_rpt_state==ERR_IDLE & ~(access==REQ&(pba_in_progress|msix_in_progress)) & ~(access==INTC&intc_in_progress) & (access_ptr[0]|(~req_valid&~intc_valid))) |
               (access==HOST&host_in_progress)) begin
            access <= HOST;
            access_ptr <= {1'b1,1'b1,1'b0};
          end
          else if ((intc_valid & ~(access==REQ&(pba_in_progress|msix_in_progress)) & (access_ptr[1]|(~host_valid&~req_valid)) & ~intc_st_tx_tvalid) | (access==INTC&intc_in_progress)) begin
            access <= INTC;
            access_ptr <= {1'b1,1'b0,1'b0};
          end
          else if ((req_valid & ~(access==INTC&intc_in_progress) & (access_ptr[2]|(~host_valid&~intc_valid))) | (access==REQ&(pba_in_progress|msix_in_progress))) begin
            access <= REQ;
            access_ptr <= {1'b0,1'b1,1'b1};
          end
          else begin
            access <= NONE;
            access_ptr <= {1'b1,1'b1,1'b1};
          end
        end
      end
    end
  end
  endgenerate

  always @(posedge axi_st_clk)
  begin
    case (access)
    HOST : access_d <= HOST;
    INTC : access_d <= INTC;
    REQ  : access_d <= REQ;
    FLR  : access_d <= FLR;
    endcase
  end

  generate
  if (MSIX_VECTOR_ALLOC=="Static") begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        msix_waddr      <= 0;
        msix_rden       <= 0;
        msix_raddr      <= 0;
        for (int i=0; i<4; i++) begin
          msix_wren[i]  <= 0;
          msix_wdata[i] <= 0;
        end
      end
      else begin
        case (access)
        HOST : begin
                 msix_wren[0]  <= host_valid & host_wr & host_msix_table_access & ~host_msix_addr[3] & (~host_msix_addr[2]|host_hdr[1]);
                 msix_wren[1]  <= host_valid & host_wr & host_msix_table_access & ~host_msix_addr[3] & (host_msix_addr[2]|host_hdr[1]);
                 msix_wren[2]  <= host_valid & host_wr & host_msix_table_access & host_msix_addr[3] & (~host_msix_addr[2]|host_hdr[1]);
                 msix_wren[3]  <= host_valid & host_wr & host_msix_table_access & host_msix_addr[3] & (host_msix_addr[2]|host_hdr[1]);
                 msix_waddr    <= host_msix_addr >> 4;
                 msix_wdata[0] <= host_wdata[31:0];
                 msix_wdata[1] <= host_hdr[1] ? host_wdata[63:32] : host_wdata[31:0];
                 msix_wdata[2] <= host_wdata[31:0];
                 msix_wdata[3] <= host_hdr[1] ? host_wdata[63:32] : host_wdata[31:0];
                 msix_rden     <= host_valid & host_rd & host_msix_table_access;
                 msix_raddr    <= host_msix_addr >> 4;
               end
        REQ  : begin
                 msix_wren[3:0]   <= {0,0,0,0};
                 msix_wdata[3:0]  <= {0,0,0,0};
                 msix_waddr       <= 0;
                 msix_rden        <= req_valid & req_msix_rden;
                 msix_raddr       <= req_msix_raddr;
               end
        INTC : begin
                 msix_wren[3:0]   <= {0,0,0,0};
                 msix_wdata[3:0]  <= {0,0,0,0};
                 msix_waddr       <= 0;
                 msix_rden        <= intc_valid;
                 msix_raddr       <= pfifo_rdata[0+:MSIX_TABLE_ADDR_WIDTH];
               end
        FLR  : begin
                 msix_wren[3:0]   <= {flr_msix_wren,flr_msix_wren,flr_msix_wren,flr_msix_wren};
                 msix_wdata[3:0]  <= {1,0,0,0};
                 msix_waddr       <= flr_msix_waddr;
                 msix_rden        <= 0;
                 msix_raddr       <= 0;
               end
        NONE : begin
                 msix_wren[3:0]   <= {0,0,0,0};
                 msix_wdata[3:0]  <= {0,0,0,0};
                 msix_waddr       <= 0;
                 msix_rden        <= 0;
                 msix_raddr       <= 0;
               end
        endcase
      end
    end
  end
  else begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        msix_waddr      <= 0;
        msix_rden       <= 0;
        msix_raddr      <= 0;
        for (int i=0; i<4; i++) begin
          msix_wren[i]  <= 0;
          msix_wdata[i] <= 0;
        end
      end
      else begin
        case (access_d)
        HOST : begin
                 msix_wren[0]  <= host_offset_ready & host_access_wr & host_msix_table_access & ~host_msix_addr[3] & (~host_msix_addr[2]|host_access_length[1]);
                 msix_wren[1]  <= host_offset_ready & host_access_wr & host_msix_table_access & ~host_msix_addr[3] & (host_msix_addr[2]|host_access_length[1]);
                 msix_wren[2]  <= host_offset_ready & host_access_wr & host_msix_table_access & host_msix_addr[3] & (~host_msix_addr[2]|host_access_length[1]);
                 msix_wren[3]  <= host_offset_ready & host_access_wr & host_msix_table_access & host_msix_addr[3] & (host_msix_addr[2]|host_access_length[1]);
                 msix_waddr    <= host_msix_addr >> 4;
                 msix_wdata[0] <= host_access_wdata[31:0];
                 msix_wdata[1] <= host_access_length[1] ? host_access_wdata[63:32] : host_access_wdata[31:0];
                 msix_wdata[2] <= host_access_wdata[31:0];
                 msix_wdata[3] <= host_access_length[1] ? host_access_wdata[63:32] : host_access_wdata[31:0];
                 msix_rden     <= host_offset_ready & host_access_rd & host_msix_table_access;
                 msix_raddr    <= host_msix_addr >> 4;
               end
        REQ  : begin
                 msix_wren[3:0]   <= {0,0,0,0};
                 msix_wdata[3:0]  <= {0,0,0,0};
                 msix_waddr       <= 0;
                 msix_rden        <= msix_state==MSIX_RD;
                 msix_raddr       <= req_msix_raddr;
               end
        INTC : begin
                 msix_wren[3:0]   <= {0,0,0,0};
                 msix_wdata[3:0]  <= {0,0,0,0};
                 msix_waddr       <= 0;
                 msix_rden        <= intc_rd_en;
                 msix_raddr       <= pfifo_rdata[0+:MSIX_TABLE_ADDR_WIDTH];
               end
        FLR  : begin
                 msix_wren[3:0]   <= {flr_msix_wren,flr_msix_wren,flr_msix_wren,flr_msix_wren};
                 msix_wdata[3:0]  <= {1,0,0,0};
                 msix_waddr       <= flr_msix_waddr;
                 msix_rden        <= 0;
                 msix_raddr       <= 0;
               end
        NONE : begin
                 msix_wren[3:0]   <= {0,0,0,0};
                 msix_wdata[3:0]  <= {0,0,0,0};
                 msix_waddr       <= 0;
                 msix_rden        <= 0;
                 msix_raddr       <= 0;
               end
        endcase
      end
    end
  end
  endgenerate

  generate
  if (MSIX_VECTOR_ALLOC=="Static") begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        pba_waddr      <= 0;
        pba_rden       <= 0;
        pba_raddr      <= 0;
        for (int j=0; j<2; j++) begin
          pba_wren[j]  <= 0;
          pba_wdata[j] <= 0;
        end
        host_pba_1st_access <= 1'b1;
      end
      else begin
        case (access)
        HOST : begin
                 pba_wren[1:0]       <= {0,0};
                 pba_wdata[1:0]      <= {0,0};
                 pba_waddr           <= 0;
                 pba_rden            <= host_rd & host_pba_access;
                 pba_raddr           <= host_pba_1st_access ? host_pba_addr : host_pba_addr+1'b1;
                 host_pba_1st_access <= ~host_pba_1st_access;
               end
        REQ  : begin
                 pba_wren[1:0]       <= pba_state==PBA_WR ? {1,1} : {0,0};
                 pba_wdata[1:0]      <= pba_state==PBA_WR ? pba_pending : {0,0};
                 pba_waddr           <= pba_state==PBA_WR ? pba_vec_num[$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:6] : 0;
                 pba_rden            <= req_valid & req_pba_rden;
                 pba_raddr           <= req_pba_raddr;
               end
        INTC : begin
                 pba_wren[1:0]       <= Intc_state==INTC_INT_OUT ? {1,1} : {0,0};
                 pba_wdata[1:0]      <= Intc_state==INTC_INT_OUT ? {intc_pba_wdata[63:32],intc_pba_wdata[31:0]} : {0,0};
                 pba_waddr           <= Intc_state==INTC_INT_OUT ? intc_vec_num[$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:6] : 0;
                 pba_rden            <= intc_valid;
                 pba_raddr           <= (pfifo_rdata[0+:MSIX_TABLE_ADDR_WIDTH])>>6;
               end
        FLR  : begin
                 pba_wren[1:0]       <= {flr_pba_wren,flr_pba_wren};
                 pba_wdata[1:0]      <= {flr_pba_wdata[63:32],flr_pba_wdata[31:0]};
                 pba_waddr           <= flr_pba_waddr;
                 pba_rden            <= flr_pba_rden;
                 pba_raddr           <= flr_pba_raddr;
               end
        NONE : begin
                 pba_wren[0]         <= 0;
                 pba_wren[1]         <= 0;
                 pba_rden            <= 0;
                 host_pba_1st_access <= 1'b1;
               end
        endcase
      end
    end
  end
  else begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        pba_waddr      <= 0;
        pba_rden       <= 0;
        pba_raddr      <= 0;
        for (int j=0; j<2; j++) begin
          pba_wren[j]  <= 0;
          pba_wdata[j] <= 0;
        end
      end
      else begin
        case (access_d)
        HOST : begin
                 pba_wren[1:0]       <= {0,0};
                 pba_wdata[1:0]      <= {0,0};
                 pba_waddr           <= 0;
                 pba_rden            <= host_offset_ready & host_rd & host_pba_access;
                 pba_raddr           <= host_pba_addr;
               end
        REQ  : begin
                 pba_wren[1:0]       <= pba_state==PBA_WR ? {1,1} : {0,0};
                 pba_wdata[1:0]      <= pba_state==PBA_WR ? pba_pending : {0,0};
                 pba_waddr           <= pba_state==PBA_WR ? pba_vec_num[$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:6] : 0;
                 pba_rden            <= pba_state==PBA_RD;
                 pba_raddr           <= req_pba_raddr;
               end
        INTC : begin
                 pba_wren[1:0]       <= Intc_state==INTC_INT_OUT ? {1,1} : {0,0};
                 pba_wdata[1:0]      <= Intc_state==INTC_INT_OUT ? {intc_pba_wdata[63:32],intc_pba_wdata[31:0]} : {0,0};
                 pba_waddr           <= Intc_state==INTC_INT_OUT ? intc_vec_num[$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:6] : 0;
                 pba_rden            <= intc_rd_en;
                 pba_raddr           <= (pfifo_rdata[0+:MSIX_TABLE_ADDR_WIDTH])>>6;
               end
        FLR  : begin
                 pba_wren[1:0]       <= {flr_pba_wren,flr_pba_wren};
                 pba_wdata[1:0]      <= {flr_pba_wdata[63:32],flr_pba_wdata[31:0]};
                 pba_waddr           <= flr_pba_waddr;
                 pba_rden            <= flr_pba_rden;
                 pba_raddr           <= flr_pba_raddr;
               end
        NONE : begin
                 pba_wren[0]         <= 0;
                 pba_wren[1]         <= 0;
                 pba_rden            <= 0;
               end
        endcase
      end
    end
  end
  endgenerate

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      ctrlshadow_rden  <= 0;
      ctrlshadow_raddr <= 0;
    end
    else begin
      case (access)
      HOST : begin
               ctrlshadow_rden  <= 0;
               ctrlshadow_raddr <= 0;
             end
      REQ  : begin
               ctrlshadow_rden  <= 1'b1;
               ctrlshadow_raddr <= req_ctrlshadow_addr;
             end
      INTC : begin
               ctrlshadow_rden  <= 1'b1;
               ctrlshadow_raddr <= intc_ctrlshadow_addr;
             end
      FLR  : begin
               ctrlshadow_rden  <= 0;
               ctrlshadow_raddr <= 0;
             end
      NONE : begin
               ctrlshadow_rden  <= 0;
               ctrlshadow_raddr <= 0;
             end
      endcase
    end
  end

  always @*
    pba_pending_bit = {pba_rdata[1],pba_rdata[0]} >> pba_vec_num[5:0];

  generate
  if (MSIX_VECTOR_ALLOC=="Static") begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        pba_state             <= PBA_IDLE;
        pba_pending           <= {0,0};
        pba_in_progress       <= 1'b0;
        pba_pf_num            <= 0;
        pba_vf_num            <= 0;
        pba_cumulative_vf_num <= 0;
        pba_vf_active         <= 0;
        pba_prefix            <= 0;
        pba_vec_num           <= 0;
        pba_cycle_cnt         <= 0;
        pba_requester         <= 0;
      end
      else begin
        case (pba_state)
        PBA_IDLE : begin
                     if ((((tx_valid | txreq_valid | lite_gen_ctrl_valid)&~pfifo_almost_full) | (lite_rd_valid & lite_rd_pba)) & msix_state==MSIX_IDLE)
                       pba_state <= PBA_WAIT4REQGRANT;
                   end
        PBA_WAIT4REQGRANT : begin
                              if (req_access==LITE|req_access==TX|req_access==TXREQ) begin
                                pba_state       <= PBA_WAIT4GRANT;
                                pba_in_progress <= 1'b1;
                                pba_requester   <= 0;
                              end
                              else if (req_access==LITERD) begin
                                pba_state       <= PBA_WAIT4GRANT2;
                                pba_in_progress <= 1'b1;
                                pba_requester   <= 1;
                              end
                              else
                                pba_in_progress <= 1'b0;
                            end
        PBA_WAIT4GRANT : begin
                           pba_pf_num      <= req_pf_num;
                           pba_vf_num      <= req_vf_num;
                           pba_vf_active   <= req_vf_active;
                           pba_prefix      <= req_prefix;
                           pba_vec_num     <= req_vec_num;
                           if (access==REQ)
                             pba_state <= PBA_WAIT4DATA;

                           case (req_pf_num)
                           3'b000 : pba_cumulative_vf_num <= PF0_VF_BASE + req_vf_num;
                           3'b001 : pba_cumulative_vf_num <= PF1_VF_BASE + req_vf_num;
                           3'b010 : pba_cumulative_vf_num <= PF2_VF_BASE + req_vf_num;
                           3'b011 : pba_cumulative_vf_num <= PF3_VF_BASE + req_vf_num;
                           3'b100 : pba_cumulative_vf_num <= PF4_VF_BASE + req_vf_num;
                           3'b101 : pba_cumulative_vf_num <= PF5_VF_BASE + req_vf_num;
                           3'b110 : pba_cumulative_vf_num <= PF6_VF_BASE + req_vf_num;
                           3'b111 : pba_cumulative_vf_num <= PF7_VF_BASE + req_vf_num;
                           endcase
                         end
        PBA_WAIT4GRANT2 : begin
                            if (access==REQ)
                              pba_state     <= PBA_WAIT4DATA;
                          end
        PBA_WAIT4DATA  : begin
                           pba_cycle_cnt <= pba_cycle_cnt+1'b1;
                           if (pba_cycle_cnt==2 & pba_requester==0) begin
                             pba_state <= ctrlshadow_rdata[2]/*msix_en*/ ? PBA_WR : PBA_END;
                             if (pba_pending_bit[0]) begin
                               pba_pending[0] <= pba_rdata[0];
                               pba_pending[1] <= pba_rdata[1];
                             end
                             else begin
                               pba_pending[0] <= ~pba_vec_num[5] ? pba_rdata[0] | (1'b1 << pba_vec_num[4:0]) : pba_rdata[0];
                               pba_pending[1] <= pba_vec_num[5] ? pba_rdata[1] | (1'b1 << pba_vec_num[4:0]) : pba_rdata[1];
                             end
                           end
                           else if (pba_cycle_cnt==2 & pba_requester==1) begin
                             pba_state <= PBA_END;
                           end
                         end
        PBA_WR        : begin
                          pba_state <= PBA_END;
                          pba_pending <= {0,0};
                        end
        PBA_END       : begin
                          pba_state       <= PBA_IDLE;
                          pba_in_progress <= 1'b0;
                          pba_cycle_cnt   <= 0;
                        end
        endcase
      end
    end
  end
  else begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        pba_state             <= PBA_IDLE;
        pba_pending           <= {0,0};
        pba_in_progress       <= 1'b0;
        pba_pf_num            <= 0;
        pba_vf_num            <= 0;
        pba_cumulative_vf_num <= 0;
        pba_vf_active         <= 0;
        pba_prefix            <= 0;
        pba_vec_num           <= 0;
        pba_cycle_cnt         <= 0;
        pba_offset_cycle_cnt  <= 0;
        pba_chk_offset_valid  <= 0;
        pba_chk_offset_range  <= 0;
        req_pba_raddr         <= 0;
        pba_requester         <= 0;
        lite_rd_pba_done      <= 0;
      end
      else begin
        case (pba_state)
        PBA_IDLE : begin
                     pba_in_progress <= 1'b0;
                     if ((((tx_valid | txreq_valid | lite_gen_ctrl_valid)&~pfifo_almost_full) | (lite_rd_valid & lite_rd_pba)) & msix_state==MSIX_IDLE)
                       pba_state <= PBA_WAIT4REQGRANT;
                   end
        PBA_WAIT4REQGRANT : begin
                              if (req_access==LITE|req_access==TX|req_access==TXREQ) begin
                                pba_state       <= PBA_WAIT4GRANT;
                                pba_in_progress <= 1'b1;
                                pba_requester   <= 0;
                              end
                              else if (req_access==LITERD) begin
                                pba_state       <= PBA_WAIT4GRANT2;
                                pba_in_progress <= 1'b1;
                                pba_requester   <= 1;
                              end
                              else
                                pba_in_progress <= 1'b0;
                            end
        PBA_WAIT4GRANT : begin
                           pba_pf_num      <= req_pf_num;
                           pba_vf_num      <= req_vf_num;
                           pba_vf_active   <= req_vf_active;
                           pba_prefix      <= req_prefix;
                           if (access==REQ)
                             pba_state <= PBA_WAIT4OFFSET;

                           case (req_pf_num)
                           3'b000 : pba_cumulative_vf_num <= PF0_VF_BASE + req_vf_num;
                           3'b001 : pba_cumulative_vf_num <= PF1_VF_BASE + req_vf_num;
                           3'b010 : pba_cumulative_vf_num <= PF2_VF_BASE + req_vf_num;
                           3'b011 : pba_cumulative_vf_num <= PF3_VF_BASE + req_vf_num;
                           3'b100 : pba_cumulative_vf_num <= PF4_VF_BASE + req_vf_num;
                           3'b101 : pba_cumulative_vf_num <= PF5_VF_BASE + req_vf_num;
                           3'b110 : pba_cumulative_vf_num <= PF6_VF_BASE + req_vf_num;
                           3'b111 : pba_cumulative_vf_num <= PF7_VF_BASE + req_vf_num;
                           endcase
                         end
        PBA_WAIT4GRANT2 : begin
                            if (access==REQ) begin
                              pba_state     <= PBA_RD;
                              req_pba_raddr <= req_rd_pba_addr;
                            end
                          end
        PBA_WAIT4OFFSET : begin
                            pba_offset_cycle_cnt <= pba_offset_cycle_cnt+1;
                            if (pba_offset_cycle_cnt==2) begin
                              pba_chk_offset_valid <= ~offset_rdata[MSIX_TABLE_ADDR_WIDTH*2];
                              pba_chk_offset_range <= offset_rdata[MSIX_TABLE_ADDR_WIDTH+:MSIX_TABLE_ADDR_WIDTH] - offset_rdata[0+:MSIX_TABLE_ADDR_WIDTH];
                              pba_state            <= PBA_RANGE_CHK;
                            end
                          end
        PBA_RANGE_CHK  : begin
                           if (pba_chk_offset_valid & req_vec_num <= pba_chk_offset_range)
                             pba_state <= PBA_VEC_CAL;
                           else
                             pba_state <= PBA_END;
                         end
        PBA_VEC_CAL    : begin
                           pba_vec_num <= req_vec_num + offset_rdata[0+:MSIX_TABLE_ADDR_WIDTH];
                           pba_state   <= PBA_RD_INIT;
                         end
        PBA_RD_INIT    : begin
                           pba_state     <= PBA_RD;
                           req_pba_raddr <= pba_vec_num[$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:6];
                         end
        PBA_RD         : begin
                           pba_state     <= PBA_WAIT4DATA;
                         end
        PBA_WAIT4DATA  : begin
                           pba_cycle_cnt <= pba_cycle_cnt+1'b1;
                           if (pba_cycle_cnt==2 & pba_requester==0) begin
                             pba_state <= ctrlshadow_rdata[2]/*msix_en*/ ? PBA_WR : PBA_END;
                             if (pba_pending_bit[0]) begin
                               pba_pending[0] <= pba_rdata[0];
                               pba_pending[1] <= pba_rdata[1];
                             end
                             else begin
                               pba_pending[0] <= ~pba_vec_num[5] ? pba_rdata[0] | (1'b1 << pba_vec_num[4:0]) : pba_rdata[0];
                               pba_pending[1] <= pba_vec_num[5] ? pba_rdata[1] | (1'b1 << pba_vec_num[4:0]) : pba_rdata[1];
                             end
                           end
                           else if (pba_cycle_cnt==2 & pba_requester==1) begin
                             pba_state <= PBA_END;
                             lite_rd_pba_done <= 1;
                           end
                         end
        PBA_WR        : begin
                          pba_state <= PBA_END;
                          pba_pending <= {0,0};
                        end
        PBA_END       : begin
                          pba_state       <= PBA_IDLE;
                          pba_in_progress <= 1'b0;
                          pba_cycle_cnt   <= 0;
                          lite_rd_pba_done <= 0;
                        end
        endcase
      end
    end
  end
  endgenerate

  generate
  if (MSIX_VECTOR_ALLOC=="Static") begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        msix_state       <= MSIX_IDLE;
        msix_cycle_cnt   <= 0;
        msix_in_progress <= 0;
      end
      else begin
        case (msix_state)
        MSIX_IDLE : begin
                      msix_cycle_cnt   <= 0;
                      msix_in_progress <= 0;
                      if (lite_rd_valid & lite_rd_msix & pba_state==PBA_IDLE & ~tx_valid&~txreq_valid&~lite_gen_ctrl_valid)
                        msix_state <= MSIX_WAIT4REQGRANT;
                    end
        MSIX_WAIT4REQGRANT : begin
                               if (req_access==LITERD) begin
                                 msix_state       <= MSIX_WAIT4GRANT;
                                 msix_in_progress <= 1'b1;
                               end
                             end
        MSIX_WAIT4GRANT : begin
                            if (access==REQ)
                              msix_state     <= MSIX_WAIT4DATA;
                          end
        MSIX_WAIT4DATA : begin
                           msix_cycle_cnt <= msix_cycle_cnt+1'b1;
                           if (msix_cycle_cnt==2)
                              msix_state <= MSIX_END;
                         end
        MSIX_END : begin
                     msix_state       <= MSIX_IDLE;
                     msix_in_progress <= 1'b0;
                   end
        endcase
      end
    end
  end
  else begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        msix_state        <= MSIX_IDLE;
        req_msix_raddr    <= 0;
        msix_cycle_cnt    <= 0;
        msix_in_progress  <= 0;
        lite_rd_msix_done <= 0;
      end
      else begin
        case (msix_state)
        MSIX_IDLE : begin
                      msix_cycle_cnt <= 0;
                      msix_in_progress <= 0;
                      if (lite_rd_valid & lite_rd_msix & pba_state==PBA_IDLE & ~tx_valid&~txreq_valid&~lite_gen_ctrl_valid)
                        msix_state <= MSIX_WAIT4REQGRANT;
                    end
        MSIX_WAIT4REQGRANT : begin
                               if (req_access==LITERD) begin
                                 msix_state <= MSIX_WAIT4GRANT;
                                 msix_in_progress <= 1'b1;
                               end
                             end
        MSIX_WAIT4GRANT : begin
                            if (access==REQ) begin
                              msix_state     <= MSIX_RD;
                              req_msix_raddr <= req_rd_msix_addr;
                            end
                          end
        MSIX_RD : begin
                      msix_state <= MSIX_WAIT4DATA;
                  end
        MSIX_WAIT4DATA : begin
                           msix_cycle_cnt <= msix_cycle_cnt+1'b1;
                           if (msix_cycle_cnt==2) begin
                              msix_state <= MSIX_END;
                              lite_rd_msix_done <= 1;
                           end
                         end
        MSIX_END : begin
                     msix_state        <= MSIX_IDLE;
                     msix_in_progress  <= 0;
                     lite_rd_msix_done <= 0;
                   end
        endcase
      end
    end
  end
  endgenerate



  reg  [PF_NUM_WIDTH-1:0]          intc_pf_num;
  reg  [VF_NUM_WIDTH-1:0]          intc_vf_num;
  reg  [CTRLSHADOW_ADDR_WIDTH-1:0] intc_cumulative_vf_num;
  reg                              intc_vf_active;
  wire [SS_PWIDTH-1:0]             intc_prefix  = pfifo_rdata[0+MSIX_TABLE_ADDR_WIDTH+PF_NUM_WIDTH+VF_NUM_WIDTH+CTRLSHADOW_ADDR_WIDTH+1 +: SS_PWIDTH];

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      pfifo_wdata  <= 0;
      pfifo_wrreq  <= 0;
    end
    else begin
      if (pba_state==PBA_WR) begin
        pfifo_wdata <= {pba_prefix, pba_vf_active, pba_cumulative_vf_num, pba_vf_num, pba_pf_num, pba_vec_num[0+:MSIX_TABLE_ADDR_WIDTH]};
        pfifo_wrreq <= ~pba_pending_bit[0];
      end
      else if (Intc_state==INTC_WR) begin
        pfifo_wdata <= {intc_prefix, intc_vf_active, intc_cumulative_vf_num, intc_vf_num, intc_pf_num, intc_vec_num[0+:MSIX_TABLE_ADDR_WIDTH]};
        pfifo_wrreq <= 1'b1;
      end
      else begin
        pfifo_wdata  <= 0;
        pfifo_wrreq  <= 0;
      end
    end
  end

  /*--------------- Pending FIFO readout for Interrupt generation -----------------*/

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      pfifo_rdreq  <= 0;
    end
    else begin
      if (~pfifo_empty & Intc_state==INTC_IDLE)
        pfifo_rdreq <= ~pfifo_rdreq ? 1'b1 : 1'b0;
      else
        pfifo_rdreq <= 0;
    end
  end

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1)
      intc_valid <= 0;
    else
      intc_valid <= ~intc_valid ? pfifo_rdreq : ~(access==INTC);
  end

  always @(posedge axi_st_clk)
    intc_pending_bit <= {pba_rdata[1],pba_rdata[0]} >> intc_vec_num[5:0];

  assign {intc_msix_en, intc_msix_mask, intc_bme} = ctrlshadow_rdata;
  assign intc_ctrlshadow_addr = intc_vf_active ? intc_cumulative_vf_num : intc_pf_num;

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      Intc_state             <= INTC_IDLE;
      intc_vec_num           <= 0;
      intc_pf_num            <= 0;
      intc_vf_num            <= 0;
      intc_cumulative_vf_num <= 0;
      intc_vf_active         <= 0;
      intc_st_tx_hdr         <= 0;
      intc_st_tx_data        <= 0;
      intc_st_tx_tvalid      <= 0;
      intc_pba_wdata         <= 0;
      intc_pba_bit_clr       <= 0;
      intc_in_progress       <= 0;
      intc_cycle_cnt         <= 0;
      intc_rd_en             <= 0;
    end
    else begin
      case (Intc_state)
      INTC_IDLE       : begin
                          intc_st_tx_tvalid <= 1'b0;
                          intc_cycle_cnt    <= 0;
                          if (pfifo_rdreq)
                            Intc_state <= INTC_CAPTURE;
                        end
      INTC_CAPTURE    : begin
                          intc_in_progress       <= 1'b1;
                          intc_vec_num           <= pfifo_rdata[0+:MSIX_TABLE_ADDR_WIDTH];
                          intc_pf_num            <= pfifo_rdata[0+MSIX_TABLE_ADDR_WIDTH +: PF_NUM_WIDTH];
                          intc_vf_num            <= pfifo_rdata[0+MSIX_TABLE_ADDR_WIDTH+PF_NUM_WIDTH +: VF_NUM_WIDTH];
                          intc_cumulative_vf_num <= pfifo_rdata[0+MSIX_TABLE_ADDR_WIDTH+PF_NUM_WIDTH+VF_NUM_WIDTH +: CTRLSHADOW_ADDR_WIDTH];
                          intc_vf_active         <= pfifo_rdata[0+MSIX_TABLE_ADDR_WIDTH+PF_NUM_WIDTH+VF_NUM_WIDTH+CTRLSHADOW_ADDR_WIDTH];
                          Intc_state             <= INTC_WAIT4GRANT;
                        end
      INTC_WAIT4GRANT : begin
                          intc_pba_bit_clr       <= ~(1'b1 << intc_vec_num[5:0]);
                          if (access==INTC) begin
                            intc_rd_en <= 1'b1;
                            Intc_state <= INTC_WAIT4DATA;
                          end
                        end
      INTC_WAIT4DATA  : begin
                          intc_rd_en     <= 0;
                          intc_cycle_cnt <= intc_cycle_cnt+1'b1;
                          if ((MSIX_VECTOR_ALLOC=="Static"&intc_cycle_cnt==3) | (MSIX_VECTOR_ALLOC=="Dynamic"&intc_cycle_cnt==4)) begin
                            if (intc_pending_bit[0]==0) begin
                              Intc_state <= INTC_IDLE;
                              intc_in_progress <= 0;
                            end
                            else if (intc_bme & intc_msix_en & ~intc_msix_mask & ~msix_rdata[3][0]/*vector mask*/) begin
                              Intc_state <= INTC_INT_OUT;
                              intc_pba_wdata <= {pba_rdata[1],pba_rdata[0]} & intc_pba_bit_clr;
                            end
                            else begin
                              Intc_state <= INTC_WR;
                              intc_in_progress <= 0;
                            end
                          end
                        end
      INTC_INT_OUT   : begin
                          Intc_state <= intc_st_tx_tready ? INTC_IDLE : INTC_HOLD;
                          intc_in_progress <= ~intc_st_tx_tready;
                          if (msix_rdata[2]==0) begin
                            intc_st_tx_hdr[9:0]     <= 10'h1;
                            intc_st_tx_hdr[23:10]   <= 0;
                            intc_st_tx_hdr[31:24]   <= {3'b010,5'b00000};
                            intc_st_tx_hdr[35:32]   <= 4'hF;
                            intc_st_tx_hdr[63:36]   <= 0;
                            intc_st_tx_hdr[95:64]   <= msix_rdata[0][31:0];
                            intc_st_tx_hdr[127:96]  <= 0;
                            intc_st_tx_hdr[159:128] <= intc_prefix;
                            intc_st_tx_hdr[162:160] <= intc_pf_num;
                            intc_st_tx_hdr[173:163] <= intc_vf_num;
                            intc_st_tx_hdr[174]     <= intc_vf_active;
                            intc_st_tx_hdr[178:175] <= 0;
                            intc_st_tx_hdr[183:179] <= 0;
                            intc_st_tx_hdr[185:184] <= 0;
                            intc_st_tx_hdr[255:186] <= 0;
                          end
                          else begin
                            intc_st_tx_hdr[9:0]     <= 10'h1;
                            intc_st_tx_hdr[23:10]   <= 0;
                            intc_st_tx_hdr[31:24]   <= {3'b011,5'b00000};
                            intc_st_tx_hdr[35:32]   <= 4'hF;
                            intc_st_tx_hdr[63:36]   <= 0;
                            intc_st_tx_hdr[95:64]   <= msix_rdata[1][31:0];
                            intc_st_tx_hdr[127:96]  <= msix_rdata[0][31:0];
                            intc_st_tx_hdr[159:128] <= intc_prefix;
                            intc_st_tx_hdr[162:160] <= intc_pf_num;
                            intc_st_tx_hdr[173:163] <= intc_vf_num;
                            intc_st_tx_hdr[174]     <= intc_vf_active;
                            intc_st_tx_hdr[178:175] <= 0;
                            intc_st_tx_hdr[183:179] <= 0;
                            intc_st_tx_hdr[185:184] <= 0;
                            intc_st_tx_hdr[255:186] <= 0;
                          end
                          intc_st_tx_data[31:0]   <= msix_rdata[2][31:0];
                          intc_st_tx_tvalid       <= 1'b1;
                        end
      INTC_HOLD       : begin
                          intc_pba_wdata      <= 0;
                          intc_in_progress    <= 0;
                          if (intc_st_tx_tready) begin
                            Intc_state        <= INTC_IDLE;
                            intc_st_tx_hdr    <= 0;
                            intc_st_tx_data   <= 0;
                            intc_st_tx_tvalid <= 0;
                          end
                        end
      INTC_WR         : Intc_state <= INTC_IDLE;
      endcase
    end
  end



  /*--------------- Host Completion Return -----------------*/

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      msix_rden_d <= 0;
      pba_rden_d  <= 0;
    end
    else begin
      msix_rden_d <= msix_rden;
      pba_rden_d  <= pba_rden;
    end
  end

  generate
  if (MSIX_VECTOR_ALLOC=="Static")
  begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        Host_cpl_state        <= IDLE;
        mem_data_sel          <= 0;
        intc_st_cpl_tx_hdr    <= 0;
        intc_st_cpl_tx_data   <= 0;
        intc_st_cpl_tx_tvalid <= 0;
        cpl_error             <= 0;
        cpl_hdr               <= 0;
        cpl_bar_num           <= 0;
        cpl_slot_num          <= 0;
        cpl_pf_num            <= 0;
        cpl_vf_num            <= 0;
        cpl_vf_active         <= 0;
        cpl_msix_size_valid   <= 0;
        cpl_lower_addr        <= 0;
        cpl_length            <= 0;
        cpl_byte_addr         <= 0;
        cpl_pba_bit_offset    <= 0;
        cpl_pba_2nd_rd        <= 0;
        cpl_pba_valid_bit     <= 0;
        cpl_cycle_cnt         <= 0;
        host_err_rpt_cpl_done <= 0;
      end
      else begin
        case (Host_cpl_state)
        IDLE : begin
                 mem_data_sel            <= 0;
                 intc_st_cpl_tx_tvalid   <= 1'b0;
                 cpl_cycle_cnt           <= 0;
                 if ((host_access_err&host_rd) | (host_rd&host_valid)) begin
                   Host_cpl_state        <= host_access_err ? CPL_OUT : (access==HOST ? WAIT4DATA : IDLE);
                   cpl_error             <= host_access_err;
                   cpl_hdr               <= host_hdr;
                   cpl_bar_num           <= host_bar_num;
                   cpl_slot_num          <= host_slot_num;
                   cpl_pf_num            <= host_pf_num;
                   cpl_vf_num            <= host_vf_num;
                   cpl_vf_active         <= host_vf_active;
                   cpl_msix_size_valid   <= host_msix_size_valid;
                   cpl_lower_addr        <= host_hdr_addr[6:0];
                   cpl_length            <= host_hdr[1];
                   cpl_byte_addr         <= host_msix_addr[3:0];
                   cpl_pba_bit_offset    <= host_pba_bit_offset[5:0];
                   cpl_pba_2nd_rd        <= host_pba_access&host_pba_2nd_rd;
                   cpl_pba_valid_bit     <= host_pba_valid_bit;
                 end
                 else begin
                   cpl_error             <= 0;
                   cpl_hdr               <= 0;
                   cpl_bar_num           <= 0;
                   cpl_slot_num          <= 0;
                   cpl_pf_num            <= 0;
                   cpl_vf_num            <= 0;
                   cpl_vf_active         <= 0;
                   cpl_msix_size_valid   <= 1;
                   cpl_length            <= 0;
                   cpl_byte_addr         <= 0;
                   cpl_pba_bit_offset    <= 0;
                   cpl_pba_2nd_rd        <= 0;
                   cpl_pba_valid_bit     <= 0;
                 end
               end

        WAIT4DATA : begin
                      cpl_cycle_cnt <= cpl_cycle_cnt+1'b1;
                      if (cpl_cycle_cnt==1) begin
                        Host_cpl_state <= FORM_DATA;
                        mem_data_sel   <= pba_rden_d;
                      end
                    end

        FORM_DATA : casez ({mem_data_sel, cpl_pba_2nd_rd})
                    2'b0? : begin
                              Host_cpl_state <= CPL_OUT;
                              case ({cpl_length,cpl_byte_addr[3]})
                              2'b00 : mem_data <= cpl_byte_addr[2] ? {32'b0,msix_rdata[1]} : {32'b0,msix_rdata[0]};
                              2'b01 : mem_data <= cpl_byte_addr[2] ? {32'b0,msix_rdata[3]} : {32'b0,msix_rdata[2]};
                              2'b10 : mem_data <= {msix_rdata[1],msix_rdata[0]};
                              2'b11 : mem_data <= {msix_rdata[3],msix_rdata[2]};
                              endcase
                            end
                    2'b10 : begin
                              Host_cpl_state <= CPL_OUT;
                              casez ({cpl_length,cpl_pba_bit_offset[5]})
                              2'b00 : mem_data <= {pba_rdata[1],pba_rdata[0]}>>cpl_pba_bit_offset[4:0];
                              2'b01 : mem_data <= {32'b0,pba_rdata[1]>>cpl_pba_bit_offset[4:0]};
                              2'b1? : mem_data <= {pba_rdata[1],pba_rdata[0]} >> cpl_pba_bit_offset;
                              endcase
                            end
                    2'b11 : begin
                              Host_cpl_state <= FORM_DATA2;
                              mem_data <= {pba_rdata[1],pba_rdata[0]} >> cpl_pba_bit_offset;
                            end
                    endcase

        FORM_DATA2 : begin
                       Host_cpl_state <= CPL_OUT;
                       mem_data <= {pba_rdata[1],pba_rdata[0]}<<('d64-cpl_pba_bit_offset) | mem_data;
                     end

        CPL_OUT : begin
                    intc_st_cpl_tx_hdr[9:0]     <= cpl_error ? 0 : cpl_hdr[9:0];
                    intc_st_cpl_tx_hdr[23:10]   <= cpl_hdr[23:10];
                    intc_st_cpl_tx_hdr[28:24]   <= 'b01010;
                    intc_st_cpl_tx_hdr[31:29]   <= cpl_error ? 3'h0 : 3'h2;
                    intc_st_cpl_tx_hdr[43:32]   <= {cpl_hdr[9:0],2'b00};
                    intc_st_cpl_tx_hdr[44]      <= 1'b0;
                    intc_st_cpl_tx_hdr[47:45]   <= cpl_error ? 3'b100 : 3'b000;
                    intc_st_cpl_tx_hdr[63:48]   <= 0;
                    intc_st_cpl_tx_hdr[70:64]   <= MSIX_BAR_OFFSET + cpl_lower_addr;
                    intc_st_cpl_tx_hdr[71]      <= 0;
                    intc_st_cpl_tx_hdr[79:72]   <= cpl_hdr[47:40];
                    intc_st_cpl_tx_hdr[95:80]   <= cpl_hdr[63:48];
                    intc_st_cpl_tx_hdr[127:96]  <= 0;
                    intc_st_cpl_tx_hdr[159:128] <= 0;
                    intc_st_cpl_tx_hdr[162:160] <= cpl_pf_num;
                    intc_st_cpl_tx_hdr[173:163] <= cpl_vf_num;
                    intc_st_cpl_tx_hdr[174]     <= cpl_vf_active;
                    intc_st_cpl_tx_hdr[178:175] <= cpl_bar_num;
                    intc_st_cpl_tx_hdr[183:179] <= cpl_slot_num;
                    intc_st_cpl_tx_hdr[255:184] <= 0;

                    intc_st_cpl_tx_data        <= (cpl_error | ~cpl_msix_size_valid) ? 0 :
                                                   ~mem_data_sel ? /*msix*/ mem_data :
                                                   {mem_data[63:32] & ({32{cpl_pba_valid_bit[6]}}|({32{cpl_pba_valid_bit[5]}} & ~({32{1'b1}}<<cpl_pba_valid_bit[4:0]))),
                                                    mem_data[31:0] & ({32{|cpl_pba_valid_bit[6:5]}}|~({32{1'b1}}<<cpl_pba_valid_bit[4:0]))};

                    intc_st_cpl_tx_tvalid      <= ~intc_st_cpl_tx_tvalid ? 1'b1 : ~intc_st_cpl_tx_tready;
                    Host_cpl_state             <= intc_st_cpl_tx_tready & host_sideband_err_rpt_done ? CPL_DONE :
                                                                                                       (intc_st_cpl_tx_tready ? CPL_WAIT4SB : CPL_HOLD);
                    host_err_rpt_cpl_done      <= intc_st_cpl_tx_tready;
                  end

        CPL_HOLD : begin
                     if (intc_st_cpl_tx_tready) begin
                       Host_cpl_state        <= host_sideband_err_rpt_done ? CPL_DONE : CPL_WAIT4SB;
                       intc_st_cpl_tx_hdr    <= 0;
                       intc_st_cpl_tx_data   <= 0;
                       intc_st_cpl_tx_tvalid <= 1'b0;
                       host_err_rpt_cpl_done <= 1'b1;
                     end
                   end

        CPL_WAIT4SB : begin
                        Host_cpl_state <= host_sideband_err_rpt_done ? CPL_DONE : CPL_WAIT4SB;
                        intc_st_cpl_tx_hdr    <= 0;
                        intc_st_cpl_tx_data   <= 0;
                        intc_st_cpl_tx_tvalid <= 1'b0;
                        host_err_rpt_cpl_done <= 1'b0;
                      end

        CPL_DONE : begin
                     Host_cpl_state        <= IDLE;
                     intc_st_cpl_tx_tvalid <= 1'b0;
                     host_err_rpt_cpl_done <= 1'b0;
                   end

        endcase
      end
    end
  end
  else begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        Host_cpl_state        <= IDLE;
        intc_st_cpl_tx_hdr    <= 0;
        intc_st_cpl_tx_data   <= 0;
        intc_st_cpl_tx_tvalid <= 0;
        cpl_error             <= 0;
        cpl_hdr               <= 0;
        cpl_bar_num           <= 0;
        cpl_slot_num          <= 0;
        cpl_pf_num            <= 0;
        cpl_vf_num            <= 0;
        cpl_vf_active         <= 0;
        cpl_msix_size_valid   <= 1;
        cpl_lower_addr        <= 0;
        cpl_length            <= 0;
        cpl_byte_addr         <= 0;
        cpl_cycle_cnt         <= 0;
        host_err_rpt_cpl_done <= 0;
      end
      else begin
        case (Host_cpl_state)
        IDLE : begin
                 intc_st_cpl_tx_tvalid <= 1'b0;
                 cpl_cycle_cnt         <= 0;
                 if ((host_access_err&host_rd) | (host_rd&host_valid)) begin
                   Host_cpl_state        <= host_access_err ? CPL_OUT : (access==HOST ? WAIT4OFFSET : IDLE);
                   cpl_error             <= host_access_err;
                   cpl_hdr               <= host_hdr;
                   cpl_bar_num           <= host_bar_num;
                   cpl_slot_num          <= host_slot_num;
                   cpl_pf_num            <= host_pf_num;
                   cpl_vf_num            <= host_vf_num;
                   cpl_vf_active         <= host_vf_active;
                   cpl_msix_size_valid   <= host_msix_size_valid;
                   cpl_lower_addr        <= host_hdr_addr[6:0];
                   cpl_length            <= host_hdr[1];
                 end
                 else begin
                   cpl_error             <= 0;
                   cpl_hdr               <= 0;
                   cpl_bar_num           <= 0;
                   cpl_slot_num          <= 0;
                   cpl_pf_num            <= 0;
                   cpl_vf_num            <= 0;
                   cpl_vf_active         <= 0;
                   cpl_msix_size_valid   <= 1;
                   cpl_length            <= 0;
                 end
               end

        WAIT4OFFSET : begin
                        if (host_offset_ready) begin
                          Host_cpl_state <= WAIT4DATA;
                          cpl_byte_addr  <= host_msix_addr[3:0];
                        end
                      end

        WAIT4DATA : begin
                      cpl_cycle_cnt <= cpl_cycle_cnt+1'b1;
                      if (cpl_cycle_cnt==1) begin
                        Host_cpl_state <= FORM_DATA;
                      end
                    end

        FORM_DATA : casez ({host_pba_access, host_pba_2nd_rd})
                    2'b0? : begin
                              Host_cpl_state <= CPL_OUT;
                              case ({cpl_length,cpl_byte_addr[3]})
                              2'b00 : mem_data <= cpl_byte_addr[2] ? {32'b0,msix_rdata[1]} : {32'b0,msix_rdata[0]};
                              2'b01 : mem_data <= cpl_byte_addr[2] ? {32'b0,msix_rdata[3]} : {32'b0,msix_rdata[2]};
                              2'b10 : mem_data <= {msix_rdata[1],msix_rdata[0]};
                              2'b11 : mem_data <= {msix_rdata[3],msix_rdata[2]};
                              endcase
                            end
                    2'b10 : begin
                              Host_cpl_state <= CPL_OUT;
                              casez ({cpl_length,host_pba_bit_offset[5]})
                              2'b00 : mem_data <= {pba_rdata[1],pba_rdata[0]}>>host_pba_bit_offset[4:0];
                              2'b01 : mem_data <= {32'b0,pba_rdata[1]>>host_pba_bit_offset[4:0]};
                              2'b1? : mem_data <= {pba_rdata[1],pba_rdata[0]} >> host_pba_bit_offset[5:0];
                              endcase
                            end
                    2'b11 : begin
                              Host_cpl_state <= FORM_DATA2;
                              mem_data <= {pba_rdata[1],pba_rdata[0]} >> host_pba_bit_offset[5:0];
                            end
                    endcase

        FORM_DATA2 : begin
                       Host_cpl_state <= CPL_OUT;
                       mem_data <= {pba_rdata[1],pba_rdata[0]}<<('d64-host_pba_bit_offset[5:0]) | mem_data;
                     end

        CPL_OUT : begin
                    intc_st_cpl_tx_hdr[9:0]    <= cpl_error ? 0 : cpl_hdr[9:0];
                    intc_st_cpl_tx_hdr[23:10]  <= cpl_hdr[23:10];
                    intc_st_cpl_tx_hdr[28:24]  <= 'b01010;
                    intc_st_cpl_tx_hdr[31:29]  <= cpl_error ? 3'h0 : 3'h2;
                    intc_st_cpl_tx_hdr[43:32]  <= {cpl_hdr[9:0],2'b00};
                    intc_st_cpl_tx_hdr[44]     <= 1'b0;
                    intc_st_cpl_tx_hdr[47:45]  <= cpl_error ? 3'b100 : 3'b000;
                    intc_st_cpl_tx_hdr[63:48]  <= 0;
                    intc_st_cpl_tx_hdr[70:64]  <= MSIX_BAR_OFFSET + cpl_lower_addr;
                    intc_st_cpl_tx_hdr[71]     <= 0;
                    intc_st_cpl_tx_hdr[79:72]  <= cpl_hdr[47:40];
                    intc_st_cpl_tx_hdr[95:80]  <= cpl_hdr[63:48];
                    intc_st_cpl_tx_hdr[127:96]  <= 0;
                    intc_st_cpl_tx_hdr[159:128] <= 0;
                    intc_st_cpl_tx_hdr[162:160] <= cpl_pf_num;
                    intc_st_cpl_tx_hdr[173:163] <= cpl_vf_num;
                    intc_st_cpl_tx_hdr[174]     <= cpl_vf_active;
                    intc_st_cpl_tx_hdr[178:175] <= cpl_bar_num;
                    intc_st_cpl_tx_hdr[183:179] <= cpl_slot_num;
                    intc_st_cpl_tx_hdr[255:184] <= 0;

                    intc_st_cpl_tx_data        <= (cpl_error | ~cpl_msix_size_valid) ? 0 :
                                                   ~host_pba_access ? /*msix*/ mem_data :
                                                   {mem_data[63:32] & ({32{host_pba_valid_bit[6]}}|({32{host_pba_valid_bit[5]}} & ~({32{1'b1}}<<host_pba_valid_bit[4:0]))),
                                                    mem_data[31:0] & ({32{|host_pba_valid_bit[6:5]}}|~({32{1'b1}}<<host_pba_valid_bit[4:0]))};

                    intc_st_cpl_tx_tvalid      <= ~intc_st_cpl_tx_tvalid ? 1'b1 : ~intc_st_cpl_tx_tready;
                    Host_cpl_state             <= intc_st_cpl_tx_tready & host_sideband_err_rpt_done ? CPL_DONE :
                                                                                                       (intc_st_cpl_tx_tready ? CPL_WAIT4SB : CPL_HOLD);
                    host_err_rpt_cpl_done      <= intc_st_cpl_tx_tready;
                  end

        CPL_HOLD : begin
                     if (intc_st_cpl_tx_tready) begin
                       Host_cpl_state        <= host_sideband_err_rpt_done ? CPL_DONE : CPL_WAIT4SB;
                       intc_st_cpl_tx_hdr    <= 0;
                       intc_st_cpl_tx_data   <= 0;
                       intc_st_cpl_tx_tvalid <= 1'b0;
                       host_err_rpt_cpl_done <= 1'b1;
                     end
                   end

        CPL_WAIT4SB : begin
                        Host_cpl_state        <= host_sideband_err_rpt_done ? CPL_DONE : CPL_WAIT4SB;
                        intc_st_cpl_tx_hdr    <= 0;
                        intc_st_cpl_tx_data   <= 0;
                        intc_st_cpl_tx_tvalid <= 1'b0;
                        host_err_rpt_cpl_done <= 1'b0;
                      end

        CPL_DONE : begin
                     Host_cpl_state        <= IDLE;
                     intc_st_cpl_tx_tvalid <= 1'b0;
                     host_err_rpt_cpl_done <= 1'b0;
                   end

        endcase
      end
    end

  end
  endgenerate


  /*--------------- FLR Handling -----------------*/

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      flrfifo_rdreq  <= 0;
    end
    else begin
      if (~flrfifo_empty & Flr_state==FLR_IDLE)
        flrfifo_rdreq <= ~flrfifo_rdreq ? 1'b1 : 1'b0;
      else
        flrfifo_rdreq <= 0;
    end
  end

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1)
      flr_valid <= 0;
    else
      flr_valid <= ~flr_valid ? flrfifo_rdreq : ~(access==FLR);
  end

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      flr_pf_num    <= 0;
      flr_vf_num    <= 0;
      flr_vf_active <= 0;
    end
    else begin
      if (flr_valid) begin
        flr_pf_num    <= flrfifo_rdata[2:0];
        flr_vf_num    <= flrfifo_rdata[13:3];
        flr_vf_active <= flrfifo_rdata[14];
      end
    end
  end

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1)
      flr_pf_vf_count <= 0;
    else begin
      case (flr_pf_num)
      3'b000 : flr_pf_vf_count <= pf0_vf_count;
      3'b001 : flr_pf_vf_count <= pf1_vf_count;
      3'b010 : flr_pf_vf_count <= pf2_vf_count;
      3'b011 : flr_pf_vf_count <= pf3_vf_count;
      3'b100 : flr_pf_vf_count <= pf4_vf_count;
      3'b101 : flr_pf_vf_count <= pf5_vf_count;
      3'b110 : flr_pf_vf_count <= pf6_vf_count;
      3'b111 : flr_pf_vf_count <= pf7_vf_count;
      endcase
    end
  end

  generate
  if (MSIX_VECTOR_ALLOC=="Static") begin
    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        flr_pf_vec_num_start <= 0;
        flr_pf_vec_num_end   <= 0;
      end
      else begin
        flr_pf_vec_num_start <= MSIX_TABLE_SIZE*flr_pf_num;
        flr_pf_vec_num_end   <= (MSIX_TABLE_SIZE*(flr_pf_num+1)) - 1'b1;
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        flr_vf_vec_num_start <= 0;
      else begin
        case (flr_pf_num)
        3'b000 : flr_vf_vec_num_start <= MSIX_TABLE_SIZE*(PF0_VF_BASE + flr_vf_num);
        3'b001 : flr_vf_vec_num_start <= MSIX_TABLE_SIZE*(PF1_VF_BASE + flr_vf_num);
        3'b010 : flr_vf_vec_num_start <= MSIX_TABLE_SIZE*(PF2_VF_BASE + flr_vf_num);
        3'b011 : flr_vf_vec_num_start <= MSIX_TABLE_SIZE*(PF3_VF_BASE + flr_vf_num);
        3'b100 : flr_vf_vec_num_start <= MSIX_TABLE_SIZE*(PF4_VF_BASE + flr_vf_num);
        3'b101 : flr_vf_vec_num_start <= MSIX_TABLE_SIZE*(PF5_VF_BASE + flr_vf_num);
        3'b110 : flr_vf_vec_num_start <= MSIX_TABLE_SIZE*(PF6_VF_BASE + flr_vf_num);
        3'b111 : flr_vf_vec_num_start <= MSIX_TABLE_SIZE*(PF7_VF_BASE + flr_vf_num);
        endcase
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        flr_vf_vec_num_end <= 0;
      else begin
        case (flr_pf_num)
        3'b000 : flr_vf_vec_num_end <= (MSIX_TABLE_SIZE*(PF0_VF_BASE + flr_vf_num + 1)) - 1'b1;
        3'b001 : flr_vf_vec_num_end <= (MSIX_TABLE_SIZE*(PF1_VF_BASE + flr_vf_num + 1)) - 1'b1;
        3'b010 : flr_vf_vec_num_end <= (MSIX_TABLE_SIZE*(PF2_VF_BASE + flr_vf_num + 1)) - 1'b1;
        3'b011 : flr_vf_vec_num_end <= (MSIX_TABLE_SIZE*(PF3_VF_BASE + flr_vf_num + 1)) - 1'b1;
        3'b100 : flr_vf_vec_num_end <= (MSIX_TABLE_SIZE*(PF4_VF_BASE + flr_vf_num + 1)) - 1'b1;
        3'b101 : flr_vf_vec_num_end <= (MSIX_TABLE_SIZE*(PF5_VF_BASE + flr_vf_num + 1)) - 1'b1;
        3'b110 : flr_vf_vec_num_end <= (MSIX_TABLE_SIZE*(PF6_VF_BASE + flr_vf_num + 1)) - 1'b1;
        3'b111 : flr_vf_vec_num_end <= (MSIX_TABLE_SIZE*(PF7_VF_BASE + flr_vf_num + 1)) - 1'b1;
        endcase
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        flr_pf_vf_vec_num_start <= 0;
      else begin
        case (flr_pf_num)
        3'b000 : flr_pf_vf_vec_num_start <= MSIX_TABLE_SIZE*PF0_VF_BASE;
        3'b001 : flr_pf_vf_vec_num_start <= MSIX_TABLE_SIZE*PF1_VF_BASE;
        3'b010 : flr_pf_vf_vec_num_start <= MSIX_TABLE_SIZE*PF2_VF_BASE;
        3'b011 : flr_pf_vf_vec_num_start <= MSIX_TABLE_SIZE*PF3_VF_BASE;
        3'b100 : flr_pf_vf_vec_num_start <= MSIX_TABLE_SIZE*PF4_VF_BASE;
        3'b101 : flr_pf_vf_vec_num_start <= MSIX_TABLE_SIZE*PF5_VF_BASE;
        3'b110 : flr_pf_vf_vec_num_start <= MSIX_TABLE_SIZE*PF6_VF_BASE;
        3'b111 : flr_pf_vf_vec_num_start <= MSIX_TABLE_SIZE*PF7_VF_BASE;
        endcase
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        flr_pf_vf_vec_num_end <= 0;
      else begin
        case (flr_pf_num)
        3'b000 : flr_pf_vf_vec_num_end <= (MSIX_TABLE_SIZE * (PF0_VF_BASE + pf0_vf_count)) - 1'b1;
        3'b001 : flr_pf_vf_vec_num_end <= (MSIX_TABLE_SIZE * (PF1_VF_BASE + pf1_vf_count)) - 1'b1;
        3'b010 : flr_pf_vf_vec_num_end <= (MSIX_TABLE_SIZE * (PF2_VF_BASE + pf2_vf_count)) - 1'b1;
        3'b011 : flr_pf_vf_vec_num_end <= (MSIX_TABLE_SIZE * (PF3_VF_BASE + pf3_vf_count)) - 1'b1;
        3'b100 : flr_pf_vf_vec_num_end <= (MSIX_TABLE_SIZE * (PF4_VF_BASE + pf4_vf_count)) - 1'b1;
        3'b101 : flr_pf_vf_vec_num_end <= (MSIX_TABLE_SIZE * (PF5_VF_BASE + pf5_vf_count)) - 1'b1;
        3'b110 : flr_pf_vf_vec_num_end <= (MSIX_TABLE_SIZE * (PF6_VF_BASE + pf6_vf_count)) - 1'b1;
        3'b111 : flr_pf_vf_vec_num_end <= (MSIX_TABLE_SIZE * (PF7_VF_BASE + pf7_vf_count)) - 1'b1;
        endcase
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        Flr_state            <= FLR_IDLE;
        flr_vec_num_start    <= 0;
        flr_vec_num_end      <= 0;
        flr_pba_initiate     <= 0;
        flr_msix_initiate    <= 0;
        flr_cycle_cnt        <= 0;
        flrcmpl_fifo_tvalid  <= 0;
        flrcmpl_fifo_tdata   <= 0;
      end
      else begin
        case (Flr_state)
        FLR_IDLE          : begin
                              flrcmpl_fifo_tvalid <= 0;
                              flrcmpl_fifo_tdata  <= 0;
                              if (flrfifo_rdreq)
                                Flr_state <= FLR_VECNUMCALC;
                            end
        FLR_VECNUMCALC    : begin
                              flr_cycle_cnt <= flr_cycle_cnt+1'b1;
                              if (flr_cycle_cnt==1)
                                Flr_state <= FLR_WAIT4GRANT;
                            end
        FLR_WAIT4GRANT    : begin
                              flr_vec_num_start <= flr_vf_active ? flr_vf_vec_num_start : flr_pf_vec_num_start;
                              flr_vec_num_end   <= flr_vf_active ? flr_vf_vec_num_end : flr_pf_vec_num_end;
                              if (access==FLR) begin
                                Flr_state <= FLR_WAIT4CMPL;
                                flr_pba_initiate  <= 1;
                                flr_msix_initiate <= 1;
                              end
                            end
        FLR_WAIT4CMPL     : begin
                              if (flr_pba_completed & flr_msix_completed) begin
                                Flr_state         <= (flr_vf_active | flr_pf_vf_count==0) ? FLR_CMPL : FLR_INIT_VF;
                                flr_pba_initiate  <= 0;
                                flr_msix_initiate <= 0;
                              end
                            end
        FLR_CMPL          : begin
                              Flr_state <= flrcmpl_fifo_tready ? FLR_IDLE : FLR_CMPL;
                              flrcmpl_fifo_tdata[2:0]   <= flr_pf_num;
                              flrcmpl_fifo_tdata[13:3]  <= flr_vf_num;
                              flrcmpl_fifo_tdata[14]    <= flr_vf_active;
                              flrcmpl_fifo_tvalid       <= flrcmpl_fifo_tready ? 1'b1 : 1'b0;
                            end
        FLR_INIT_VF       : begin
                              flr_vec_num_start <= flr_pf_vf_vec_num_start;
                              flr_vec_num_end   <= flr_pf_vf_vec_num_end;
                              flr_pba_initiate  <= 1;
                              flr_msix_initiate <= 1;
                              Flr_state         <= FLR_WAIT4VFCMPL;
                            end
        FLR_WAIT4VFCMPL   : begin
                              if (flr_pba_completed & flr_msix_completed) begin
                                Flr_state         <= FLR_CMPL;
                                flr_pba_initiate  <= 0;
                                flr_msix_initiate <= 0;
                              end
                            end
        FLR_HOLD          : begin
                              if (flrcmpl_fifo_tready) begin
                                Flr_state           <= FLR_IDLE;
                                flrcmpl_fifo_tdata  <= 0;
                                flrcmpl_fifo_tvalid <= 0;
                              end
                            end
        endcase
      end
    end
  end
  else begin

    always @* begin
      case (flr_pf_num)
      3'b000 : cumulative_flr_vf_num = PF0_VF_BASE + flr_vf_num;
      3'b001 : cumulative_flr_vf_num = PF1_VF_BASE + flr_vf_num;
      3'b010 : cumulative_flr_vf_num = PF2_VF_BASE + flr_vf_num;
      3'b011 : cumulative_flr_vf_num = PF3_VF_BASE + flr_vf_num;
      3'b100 : cumulative_flr_vf_num = PF4_VF_BASE + flr_vf_num;
      3'b101 : cumulative_flr_vf_num = PF5_VF_BASE + flr_vf_num;
      3'b110 : cumulative_flr_vf_num = PF6_VF_BASE + flr_vf_num;
      3'b111 : cumulative_flr_vf_num = PF7_VF_BASE + flr_vf_num;
      endcase
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        flr_pf_vf_start <= 0;
      else begin
        case (flr_pf_num)
        3'b000 : flr_pf_vf_start <= PF0_VF_BASE;
        3'b001 : flr_pf_vf_start <= PF1_VF_BASE;
        3'b010 : flr_pf_vf_start <= PF2_VF_BASE;
        3'b011 : flr_pf_vf_start <= PF3_VF_BASE;
        3'b100 : flr_pf_vf_start <= PF4_VF_BASE;
        3'b101 : flr_pf_vf_start <= PF5_VF_BASE;
        3'b110 : flr_pf_vf_start <= PF6_VF_BASE;
        3'b111 : flr_pf_vf_start <= PF7_VF_BASE;
        endcase
      end
    end

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        flr_pf_vf_end <= 0;
      else begin
        case (flr_pf_num)
        3'b000 : flr_pf_vf_end <= PF0_VF_BASE + pf0_vf_count - 1;
        3'b001 : flr_pf_vf_end <= PF1_VF_BASE + pf1_vf_count - 1;
        3'b010 : flr_pf_vf_end <= PF2_VF_BASE + pf2_vf_count - 1;
        3'b011 : flr_pf_vf_end <= PF3_VF_BASE + pf3_vf_count - 1;
        3'b100 : flr_pf_vf_end <= PF4_VF_BASE + pf4_vf_count - 1;
        3'b101 : flr_pf_vf_end <= PF5_VF_BASE + pf5_vf_count - 1;
        3'b110 : flr_pf_vf_end <= PF6_VF_BASE + pf6_vf_count - 1;
        3'b111 : flr_pf_vf_end <= PF7_VF_BASE + pf7_vf_count - 1;
        endcase
      end
    end


    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1) begin
        Flr_state            <= FLR_IDLE;
        flr_vec_num_start    <= 0;
        flr_vec_num_end      <= 0;
        flr_vf_vec_num_valid <= 0;
        flr_pba_initiate     <= 0;
        flr_msix_initiate    <= 0;
        flr_cycle_cnt        <= 0;
        flrcmpl_fifo_tvalid  <= 0;
        flrcmpl_fifo_tdata   <= 0;
        flr_offset_rden      <= 0;
        flr_offset_raddr     <= 0;
        flr_offset_cycle_cnt <= 0;
        flr_pf_vf_offset     <= 0;
      end
      else begin
        case (Flr_state)
        FLR_IDLE          : begin
                              flr_vf_vec_num_valid <= 0;
                              flr_offset_cycle_cnt <= 0;
                              flr_pf_vf_offset     <= 0;
                              flrcmpl_fifo_tvalid  <= 0;
                              flrcmpl_fifo_tdata   <= 0;
                              if (flrfifo_rdreq)
                                Flr_state <= FLR_VECNUMCALC;
                            end
        FLR_VECNUMCALC    : begin
                              flr_cycle_cnt <= flr_cycle_cnt+1'b1;
                              if (flr_cycle_cnt==1)
                                Flr_state <= FLR_WAIT4GRANT;
                            end
        FLR_WAIT4GRANT    : begin
                              if (access==FLR) begin
                                Flr_state <= FLR_WAIT4OFFSET;
                                flr_offset_rden  <= 1;
                                flr_offset_raddr <= flr_vf_active ? cumulative_flr_vf_num : flr_pf_num;
                              end
                            end
        FLR_WAIT4OFFSET   : begin
                              flr_offset_rden      <= 0;
                              flr_offset_raddr     <= 0;
                              flr_offset_cycle_cnt <= flr_offset_cycle_cnt+1'b1;
                              if (flr_offset_cycle_cnt==3) begin
                                Flr_state         <= offset_rdata[MSIX_TABLE_ADDR_WIDTH*2] ? FLR_CMPL : FLR_WAIT4CMPL;
                                flr_pba_initiate  <= offset_rdata[MSIX_TABLE_ADDR_WIDTH*2] ? 0 : 1;
                                flr_msix_initiate <= offset_rdata[MSIX_TABLE_ADDR_WIDTH*2] ? 0 : 1;
                                flr_vec_num_start <= offset_rdata[0+:MSIX_TABLE_ADDR_WIDTH];
                                flr_vec_num_end   <= offset_rdata[MSIX_TABLE_ADDR_WIDTH+:MSIX_TABLE_ADDR_WIDTH];
                              end
                            end
        FLR_WAIT4CMPL     : begin
                              flr_offset_cycle_cnt <= 0;
                              if (flr_pba_completed & flr_msix_completed) begin
                                Flr_state         <= (flr_vf_active | flr_pf_vf_count==0) ? FLR_CMPL : FLR_GETVFOFFSET;
                                flr_pba_initiate  <= 0;
                                flr_msix_initiate <= 0;
                              end
                            end
        FLR_GETVFOFFSET      : begin
                              flr_offset_rden      <= 1;
                              flr_offset_raddr     <= flr_pf_vf_start + flr_pf_vf_offset;
                              flr_offset_cycle_cnt <= 0;
                              Flr_state            <= FLR_WAIT4VFOFFSET;
                            end
        FLR_WAIT4VFOFFSET : begin
                              flr_offset_rden      <= 0;
                              flr_offset_cycle_cnt <= flr_offset_cycle_cnt+1'b1;
                              if (flr_offset_cycle_cnt==3) begin
                                Flr_state            <= flr_offset_raddr==flr_pf_vf_end ? FLR_INIT_VF : FLR_GETVFOFFSET;
                                flr_pf_vf_offset     <= flr_offset_raddr==flr_pf_vf_end ? 0 : flr_pf_vf_offset+1'b1;
                                flr_vec_num_start    <= ~flr_vf_vec_num_valid ? (offset_rdata[MSIX_TABLE_ADDR_WIDTH*2] ? flr_vec_num_start : offset_rdata[0+:MSIX_TABLE_ADDR_WIDTH]) : flr_vec_num_start;
                                flr_vec_num_end      <= ~offset_rdata[MSIX_TABLE_ADDR_WIDTH*2] ? offset_rdata[MSIX_TABLE_ADDR_WIDTH+:MSIX_TABLE_ADDR_WIDTH] : flr_vec_num_end;
                                flr_vf_vec_num_valid <= ~flr_vf_vec_num_valid ? ~offset_rdata[MSIX_TABLE_ADDR_WIDTH*2] : flr_vf_vec_num_valid;
                              end
                            end
        FLR_INIT_VF       : begin
                              Flr_state         <= flr_vf_vec_num_valid ? FLR_WAIT4VFCMPL : FLR_CMPL;
                              flr_pba_initiate  <= flr_vf_vec_num_valid ? 1 : 0;
                              flr_msix_initiate <= flr_vf_vec_num_valid ? 1 : 0;
                            end
        FLR_WAIT4VFCMPL   : begin
                              if (flr_pba_completed & flr_msix_completed) begin
                                Flr_state         <= FLR_CMPL;
                                flr_pba_initiate  <= 0;
                                flr_msix_initiate <= 0;
                              end
                            end
        FLR_CMPL          : begin
                              Flr_state <= flrcmpl_fifo_tready ? FLR_IDLE : FLR_CMPL;
                              flrcmpl_fifo_tdata[2:0]   <= flr_pf_num;
                              flrcmpl_fifo_tdata[13:3]  <= flr_vf_num;
                              flrcmpl_fifo_tdata[14]    <= flr_vf_active;
                              flrcmpl_fifo_tvalid       <= flrcmpl_fifo_tready ? 1'b1 : 1'b0;
                            end
        FLR_HOLD          : begin
                              if (flrcmpl_fifo_tready) begin
                                Flr_state           <= FLR_IDLE;
                                flrcmpl_fifo_tdata  <= 0;
                                flrcmpl_fifo_tvalid <= 0;
                              end
                            end
        endcase
      end
    end
  end
  endgenerate


  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      Flr_msix_state         <= FLR_MSIX_IDLE;
      flr_msix_completed     <= 0;
      flr_msix_waddr         <= 0;
      flr_msix_wren          <= 0;
    end
    else begin
      case (Flr_msix_state)
      FLR_MSIX_IDLE :  begin
                         flr_msix_completed <= 0;
                         if (flr_msix_initiate) begin
                           Flr_msix_state <= FLR_MSIX_CLEAR;
                           flr_msix_waddr <= flr_vec_num_start;
                           flr_msix_wren  <= 1;
                         end
                       end
      FLR_MSIX_CLEAR : begin
                         if (flr_msix_waddr==flr_vec_num_end) begin
                           Flr_msix_state     <= FLR_MSIX_HOLD;
                           flr_msix_wren      <= 0;
                           flr_msix_waddr     <= 0;
                         end
                         else
                           flr_msix_waddr <= flr_msix_waddr+1;
                       end
      FLR_MSIX_HOLD  : begin
                         flr_msix_completed <= 1;
                         if (Flr_state==FLR_CMPL | Flr_state==FLR_INIT_VF)
                           Flr_msix_state   <= FLR_MSIX_IDLE;
                       end
      endcase
    end
  end

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      flr_pba_raddr_d1 <= 0;
      flr_pba_raddr_d2 <= 0;
      flr_pba_raddr_d3 <= 0;
    end
    else begin
      flr_pba_raddr_d1 <= flr_pba_raddr;
      flr_pba_raddr_d2 <= flr_pba_raddr_d1;
      flr_pba_raddr_d3 <= flr_pba_raddr_d2;
    end
  end

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      Flr_pba_state         <= FLR_PBA_IDLE;
      flr_pba_completed     <= 0;
      flr_pba_raddr         <= 0;
      flr_pba_rden          <= 0;
      flr_pba_waddr         <= 0;
      flr_pba_wren          <= 0;
      flr_pba_wdata         <= 0;
    end
    else begin
      case (Flr_pba_state)
      FLR_PBA_IDLE :    begin
                           flr_pba_cycle_cnt <= 0;
                           flr_pba_completed <= 0;
                           if (flr_pba_initiate) begin
                             Flr_pba_state <= FLR_PBA_INITIATE;
                             flr_pba_raddr <= flr_vec_num_start[$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:6];
                             flr_pba_rden  <= 1'b1;
                           end
                         end
      FLR_PBA_INITIATE : begin
                           flr_pba_cycle_cnt <= flr_pba_cycle_cnt+1'b1;
                           if (flr_pba_cycle_cnt==2)
                             Flr_pba_state <= FLR_PBA_CLEAR;

                           if (flr_pba_raddr != flr_vec_num_end[$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:6])
                             flr_pba_raddr <= flr_pba_raddr+1'b1;
                           else
                             flr_pba_rden <= 1'b0;
                         end
      FLR_PBA_CLEAR :    begin
                           if ((flr_pba_raddr_d3==flr_vec_num_end[$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:6]) & (flr_pba_raddr_d3==flr_vec_num_start[$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:6])) begin
                             flr_pba_wdata <= ({pba_rdata[1],pba_rdata[0]}&~({64{1'b1}}<<flr_vec_num_start[5:0])) |
                                              ({pba_rdata[1],pba_rdata[0]}&({64{1'b1}}<<({1'b0,flr_vec_num_end[5:0]} + 1'b1)));
                             flr_pba_wren  <= 1'b1;
                             flr_pba_waddr <= flr_pba_raddr_d3;
                             flr_pba_rden  <= 1'b0;
                             Flr_pba_state <= FLR_PBA_HOLD;
                           end
                           else if (flr_pba_raddr_d3==flr_vec_num_start[$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:6]) begin
                             flr_pba_wdata <= {pba_rdata[1],pba_rdata[0]}&~({64{1'b1}}<<flr_vec_num_start[5:0]);
                             flr_pba_wren  <= 1'b1;
                             flr_pba_waddr <= flr_pba_raddr_d3;
                             flr_pba_raddr <= flr_pba_raddr+1'b1;
                           end
                           else if (flr_pba_raddr_d3==flr_vec_num_end[$clog2(MAX_TOTAL_MSIX_TABLE_SIZE)-1:6]) begin
                             flr_pba_wdata <= {pba_rdata[1],pba_rdata[0]}&({64{1'b1}}<<({1'b0,flr_vec_num_end[5:0]} + 1'b1));
                             flr_pba_wren  <= 1'b1;
                             flr_pba_waddr <= flr_pba_raddr_d3;
                             flr_pba_rden  <= 1'b0;
                             Flr_pba_state <= FLR_PBA_HOLD;
                           end
                           else begin
                             flr_pba_wdata <= 0;
                             flr_pba_wren  <= 1'b1;
                             flr_pba_waddr <= flr_pba_raddr_d3;
                             flr_pba_raddr <= flr_pba_raddr+1'b1;
                           end
                         end
      FLR_PBA_HOLD  :    begin
                           flr_pba_wdata <= 0;
                           flr_pba_wren  <= 1'b0;
                           if (Flr_state==FLR_CMPL | Flr_state==FLR_INIT_VF) begin
                             Flr_pba_state     <= FLR_PBA_IDLE;
                             flr_pba_completed <= 0;
                           end
                           else
                             flr_pba_completed <= 1;
                         end
      endcase
    end
  end


  /*--------------- SS Reset Request Handling -----------------*/

  always @(posedge axi_st_clk or negedge stclk_rst_n_1)
  begin
    if (~stclk_rst_n_1) begin
      rst_req_msix_waddr <= 0;
      rst_req_pba_waddr  <= 0;
    end
    else begin
      if (subsystem_rst_req) begin
        rst_req_msix_waddr <= rst_req_msix_waddr==(2**MSIX_TABLE_ADDR_WIDTH-1) ? rst_req_msix_waddr : rst_req_msix_waddr+1'b1;
        rst_req_pba_waddr  <= rst_req_pba_waddr==(2**PBA_DEPTH-1) ? rst_req_pba_waddr : rst_req_pba_waddr+1'b1;
      end
    end
  end

  assign subsystem_rst_rdy = subsystem_rst_req & rst_req_msix_waddr==(2**MSIX_TABLE_ADDR_WIDTH-1);

  genvar i;
  generate
    for (i=0; i<4; i++) begin : gen_msix
      altera_syncram #(
      .width_a                              ( 32                                                              ),
      .widthad_a                            ( MSIX_TABLE_ADDR_WIDTH                                           ),
      .widthad2_a                           ( MSIX_TABLE_ADDR_WIDTH                                           ),
      .numwords_a                           ( 2**MSIX_TABLE_ADDR_WIDTH                                        ),
      .outdata_reg_a                        ( "CLOCK0"                                                        ),
      .address_aclr_a                       ( "NONE"                                                          ),
      .outdata_aclr_a                       ( "NONE"                                                          ),
      .width_byteena_a                      ( 1                                                               ),

      .width_b                              ( 32                                                              ),
      .widthad_b                            ( MSIX_TABLE_ADDR_WIDTH                                           ),
      .widthad2_b                           ( MSIX_TABLE_ADDR_WIDTH                                           ),
      .numwords_b                           ( 2**MSIX_TABLE_ADDR_WIDTH                                        ),
      .rdcontrol_reg_b                      ( "CLOCK0"                                                        ),
      .address_reg_b                        ( "CLOCK0"                                                        ),
      .outdata_reg_b                        ( "CLOCK0"                                                        ),
      .outdata_aclr_b                       ( "CLEAR0"                                                        ),
      .indata_reg_b                         ( "CLOCK0"                                                        ),
      .byteena_reg_b                        ( "CLOCK0"                                                        ),
      .address_aclr_b                       ( "NONE"                                                          ),
      .width_byteena_b                      ( 1                                                               ),

      .clock_enable_input_a                 ( "BYPASS"                                                        ),
      .clock_enable_output_a                ( "BYPASS"                                                        ),
      .clock_enable_input_b                 ( "BYPASS"                                                        ),
      .clock_enable_output_b                ( "BYPASS"                                                        ),
      .clock_enable_core_a                  ( "BYPASS"                                                        ),
      .clock_enable_core_b                  ( "BYPASS"                                                        ),

      .operation_mode                       ( "DUAL_PORT"                                                     ),
      .optimization_option                  ( "AUTO"                                                          ),
      .ram_block_type                       ( "AUTO"                                                          ),
      .init_file                            ( "UNUSED"                                                        ),
      .intended_device_family               ( DEVICE_FAMILY                                                   ),
      .read_during_write_mode_port_b        ( "OLD_DATA"                                                      ),
      .read_during_write_mode_mixed_ports   ( "OLD_DATA"                                                      )
      ) u_msix_table (
      .wren_a                               ( subsystem_rst_req ? 1'b1 : msix_wren[i]                         ),
      .wren_b                               ( 1'b0                                                            ),
      .rden_a                               ( 1'b0                                                            ),
      .rden_b                               ( msix_rden                                                       ),
      .data_a                               ( subsystem_rst_req ? (i==3 ? 32'h1 : {32{1'b0}}) : msix_wdata[i] ),
      .data_b                               ( {32{1'b0}}                                                      ),
      .address_a                            ( subsystem_rst_req ? rst_req_msix_waddr : msix_waddr             ),
      .address_b                            ( msix_raddr                                                      ),
      .clock0                               ( axi_st_clk                                                      ),
      .clock1                               ( 1'b1                                                            ),
      .clocken0                             ( 1'b1                                                            ),
      .clocken1                             ( 1'b1                                                            ),
      .clocken2                             ( 1'b1                                                            ),
      .clocken3                             ( 1'b1                                                            ),
      .aclr0                                ( ~stclk_rst_n_3                                                  ),
      .aclr1                                ( 1'b0                                                            ),
      .byteena_a                            ( 1'b1                                                            ),
      .byteena_b                            ( 1'b1                                                            ),
      .addressstall_a                       ( 1'b0                                                            ),
      .addressstall_b                       ( 1'b0                                                            ),
      .sclr                                 ( 1'b0                                                            ),
      .eccencbypass                         ( 1'b0                                                            ),
      .eccencparity                         ( 8'b0                                                            ),
      .eccstatus                            (                                                                 ),
      .address2_a                           ( {MSIX_TABLE_ADDR_WIDTH{1'b1}}                                   ),
      .address2_b                           ( {MSIX_TABLE_ADDR_WIDTH{1'b1}}                                   ),
      .q_a                                  (                                                                 ),
      .q_b                                  ( msix_rdata[i]                                                   )
      );
    end
  endgenerate


  genvar j;
  generate
    for (j=0; j<2; j++) begin : gen_pba
      altera_syncram #(
      .width_a                              ( 32                                                  ),
      .widthad_a                            ( PBA_DEPTH                                           ),
      .widthad2_a                           ( PBA_DEPTH                                           ),
      .numwords_a                           ( 2**PBA_DEPTH                                        ),
      .outdata_reg_a                        ( "CLOCK0"                                            ),
      .address_aclr_a                       ( "NONE"                                              ),
      .outdata_aclr_a                       ( "NONE"                                              ),
      .width_byteena_a                      ( 1                                                   ),

      .width_b                              ( 32                                                  ),
      .widthad_b                            ( PBA_DEPTH                                           ),
      .widthad2_b                           ( PBA_DEPTH                                           ),
      .numwords_b                           ( 2**PBA_DEPTH                                        ),
      .rdcontrol_reg_b                      ( "CLOCK0"                                            ),
      .address_reg_b                        ( "CLOCK0"                                            ),
      .outdata_reg_b                        ( "CLOCK0"                                            ),
      .outdata_aclr_b                       ( "CLEAR0"                                            ),
      .indata_reg_b                         ( "CLOCK0"                                            ),
      .byteena_reg_b                        ( "CLOCK0"                                            ),
      .address_aclr_b                       ( "NONE"                                              ),
      .width_byteena_b                      ( 1                                                   ),

      .clock_enable_input_a                 ( "BYPASS"                                            ),
      .clock_enable_output_a                ( "BYPASS"                                            ),
      .clock_enable_input_b                 ( "BYPASS"                                            ),
      .clock_enable_output_b                ( "BYPASS"                                            ),
      .clock_enable_core_a                  ( "BYPASS"                                            ),
      .clock_enable_core_b                  ( "BYPASS"                                            ),

      .operation_mode                       ( "DUAL_PORT"                                         ),
      .optimization_option                  ( "AUTO"                                              ),
      .ram_block_type                       ( "AUTO"                                              ),
      .intended_device_family               ( DEVICE_FAMILY                                       ),
      .read_during_write_mode_port_b        ( "OLD_DATA"                                          ),
      .read_during_write_mode_mixed_ports   ( "OLD_DATA"                                          )
      ) u_pba (
      .wren_a                               ( subsystem_rst_req ? 1'b1 : pba_wren[j]              ),
      .wren_b                               ( 1'b0                                                ),
      .rden_a                               ( 1'b0                                                ),
      .rden_b                               ( pba_rden                                            ),
      .data_a                               ( subsystem_rst_req ? {32{1'b0}} : pba_wdata[j]       ),
      .data_b                               ( {32{1'b0}}                                          ),
      .address_a                            ( subsystem_rst_req ? rst_req_pba_waddr : pba_waddr   ),
      .address_b                            ( pba_raddr                                           ),
      .clock0                               ( axi_st_clk                                          ),
      .clock1                               ( 1'b1                                                ),
      .clocken0                             ( 1'b1                                                ),
      .clocken1                             ( 1'b1                                                ),
      .clocken2                             ( 1'b1                                                ),
      .clocken3                             ( 1'b1                                                ),
      .aclr0                                ( ~stclk_rst_n_1                                        ),
      .aclr1                                ( 1'b0                                                ),
      .byteena_a                            ( 1'b1                                                ),
      .byteena_b                            ( 1'b1                                                ),
      .addressstall_a                       ( 1'b0                                                ),
      .addressstall_b                       ( 1'b0                                                ),
      .sclr                                 ( 1'b0                                                ),
      .eccencbypass                         ( 1'b0                                                ),
      .eccencparity                         ( 8'b0                                                ),
      .eccstatus                            (                                                     ),
      .address2_a                           ( {PBA_DEPTH{1'b1}}                                   ),
      .address2_b                           ( {PBA_DEPTH{1'b1}}                                   ),
      .q_a                                  (                                                     ),
      .q_b                                  ( pba_rdata[j]                                        )
      );
    end
  endgenerate

  scfifo #(
  .lpm_width                ( PFIFO_WIDTH                                    ),
  .lpm_widthu               ( $clog2(PFIFO_DEPTH)                            ),
  .lpm_numwords             ( 2**$clog2(PFIFO_DEPTH)                         ),
  .overflow_checking        ( "OFF"                                          ),
  .underflow_checking       ( "OFF"                                          ),
  .use_eab                  ( "ON"                                           ),
  .almost_full_value        ( PFIFO_DEPTH-2                                  ),
  .add_ram_output_register  ( "ON"                                           )
  ) u_pending_fifo (
  .data                     ( pfifo_wdata                                    ),
  .clock                    ( axi_st_clk                                     ),
  .wrreq                    ( pfifo_wrreq & ~pfifo_full                      ),
  .rdreq                    ( subsystem_rst_req ? ~pfifo_empty : pfifo_rdreq ),
  .aclr                     ( ~stclk_rst_n_1                                   ),
  .sclr                     ( 1'b0                                           ),
  .q                        ( pfifo_rdata                                    ),
  .eccstatus                (                                                ),
  .usedw                    (                                                ),
  .full                     ( pfifo_full                                     ),
  .empty                    ( pfifo_empty                                    ),
  .almost_full              ( pfifo_almost_full                              ),
  .almost_empty             (                                                )
  );

  // Incoming FLR, cross from axi_lite_clk to axi_st_clk
  dcfifo #(
  .lpm_width                ( FLRFIFO_WIDTH                                                       ),
  .lpm_widthu               ( FLRFIFO_DEPTH                                                       ),
  .lpm_numwords             ( 2**FLRFIFO_DEPTH                                                    ),
  .overflow_checking        ( "OFF"                                                               ),
  .underflow_checking       ( "OFF"                                                               ),
  .ram_block_type           ( "M20K"                                                              )
  ) u_flrrcvd_fifo (
  .aclr                     ( ~stclk_rst_n_1                                                        ),
  .wrclk                    ( axi_lite_clk                                                        ),
  .data                     ( flrrcvd_tdata[14:0]                                                 ),
  .wrreq                    ( flrrcvd_tvalid                                                      ),
  .wrusedw                  (                                                                     ),
  .wrempty                  (                                                                     ),
  .wrfull                   (                                                                     ),
  .rdclk                    ( axi_st_clk                                                          ),
  .rdreq                    ( subsystem_rst_req ? ~flrfifo_empty : flrfifo_rdreq & ~flrfifo_empty ),
  .rdfull                   (                                                                     ),
  .rdempty                  ( flrfifo_empty                                                       ),
  .rdusedw                  (                                                                     ),
  .q                        ( flrfifo_rdata                                                       ),
  .eccstatus                (                                                                     )
  );


  // Outgoing FLR completion, cross back to axi_lite_clk
  logic flrcmpl_fifo_full;
  assign flrcmpl_fifo_tready = ~flrcmpl_fifo_full;
  logic flrcmpl_fifo_empty;
  assign intc_flrcmpl_tvalid = ~flrcmpl_fifo_empty;

  dcfifo #(
  .lpm_width                ( $bits(flrcmpl_fifo_tdata)                                           ),
  .lpm_widthu               ( 2                                                                   ),
  .lpm_numwords             ( 4                                                                   ),
  .lpm_showahead            ( "ON"                                                                ),
  .overflow_checking        ( "OFF"                                                               ),
  .underflow_checking       ( "OFF"                                                               )
) u_flrcmpl_fifo (
  .aclr                     ( ~stclk_rst_n_1                                                      ),
  .wrclk                    ( axi_st_clk                                                          ),
  .data                     ( flrcmpl_fifo_tdata                                                  ),
  .wrreq                    ( flrcmpl_fifo_tvalid & ~flrcmpl_fifo_full                            ),
  .wrusedw                  (                                                                     ),
  .wrempty                  (                                                                     ),
  .wrfull                   ( flrcmpl_fifo_full                                                   ),
  .rdclk                    ( axi_lite_clk                                                        ),
  .rdreq                    ( flrif_flrcmpl_tready & ~flrcmpl_fifo_empty                          ),
  .rdfull                   (                                                                     ),
  .rdempty                  ( flrcmpl_fifo_empty                                                  ),
  .rdusedw                  (                                                                     ),
  .q                        ( intc_flrcmpl_tdata                                                  ),
  .eccstatus                (                                                                     )
  );


  generate
  if (MSIX_VECTOR_ALLOC=="Dynamic") begin : gen_dyn

    always @(posedge axi_st_clk or negedge stclk_rst_n_1)
    begin
      if (~stclk_rst_n_1)
        rst_req_size_waddr  <= 0;
      else
        if (subsystem_rst_req)
          rst_req_size_waddr  <= rst_req_size_waddr==(2**SIZE_REG_ADDR_WIDTH-1) ? rst_req_size_waddr : rst_req_size_waddr+1'b1;
    end

    altera_syncram #(
      .width_a                              ( 12                                                  ),
      .widthad_a                            ( SIZE_REG_ADDR_WIDTH                                 ),
      .widthad2_a                           ( SIZE_REG_ADDR_WIDTH                                 ),
      .numwords_a                           ( 2**SIZE_REG_ADDR_WIDTH                              ),
      .outdata_reg_a                        ( "CLOCK0"                                            ),
      .address_aclr_a                       ( "NONE"                                              ),
      .outdata_aclr_a                       ( "NONE"                                              ),
      .width_byteena_a                      ( 1                                                   ),

      .width_b                              ( 12                                                  ),
      .widthad_b                            ( SIZE_REG_ADDR_WIDTH                                 ),
      .widthad2_b                           ( SIZE_REG_ADDR_WIDTH                                 ),
      .numwords_b                           ( 2**SIZE_REG_ADDR_WIDTH                              ),
      .rdcontrol_reg_b                      ( "CLOCK0"                                            ),
      .address_reg_b                        ( "CLOCK0"                                            ),
      .outdata_reg_b                        ( "UNREGISTERED"                                      ),
      .outdata_aclr_b                       ( "CLEAR0"                                            ),
      .indata_reg_b                         ( "CLOCK0"                                            ),
      .byteena_reg_b                        ( "CLOCK0"                                            ),
      .address_aclr_b                       ( "NONE"                                              ),
      .width_byteena_b                      ( 1                                                   ),

      .clock_enable_input_a                 ( "BYPASS"                                            ),
      .clock_enable_output_a                ( "BYPASS"                                            ),
      .clock_enable_input_b                 ( "BYPASS"                                            ),
      .clock_enable_output_b                ( "BYPASS"                                            ),
      .clock_enable_core_a                  ( "BYPASS"                                            ),
      .clock_enable_core_b                  ( "BYPASS"                                            ),

      .operation_mode                       ( "DUAL_PORT"                                         ),
      .optimization_option                  ( "AUTO"                                              ),
      .ram_block_type                       ( "AUTO"                                              ),
      .intended_device_family               ( DEVICE_FAMILY                                       ),
      .read_during_write_mode_port_b        ( "OLD_DATA"                                          ),
      .read_during_write_mode_mixed_ports   ( "OLD_DATA"                                          )
      ) u_size (
      .wren_a                               ( subsystem_rst_req ? 1'b1 : size_wren                ),
      .wren_b                               ( 1'b0                                                ),
      .rden_a                               ( 1'b0                                                ),
      .rden_b                               ( size_rden                                           ),
      .data_a                               ( subsystem_rst_req ? {12{1'b0}} : size_wdata         ),
      .data_b                               ( {12{1'b0}}                                          ),
      .address_a                            ( subsystem_rst_req ? rst_req_size_waddr : size_waddr ),
      .address_b                            ( size_raddr                                          ),
      .clock0                               ( axi_st_clk                                          ),
      .clock1                               ( 1'b1                                                ),
      .clocken0                             ( 1'b1                                                ),
      .clocken1                             ( 1'b1                                                ),
      .clocken2                             ( 1'b1                                                ),
      .clocken3                             ( 1'b1                                                ),
      .aclr0                                ( ~stclk_rst_n_1                                        ),
      .aclr1                                ( 1'b0                                                ),
      .byteena_a                            ( 1'b1                                                ),
      .byteena_b                            ( 1'b1                                                ),
      .addressstall_a                       ( 1'b0                                                ),
      .addressstall_b                       ( 1'b0                                                ),
      .sclr                                 ( 1'b0                                                ),
      .eccencbypass                         ( 1'b0                                                ),
      .eccencparity                         ( 8'b0                                                ),
      .eccstatus                            (                                                     ),
      .address2_a                           ( {SIZE_REG_ADDR_WIDTH{1'b1}}                         ),
      .address2_b                           ( {SIZE_REG_ADDR_WIDTH{1'b1}}                         ),
      .q_a                                  (                                                     ),
      .q_b                                  ( size_rdata                                          )
      );

    altera_syncram #(
      .width_a                              ( MSIX_TABLE_ADDR_WIDTH*2+1                                              ),
      .widthad_a                            ( SIZE_REG_ADDR_WIDTH                                                    ),
      .widthad2_a                           ( SIZE_REG_ADDR_WIDTH                                                    ),
      .numwords_a                           ( 2**SIZE_REG_ADDR_WIDTH                                                 ),
      .outdata_reg_a                        ( "CLOCK0"                                                               ),
      .address_aclr_a                       ( "NONE"                                                                 ),
      .outdata_aclr_a                       ( "NONE"                                                                 ),
      .width_byteena_a                      ( 1                                                                      ),

      .width_b                              ( MSIX_TABLE_ADDR_WIDTH*2+1                                              ),
      .widthad_b                            ( SIZE_REG_ADDR_WIDTH                                                    ),
      .widthad2_b                           ( SIZE_REG_ADDR_WIDTH                                                    ),
      .numwords_b                           ( 2**SIZE_REG_ADDR_WIDTH                                                 ),
      .rdcontrol_reg_b                      ( "CLOCK0"                                                               ),
      .address_reg_b                        ( "CLOCK0"                                                               ),
      .outdata_reg_b                        ( "CLOCK0"                                                               ),
      .outdata_aclr_b                       ( "CLEAR0"                                                               ),
      .indata_reg_b                         ( "CLOCK0"                                                               ),
      .byteena_reg_b                        ( "CLOCK0"                                                               ),
      .address_aclr_b                       ( "NONE"                                                                 ),
      .width_byteena_b                      ( 1                                                                      ),

      .clock_enable_input_a                 ( "BYPASS"                                                               ),
      .clock_enable_output_a                ( "BYPASS"                                                               ),
      .clock_enable_input_b                 ( "BYPASS"                                                               ),
      .clock_enable_output_b                ( "BYPASS"                                                               ),
      .clock_enable_core_a                  ( "BYPASS"                                                               ),
      .clock_enable_core_b                  ( "BYPASS"                                                               ),

      .operation_mode                       ( "DUAL_PORT"                                                            ),
      .optimization_option                  ( "AUTO"                                                                 ),
      .ram_block_type                       ( "AUTO"                                                                 ),
      .intended_device_family               ( DEVICE_FAMILY                                                          ),
      .read_during_write_mode_port_b        ( "OLD_DATA"                                                             ),
      .read_during_write_mode_mixed_ports   ( "OLD_DATA"                                                             )
      ) u_offset (
      .wren_a                               ( subsystem_rst_req ? 1'b1 : offset_wren                                 ),
      .wren_b                               ( 1'b0                                                                   ),
      .rden_a                               ( 1'b0                                                                   ),
      .rden_b                               ( offset_rden                                                            ),
      .data_a                               ( subsystem_rst_req ? {(MSIX_TABLE_ADDR_WIDTH*2+1){1'b0}} : offset_wdata ),
      .data_b                               ( {(MSIX_TABLE_ADDR_WIDTH*2+1){1'b0}}                                    ),
      .address_a                            ( subsystem_rst_req ? rst_req_size_waddr : offset_waddr                  ),
      .address_b                            ( offset_raddr                                                           ),
      .clock0                               ( axi_st_clk                                                             ),
      .clock1                               ( 1'b1                                                                   ),
      .clocken0                             ( 1'b1                                                                   ),
      .clocken1                             ( 1'b1                                                                   ),
      .clocken2                             ( 1'b1                                                                   ),
      .clocken3                             ( 1'b1                                                                   ),
      .aclr0                                ( ~stclk_rst_n_1                                                           ),
      .aclr1                                ( 1'b0                                                                   ),
      .byteena_a                            ( 1'b1                                                                   ),
      .byteena_b                            ( 1'b1                                                                   ),
      .addressstall_a                       ( 1'b0                                                                   ),
      .addressstall_b                       ( 1'b0                                                                   ),
      .sclr                                 ( 1'b0                                                                   ),
      .eccencbypass                         ( 1'b0                                                                   ),
      .eccencparity                         ( 8'b0                                                                   ),
      .eccstatus                            (                                                                        ),
      .address2_a                           ( {SIZE_REG_ADDR_WIDTH{1'b1}}                                            ),
      .address2_b                           ( {SIZE_REG_ADDR_WIDTH{1'b1}}                                            ),
      .q_a                                  (                                                                        ),
      .q_b                                  ( offset_rdata                                                           )
      );

  end
  endgenerate


endmodule // ofs_fim_pcie_ss_msix_table


// Dummy implementation of clock crossing sync, replacing the version
// from the original source. The module is used only on the lite CSR
// path, which OFS never drives.
module  dummy_msix_vecsync_handshake #(

  parameter	DWIDTH            = 1,		
  parameter	RESET_VAL         = 0,		
  parameter	SRC_CLK_FREQ_MHZ  = 500,	
  parameter	DST_CLK_FREQ_MHZ  = 500		

) (

  input                                 wr_clk, 
  input                                 wr_rst_n, 
  input                                 rd_clk, 
  input                                 rd_rst_n, 

  input      [ (DWIDTH-1) : 0 ]         data_in,
  input                                 load_data_in,
  output                                data_in_rdy2ld,
  output     [ (DWIDTH-1) : 0 ]         data_out,
  output                                data_out_vld,
  input                                 ack_data_out

); 

  // Drive 0 on the output
  assign data_out = '0;
  assign data_out_vld = 1'b0;
  assign data_in_rdy2ld = 1'b0;

endmodule // dummy_msix_vecsync_handshake
