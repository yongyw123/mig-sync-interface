`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 22.05.2023 17:58:38
// Design Name: 
// Module Name: test_top_tb
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


module test_top_tb
    (
        input logic clk_in_100M,
        input logic [15:0] LED               
    );
    
    //localparam TERMINATE_THRESHOLD = 5;
    initial begin
        #(1000);
        @(posedge clk_in_100M);        
        wait(LED == 5);
        @(posedge clk_in_100M);
        @(posedge clk_in_100M);
        @(posedge clk_in_100M);
        @(posedge clk_in_100M);
        #(10000);
        $stop; 
    end
endmodule
