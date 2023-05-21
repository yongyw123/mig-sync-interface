`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 21.05.2023 15:53:24
// Design Name: 
// Module Name: user_mem_ctrl_tb
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


module user_mem_ctrl_tb
    (
        // general;
        input logic clk_sys,
        
        // stimulus for uut;
        output logic user_wr_strobe,
        output logic user_rd_strobe,
        output logic [26:0] user_addr,
        output logic [63:0] user_wr_data,
        
        // uut status;
        input logic MIG_user_init_complete,        // MIG done calibarating and initializing the DDR2;
        input logic MIG_user_ready,                // this implies init_complete and also other status; see UG586; app_rdy;
        input logic MIG_user_transaction_complete // read/write transaction complete?
        
    );
    
    localparam addr01 = 26'b0;
    localparam addr02 = 26'b1;
    
    initial
    begin
        /* test 01: first write */
        @(posedge clk_sys);
        user_wr_strobe <= 1'b0;
        user_rd_strobe <= 1'b0;
        //user_addr <= {22'b0, 2'b10, 3'b000};
        user_addr <= addr01;
        user_wr_data = {16'hDDDD, 16'hCCCC, 16'hBBBB, 16'hAAAA};
               
        wait(MIG_user_init_complete == 1'b1);
        #(100);
        
        // submit the write request;
        @(posedge clk_sys);
        user_wr_strobe <= 1'b1;                        
        
        // disable write;
        @(posedge clk_sys);
        user_wr_strobe <= 1'b0;
        
        // wait for the write transaction to complete
        @(posedge clk_sys);
        wait(MIG_user_transaction_complete == 1'b1);
        #(1000);
                
        /* test 02: second write */
        @(posedge clk_sys);
        user_addr <= addr02;
        user_wr_data = {16'h4444, 16'h3333, 16'h2222, 16'h1111};
                        
        // submit the write request;
        @(posedge clk_sys);
        user_wr_strobe <= 1'b1;                        
        
        // disable write;
        @(posedge clk_sys);
        user_wr_strobe <= 1'b0;
        
        // wait for the write transaction to complete
        @(posedge clk_sys);
        wait(MIG_user_transaction_complete == 1'b1);
        #(1000);
        
                                
        /* test 03: first read */                
        // enable read;
        @(posedge clk_sys);
        user_addr <= addr01;
        @(posedge clk_sys);
        user_rd_strobe <= 1'b1;
        
        // disable read;
        @(posedge clk_sys);
        user_rd_strobe <= 1'b0;
    
        @(posedge clk_sys);
        wait(MIG_user_transaction_complete == 1'b1);
        
        #(1000);
        
        /* test 04: second read */                
        // enable read;
        @(posedge clk_sys);
        user_addr <= addr02;
        @(posedge clk_sys);
        user_rd_strobe <= 1'b1;
        
        // disable read;
        @(posedge clk_sys);
        user_rd_strobe <= 1'b0;
    
        @(posedge clk_sys);
        wait(MIG_user_transaction_complete == 1'b1);
        
        #(1000);
        
        $stop;
    end
    
endmodule
