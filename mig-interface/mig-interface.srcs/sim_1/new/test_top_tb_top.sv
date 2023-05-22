`timescale 1ns / 1fs
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 22.05.2023 17:58:53
// Design Name: 
// Module Name: test_top_tb_top
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


module test_top_tb_top();
    // general;
    localparam T = 10;  // system clock period: 10ns;
    logic clk_in_100M;         // common system clock;
    logic CPU_RESETN;        // async;
        
    /* uut signals */
    // LEDs;
    logic [15:0] LED;
        
    // ddr2 sdram memory interface (defined by the imported ucf file);
    logic [12:0] ddr2_addr;  // address; 
    logic [2:0]  ddr2_ba;   
    logic ddr2_cas_n; //                                         ddr2_cas_n
    logic [0:0] ddr2_ck_n; //   [0:0]                        ddr2_ck_n
    logic [0:0] ddr2_ck_p; //   [0:0]                        ddr2_ck_p
    logic [0:0] ddr2_cke; //   [0:0]                       ddr2_cke
    logic ddr2_ras_n; //                                         ddr2_ras_n
    logic ddr2_we_n; //                                         ddr2_we_n
    tri [15:0] ddr2_dq; // [15:0]                         ddr2_dq
    tri [1:0] ddr2_dqs_n; // [1:0]                        ddr2_dqs_n
    tri [1:0] ddr2_dqs_p; // [1:0]                        ddr2_dqs_p      
    logic [0:0] ddr2_cs_n; //   [0:0]           ddr2_cs_n
    tri [1:0] ddr2_dm; //   [1:0]                        ddr2_dm
    logic [0:0] ddr2_odt;  //   [0:0]                       ddr2_odt
        
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
    
    
    // uut;
    test_top uut (.*);
    
    // test stimulus;
    test_top_tb tb(.*);
        
    /* simulate clk */
     always
        begin 
           clk_in_100M = 1'b1;  
           #(T/2); 
           clk_in_100M = 1'b0;  
           #(T/2);
        end
    
     /* reset pulse */
     initial
        begin
            CPU_RESETN = 1'b0;
            #(100);
            CPU_RESETN = 1'b1;
            #(100);
        end          
    
    /* monitoring */
    initial begin
           $monitor("USER MONITORING - time: %0t, uut.state_reg: %s, uut.state_next: %s",
            $time,
            uut.state_reg.name,
            uut.state_next.name            
            );           
    end                        

endmodule
