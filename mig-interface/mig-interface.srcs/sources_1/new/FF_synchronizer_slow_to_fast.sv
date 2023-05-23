`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 21.05.2023 15:48:55
// Design Name: 
// Module Name: FF_synchronizer_slow_to_fast
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


/*
* Purpose: synchronizer from slow clock domain to fast clock domain;
* Assumption:
*   1. slow clock: 100MHz;
*   2. fast clock: 150MHz;
*
* Note:
* 1. by above, fast is ~1.5 times of the slow; this is not fast enough;
* 2. a simple double FF may not be sufficient because
*   the input may be missed even when sampled on the fast clock;
* 3. to mitigate the above; 
*
* Reference:
* 1. https://www.verilogpro.com/clock-domain-crossing-part-1/#:~:text=The%20easy%20case%20is%20passing%20signals%20from%20a,these%20cases%2C%20a%20simple%20two-flip-flop%20synchronizer%20may%20suffice.
* 2. http://www.verilab.com/files/sva_cdc_paper_dvcon2006.pdf

*
*/

module FF_synchronizer_slow_to_fast
    (
        // src: from slow domain
        input logic in_async,
        
        // dest: from fast domain;
        input logic f_clk,
        input logic f_rst_n,        
        output logic out_sync
    );        
    /*
    NOTE on ASYNC_REG;
    1. This is reported in the route design;
    2. Encountered Error: "TIMING-10#1 Warning
        Missing property on synchronizer  
        One or more logic synchronizer has been detected between 2 clock domains 
        but the synchronizer does not have the property ASYNC_REG defined on one 
        or both registers. 
        It is recommended to run report_cdc for a complete and detailed CDC coverage
    "
    3. See Xilinx UG901 (https://docs.xilinx.com/r/en-US/ug901-vivado-synthesis/ASYNC_REG)
    The ASYNC_REG is an attribute that affects many processes in the Vivado tools flow. 
    The purpose of this attribute is to inform the tool that a register is capable of receiving 
    asynchronous data in the D input pin relative to the source clock, 
    or that the register is a synchronizing register within a synchronization chain.
    */

    
    (* ASYNC_REG = "TRUE" *) logic sync_reg;
    always @(posedge f_clk or negedge f_rst_n) begin
        if(~f_rst_n) begin 
            sync_reg <= 1'b0;
            out_sync <= 1'b0;
        end
	    else begin
            sync_reg <= in_async;
            out_sync <= sync_reg;	    
	    end
    end
        
endmodule

