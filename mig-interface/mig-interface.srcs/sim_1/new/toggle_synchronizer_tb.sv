`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 21.05.2023 15:42:19
// Design Name: 
// Module Name: toggle_synchronizer_tb
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


module toggle_synchronizer_tb
    (
        // need to wait for the mmcm to lock before start the test stimulus;
        input logic locked,
        
        // src domain;
        input logic clk_src,
        // test stimulus;
        output logic in_async,
        
        // dest domain;
        input logic clk_dest
    );
    
    initial begin
        
    // initial condition;
    @(posedge clk_src);
    in_async <= 1'b0;
    
    // need to wait for the mmcm to lock before start the test stimulus;
    wait(locked == 1'b1);

    /* there exists two strict conditions so that the synchronized signal
    is correct;
    
    conditions:
    1. Pulse is only one fast-clock-cycle wide.
    2. There should be only one fast-clock-pulse in at least three slow-clock cycles.
    */
    
    /* case 01: 
    when there is only one short pulse with respect to the fast clock;
    that said, ideally, we want it to be in between two rising edges of the slow clock (dest);
    to check whether the toggle synchronizer detects it and synchronizes it;
    */
    @(posedge clk_src);
    in_async <= 1'b1;
    @(posedge clk_src);
    in_async <= 1'b0;
       
    /* case 02: to violate condition 01
    by creating a "static" signal wrt to the fast clock;
    */    
    #(100);
    @(posedge clk_src);
    in_async <= 1'b1;
    #(1000);
    
    @(posedge clk_src);
    in_async <= 1'b0;
    #(1000);
    
    /* case 03: to violate condition 02
    by creating ten pulses in successive with
    respect to the fast clock;
    */
    for(int i = 0; i < 10; i++) begin
        @(posedge clk_src);
        in_async <= 1'b1;
        @(posedge clk_src);
        in_async <= 1'b0;
    end
    

    /* case 04: when all conditions are met;
    to create ten pulses in the fast clock
    by respecting condition 02;
    */    
    #(1000);
  
    
    for(int i = 0; i < 10; i++) begin
        @(posedge clk_src);
        in_async <= 1'b1;
        @(posedge clk_src);
        in_async <= 1'b0;
        
        // three slow clock cycle "gap"
        for(int j = 0; j < 3; j++) begin
            @(posedge clk_dest);        
        end
    end
    
    #(100);
    $stop;
    end
endmodule
