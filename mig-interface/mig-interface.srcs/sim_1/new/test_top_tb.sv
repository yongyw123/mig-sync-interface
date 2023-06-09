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
        //input logic debug_MMCM_locked         
    );
    
    localparam LED_END_RANGE = 4;
        
    initial begin
        /* initial reset pulse */
        CPU_RESETN = 1'b0;
        #(100);
        CPU_RESETN = 1'b1;
        #(100);

        /*
        wait(debug_MMCM_locked == 1'b1);
        #(5000);
        
        // reset yp start over;
        CPU_RESETN = 1'b0;
        #(100);
        CPU_RESETN = 1'b1;
        #(100);
        
        #(5000);
        */
        
        // wait for the LED to increase;
        // and wraps around twice to conclude the simulation;    
        wait(LED[LED_END_RANGE:0] == 1);
        
        // first round is done;
        wait(LED[LED_END_RANGE:0] == 0);
        wait(LED[LED_END_RANGE:0] == 1);
        
        // second round is done;
        wait(LED[LED_END_RANGE:0] == 0);
                
        // reset yp start over;
        CPU_RESETN = 1'b0;
        #(100);
        CPU_RESETN = 1'b1;
        #(100);
        
        
        // wait for the LED to increase;
        // and wraps around twice to conclude the simulation;    
        wait(LED[LED_END_RANGE:0] == 1);
        
        // first round is done;
        wait(LED[LED_END_RANGE:0] == 0);
        wait(LED[LED_END_RANGE:0] == 1);
        
        // second round is done;
        wait(LED[LED_END_RANGE:0] == 0);
        
        @(posedge clk_in_100M);
                
        $stop; 
    end
endmodule
