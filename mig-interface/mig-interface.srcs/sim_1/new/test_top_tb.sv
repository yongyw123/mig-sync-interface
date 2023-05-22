`timescale 1ns / 1fs
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
    
    
    initial begin
        
        // wait for the LED to increase;
        // and wraps around twice to conclude the simulation;    
        wait(LED == 1);
        
        // first round is done;
        wait(LED == 0);
        wait(LED == 1);
        
        // second round is done;
        wait(LED == 0);
        
        @(posedge clk_in_100M);
        $stop; 
    end
endmodule
