// Copyright (C) 2020 Intel Corporation.
// SPDX-License-Identifier: MIT

//
// Description
//-----------------------------------------------------------------------------
//
// Top level module of PCIe subsystem.
//
//-----------------------------------------------------------------------------

`include "fpga_defines.vh"
`include "ofs_ip_cfg_db.vh"

import ofs_fim_cfg_pkg::*;
import ofs_fim_if_pkg::*;
import pcie_ss_axis_pkg::*;

module pcie_ss_top # (
   parameter PCIE_LANES = 16,
   parameter PCIE_NUM_LINKS = 1,
   parameter SOC_ATTACH = 0
)(

   input  logic                     fim_clk,
   input  logic                     csr_clk,
   input  logic                     ninit_done,
   output logic [PCIE_NUM_LINKS-1:0] reset_status,

   input  logic [PCIE_NUM_LINKS-1:0] fim_rst_n,
   input  logic [PCIE_NUM_LINKS-1:0] csr_rst_n,
   input  logic [PCIE_NUM_LINKS-1:0] subsystem_cold_rst_n,  
   input  logic [PCIE_NUM_LINKS-1:0] subsystem_warm_rst_n,    
   output logic [PCIE_NUM_LINKS-1:0] subsystem_cold_rst_ack_n,
   output logic [PCIE_NUM_LINKS-1:0] subsystem_warm_rst_ack_n,

   // PCIe pins
   input  logic                     pin_pcie_refclk0_p,
   input  logic                     pin_pcie_refclk1_p,
   input  logic                     pin_pcie_in_perst_n,   // connected to HIP
   input  logic [PCIE_LANES-1:0]    pin_pcie_rx_p,
   input  logic [PCIE_LANES-1:0]    pin_pcie_rx_n,
   output logic [PCIE_LANES-1:0]    pin_pcie_tx_p,
   output logic [PCIE_LANES-1:0]    pin_pcie_tx_n,

   //TXREQ ports
   pcie_ss_axis_if.sink             axi_st_txreq_if[PCIE_NUM_LINKS-1:0],

   //Ctrl Shadow ports
   output logic [PCIE_NUM_LINKS-1:0]         ss_app_st_ctrlshadow_tvalid,
   output logic [PCIE_NUM_LINKS-1:0][39:0]   ss_app_st_ctrlshadow_tdata,

   // Application to FPGA request port (MMIO/VDM)
   pcie_ss_axis_if.source           axi_st_rxreq_if[PCIE_NUM_LINKS-1:0],

   // FPGA to application request/response ports (DM req/rsp, MMIO rsp)
   pcie_ss_axis_if.source           axi_st_rx_if[PCIE_NUM_LINKS-1:0],
   pcie_ss_axis_if.sink             axi_st_tx_if[PCIE_NUM_LINKS-1:0],
   
   ofs_fim_axi_lite_if.slave        ss_csr_lite_if[PCIE_NUM_LINKS-1:0],
 
   // FLR interface
   output t_axis_pcie_flr           flr_req_if[PCIE_NUM_LINKS-1:0],
   input  t_axis_pcie_flr           flr_rsp_if[PCIE_NUM_LINKS-1:0],

   // Completion Timeout interface
   output t_axis_pcie_cplto         cpl_timeout_if[PCIE_NUM_LINKS-1:0],

   output t_sideband_from_pcie      pcie_p2c_sideband[PCIE_NUM_LINKS-1:0]
);

import ofs_fim_pcie_pkg::*;

// Clock & Reset
logic                             coreclkout_hip;
logic [PCIE_NUM_LINKS-1:0]        reset_status_n;

assign reset_status = ~reset_status_n;

// PCIe bridge AXIS interface
ofs_fim_pcie_rxs_axis_if          axis_rx_st();
ofs_fim_pcie_txs_axis_if          axis_tx_st();


//PCIE SS signals
logic [PCIE_NUM_LINKS-1:0]                             ss_app_st_rx_tvalid;      
logic [PCIE_NUM_LINKS-1:0]                             app_ss_st_rx_tready;      
logic [PCIE_NUM_LINKS-1:0] [511:0]                     ss_app_st_rx_tdata;       
logic [PCIE_NUM_LINKS-1:0] [63:0]                      ss_app_st_rx_tkeep;      
logic [PCIE_NUM_LINKS-1:0]                             ss_app_st_rx_tlast;      
logic [PCIE_NUM_LINKS-1:0] [2:0]                       ss_app_st_rx_tuser_vendor;
logic [PCIE_NUM_LINKS-1:0] [7:0]                       ss_app_st_rx_tuser; 

logic [PCIE_NUM_LINKS-1:0]                             ss_app_st_rxreq_tvalid;      
logic [PCIE_NUM_LINKS-1:0]                             app_ss_st_rxreq_tready;       
logic [PCIE_NUM_LINKS-1:0] [511:0]                     ss_app_st_rxreq_tdata;         
logic [PCIE_NUM_LINKS-1:0] [63:0]                      ss_app_st_rxreq_tkeep;        
logic [PCIE_NUM_LINKS-1:0]                             ss_app_st_rxreq_tlast;        
logic [PCIE_NUM_LINKS-1:0] [2:0]                       ss_app_st_rxreq_tuser_vendor;  

logic [PCIE_NUM_LINKS-1:0]                             app_ss_st_tx_tvalid;
logic [PCIE_NUM_LINKS-1:0]                             ss_app_st_tx_tready;     
logic [PCIE_NUM_LINKS-1:0] [511:0]                     app_ss_st_tx_tdata;     
logic [PCIE_NUM_LINKS-1:0] [63:0]                      app_ss_st_tx_tkeep;      
logic [PCIE_NUM_LINKS-1:0]                             app_ss_st_tx_tlast;      
logic [PCIE_NUM_LINKS-1:0] [1:0]                       app_ss_st_tx_tuser_vendor;
logic [PCIE_NUM_LINKS-1:0] [7:0]                       app_ss_st_tx_tuser;

//FLR Signals
logic [PCIE_NUM_LINKS-1:0]                             ss_app_st_flrrcvd_tvalid;
logic [PCIE_NUM_LINKS-1:0] [19:0]                      ss_app_st_flrrcvd_tdata;
logic [PCIE_NUM_LINKS-1:0]                             app_ss_st_flrcmpl_tvalid;
logic [PCIE_NUM_LINKS-1:0] [19:0]                      app_ss_st_flrcmpl_tdata;

//Completion Timeout
logic [PCIE_NUM_LINKS-1:0]                             ss_app_st_cplto_tvalid;
logic [PCIE_NUM_LINKS-1:0] [29:0]                      ss_app_st_cplto_tdata;

logic [PCIE_NUM_LINKS-1:0]                             ss_app_lite_csr_awready;
logic [PCIE_NUM_LINKS-1:0]                             ss_app_lite_csr_wready;
logic [PCIE_NUM_LINKS-1:0]                             ss_app_lite_csr_arready;
logic [PCIE_NUM_LINKS-1:0]                             ss_app_lite_csr_bvalid;
logic [PCIE_NUM_LINKS-1:0]                             ss_app_lite_csr_rvalid; 
logic [PCIE_NUM_LINKS-1:0]                             app_ss_lite_csr_awvalid;
logic [PCIE_NUM_LINKS-1:0] [ofs_fim_cfg_pkg::PCIE_LITE_CSR_WIDTH-1:0] app_ss_lite_csr_awaddr;
logic [PCIE_NUM_LINKS-1:0]                             app_ss_lite_csr_wvalid;
logic [PCIE_NUM_LINKS-1:0] [31:0]                      app_ss_lite_csr_wdata;
logic [PCIE_NUM_LINKS-1:0] [3:0]                       app_ss_lite_csr_wstrb;  
logic [PCIE_NUM_LINKS-1:0]                             app_ss_lite_csr_bready; 
logic [PCIE_NUM_LINKS-1:0] [1:0]                       ss_app_lite_csr_bresp;
logic [PCIE_NUM_LINKS-1:0]                             app_ss_lite_csr_arvalid;
logic [PCIE_NUM_LINKS-1:0] [ofs_fim_cfg_pkg::PCIE_LITE_CSR_WIDTH-1:0] app_ss_lite_csr_araddr; 
logic [PCIE_NUM_LINKS-1:0]                             app_ss_lite_csr_rready; 
logic [PCIE_NUM_LINKS-1:0] [31:0]                      ss_app_lite_csr_rdata;  
logic [PCIE_NUM_LINKS-1:0] [1:0]                       ss_app_lite_csr_rresp;  

logic [PCIE_NUM_LINKS-1:0]                             initiate_warmrst_req;
logic [PCIE_NUM_LINKS-1:0]        ss_app_dlup;
logic [PCIE_NUM_LINKS-1:0]        ss_app_serr;


localparam CSR_STAT_SYNC_WIDTH = 33;
for (genvar j=0; j<PCIE_NUM_LINKS; j++) begin : PCIE_LINK_CONN

//---------------------------------------------------------------
//Connecting the RX ST Interface
assign axi_st_rx_if[j].tvalid            = ss_app_st_rx_tvalid[j] ;     
assign app_ss_st_rx_tready[j]         = axi_st_rx_if[j].tready    ;
assign axi_st_rx_if[j].tdata             = ss_app_st_rx_tdata[j] ;     
assign axi_st_rx_if[j].tkeep             = ss_app_st_rx_tkeep[j] ;     
assign axi_st_rx_if[j].tlast             = ss_app_st_rx_tlast[j] ;     
assign axi_st_rx_if[j].tuser_vendor[2:0] = ss_app_st_rx_tuser_vendor[j][2:0];
assign axi_st_rx_if[j].tuser_vendor[9:3] = ss_app_st_rx_tuser[j]; 

//Connecting the RX-REQ ST Interface
assign axi_st_rxreq_if[j].tvalid            = ss_app_st_rxreq_tvalid[j] ;     
assign app_ss_st_rxreq_tready[j]         = axi_st_rxreq_if[j].tready    ;
assign axi_st_rxreq_if[j].tdata             = ss_app_st_rxreq_tdata[j] ;     
assign axi_st_rxreq_if[j].tkeep             = ss_app_st_rxreq_tkeep[j] ;     
assign axi_st_rxreq_if[j].tlast             = ss_app_st_rxreq_tlast[j] ;     
assign axi_st_rxreq_if[j].tuser_vendor[2:0] = ss_app_st_rxreq_tuser_vendor[j];
assign axi_st_rxreq_if[j].tuser_vendor[9:3] = 7'h0;

//Connecting the TX ST Interface
assign app_ss_st_tx_tvalid[j]         = axi_st_tx_if[j].tvalid; 
assign axi_st_tx_if[j].tready            = ss_app_st_tx_tready[j];
assign app_ss_st_tx_tdata[j]          = axi_st_tx_if[j].tdata;
assign app_ss_st_tx_tkeep[j]          = axi_st_tx_if[j].tkeep;
assign app_ss_st_tx_tlast[j]          = axi_st_tx_if[j].tlast;
assign app_ss_st_tx_tuser_vendor[j]   = axi_st_tx_if[j].tuser_vendor[1:0];
assign app_ss_st_tx_tuser[j]          = axi_st_tx_if[j].tuser_vendor[9:2];

//Connecting the FLR Interface
assign flr_req_if[j].tvalid = ss_app_st_flrrcvd_tvalid[j];
assign flr_req_if[j].tdata  = ss_app_st_flrrcvd_tdata[j];

assign app_ss_st_flrcmpl_tvalid[j] = flr_rsp_if[j].tvalid;
assign app_ss_st_flrcmpl_tdata[j]  = flr_rsp_if[j].tdata;


//Connecting the csr interface
assign ss_csr_lite_if[j].awready        = ss_app_lite_csr_awready[j];
assign ss_csr_lite_if[j].wready         = ss_app_lite_csr_wready[j];
assign ss_csr_lite_if[j].arready        = ss_app_lite_csr_arready[j];
assign ss_csr_lite_if[j].bvalid         = ss_app_lite_csr_bvalid[j];
assign ss_csr_lite_if[j].rvalid         = ss_app_lite_csr_rvalid[j];
assign app_ss_lite_csr_awvalid[j]    = ss_csr_lite_if[j].awvalid; 
assign app_ss_lite_csr_awaddr[j]     = ss_csr_lite_if[j].awaddr;
assign app_ss_lite_csr_wvalid[j]     = ss_csr_lite_if[j].wvalid;
assign app_ss_lite_csr_wdata[j]      = ss_csr_lite_if[j].wdata;
assign app_ss_lite_csr_wstrb[j]      = ss_csr_lite_if[j].wstrb;
assign app_ss_lite_csr_bready[j]     = ss_csr_lite_if[j].bready;
assign ss_csr_lite_if[j].bresp          = ss_app_lite_csr_bresp[j];
assign app_ss_lite_csr_arvalid[j]    = ss_csr_lite_if[j].arvalid;
assign app_ss_lite_csr_araddr[j]     = ss_csr_lite_if[j].araddr;
assign app_ss_lite_csr_rready[j]     = ss_csr_lite_if[j].rready;
assign ss_csr_lite_if[j].rdata          = ss_app_lite_csr_rdata[j];
assign ss_csr_lite_if[j].rresp          = ss_app_lite_csr_rresp[j];

//-------------------------------------
// Completion timeout interface 
//-------------------------------------
always_comb begin
   cpl_timeout_if[j].tvalid = ss_app_st_cplto_tvalid[j];
   cpl_timeout_if[j].tdata  = ss_app_st_cplto_tdata[j];
end

// PCIE stat signals clock crossing (fim_clk -> csr_clk)
fim_resync #(
   .SYNC_CHAIN_LENGTH(3),
   .WIDTH(CSR_STAT_SYNC_WIDTH),
   .INIT_VALUE(0),
   .NO_CUT(1)
) csr_resync (
   .clk   (csr_clk),
   .reset (~csr_rst_n[j]),
   .d     ({ss_app_dlup[j],32'b0}),
   .q     ({pcie_p2c_sideband[j].pcie_linkup, pcie_p2c_sideband[j].pcie_chk_rx_err_code})
);



end //for (genvar j=0; j<PCIE_NUM_LINKS;..


`ifdef OFS_FIM_IP_CFG_PCIE_SS_GEN5_2X8    
`ifndef OFS_FIM_IP_CFG_PCIE_SS_EN_LINK_1
// IP topology is Gen5_2x8 but link1 is tied off
// Signals used in Tieoff
wire p1_initiate_warmrst_req;
`endif
`endif

//-------------------------------------
// PCIe SS
//-------------------------------------
generate if (SOC_ATTACH == 1) begin : soc_pcie
soc_pcie_ss pcie_ss(
.refclk0                        (pin_pcie_refclk0_p             ),               
.refclk1                        (pin_pcie_refclk1_p             ),
.pin_perst_n                    (pin_pcie_in_perst_n            ),
.coreclkout_hip_toapp           (coreclkout_hip                 ),
.p0_pin_perst_n                 (                               ), 
.p0_reset_status_n              (reset_status_n[0]                 ),
.ninit_done                     (ninit_done                     ), 
.dummy_user_avmm_rst            (                               ), 
.p0_axi_st_clk                  (fim_clk                        ),
.p0_axi_lite_clk                (csr_clk                        ),  
.p0_axi_st_areset_n             (fim_rst_n[0]                      ),       
.p0_axi_lite_areset_n           (csr_rst_n[0]                      ),        
.p0_subsystem_cold_rst_n        (subsystem_cold_rst_n[0]        ),
.p0_subsystem_warm_rst_n        (subsystem_warm_rst_n[0]        ),
.p0_subsystem_cold_rst_ack_n    (subsystem_cold_rst_ack_n[0]    ),
.p0_subsystem_warm_rst_ack_n    (subsystem_warm_rst_ack_n[0]    ),
.p0_subsystem_rst_req           ('0                             ),
.p0_subsystem_rst_rdy           (                               ),      
.p0_initiate_warmrst_req        (initiate_warmrst_req[0]        ),
.p0_initiate_rst_req_rdy        (initiate_warmrst_req[0]        ),          
.p0_ss_app_st_rx_tvalid         (ss_app_st_rx_tvalid[0]         ),   
.p0_app_ss_st_rx_tready         (app_ss_st_rx_tready[0]         ),   
.p0_ss_app_st_rx_tdata          (ss_app_st_rx_tdata[0]          ), 
.p0_ss_app_st_rx_tkeep          (ss_app_st_rx_tkeep[0]          ),
.p0_ss_app_st_rx_tlast          (ss_app_st_rx_tlast[0]          ),
.p0_ss_app_st_rx_tuser          (ss_app_st_rx_tuser[0]          ),
.p0_ss_app_st_rx_tuser_vendor   (ss_app_st_rx_tuser_vendor[0]   ),
.p0_app_ss_st_tx_tvalid         (app_ss_st_tx_tvalid[0]         ),
.p0_ss_app_st_tx_tready         (ss_app_st_tx_tready[0]         ),
.p0_app_ss_st_tx_tdata          (app_ss_st_tx_tdata[0]          ),
.p0_app_ss_st_tx_tkeep          (app_ss_st_tx_tkeep[0]          ),
.p0_app_ss_st_tx_tlast          (app_ss_st_tx_tlast[0]          ),
.p0_app_ss_st_tx_tuser          (app_ss_st_tx_tuser[0]          ),
.p0_app_ss_st_tx_tuser_vendor   (app_ss_st_tx_tuser_vendor[0]   ),
.p0_ss_app_st_rxreq_tvalid      (ss_app_st_rxreq_tvalid[0]      ),  
.p0_app_ss_st_rxreq_tready      (app_ss_st_rxreq_tready[0]      ),  
.p0_ss_app_st_rxreq_tdata       (ss_app_st_rxreq_tdata[0]       ),  
.p0_ss_app_st_rxreq_tkeep       (ss_app_st_rxreq_tkeep[0]       ),  
.p0_ss_app_st_rxreq_tlast       (ss_app_st_rxreq_tlast[0]       ),  
.p0_ss_app_st_rxreq_tuser_vendor(ss_app_st_rxreq_tuser_vendor[0]),  
.p0_app_ss_st_txreq_tvalid      (axi_st_txreq_if[0].tvalid      ),  
.p0_ss_app_st_txreq_tready      (axi_st_txreq_if[0].tready      ),    
.p0_app_ss_st_txreq_tdata       (axi_st_txreq_if[0].tdata[255:0]), 
.p0_app_ss_st_txreq_tlast       (axi_st_txreq_if[0].tlast       ),      
.p0_ss_app_st_flrrcvd_tvalid    (ss_app_st_flrrcvd_tvalid[0]    ),
.p0_ss_app_st_flrrcvd_tdata     (ss_app_st_flrrcvd_tdata[0]     ),
.p0_app_ss_st_flrcmpl_tvalid    (app_ss_st_flrcmpl_tvalid[0]    ),
.p0_app_ss_st_flrcmpl_tdata     (app_ss_st_flrcmpl_tdata[0]     ),
.p0_ss_app_st_ctrlshadow_tvalid (ss_app_st_ctrlshadow_tvalid[0] ),
.p0_ss_app_st_ctrlshadow_tdata  (ss_app_st_ctrlshadow_tdata[0]  ),
.p0_ss_app_st_txcrdt_tvalid     (                               ),
.p0_ss_app_st_txcrdt_tdata      (                               ),
.p0_ss_app_st_cplto_tvalid      (ss_app_st_cplto_tvalid[0]      ),    
.p0_ss_app_st_cplto_tdata       (ss_app_st_cplto_tdata[0]       ),
.p0_app_ss_lite_csr_awvalid     (app_ss_lite_csr_awvalid[0]     ),
.p0_ss_app_lite_csr_awready     (ss_app_lite_csr_awready[0]     ),
.p0_app_ss_lite_csr_awaddr      (app_ss_lite_csr_awaddr[0]      ),
.p0_app_ss_lite_csr_wvalid      (app_ss_lite_csr_wvalid[0]      ),
.p0_ss_app_lite_csr_wready      (ss_app_lite_csr_wready[0]      ),
.p0_app_ss_lite_csr_wdata       (app_ss_lite_csr_wdata[0]       ),
.p0_app_ss_lite_csr_wstrb       (app_ss_lite_csr_wstrb[0]       ),
.p0_ss_app_lite_csr_bvalid      (ss_app_lite_csr_bvalid[0]      ),
.p0_app_ss_lite_csr_bready      (app_ss_lite_csr_bready[0]      ),
.p0_ss_app_lite_csr_bresp       (ss_app_lite_csr_bresp[0]       ),
.p0_app_ss_lite_csr_arvalid     (app_ss_lite_csr_arvalid[0]     ),
.p0_ss_app_lite_csr_arready     (ss_app_lite_csr_arready[0]     ),
.p0_app_ss_lite_csr_araddr      (app_ss_lite_csr_araddr[0]      ),
.p0_ss_app_lite_csr_rvalid      (ss_app_lite_csr_rvalid[0]      ),
.p0_app_ss_lite_csr_rready      (app_ss_lite_csr_rready[0]      ),
.p0_ss_app_lite_csr_rdata       (ss_app_lite_csr_rdata[0]       ),
.p0_ss_app_lite_csr_rresp       (ss_app_lite_csr_rresp[0]       ),
.p0_ss_app_dlup                 (ss_app_dlup[0]                 ),
.tx_n_out0                      (pin_pcie_tx_n[0]               ),      
.tx_n_out1                      (pin_pcie_tx_n[1]               ),      
.tx_n_out2                      (pin_pcie_tx_n[2]               ),      
.tx_n_out3                      (pin_pcie_tx_n[3]               ),      
.tx_n_out4                      (pin_pcie_tx_n[4]               ),      
.tx_n_out5                      (pin_pcie_tx_n[5]               ),      
.tx_n_out6                      (pin_pcie_tx_n[6]               ),      
.tx_n_out7                      (pin_pcie_tx_n[7]               ),      
.tx_n_out8                      (pin_pcie_tx_n[8]               ),      
.tx_n_out9                      (pin_pcie_tx_n[9]               ),      
.tx_n_out10                     (pin_pcie_tx_n[10]              ),       
.tx_n_out11                     (pin_pcie_tx_n[11]              ),       
.tx_n_out12                     (pin_pcie_tx_n[12]              ),       
.tx_n_out13                     (pin_pcie_tx_n[13]              ),       
.tx_n_out14                     (pin_pcie_tx_n[14]              ),       
.tx_n_out15                     (pin_pcie_tx_n[15]              ),       
.tx_p_out0                      (pin_pcie_tx_p[0]               ),
.tx_p_out1                      (pin_pcie_tx_p[1]               ),
.tx_p_out2                      (pin_pcie_tx_p[2]               ),
.tx_p_out3                      (pin_pcie_tx_p[3]               ),
.tx_p_out4                      (pin_pcie_tx_p[4]               ),
.tx_p_out5                      (pin_pcie_tx_p[5]               ),
.tx_p_out6                      (pin_pcie_tx_p[6]               ),
.tx_p_out7                      (pin_pcie_tx_p[7]               ),
.tx_p_out8                      (pin_pcie_tx_p[8]               ),
.tx_p_out9                      (pin_pcie_tx_p[9]               ),
.tx_p_out10                     (pin_pcie_tx_p[10]              ), 
.tx_p_out11                     (pin_pcie_tx_p[11]              ), 
.tx_p_out12                     (pin_pcie_tx_p[12]              ), 
.tx_p_out13                     (pin_pcie_tx_p[13]              ), 
.tx_p_out14                     (pin_pcie_tx_p[14]              ), 
.tx_p_out15                     (pin_pcie_tx_p[15]              ), 
.rx_n_in0                       (pin_pcie_rx_n[0]               ),    
.rx_n_in1                       (pin_pcie_rx_n[1]               ),    
.rx_n_in2                       (pin_pcie_rx_n[2]               ),    
.rx_n_in3                       (pin_pcie_rx_n[3]               ),    
.rx_n_in4                       (pin_pcie_rx_n[4]               ),    
.rx_n_in5                       (pin_pcie_rx_n[5]               ),    
.rx_n_in6                       (pin_pcie_rx_n[6]               ),    
.rx_n_in7                       (pin_pcie_rx_n[7]               ),    
.rx_n_in8                       (pin_pcie_rx_n[8]               ),    
.rx_n_in9                       (pin_pcie_rx_n[9]               ),    
.rx_n_in10                      (pin_pcie_rx_n[10]              ),    
.rx_n_in11                      (pin_pcie_rx_n[11]              ),    
.rx_n_in12                      (pin_pcie_rx_n[12]              ),    
.rx_n_in13                      (pin_pcie_rx_n[13]              ),    
.rx_n_in14                      (pin_pcie_rx_n[14]              ),    
.rx_n_in15                      (pin_pcie_rx_n[15]              ),    
.rx_p_in0                       (pin_pcie_rx_p[0]               ),    
.rx_p_in1                       (pin_pcie_rx_p[1]               ),    
.rx_p_in2                       (pin_pcie_rx_p[2]               ),    
.rx_p_in3                       (pin_pcie_rx_p[3]               ),    
.rx_p_in4                       (pin_pcie_rx_p[4]               ),    
.rx_p_in5                       (pin_pcie_rx_p[5]               ),    
.rx_p_in6                       (pin_pcie_rx_p[6]               ),    
.rx_p_in7                       (pin_pcie_rx_p[7]               ),    
.rx_p_in8                       (pin_pcie_rx_p[8]               ),    
.rx_p_in9                       (pin_pcie_rx_p[9]               ),    
.rx_p_in10                      (pin_pcie_rx_p[10]              ),    
.rx_p_in11                      (pin_pcie_rx_p[11]              ),    
.rx_p_in12                      (pin_pcie_rx_p[12]              ),    
.rx_p_in13                      (pin_pcie_rx_p[13]              ),    
.rx_p_in14                      (pin_pcie_rx_p[14]              ),    
.rx_p_in15                      (pin_pcie_rx_p[15]              )
);
end : soc_pcie
else begin : host_pcie
pcie_ss pcie_ss(
.refclk0                        (pin_pcie_refclk0_p             ),               
.refclk1                        (pin_pcie_refclk1_p             ),
.pin_perst_n                    (pin_pcie_in_perst_n            ),
.coreclkout_hip_toapp           (coreclkout_hip                 ),
.p0_pin_perst_n                 (                               ), 
.p0_reset_status_n              (reset_status_n[0]              ),
.ninit_done                     (ninit_done                     ), 
.dummy_user_avmm_rst            (                               ), 
.p0_axi_st_clk                  (fim_clk                        ),
.p0_axi_lite_clk                (csr_clk                        ),  
.p0_axi_st_areset_n             (fim_rst_n[0]                   ),       
.p0_axi_lite_areset_n           (csr_rst_n[0]                   ),        
.p0_subsystem_cold_rst_n        (subsystem_cold_rst_n[0]     ),
.p0_subsystem_warm_rst_n        (subsystem_warm_rst_n[0]     ),
.p0_subsystem_cold_rst_ack_n    (subsystem_cold_rst_ack_n[0] ),
.p0_subsystem_warm_rst_ack_n    (subsystem_warm_rst_ack_n[0] ),
.p0_subsystem_rst_req           ('0                             ),
.p0_subsystem_rst_rdy           (                               ),      
.p0_initiate_warmrst_req        (initiate_warmrst_req[0]        ),
.p0_initiate_rst_req_rdy        (initiate_warmrst_req[0]        ),          
.p0_ss_app_st_rx_tvalid         (ss_app_st_rx_tvalid[0]         ),   
.p0_app_ss_st_rx_tready         (app_ss_st_rx_tready[0]         ),   
.p0_ss_app_st_rx_tdata          (ss_app_st_rx_tdata[0]          ), 
.p0_ss_app_st_rx_tkeep          (ss_app_st_rx_tkeep[0]          ),
.p0_ss_app_st_rx_tlast          (ss_app_st_rx_tlast[0]          ),
.p0_ss_app_st_rx_tuser          (ss_app_st_rx_tuser[0]          ),
.p0_ss_app_st_rx_tuser_vendor   (ss_app_st_rx_tuser_vendor[0]   ),
.p0_app_ss_st_tx_tvalid         (app_ss_st_tx_tvalid[0]         ),
.p0_ss_app_st_tx_tready         (ss_app_st_tx_tready[0]         ),
.p0_app_ss_st_tx_tdata          (app_ss_st_tx_tdata[0]          ),
.p0_app_ss_st_tx_tkeep          (app_ss_st_tx_tkeep[0]          ),
.p0_app_ss_st_tx_tlast          (app_ss_st_tx_tlast[0]          ),
.p0_app_ss_st_tx_tuser          (app_ss_st_tx_tuser[0]          ),
.p0_app_ss_st_tx_tuser_vendor   (app_ss_st_tx_tuser_vendor[0]   ),
.p0_ss_app_st_rxreq_tvalid      (ss_app_st_rxreq_tvalid[0]      ),   
.p0_app_ss_st_rxreq_tready      (app_ss_st_rxreq_tready[0]      ),   
.p0_ss_app_st_rxreq_tdata       (ss_app_st_rxreq_tdata[0]       ),   
.p0_ss_app_st_rxreq_tkeep       (ss_app_st_rxreq_tkeep[0]       ),   
.p0_ss_app_st_rxreq_tlast       (ss_app_st_rxreq_tlast[0]       ),   
.p0_ss_app_st_rxreq_tuser_vendor(ss_app_st_rxreq_tuser_vendor[0]),   
.p0_app_ss_st_txreq_tvalid      (axi_st_txreq_if[0].tvalid      ),  
.p0_ss_app_st_txreq_tready      (axi_st_txreq_if[0].tready      ),    
.p0_app_ss_st_txreq_tdata       (axi_st_txreq_if[0].tdata[255:0]), 
.p0_app_ss_st_txreq_tlast       (axi_st_txreq_if[0].tlast       ),      
.p0_ss_app_st_flrrcvd_tvalid    (ss_app_st_flrrcvd_tvalid[0]    ),
.p0_ss_app_st_flrrcvd_tdata     (ss_app_st_flrrcvd_tdata[0]     ),
.p0_app_ss_st_flrcmpl_tvalid    (app_ss_st_flrcmpl_tvalid[0]    ),
.p0_app_ss_st_flrcmpl_tdata     (app_ss_st_flrcmpl_tdata[0]     ),
.p0_ss_app_st_ctrlshadow_tvalid (ss_app_st_ctrlshadow_tvalid[0] ),
.p0_ss_app_st_ctrlshadow_tdata  (ss_app_st_ctrlshadow_tdata[0]  ),
.p0_ss_app_st_txcrdt_tvalid     (                               ),
.p0_ss_app_st_txcrdt_tdata      (                               ),
.p0_ss_app_st_cplto_tvalid      (ss_app_st_cplto_tvalid[0]      ),    
.p0_ss_app_st_cplto_tdata       (ss_app_st_cplto_tdata[0]       ),
.p0_app_ss_lite_csr_awvalid     (app_ss_lite_csr_awvalid[0]     ),
.p0_ss_app_lite_csr_awready     (ss_app_lite_csr_awready[0]     ),
.p0_app_ss_lite_csr_awaddr      (app_ss_lite_csr_awaddr[0]      ),
.p0_app_ss_lite_csr_wvalid      (app_ss_lite_csr_wvalid[0]      ),
.p0_ss_app_lite_csr_wready      (ss_app_lite_csr_wready[0]      ),
.p0_app_ss_lite_csr_wdata       (app_ss_lite_csr_wdata[0]       ),
.p0_app_ss_lite_csr_wstrb       (app_ss_lite_csr_wstrb[0]       ),
.p0_ss_app_lite_csr_bvalid      (ss_app_lite_csr_bvalid[0]      ),
.p0_app_ss_lite_csr_bready      (app_ss_lite_csr_bready[0]      ),
.p0_ss_app_lite_csr_bresp       (ss_app_lite_csr_bresp[0]       ),
.p0_app_ss_lite_csr_arvalid     (app_ss_lite_csr_arvalid[0]     ),
.p0_ss_app_lite_csr_arready     (ss_app_lite_csr_arready[0]     ),
.p0_app_ss_lite_csr_araddr      (app_ss_lite_csr_araddr[0]      ),
.p0_ss_app_lite_csr_rvalid      (ss_app_lite_csr_rvalid[0]      ),
.p0_app_ss_lite_csr_rready      (app_ss_lite_csr_rready[0]      ),
.p0_ss_app_lite_csr_rdata       (ss_app_lite_csr_rdata[0]       ),
.p0_ss_app_lite_csr_rresp       (ss_app_lite_csr_rresp[0]       ),
.p0_ss_app_dlup                 (ss_app_dlup[0]                 ),



`ifdef OFS_FIM_IP_CFG_PCIE_SS_GEN5_2X8    
`ifdef OFS_FIM_IP_CFG_PCIE_SS_EN_LINK_1
// Gen5_2x8 IP topology and ports used in OFS reference design
.p1_reset_status_n              (reset_status_n[1]              ),
.p1_axi_st_clk                  (fim_clk                        ),
.p1_axi_lite_clk                (csr_clk                        ),  
.p1_axi_st_areset_n             (fim_rst_n[1]                   ),       
.p1_axi_lite_areset_n           (csr_rst_n[1]                   ),        
.p1_subsystem_cold_rst_n        (subsystem_cold_rst_n[1]     ),
.p1_subsystem_warm_rst_n        (subsystem_warm_rst_n[1]     ),
.p1_subsystem_cold_rst_ack_n    (subsystem_cold_rst_ack_n[1] ),
.p1_subsystem_warm_rst_ack_n    (subsystem_warm_rst_ack_n[1] ),
.p1_subsystem_rst_req           ('0                             ),
.p1_subsystem_rst_rdy           (                               ),      
.p1_initiate_warmrst_req        (initiate_warmrst_req[1]        ),
.p1_initiate_rst_req_rdy        (initiate_warmrst_req[1]        ),          
.p1_ss_app_st_rx_tvalid         (ss_app_st_rx_tvalid[1]         ),   
.p1_app_ss_st_rx_tready         (app_ss_st_rx_tready[1]         ),   
.p1_ss_app_st_rx_tdata          (ss_app_st_rx_tdata[1]          ), 
.p1_ss_app_st_rx_tkeep          (ss_app_st_rx_tkeep[1]          ),
.p1_ss_app_st_rx_tlast          (ss_app_st_rx_tlast[1]          ),
.p1_ss_app_st_rx_tuser          (ss_app_st_rx_tuser[1]          ),
.p1_ss_app_st_rx_tuser_vendor   (ss_app_st_rx_tuser_vendor[1]   ),
.p1_app_ss_st_tx_tvalid         (app_ss_st_tx_tvalid[1]         ),
.p1_ss_app_st_tx_tready         (ss_app_st_tx_tready[1]         ),
.p1_app_ss_st_tx_tdata          (app_ss_st_tx_tdata[1]          ),
.p1_app_ss_st_tx_tkeep          (app_ss_st_tx_tkeep[1]          ),
.p1_app_ss_st_tx_tlast          (app_ss_st_tx_tlast[1]          ),
.p1_app_ss_st_tx_tuser          (app_ss_st_tx_tuser[1]          ),
.p1_app_ss_st_tx_tuser_vendor   (app_ss_st_tx_tuser_vendor[1]   ),
.p1_ss_app_st_rxreq_tvalid      (ss_app_st_rxreq_tvalid[1]      ),
.p1_app_ss_st_rxreq_tready      (app_ss_st_rxreq_tready[1]      ),
.p1_ss_app_st_rxreq_tdata       (ss_app_st_rxreq_tdata[1]       ),
.p1_ss_app_st_rxreq_tkeep       (ss_app_st_rxreq_tkeep[1]       ),
.p1_ss_app_st_rxreq_tlast       (ss_app_st_rxreq_tlast[1]       ),
.p1_ss_app_st_rxreq_tuser_vendor(ss_app_st_rxreq_tuser_vendor[1]),
.p1_app_ss_st_txreq_tvalid      (axi_st_txreq_if[1].tvalid      ),  
.p1_ss_app_st_txreq_tready      (axi_st_txreq_if[1].tready      ),    
.p1_app_ss_st_txreq_tdata       (axi_st_txreq_if[1].tdata[255:0]), 
.p1_app_ss_st_txreq_tlast       (axi_st_txreq_if[1].tlast       ),      
.p1_ss_app_st_flrrcvd_tvalid    (ss_app_st_flrrcvd_tvalid[1]    ),
.p1_ss_app_st_flrrcvd_tdata     (ss_app_st_flrrcvd_tdata[1]     ),
.p1_app_ss_st_flrcmpl_tvalid    (app_ss_st_flrcmpl_tvalid[1]    ),
.p1_app_ss_st_flrcmpl_tdata     (app_ss_st_flrcmpl_tdata[1]  ),
.p1_ss_app_st_ctrlshadow_tvalid (ss_app_st_ctrlshadow_tvalid[1] ),
.p1_ss_app_st_ctrlshadow_tdata  (ss_app_st_ctrlshadow_tdata[1]  ),
.p1_ss_app_st_txcrdt_tvalid     (                               ),
.p1_ss_app_st_txcrdt_tdata      (                               ),
.p1_ss_app_st_cplto_tvalid      (ss_app_st_cplto_tvalid[1]      ),    
.p1_ss_app_st_cplto_tdata       (ss_app_st_cplto_tdata[1]       ),
.p1_app_ss_lite_csr_awvalid     (app_ss_lite_csr_awvalid[1]     ),
.p1_ss_app_lite_csr_awready     (ss_app_lite_csr_awready[1]     ),
.p1_app_ss_lite_csr_awaddr      (app_ss_lite_csr_awaddr[1]      ),
.p1_app_ss_lite_csr_wvalid      (app_ss_lite_csr_wvalid[1]      ),
.p1_ss_app_lite_csr_wready      (ss_app_lite_csr_wready[1]      ),
.p1_app_ss_lite_csr_wdata       (app_ss_lite_csr_wdata[1]       ),
.p1_app_ss_lite_csr_wstrb       (app_ss_lite_csr_wstrb[1]       ),
.p1_ss_app_lite_csr_bvalid      (ss_app_lite_csr_bvalid[1]      ),
.p1_app_ss_lite_csr_bready      (app_ss_lite_csr_bready[1]      ),
.p1_ss_app_lite_csr_bresp       (ss_app_lite_csr_bresp[1]       ),
.p1_app_ss_lite_csr_arvalid     (app_ss_lite_csr_arvalid[1]     ),
.p1_ss_app_lite_csr_arready     (ss_app_lite_csr_arready[1]     ),
.p1_app_ss_lite_csr_araddr      (app_ss_lite_csr_araddr[1]      ),
.p1_ss_app_lite_csr_rvalid      (ss_app_lite_csr_rvalid[1]      ),
.p1_app_ss_lite_csr_rready      (app_ss_lite_csr_rready[1]      ),
.p1_ss_app_lite_csr_rdata       (ss_app_lite_csr_rdata[1]       ),
.p1_ss_app_lite_csr_rresp       (ss_app_lite_csr_rresp[1]       ),
.p1_ss_app_dlup                 (ss_app_dlup[1]                 ),

`else
// Gen5_2x8 IP topology but second PCIe port is tied off 
// and not used in OFS example
.p1_axi_st_clk                  (fim_clk                        ),
.p1_axi_lite_clk                (csr_clk                        ),  
.p1_axi_st_areset_n             (fim_rst_n[0]                   ),       
.p1_axi_lite_areset_n           (csr_rst_n[0]                   ),        
.p1_subsystem_cold_rst_n        (subsystem_cold_rst_n[0]        ),
.p1_subsystem_warm_rst_n        (subsystem_warm_rst_n[0]        ),
.p1_subsystem_cold_rst_ack_n    (                               ),
.p1_subsystem_warm_rst_ack_n    (                               ),
.p1_subsystem_rst_req           ('0                             ),
.p1_subsystem_rst_rdy           (                               ),      
.p1_initiate_warmrst_req        (p1_initiate_warmrst_req        ),
.p1_initiate_rst_req_rdy        (p1_initiate_warmrst_req        ),          
.p1_ss_app_st_rx_tvalid         (                               ),   
.p1_app_ss_st_rx_tready         (1'b1                           ),   
.p1_ss_app_st_rx_tdata          (                               ), 
.p1_ss_app_st_rx_tkeep          (                               ),
.p1_ss_app_st_rx_tlast          (                               ),
.p1_ss_app_st_rx_tuser          (                               ),
.p1_ss_app_st_rx_tuser_vendor   (                               ),
.p1_app_ss_st_tx_tvalid         ('0                             ),
.p1_ss_app_st_tx_tready         (                               ),
.p1_app_ss_st_tx_tdata          ('0                             ),
.p1_app_ss_st_tx_tkeep          ('0                             ),
.p1_app_ss_st_tx_tlast          ('0                             ),
.p1_app_ss_st_tx_tuser          ('0                             ),
.p1_app_ss_st_tx_tuser_vendor   ('0                             ),
.p1_ss_app_st_rxreq_tvalid      (                               ),
.p1_app_ss_st_rxreq_tready      (1'b1                           ),
.p1_ss_app_st_rxreq_tdata       (                               ),
.p1_ss_app_st_rxreq_tkeep       (                               ),
.p1_ss_app_st_rxreq_tlast       (                               ),
.p1_ss_app_st_rxreq_tuser_vendor(                               ),
.p1_app_ss_st_txreq_tvalid      ('0                             ),  
.p1_ss_app_st_txreq_tready      (                               ),    
.p1_app_ss_st_txreq_tdata       ('0                             ), 
.p1_app_ss_st_txreq_tlast       ('0                             ),      
.p1_ss_app_st_flrrcvd_tvalid    (                               ),
.p1_ss_app_st_flrrcvd_tdata     (                               ),
.p1_app_ss_st_flrcmpl_tvalid    ('0                             ),
.p1_app_ss_st_flrcmpl_tdata     ('0                             ),
.p1_ss_app_st_txcrdt_tvalid     (                               ),
.p1_ss_app_st_txcrdt_tdata      (                               ),
//1p0_ss_app_st_cplto_tvalid      (p0_ss_app_st_cplto_tvalid      ),    
//1p0_ss_app_st_cplto_tdata       (p0_ss_app_st_cplto_tdata       ),
.p1_app_ss_lite_csr_awvalid     ('0                             ),
.p1_ss_app_lite_csr_awready     (                               ),
.p1_app_ss_lite_csr_awaddr      ('0                             ),
.p1_app_ss_lite_csr_wvalid      ('0                             ),
.p1_ss_app_lite_csr_wready      (                               ),
.p1_app_ss_lite_csr_wdata       ('0                             ),
.p1_app_ss_lite_csr_wstrb       ('0                             ),
.p1_ss_app_lite_csr_bvalid      (                               ),
.p1_app_ss_lite_csr_bready      ('0                             ),
.p1_ss_app_lite_csr_bresp       (                               ),
.p1_app_ss_lite_csr_arvalid     ('0                             ),
.p1_ss_app_lite_csr_arready     (                               ),
.p1_app_ss_lite_csr_araddr      ('0                             ),
.p1_ss_app_lite_csr_rvalid      (                               ),
.p1_app_ss_lite_csr_rready      ('0                             ),
.p1_ss_app_lite_csr_rdata       (                               ),
.p1_ss_app_lite_csr_rresp       (                               ),
.p1_ss_app_dlup                 (                               ),
`endif // `else
`endif // `ifdef OFS_FIM_IP_CFG_PCIE_SS_GEN5_2X8


.tx_n_out0                      (pin_pcie_tx_n[0]               ),      
.tx_n_out1                      (pin_pcie_tx_n[1]               ),      
.tx_n_out2                      (pin_pcie_tx_n[2]               ),      
.tx_n_out3                      (pin_pcie_tx_n[3]               ),      
.tx_n_out4                      (pin_pcie_tx_n[4]               ),      
.tx_n_out5                      (pin_pcie_tx_n[5]               ),      
.tx_n_out6                      (pin_pcie_tx_n[6]               ),      
.tx_n_out7                      (pin_pcie_tx_n[7]               ),      
.tx_n_out8                      (pin_pcie_tx_n[8]               ),      
.tx_n_out9                      (pin_pcie_tx_n[9]               ),      
.tx_n_out10                     (pin_pcie_tx_n[10]              ),       
.tx_n_out11                     (pin_pcie_tx_n[11]              ),       
.tx_n_out12                     (pin_pcie_tx_n[12]              ),       
.tx_n_out13                     (pin_pcie_tx_n[13]              ),       
.tx_n_out14                     (pin_pcie_tx_n[14]              ),       
.tx_n_out15                     (pin_pcie_tx_n[15]              ),       
.tx_p_out0                      (pin_pcie_tx_p[0]               ),
.tx_p_out1                      (pin_pcie_tx_p[1]               ),
.tx_p_out2                      (pin_pcie_tx_p[2]               ),
.tx_p_out3                      (pin_pcie_tx_p[3]               ),
.tx_p_out4                      (pin_pcie_tx_p[4]               ),
.tx_p_out5                      (pin_pcie_tx_p[5]               ),
.tx_p_out6                      (pin_pcie_tx_p[6]               ),
.tx_p_out7                      (pin_pcie_tx_p[7]               ),
.tx_p_out8                      (pin_pcie_tx_p[8]               ),
.tx_p_out9                      (pin_pcie_tx_p[9]               ),
.tx_p_out10                     (pin_pcie_tx_p[10]              ), 
.tx_p_out11                     (pin_pcie_tx_p[11]              ), 
.tx_p_out12                     (pin_pcie_tx_p[12]              ), 
.tx_p_out13                     (pin_pcie_tx_p[13]              ), 
.tx_p_out14                     (pin_pcie_tx_p[14]              ), 
.tx_p_out15                     (pin_pcie_tx_p[15]              ), 
.rx_n_in0                       (pin_pcie_rx_n[0]               ),    
.rx_n_in1                       (pin_pcie_rx_n[1]               ),    
.rx_n_in2                       (pin_pcie_rx_n[2]               ),    
.rx_n_in3                       (pin_pcie_rx_n[3]               ),    
.rx_n_in4                       (pin_pcie_rx_n[4]               ),    
.rx_n_in5                       (pin_pcie_rx_n[5]               ),    
.rx_n_in6                       (pin_pcie_rx_n[6]               ),    
.rx_n_in7                       (pin_pcie_rx_n[7]               ),    
.rx_n_in8                       (pin_pcie_rx_n[8]               ),    
.rx_n_in9                       (pin_pcie_rx_n[9]               ),    
.rx_n_in10                      (pin_pcie_rx_n[10]              ),    
.rx_n_in11                      (pin_pcie_rx_n[11]              ),    
.rx_n_in12                      (pin_pcie_rx_n[12]              ),    
.rx_n_in13                      (pin_pcie_rx_n[13]              ),    
.rx_n_in14                      (pin_pcie_rx_n[14]              ),    
.rx_n_in15                      (pin_pcie_rx_n[15]              ),    
.rx_p_in0                       (pin_pcie_rx_p[0]               ),    
.rx_p_in1                       (pin_pcie_rx_p[1]               ),    
.rx_p_in2                       (pin_pcie_rx_p[2]               ),    
.rx_p_in3                       (pin_pcie_rx_p[3]               ),    
.rx_p_in4                       (pin_pcie_rx_p[4]               ),    
.rx_p_in5                       (pin_pcie_rx_p[5]               ),    
.rx_p_in6                       (pin_pcie_rx_p[6]               ),    
.rx_p_in7                       (pin_pcie_rx_p[7]               ),    
.rx_p_in8                       (pin_pcie_rx_p[8]               ),    
.rx_p_in9                       (pin_pcie_rx_p[9]               ),    
.rx_p_in10                      (pin_pcie_rx_p[10]              ),    
.rx_p_in11                      (pin_pcie_rx_p[11]              ),    
.rx_p_in12                      (pin_pcie_rx_p[12]              ),    
.rx_p_in13                      (pin_pcie_rx_p[13]              ),    
.rx_p_in14                      (pin_pcie_rx_p[14]              ),    
.rx_p_in15                      (pin_pcie_rx_p[15]              )
);
end : host_pcie
endgenerate
endmodule
