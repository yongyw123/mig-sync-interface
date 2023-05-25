`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 21.05.2023 15:50:51
// Design Name: 
// Module Name: user_mem_ctrl_top_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module user_mem_ctrl_top_tb();
     // general;
    localparam T = 10;  // system clock period: 10ns;
    logic clk_sys;         // common system clock;
    logic rst_sys;        // async system clock;
    
    /* MMCM clock signals */
    logic locked;
    
    /* ---------------------------- 
    * UUT: MIG memory controller;
    ------------------------------*/
    // user signals for the uut;
    logic user_wr_strobe;             // write request;
    logic user_rd_strobe;             // read request;
    logic [22:0] user_addr;           // address;
    
    // data;
    logic [127:0] user_wr_data;       
    logic [127:0] user_rd_data;   
    
    // status
    logic MIG_user_init_complete;        // MIG done calibarating and initializing the DDR2;
    logic MIG_user_ready;                // this implies init_complete and also other status; see UG586; app_rdy;
    logic MIG_user_transaction_complete; // read/write transaction complete?
    
    // ddr2 MIG general signals 
    logic clk_mem;    // MIG memory clock;
    logic rst_mem_n;    // active low to reset the mig interface;
    
    // ddr2 sdram memory interface (defined by the imported ucf file); 
    logic [12:0] ddr2_addr;   // address; 
    logic [2:0]  ddr2_ba;    
    logic ddr2_cas_n;  // output                                       ddr2_cas_n
    logic [0:0] ddr2_ck_n;  // output [0:0]                        ddr2_ck_n
    logic [0:0] ddr2_ck_p;  // output [0:0]                        ddr2_ck_p
    logic [0:0] ddr2_cke;  // output [0:0]                       ddr2_cke
    logic ddr2_ras_n;  // output                                       ddr2_ras_n
    logic ddr2_we_n;  // output                                       ddr2_we_n
    tri [15:0] ddr2_dq;  // inout [15:0]                         ddr2_dq
    tri [1:0] ddr2_dqs_n;  // inout [1:0]                        ddr2_dqs_n
    tri [1:0] ddr2_dqs_p;  // inout [1:0]                        ddr2_dqs_p
    logic init_calib_complete;  // output                                       init_calib_complete
	logic [0:0] ddr2_cs_n;  // output [0:0]           ddr2_cs_n
    //logic [1:0] ddr2_dm;  // output [1:0]                        ddr2_dm
    tri [1:0] ddr2_dm;  // output [1:0]                        ddr2_dm; data mask;
    logic [0:0] ddr2_odt;  // output [0:0]                       ddr2_odt
   
    // debugging interface;
    // MIG signals read data is valid;
    logic debug_app_rd_data_valid;
       
    // MIG signals that the data on the app_rd_data[] bus in the current cycle is the 
    // last data for the current request
    logic debug_app_rd_data_end;
    
    // mig own driving clock; 
    logic debug_ui_clk;
    
    // mig own synhcronous reset wrt to ui_clk;
    logic debug_ui_clk_sync_rst;
    logic debug_app_rdy;
    logic debug_app_wdf_rdy;
    logic debug_app_en;
    logic [63:0] debug_app_wdf_data;
    logic debug_app_wdf_end;
    logic debug_app_wdf_wren;
    logic debug_init_calib_complete;
    logic debug_transaction_complete_async;
    logic [2:0] debug_app_cmd;
    logic [63:0] debug_app_rd_data;
    logic debug_user_wr_strobe_sync;
    logic debug_user_rd_strobe_sync;
    logic [3:0] debug_FSM;
    
    /*------------------------------------
    * instantiation 
    ------------------------------------*/
    
    /* ddr2 model;
    fake model to simulate the mig interface with;
    otherwise, what will the mig interface be interfacing with;
    ie without the model; the mig interface will not
    receive any simulated ddr2 memory feedback;
    
    note:
    1. this ddr2 model is copied directly from th ip-example;
    
    reference: 
    https://support.xilinx.com/s/question/0D52E00006hpsNVSAY/mig-simulation-initcalibcomplete-stays-low?language=en_US
    
    */
    /*
    ddr2_model ddr2_model_unit
    (
        .ck(ddr2_ck_p),
        .ck_n(ddr2_ck_n),
        .cke(ddr2_cke),
        .cs_n(ddr2_cs_n),
        .ras_n(ddr2_ras_n),
        .cas_n(ddr2_cas_n),
        .we_n(ddr2_we_n),
        .dm_rdqs(ddr2_dm),
        .ba(ddr2_ba),
        .addr(ddr2_addr),
        .dq(ddr2_dq),
        .dqs(ddr2_dqs_p),
        .dqs_n(ddr2_dqs_n),
        .rdqs_n(),
        .odt(ddr2_odt)
    );
    */
    
    // MMCM;    
    clk_wiz_0 mmcm_unit
   (
    // Clock out ports
    .clk_200M(clk_200M),     // output clk_200M
    .clk_250M(),     // output clk_250M
    .clk_100M(),     // output clk_100M
    // Status and control signals    
    .locked(locked),       // output locked
   // Clock in ports
    .clk_in1(clk_sys)
    );      // input clk_in1

    assign rst_mem_n = (!rst_sys) && (locked);
    assign clk_mem = clk_200M;
    user_mem_ctrl uut (.*, .clk_mem(clk_mem), .rst_mem_n(rst_mem_n));
    
    // test stimuls;
    user_mem_ctrl_tb tb(.*);
            
    /* simulate clk */
     always
        begin 
           clk_sys = 1'b1;  
           #(T/2); 
           clk_sys = 1'b0;  
           #(T/2);
        end
    
        
    /* monitoring */
    initial begin
        $monitor("time: %t, uut.state_reg: %s",
        $time,
        uut.state_reg.name
        );    
    end

endmodule
