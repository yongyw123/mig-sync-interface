`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 21.05.2023 15:41:55
// Design Name: 
// Module Name: toggle_synchronizer_top_tb
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


module toggle_synchronizer_top_tb();
    // general;
    localparam T = 10;  // system clock period: 10ns;
    logic clk_sys;         // common system clock;
    logic rst_sys;        // async;
    logic rst_common;      // common reset signal for both clock domains in the synchronizer;
    
    /* MMCM clock signals */
    logic locked;
    logic clkout_200M;
    logic clkout_250M;
    assign rst_common = rst_sys &&  ~locked;    
    
    /* uut signals */
    // src;
    logic clk_src;  // 150MHz from the MMCM;
    logic rst_src;
    logic in_async; // driven by the test stimulus
    
    // dest;    
    logic clk_dest; // system clock at 100Mhz
    logic rst_dest;
    logic out_sync;

    //> mapping
    // first set;
    
    // source  
    assign clk_src = clkout_250M;
    assign rst_src = rst_common;    // common async reset signal;
    
    // destination
    assign clk_dest = clk_sys;
    assign rst_dest = rst_common;  // common async reset signal;
    
    
    /*
    // second set;
    assign clk_src = clk_sys;
    assign rst_src = rst_common;    // common async reset signal;
    
    // destination
    assign clk_dest = clkout_250M;
    assign rst_dest = rst_common;  // common async reset signal;
    */
    
    /*------------------------------------
    * instantiation 
    ------------------------------------*/
    // uut;
    toggle_synchronizer uut(.*);
    
    // test stimulus;
    toggle_synchronizer_tb tb(.*);
    
    // MMCM;
    
    clk_wiz_0 mmcm_unit
   (
    // Clock out ports
    .clk_200M(clkout_200M),     // output clk_200M
    .clk_250M(clkout_250M),     // output clk_250M
    .clk_100M(),                // output clk_100M
    // Status and control signals    
    .locked(locked),       // output locked
   // Clock in ports
    .clk_in1(clk_sys)
    );      // input clk_in1

    
    /* simulate clk */
     always
        begin 
           clk_sys = 1'b1;  
           #(T/2); 
           clk_sys = 1'b0;  
           #(T/2);
        end
    
     /* reset pulse */
     initial
        begin
            rst_sys = 1'b1;
            #(100);
            rst_sys = 1'b0;
            #(100);
        end
     
endmodule
