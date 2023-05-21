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
        // from slow domain
        input logic s_clk,
        input logic s_rst_n,
        input logic in_async,
        
        // from fast domain;
        input logic f_clk,
        input logic f_rst_n,        
        output logic out_sync
    );

    // from slow domain;
    logic flag;
    always_ff @(posedge s_clk or negedge s_rst_n) begin
        if(~s_rst_n) 
           flag <= 0;
	    else 
	       flag <= in_async;
    end

    // from fast domain;
    logic sync_reg;
    always @(posedge f_clk or negedge f_rst_n) begin
        if(~f_rst_n) begin 
            sync_reg <= 1'b0;
            out_sync <= 1'b0;
        end
	    else begin
            sync_reg <= flag;
            out_sync <= sync_reg;	    
	    end
    end
        
endmodule

