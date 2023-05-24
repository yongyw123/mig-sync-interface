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
        input logic [15:0] LED,
        output logic CPU_RESETN            
    );
    
    
    initial begin
        
        // wait for the LED to increase;
        // and wraps around twice to conclude the simulation;    
        wait(LED[13:0] == 1);
        
        // first round is done;
        wait(LED[13:0] == 0);
        wait(LED[13:0] == 1);
        
        // second round is done;
        wait(LED[13:0] == 0);
        
        @(posedge clk_in_100M);
        
        
        // reset yp start over;
        CPU_RESETN = 1'b0;
        #(100);
        CPU_RESETN = 1'b1;
        #(100);
        
        
        // wait for the LED to increase;
        // and wraps around twice to conclude the simulation;    
        wait(LED[13:0] == 1);
        
        // first round is done;
        wait(LED[13:0] == 0);
        wait(LED[13:0] == 1);
        
        // second round is done;
        wait(LED[13:0] == 0);
        
        @(posedge clk_in_100M);
        
        
        $stop; 
    end
endmodule
