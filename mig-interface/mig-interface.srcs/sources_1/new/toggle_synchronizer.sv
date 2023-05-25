`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 21.05.2023 15:38:36
// Design Name: 
// Module Name: toggle_synchronizer
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


/*----------------------------
What: Toggle Synchronizer
Purpose: to synchronize a pulse from a fast clock domain to a slow clock domain;

Intended Application:
(Destination) Slow Clock Rate: 100MHz;
(Source) Fast Clock Rate: 150MHz;

Construction:
This is commonly used; google it;
that said, it consists three stages;
1. stage 01: toggling circuit in the fast clock domain;
2. stage 02: double FF synchronizer with respect to the slow clock domain;
3. stage 03: falling/rising edge detector;
-----------------------------------*/

module toggle_synchronizer
    (
        // src;
        input logic clk_src,
        input logic rst_src,
        input logic in_async,
        
        // dest;
        input logic clk_dest,
        input logic rst_dest,
        output logic out_sync
    );
    
    /*
    NOTE on ASYNC_REG;
    1. This is reported in the route design;
    2. Encountered Error: "TIMING-10#1 Warning
        Missing property on synchronizer  
        One or more logic synchronizer has been detected between 2 clock domains 
        but the synchronizer does not have the property ASYNC_REG defined on one or both registers. 
        It is recommended to run report_cdc for a complete and detailed CDC coverage
    "
    3. See Xilinx UG901 (https://docs.xilinx.com/r/en-US/ug901-vivado-synthesis/ASYNC_REG)
    The ASYNC_REG is an attribute that affects many processes in the Vivado tools flow. 
    The purpose of this attribute is to inform the tool that a register is capable of receiving 
    asynchronous data in the D input pin relative to the source clock, 
    or that the register is a synchronizing register within a synchronization chain.
    */


    /* -------------------------
    * signal declarations;
    ---------------------------*/
    // stage 01;
    (* ASYNC_REG = "TRUE" *) logic src_reg, src_next;

    
    ///// stage 02;        
    (* ASYNC_REG = "TRUE" *) logic stage02_first_reg, stage02_first_next;         
    (* ASYNC_REG = "TRUE" *) logic stage02_second_reg, stage02_second_next;
    
    // stage 03;
    (* ASYNC_REG = "TRUE" *) logic stage03_reg, stage03_next;

    /*----------------------------------
    * Stage 01:
    * source clock domain;
    * toggling circuit: FF + multiplexer    
    --------------------------------------*/
    // src ff;
    always_ff @(posedge clk_src, posedge rst_src) begin
        if(rst_src) begin
            src_reg <= 0; 
        end
        else begin
            src_reg <= src_next;             
        end
    end
    // next state (toggling circuit)
    assign src_next = (in_async) ? ~(src_reg) : src_reg;
    
    /*----------------------------------
    * Stage 02:
    * double FF synchronizer
    * clock domain: destination;
    --------------------------------------*/
    always_ff @(posedge clk_dest, posedge rst_dest) begin
        if(rst_dest) begin
            stage02_first_reg <= 0;
            stage02_second_reg <= 0; 
        end
        else begin
            stage02_first_reg <= stage02_first_next;
            stage02_second_reg <= stage02_second_next;
        end
    end
    // next state;
    assign stage02_first_next = src_reg;
    assign stage02_second_next = stage02_first_reg;
    
    /*----------------------------------
    * Stage 03: output
    * clock domain: destination;
    * falling/rising edge detector;
    --------------------------------------*/
    // stage 03;
    always_ff @(posedge clk_dest, posedge rst_dest) begin
        if(rst_dest) begin
            stage03_reg <= 0;
             
        end
        else begin
            stage03_reg <= stage03_next;            
        end
    end
    
    // next state;
    assign stage03_next = stage02_second_reg;
        
    // output; should be synchronized by now?
    assign out_sync = stage03_reg ^ stage02_second_reg;     
endmodule
