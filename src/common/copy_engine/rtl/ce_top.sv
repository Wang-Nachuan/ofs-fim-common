// Copyright 2021 Intel Corporation
// SPDX-License-Identifier: MIT

// Engineer     : Liaqat                      
// Create Date  : Nov 2020
// Module Name  : ce_top.sv
// Project      : IOFS
// -----------------------------------------------------------------------------
//
// Description: 
// The Copy Engine is responsible for copying the firmware image from Host DDR to HPS-DDR once
// the descriptors within the copy engine are programmed by the host.
// Copy Engine is a part of AFU block.
// ***************************************************************************
module ce_top #(
   parameter bit [11:0] CE_FEAT_ID                     = 12'h1               , //DFH Feature ID
   parameter bit [3:0]  CE_FEAT_VER                    = 4'h1                , //DFH Feature Version
   parameter bit [23:0] CE_NEXT_DFH_OFFSET             = 24'h1000            , //DFH Next DFH Offset
   parameter bit        CE_END_OF_LIST                 = 1'b1                , //DFH End of list
   parameter            CE_BUS_ADDR_WIDTH              = 32                  , //Axi Stream & Ace lite addr width 
   parameter            CE_AXI4MM_ADDR_WIDTH           = 21                  , //Axi4MM Addrwidth 
   parameter            CE_BUS_DATA_WIDTH              = 512                 , //Axi Stream & Ace Lite data width
   parameter            CE_BUS_USER_WIDTH              = 10                  , //Axi Stream tuser width
   parameter            CE_AXI4MM_DATA_WIDTH           = 32                  , //AXI4MM Data width
   parameter            CE_BUS_STRB_WIDTH              = CE_BUS_DATA_WIDTH>>3, //Axi Stream tkeep width & Ace Lite wstrb width
   parameter            CE_MMIO_RSP_FIFO_DEPTH         = 4                   , //MMIO Response FIFO depth
   parameter            CE_HST2HPS_FIFO_DEPTH          = 5                   , //Completion FIFO depth; Axi Stream to Ace Lite conversion FIFO
   parameter            CE_PF_ID                       = 4                   , //PF ID of Cpld Packet to host                                                       
   parameter            CE_VF_ID                       = 0                   , //VF ID of Cpld Packet to host
   parameter            CE_VF_ACTIVE                   = 0                   , //VF_ACTIVE of Cpld Packet to host
   parameter            PCIE_DM_ENCODING               = 0                     //PU vs. DM encoding
)( 
   // global signals
   input   logic                           clk                      ,
   input   logic                           rst                      ,
   input   logic                           h2f_reset                ,
   
   // AXI-ST Tx interface signals
   pcie_ss_axis_if.source                axis_tx_if                ,
                                                                                                
   // AXI-ST Rx interface signals
   pcie_ss_axis_if.sink                   axis_rx_if                ,
   pcie_ss_axis_if.sink                   axis_rxreq_if            ,

   // ACE Lite Tx interface signals
   ofs_fim_ace_lite_if.master             ace_lite_tx_if            ,

   // AXI4-MM Rx interface signals
   ofs_fim_axi_mmio_if.slave              axi4mm_rx_if            


);
//--------------------------------------------------------
// Local Parameters
//--------------------------------------------------------
//localparam FIFO_CNT_WIDTH = CE_HST2HPS_FIFO_DEPTH; 
localparam TAG_WIDTH              = 10                              ;                    // Tag width 
localparam REQ_ID_WIDTH           = 16                              ;                    // Requester ID width PU mode
localparam CSR_ADDR_WIDTH         = 16                              ;                    // CSR Addr Width
localparam CSR_DATA_WIDTH         = 64                              ;                    // CSR Data Width
localparam CE_MMIO_RSP_FIFO_THRHLD = (2**CE_MMIO_RSP_FIFO_DEPTH) - 4;
localparam CE_HST2HPS_FIFO_THRSHLD = (2**CE_HST2HPS_FIFO_DEPTH) - 4 ;

//--------------------------------------------------------
// Declare Variables 
//--------------------------------------------------------
wire                              csr_mrdstart                  ;
wire                              axisttx_csr_dmaerr            ;
wire                              csr_axisttx_rspvalid          ;
wire                              csr_hpsrdy                    ;
wire                              axistrx_csr_wen               ;
wire                              axistrx_csr_ren               ;
wire                              axistrx_cpldfifo_wen          ;
wire                              axistrx_fc                    ;
wire                              axistrx_fc_req                ;
wire                              cpldfifo_axistrx_full         ;
wire                              cpldfifo_axistrx_almostfull   ;
wire                              acelitetx_cpldfifo_ren        ;
wire                              cpldfifo_acelitetx_empty      ;
wire                              cpldfifo_notempty             ;
wire                              cpldfifo_csr_fifoerr          ;
wire                              cpldfifo_csr_overflow         ;
wire                              cpldfifo_csr_underflow        ;
wire                              axisttx_csr_mmiofifooverflow  ;    
wire                              axisttx_csr_mmiofifounderflow ;    
wire                              mmiorspfifo_axistrx_almostfull;                   
wire                              fifo_err_flag                 ;                   

wire  [576:0]                     cpldfifo_acelitetx_rddata     ;
wire  [CE_HST2HPS_FIFO_DEPTH-1:0] cpldfifo_occupancy            ;
wire  [2:0  ]                     axistrx_csr_cplstatus         ;
wire  [2:0  ]                     axistrx_csr_cplstatus_req     ;
wire  [8:0  ]                     csr_axisttx_rspattr           ;
wire  [2:0  ]                     csr_axisttx_tc                ;
wire  [10:0 ]                     csr_axisttx_datareqlimit      ;
wire  [3:0 ]                      csr_axisttx_datareqlimit_log2 ;
wire  [8:0  ]                     axistrx_csr_rspatrr           ;
wire  [2:0  ]                     axistrx_csr_tc                ;
wire  [576:0]                     axistrx_cpldfifo_wrdata       ;
wire  [1:0  ]                     acelitetx_bresp               ;
wire                              acelitetx_bresperrpulse       ;
wire                              acelitetx_csr_dmadone         ;
wire                              axistrx_cplerr                ;
wire                              axistrx_cplerr_req            ;
wire                              axistrx_cplerr_comb           ;
wire                              acelitetx_axisttx_req_en      ;
logic                             axistrx_fc_comb;


wire                                    ce_softreset            ;
wire                                    ce_corereset            ;
wire                                    axi4mmrx_csr_ren        ; 
wire                                    axi4mmrx_csr_wen        ;
wire  [(CE_AXI4MM_DATA_WIDTH>>3)-1:0]   axi4mmrx_csr_wstrb      ; 
wire  [CSR_ADDR_WIDTH-1:0           ]   csr_axisttx_rspaddr     ;
wire  [CSR_DATA_WIDTH-1:0           ]   csr_axisttx_hostaddr    ;
wire  [CSR_DATA_WIDTH-1:0           ]   csr_imgxfrsize          ;
wire  [TAG_WIDTH-1:0                ]   csr_axisttx_rsptag      ;
wire  [REQ_ID_WIDTH-1:0             ]   axistrx_csr_reqid       ;
wire  [REQ_ID_WIDTH-1:0             ]   csr_axisttx_reqid       ;
wire  [CSR_DATA_WIDTH-1:0           ]   csr_axisttx_rspdata     ;
wire  [(CSR_DATA_WIDTH>>3)-1:0      ]   csr_axisttx_tkeep       ;
wire  [CE_AXI4MM_DATA_WIDTH-1:0     ]   csr_axi4mmrx_rdata      ;
wire  [CSR_DATA_WIDTH-1:0           ]   csr_acelitetx_hpsaddr   ;
wire  [CSR_ADDR_WIDTH-1:0           ]   axistrx_csr_alignaddr   ;
wire  [CSR_ADDR_WIDTH-1:0           ]   axistrx_csr_unalignaddr ;
wire  [TAG_WIDTH-1:0                ]   axistrx_csr_rsptag      ;
wire  [CSR_DATA_WIDTH-1:0           ]   axistrx_csr_wrdata      ;

wire  [CE_AXI4MM_DATA_WIDTH-1:0     ]   axi4mmrx_csr_wdata      ; 
wire  [CSR_ADDR_WIDTH-1:0           ]   axi4mmrx_csr_raddr      ; 
wire  [CSR_ADDR_WIDTH-1:0           ]   axi4mmrx_csr_waddr      ; 

   ofs_fim_ace_lite_if #(
      .AWADDR_WIDTH (ace_lite_tx_if.AWADDR_WIDTH),
      .WDATA_WIDTH  (ace_lite_tx_if.WDATA_WIDTH),
      .ARADDR_WIDTH (ace_lite_tx_if.ARADDR_WIDTH),
      .RDATA_WIDTH  (ace_lite_tx_if.RDATA_WIDTH)
   ) ace_lite_tx_d ();

   ace_lite_bridge ace_lite_bridge_inst(
      .clk   (clk),
      .rst_n (!ce_corereset),
      .s_if  (ace_lite_tx_d),
      .m_if  (ace_lite_tx_if)
   );
   
   ofs_fim_axi_mmio_if #(
      .AWID_WIDTH(axi4mm_rx_if.AWID_WIDTH),
      .AWADDR_WIDTH(axi4mm_rx_if.AWADDR_WIDTH),
      .AWUSER_WIDTH(axi4mm_rx_if.AWUSER_WIDTH),
      .WDATA_WIDTH(axi4mm_rx_if.WDATA_WIDTH),
      .WUSER_WIDTH(axi4mm_rx_if.WUSER_WIDTH),
      .BUSER_WIDTH(axi4mm_rx_if.BUSER_WIDTH),
      .ARID_WIDTH(axi4mm_rx_if.ARID_WIDTH),
      .ARADDR_WIDTH(axi4mm_rx_if.ARADDR_WIDTH),
      .ARUSER_WIDTH(axi4mm_rx_if.ARUSER_WIDTH),
      .RDATA_WIDTH(axi4mm_rx_if.RDATA_WIDTH),
      .RUSER_WIDTH(axi4mm_rx_if.RUSER_WIDTH)
   ) axi4mm_rx_d ();

   assign axi4mm_rx_d.rst_n = ~h2f_reset;
   assign axi4mm_rx_d.clk = clk;

   // Simple buffering is sufficient. The state machine in the ce_axi4mm_rx
   // endpoint is not pipelined.
   ofs_fim_axi_mmio_reg #(
      .AW_REG_MODE(1),
      .W_REG_MODE(1),
      .B_REG_MODE(1),
      .AR_REG_MODE(1),
      .R_REG_MODE(1)
   ) axi4mm_rx_reg(
      .clk,
      .rst_n(~h2f_reset),
      .s_mmio(axi4mm_rx_if),
      .m_mmio(axi4mm_rx_d)
   );
   
//wire                              MmioRspFiFo_AxistRx_full      ;                   

assign cpldfifo_acelitetx_empty =!cpldfifo_notempty ;

(* altera_attribute = {"-name PRESERVE_REGISTER ON"} *) reg [3:0] ce_corereset_reg = 4'hf;
assign ce_corereset = ce_corereset_reg[3];
always @(posedge clk) begin
   ce_corereset_reg <= { ce_corereset_reg[2:0], rst | ce_softreset };
end

assign cpldfifo_csr_overflow    = cpldfifo_csr_fifoerr& cpldfifo_axistrx_full;
assign cpldfifo_csr_underflow   = cpldfifo_csr_fifoerr& !cpldfifo_notempty   ; 

assign axistrx_cplerr_comb        = axistrx_cplerr | axistrx_cplerr_req;
assign axistrx_fc_comb            = axistrx_fc | axistrx_fc_req; 
                                                                                 
ce_csr #(  
         .CE_FEAT_ID            (CE_FEAT_ID             ), 
         .CE_FEAT_VER           (CE_FEAT_VER            ), 
         .CE_NEXT_DFH_OFFSET    (CE_NEXT_DFH_OFFSET     ), 
         .CE_END_OF_LIST        (CE_END_OF_LIST         ), 
         .CE_AXI4MM_DATA_WIDTH  (CE_AXI4MM_DATA_WIDTH   ),
         .CE_BUS_STRB_WIDTH     (CE_AXI4MM_DATA_WIDTH>>3), 
         .CSR_ADDR_WIDTH        (CSR_ADDR_WIDTH         ),
         .CSR_DATA_WIDTH        (CSR_DATA_WIDTH         ),
         .PCIE_DM_ENCODING      (PCIE_DM_ENCODING       ),
         .TAG_WIDTH             (TAG_WIDTH              ),
         .REQ_ID_WIDTH          (REQ_ID_WIDTH           ))

ce_csr_inst(

   .clk                          (clk                          ),     
   .rst                          (rst                          ), 
   .ce_corereset                 (ce_corereset                 ), 
   .csr_axisttx_hostaddr         (csr_axisttx_hostaddr         ), 
   .csr_imgxfrsize               (csr_imgxfrsize               ), 
   .ce_softreset                 (ce_softreset                 ), 
   .csr_mrdstart                 (csr_mrdstart                 ), 
   .csr_axisttx_rspaddr          (csr_axisttx_rspaddr          ), 
   .csr_axisttx_rsptag           (csr_axisttx_rsptag           ), 
   .csr_axisttx_tkeep            (csr_axisttx_tkeep            ), 
   .csr_axisttx_length           (csr_axisttx_length           ),  
   .csr_axisttx_rspattr          (csr_axisttx_rspattr          ),            
   .csr_axisttx_tc               (csr_axisttx_tc               ),            
   .csr_axisttx_datareqlimit     (csr_axisttx_datareqlimit     ),            
   .csr_axisttx_datareqlimit_log2(csr_axisttx_datareqlimit_log2),            
   .fifo_err_flag                (fifo_err_flag                ),            
   .csr_axisttx_rspdata          (csr_axisttx_rspdata          ), 
   .csr_axisttx_rspvalid         (csr_axisttx_rspvalid         ),  
   .axisttx_csr_dmaerr           (axisttx_csr_dmaerr           ), 
   .acelitetx_bresp              (acelitetx_bresp              ),
   .cpldfifo_csr_overflow        (cpldfifo_csr_overflow        ),
   .cpldfifo_csr_underflow       (cpldfifo_csr_underflow       ),
   .axisttx_csr_mmiofifooverflow (axisttx_csr_mmiofifooverflow ),    
   .axisttx_csr_mmiofifounderflow(axisttx_csr_mmiofifounderflow),    
   .csr_axisttx_reqid            (csr_axisttx_reqid            ),
   .acelitetx_csr_dmadone        (acelitetx_csr_dmadone        ),
   .axistrx_csr_wrdata           (axistrx_csr_wrdata           ), 
   .axistrx_csr_wen              (axistrx_csr_wen              ), 
   .axistrx_csr_ren              (axistrx_csr_ren              ), 
   .axistrx_csr_length           (axistrx_csr_length           ),          
   .axistrx_csr_reqid            (axistrx_csr_reqid            ),
   .axistrx_csr_cplstatus        (axistrx_csr_cplstatus        ), 
   .axistrx_csr_alignaddr        (axistrx_csr_alignaddr        ), 
   .axistrx_csr_unalignaddr      (axistrx_csr_unalignaddr      ), 
   .axistrx_csr_rsptag           (axistrx_csr_rsptag           ),
   .axistrx_csr_rspatrr          (axistrx_csr_rspatrr          ),
   .axistrx_csr_tc               (axistrx_csr_tc               ),
   .csr_hpsrdy                   (csr_hpsrdy                   ),
   .csr_acelitetx_hpsaddr        (csr_acelitetx_hpsaddr        ),
   .axi4mmrx_csr_wdata           (axi4mmrx_csr_wdata           ),
   .axi4mmrx_csr_wen             (axi4mmrx_csr_wen             ),
   .axi4mmrx_csr_wstrb           (axi4mmrx_csr_wstrb           ),            
   .axi4mmrx_csr_ren             (axi4mmrx_csr_ren             ),
   .csr_axi4mmrx_rdata           (csr_axi4mmrx_rdata           ),
   .axi4mmrx_csr_raddr           (axi4mmrx_csr_raddr           ), 
   .axi4mmrx_csr_waddr           (axi4mmrx_csr_waddr           ) 
);


ce_axist_tx    
   #(.CE_BUS_DATA_WIDTH           (CE_BUS_DATA_WIDTH      ),
   .CE_BUS_STRB_WIDTH           (CE_BUS_STRB_WIDTH      ),
   .CE_MMIO_RSP_FIFO_DEPTH      (CE_MMIO_RSP_FIFO_DEPTH ),
   .CE_MMIO_RSP_FIFO_THRHLD     (CE_MMIO_RSP_FIFO_THRHLD),  
   .CE_HST2HPS_FIFO_DEPTH       (CE_HST2HPS_FIFO_DEPTH  ),  
   .CE_PF_ID                    (CE_PF_ID               ),
   .CE_VF_ID                    (CE_VF_ID               ),
   .CE_VF_ACTIVE                (CE_VF_ACTIVE           ),
   .CSR_ADDR_WIDTH              (CSR_ADDR_WIDTH         ),
   .CSR_DATA_WIDTH              (CSR_DATA_WIDTH         ),
   .PCIE_DM_ENCODING            (PCIE_DM_ENCODING       ),
   .TAG_WIDTH                   (TAG_WIDTH              ),
   .REQ_ID_WIDTH                (REQ_ID_WIDTH           ))

   ce_axist_tx_inst(

   .clk                              (clk                           ),
   .ce_corereset                     (ce_corereset                  ), 
   .csr_axisttx_hostaddr             (csr_axisttx_hostaddr          ),        
   .csr_axisttx_imgxfrsize           (csr_imgxfrsize                ),        
   .csr_axisttx_mrdstart             (csr_mrdstart                  ),        
   .csr_axisttx_rspaddr              (csr_axisttx_rspaddr           ),        
   .csr_axisttx_rspdata              (csr_axisttx_rspdata           ),        
   .csr_axisttx_rsptag               (csr_axisttx_rsptag            ),            
   .csr_axisttx_fifoerr              (fifo_err_flag                 ),            
   .csr_axisttx_length               (csr_axisttx_length            ),  
   .csr_axisttx_rspattr              (csr_axisttx_rspattr           ),            
   .csr_axisttx_tc                   (csr_axisttx_tc                ),            
   .csr_axisttx_datareqlimit         (csr_axisttx_datareqlimit      ),            
   .csr_axisttx_datareqlimit_log2    (csr_axisttx_datareqlimit_log2 ),            
   .axisttx_csr_mmiofifooverflow     (axisttx_csr_mmiofifooverflow  ),    
   .axisttx_csr_mmiofifounderflow    (axisttx_csr_mmiofifounderflow ),    
   .csr_axisttx_rspvalid             (csr_axisttx_rspvalid          ),       
   .csr_axisttx_reqid                (csr_axisttx_reqid             ),
   .csr_axisttx_tkeep                (csr_axisttx_tkeep             ), 
   .mmiorspfifo_axistrx_almostfull   (mmiorspfifo_axistrx_almostfull),
   .acelitetx_axisttx_bresp          (acelitetx_bresp               ),
   .axistrx_csr_ren                  (axistrx_csr_ren               ), 
   .axistrx_axisttx_cplerr           (axistrx_cplerr_comb           ),     
   .acelitetx_axisttx_req_en         (acelitetx_axisttx_req_en      ),
   .csr_axisttx_hpsrdy               (csr_hpsrdy                    ),    
   .axistrx_axisttx_fc               (axistrx_fc_comb               ), 
   .axisttx_csr_dmaerr               (axisttx_csr_dmaerr            ), 
   .ce2mux_tx_tvalid                 (axis_tx_if.tvalid             ),         
   .mux2ce_tx_tready                 (axis_tx_if.tready             ),         
   .ce2mux_tx_tdata                  (axis_tx_if.tdata              ),         
   .ce2mux_tx_tkeep                  (axis_tx_if.tkeep              ),         
   .ce2mux_tx_tuser                  (axis_tx_if.tuser_vendor       ),               
   .ce2mux_tx_tlast                  (axis_tx_if.tlast              ) 
);


// DMA
ce_axist_rx     
   #(.CE_BUS_DATA_WIDTH        (CE_BUS_DATA_WIDTH ),
   .CE_BUS_STRB_WIDTH        (CE_BUS_STRB_WIDTH ),
   .CSR_ADDR_WIDTH           (CSR_ADDR_WIDTH    ),
   .CSR_DATA_WIDTH           (CSR_DATA_WIDTH    ),
   .PCIE_DM_ENCODING         (PCIE_DM_ENCODING  ),
   .TAG_WIDTH                (TAG_WIDTH         ),
   .REQ_ID_WIDTH             (REQ_ID_WIDTH      ))
ce_axist_rx_inst(
   .clk                                (clk                           ),
   .ce_corereset                       (ce_corereset                  ), 
   .mux2ce_axis_rx_if                  (axis_rx_if                    ),
   .axistrx_cpldfifo_wrdata            (axistrx_cpldfifo_wrdata       ),
   .csr_axistrx_fifoerr                (fifo_err_flag                 ),            
   .axistrx_cpldfifo_wen               (axistrx_cpldfifo_wen          ),            
   .cpldfifo_axistrx_full              (cpldfifo_axistrx_full         ),  
   .cpldfifo_axistrx_almostfull        (cpldfifo_axistrx_almostfull   ),  
   .acelitetx_axistrx_bresperrpulse    (acelitetx_bresperrpulse       ),
   .axistrx_fc                         (axistrx_fc                    ),
   .axistrx_csr_cplstatus              (axistrx_csr_cplstatus         ), 
   .csr_axistrx_mrdstart               (csr_mrdstart                  ),
   .acelitetx_axistrx_bresp            (acelitetx_bresp               ),
   .axistrx_axisttx_cplerr             (axistrx_cplerr                )
);

// MMIO - CSR
ce_axist_rx_req     
   #(.CE_BUS_DATA_WIDTH        (CE_BUS_DATA_WIDTH ),
   .CE_BUS_STRB_WIDTH        (CE_BUS_STRB_WIDTH ),
   .CSR_ADDR_WIDTH           (CSR_ADDR_WIDTH    ),
   .CSR_DATA_WIDTH           (CSR_DATA_WIDTH    ),
   .TAG_WIDTH                (TAG_WIDTH         ),
   .REQ_ID_WIDTH             (REQ_ID_WIDTH      )
) ce_axist_rx_req_inst (
   .clk                                (clk                            ),
   .ce_corereset                       (ce_corereset                   ), 
   .mux2ce_axis_rx_if                  (axis_rxreq_if                  ),
   .acelitetx_axistrx_bresperrpulse    (acelitetx_bresperrpulse        ),    
   .axistrx_csr_wen                    (axistrx_csr_wen                ),          
   .axistrx_csr_ren                    (axistrx_csr_ren                ),          
   .axistrx_csr_length                 (axistrx_csr_length             ),          
   .axistrx_csr_alignaddr              (axistrx_csr_alignaddr          ),         
   .axistrx_csr_unalignaddr            (axistrx_csr_unalignaddr        ), 
   .axistrx_csr_wrdata                 (axistrx_csr_wrdata             ),        
   .axistrx_csr_rsptag                 (axistrx_csr_rsptag             ),
   .axistrx_csr_reqid                  (axistrx_csr_reqid              ),
   .axistrx_csr_rspatrr                (axistrx_csr_rspatrr            ),
   .axistrx_csr_tc                     (axistrx_csr_tc                 ),
   .csr_axistrx_mrdstart               (csr_mrdstart                   ),
   .mmiorspfifo_axistrx_almostfull     (mmiorspfifo_axistrx_almostfull ),
   .axistrx_fc                         (axistrx_fc_req                 ),
   .axistrx_csr_cplstatus              (axistrx_csr_cplstatus_req      ), 
   .axistrx_axisttx_cplerr             (axistrx_cplerr_req             )
);



ce_acelite_tx      
   #(.CE_BUS_DATA_WIDTH         (CE_BUS_DATA_WIDTH    ),
   .CE_BUS_ADDR_WIDTH         (CE_BUS_ADDR_WIDTH    ),
   .CSR_DATA_WIDTH            (CSR_DATA_WIDTH       ),
   .CE_HST2HPS_FIFO_DEPTH     (CE_HST2HPS_FIFO_DEPTH),
   .CE_BUS_STRB_WIDTH         (CE_BUS_STRB_WIDTH    )) 

   ce_acelite_tx_inst(

   .clk                             (clk                             ),
   .ce_corereset                    (ce_corereset                    ), 
   .hps2ce_tx_awready               (ace_lite_tx_d.awready          ),
   .ce2hps_tx_awvalid               (ace_lite_tx_d.awvalid          ),
   .ce2hps_tx_awaddr                (ace_lite_tx_d.awaddr           ),
   .ce2hps_tx_awprot                (ace_lite_tx_d.awprot           ),
   .ce2hps_tx_awlen                 (ace_lite_tx_d.awlen            ),
   .ce2hps_tx_awsize                (ace_lite_tx_d.awsize           ),
   .ce2hps_tx_awburst               (ace_lite_tx_d.awburst          ),
   .ce2hps_tx_awsnoop               (ace_lite_tx_d.awsnoop          ),  
   .ce2hps_tx_awdomain              (ace_lite_tx_d.awdomain         ), 
   .ce2hps_tx_awbar                 (ace_lite_tx_d.awbar            ), 
   .hps2ce_tx_wready                (ace_lite_tx_d.wready           ),
   .ce2hps_tx_wvalid                (ace_lite_tx_d.wvalid           ),
   .ce2hps_tx_wlast                 (ace_lite_tx_d.wlast            ),
   .ce2hps_tx_wdata                 (ace_lite_tx_d.wdata            ),
   .ce2hps_tx_wstrb                 (ace_lite_tx_d.wstrb            ),
   .hps2ce_tx_bvalid                (ace_lite_tx_d.bvalid           ),
   .hps2ce_tx_bresp                 (ace_lite_tx_d.bresp            ),            
   .ce2hps_tx_bready                (ace_lite_tx_d.bready           ), 
   .cpldfifo_acelitetx_rddata       (cpldfifo_acelitetx_rddata       ),
   .acelitetx_cpldfifo_ren          (acelitetx_cpldfifo_ren          ),            
   .cpldfifo_acelitetx_cnt          (cpldfifo_occupancy              ),
   .csr_acelitetx_fifoerr           (fifo_err_flag                   ),            
   .cpldfifo_acelitetx_empty        (cpldfifo_acelitetx_empty        ),  
   .axistrx_acelitetx_fc            (axistrx_fc                      ),
   .csr_acelitetx_hpsaddr           (csr_acelitetx_hpsaddr           ),    
   .csr_acelitetx_mrdstart          (csr_mrdstart                    ),
   .axistrx_acelitetx_cplerr        (axistrx_cplerr                  ),     
   .acelitetx_bresp                 (acelitetx_bresp                 ),
   .acelitetx_axisttx_req_en        (acelitetx_axisttx_req_en        ),
   .acelitetx_bresperrpulse         (acelitetx_bresperrpulse         ),     
   .acelitetx_csr_dmadone           (acelitetx_csr_dmadone           ),
   .csr_acelitetx_imgxfrsize        (csr_imgxfrsize                  ),    
   .csr_acelitetx_datareqlimit_log2 (csr_axisttx_datareqlimit_log2   ),            
   .csr_acelitetx_datareqlimit      (csr_axisttx_datareqlimit        )

);
//bfifo
//  #(.WIDTH             ( 576                    ),
//    .DEPTH             ( CE_HST2HPS_FIFO_DEPTH  ),
//    .FULL_THRESHOLD    ( CE_HST2HPS_FIFO_THRSHLD),       
//    .REG_OUT           ( 1                      ), 
//    .GRAM_STYLE        ( 0                      ), //TBD
//    .BITS_PER_PARITY   ( 32                     )
//  )
//
//hst2hps_cpld_fifo(
//     
//    .fifo_din          (AxistRx_CpldFiFo_WrData   ),
//    .fifo_wen          (AxistRx_CpldFiFo_wen      ),
//    .fifo_ren          (AceliteTx_CpldFiFo_ren    ),
//    .clk               (clk                       ),
//    .Resetb            (!ce_CoreReset             ),
//    .fifo_out          (                          ),
//    .fifo_dout         (CpldFiFo_AceliteTx_RdData ),       
//    .fifo_count        (CpldFiFo_AxistRx_cnt      ),
//    .full              (CpldFiFo_AxistRx_full     ),
//    .not_empty         (CpldFiFo_NotEmpty         ),
//    .not_empty_out     (                          ),
//    .not_empty_dup     (                          ),
//    .fifo_err          (                          ),
//    .fifo_perr         (                          )
//  );

quartus_bfifo
   #(.WIDTH             ( 577                    ),
   .DEPTH             ( CE_HST2HPS_FIFO_DEPTH  ), 
   .FULL_THRESHOLD    ( CE_HST2HPS_FIFO_THRSHLD),
   .REG_OUT           ( 1                      ), 
   .RAM_STYLE         ( "AUTO"                 ),  
   .ECC_EN            ( 0                      ))

hst2hps_cpld_fifo(

      .fifo_din        (axistrx_cpldfifo_wrdata         ),
      .fifo_wen        (axistrx_cpldfifo_wen            ),
      .fifo_ren        (acelitetx_cpldfifo_ren          ),
      .clk             (clk                             ),
      .Resetb          (!ce_corereset                   ),
      .fifo_dout       (cpldfifo_acelitetx_rddata       ),       
      .fifo_count      (cpldfifo_occupancy              ), 
      .full            (cpldfifo_axistrx_full           ),
      .almost_full     (cpldfifo_axistrx_almostfull     ),
      .not_empty       (cpldfifo_notempty               ),
      .almost_empty    (                                ),
      .fifo_eccstatus  (                                ),
      .fifo_err        (cpldfifo_csr_fifoerr            )
);

ce_axi4mm_rx      
   #(.CE_AXI4MM_DATA_WIDTH     (CE_AXI4MM_DATA_WIDTH   ),
   .CE_AXI4MM_ADDR_WIDTH     (CE_AXI4MM_ADDR_WIDTH   ),
   .CSR_ADDR_WIDTH           (CSR_ADDR_WIDTH         ),
   .CE_BUS_STRB_WIDTH        (CE_AXI4MM_DATA_WIDTH>>3)) 

   ce_axi4mm_rx_inst(

   .clk                          (clk                        ),
   .h2f_reset                    (h2f_reset                  ),
   .ce2hps_rx_awready            (axi4mm_rx_d.awready       ),
   .hps2ce_rx_awvalid            (axi4mm_rx_d.awvalid       ),
   .hps2ce_rx_awaddr             (axi4mm_rx_d.awaddr        ),
   .hps2ce_rx_awprot             (axi4mm_rx_d.awprot        ),
   .hps2ce_rx_awlen              (axi4mm_rx_d.awlen         ),
   .hps2ce_rx_awid               (axi4mm_rx_d.awid          ),
   .hps2ce_rx_awsize             (axi4mm_rx_d.awsize        ),
   .hps2ce_rx_awburst            (axi4mm_rx_d.awburst       ),
   .hps2ce_rx_awcache            (axi4mm_rx_d.awcache       ),
   .hps2ce_rx_awqos              (axi4mm_rx_d.awqos         ), //
   .ce2hps_rx_wready             (axi4mm_rx_d.wready        ),
   .hps2ce_rx_wvalid             (axi4mm_rx_d.wvalid        ),
   .hps2ce_rx_wdata              (axi4mm_rx_d.wdata         ),
   .hps2ce_rx_wstrb              (axi4mm_rx_d.wstrb         ),
   .hps2ce_rx_wlast              (axi4mm_rx_d.wlast         ),
   .ce2hps_rx_bvalid             (axi4mm_rx_d.bvalid        ),
   .ce2hps_rx_bresp              (axi4mm_rx_d.bresp         ),
   .ce2hps_rx_bid                (axi4mm_rx_d.bid           ),
   .hps2ce_rx_bready             (axi4mm_rx_d.bready        ),
   .ce2hps_rx_arready            (axi4mm_rx_d.arready       ),
   .hps2ce_rx_arvalid            (axi4mm_rx_d.arvalid       ),
   .hps2ce_rx_araddr             (axi4mm_rx_d.araddr        ),
   .hps2ce_rx_arprot             (axi4mm_rx_d.arprot        ),
   .hps2ce_rx_arid               (axi4mm_rx_d.arid          ),
   .hps2ce_rx_arlen              (axi4mm_rx_d.arlen         ),
   .hps2ce_rx_arsize             (axi4mm_rx_d.arsize        ),
   .hps2ce_rx_arburst            (axi4mm_rx_d.arburst       ),
   .hps2ce_rx_arcache            (axi4mm_rx_d.arcache       ),
   .hps2ce_rx_arqos              (axi4mm_rx_d.arqos         ), //
   .hps2ce_rx_rready             (axi4mm_rx_d.rready        ),
   .ce2hps_rx_rvalid             (axi4mm_rx_d.rvalid        ),
   .ce2hps_rx_rdata              (axi4mm_rx_d.rdata         ),
   .ce2hps_rx_rlast              (axi4mm_rx_d.rlast         ),
   .ce2hps_rx_rid                (axi4mm_rx_d.rid           ),
   .ce2hps_rx_rresp              (axi4mm_rx_d.rresp         ),
   .acelitetx_axi4mmrx_bresp     (acelitetx_bresp            ),     
   .axistrx_axi4mmrx_cplerr      (axistrx_cplerr             ),     
   .axi4mmrx_csr_wdata           (axi4mmrx_csr_wdata         ), 
   .axi4mmrx_csr_wen             (axi4mmrx_csr_wen           ),            
   .axi4mmrx_csr_wstrb           (axi4mmrx_csr_wstrb         ),            
   .axi4mmrx_csr_ren             (axi4mmrx_csr_ren           ),  
   .axi4mmrx_csr_raddr           (axi4mmrx_csr_raddr         ),    
   .csr_axi4mmrx_fifoerr         (fifo_err_flag              ),            
   .axi4mmrx_csr_waddr           (axi4mmrx_csr_waddr         ),
   .csr_axi4mmrx_rdata           (csr_axi4mmrx_rdata         )

);

//tie off for unused outputs

assign  ace_lite_tx_d.awid       = 5'd0                     ;
assign  ace_lite_tx_d.awlock     = 1'd0                     ;
assign  ace_lite_tx_d.awcache    = 4'b0010                  ;
assign  ace_lite_tx_d.awqos      = 4'd0                     ;
assign  ace_lite_tx_d.awuser     = 23'b11100000             ;
assign  ace_lite_tx_d.arid       = 5'd0                     ;
assign  ace_lite_tx_d.arlock     = 1'd0                     ;
assign  ace_lite_tx_d.arcache    = 4'b0010                  ;
assign  ace_lite_tx_d.arqos      = 4'd0                     ;
assign  ace_lite_tx_d.aruser     = 23'b11100000             ;
assign  ace_lite_tx_d.arvalid    = 1'd0                     ;
assign  ace_lite_tx_d.araddr     = {CE_BUS_ADDR_WIDTH{1'h0}};
assign  ace_lite_tx_d.arprot     = 3'd0                     ;
assign  ace_lite_tx_d.arlen      = 8'd0                     ;
assign  ace_lite_tx_d.arsize     = 3'd0                     ;
assign  ace_lite_tx_d.arburst    = 2'd0                     ;
assign  ace_lite_tx_d.arsnoop    = 4'd0                     ;
assign  ace_lite_tx_d.ardomain   = 2'd3                     ;
assign  ace_lite_tx_d.arbar      = 2'd0                     ;
assign  ace_lite_tx_d.rready     = 1'd1                     ;

endmodule
