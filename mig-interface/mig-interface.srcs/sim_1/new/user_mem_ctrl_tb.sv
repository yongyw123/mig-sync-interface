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
        output logic [22:0] user_addr,
        output logic [127:0] user_wr_data,
        input logic [127:0] user_rd_data,
        
        // uut status;
        input logic MIG_user_init_complete,        // MIG done calibarating and initializing the DDR2;
        input logic MIG_user_ready,                // this implies init_complete and also other status; see UG586; app_rdy;
        input logic MIG_user_transaction_complete // read/write transaction complete?
        
    );
    
    localparam addr01 = 23'b0;
    localparam addr02 = {22'b0, 1'b1};
    localparam TEST_ARRAY_SIZE = 100;
    bit[TEST_ARRAY_SIZE-1:0][127:0] TEST_ARRAY;
    
    
    initial
    begin        
        /* test 01: first write */
        @(posedge clk_sys);
        user_wr_strobe <= 1'b0;
        user_rd_strobe <= 1'b0;        
        user_addr <= addr01;
        user_wr_data = {64'hFFFF_EEEE_DDDD_CCCC, 64'hBBBB_AAAA_9999_8888};        
               
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
        user_wr_data = {64'h7777_6666_5555_4444, 64'h3333_2222_1111_0A0A};
                        
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
    
        // wait for the transaction to complete
        @(posedge clk_sys);
        wait(MIG_user_transaction_complete == 1'b1);
        
        #(500);
        
        /* test 04: second read */                
        // enable read;
        @(posedge clk_sys);
        user_addr <= addr02;
        @(posedge clk_sys);
        user_rd_strobe <= 1'b1;
        
        // disable read;
        @(posedge clk_sys);
        user_rd_strobe <= 1'b0;
    
        // wait for the transaction to complete
        @(posedge clk_sys);
        wait(MIG_user_transaction_complete == 1'b1);
        
        #(500);
        
        /* test 04: sequential write's followed by sequential read's */
        
        // prepare an array of random data to write;
        for(int i = 0; i < TEST_ARRAY_SIZE; i++) begin
            TEST_ARRAY[i] = {128{$random}};        
        end
        
        // sequential write;
        for(int i = 0; i < TEST_ARRAY_SIZE; i++) begin
            // setup;
            @(posedge clk_sys);
            user_wr_strobe <= 1'b0;                    
            user_addr <= i;
            user_wr_data = TEST_ARRAY[i];        
            
            // submit the write request;
            @(posedge clk_sys);
            user_wr_strobe <= 1'b1;                                            
            @(posedge clk_sys);
            user_wr_strobe <= 1'b0; // disable write;
                        
            // wait for the transaction to complete
            @(posedge clk_sys);
            wait(MIG_user_transaction_complete == 1'b1);
            @(posedge clk_sys);
        
        end
        
        // sequential read;
        for(int i = 0; i < TEST_ARRAY_SIZE; i++) begin
            // setup;
            @(posedge clk_sys);
            user_rd_strobe <= 1'b0;                    
            user_addr <= i;
            user_wr_data = TEST_ARRAY[i];        
            
            // submit the read request;
            @(posedge clk_sys);
            user_rd_strobe <= 1'b1;                                            
            @(posedge clk_sys);
            user_rd_strobe <= 1'b0; 
                        
            // wait for the transaction to complete
            @(posedge clk_sys);
            wait(MIG_user_transaction_complete == 1'b1);
            
            @(posedge clk_sys);            
            // check if the read data matches with what it is written at a given address;
             assert(user_rd_data == TEST_ARRAY[i]) $display("Test index: %0d, Time; %t, Status: OK, read data matches with the written data at Address: %0d", i, $time, user_addr);  
             else begin 
                    $error("Read Data does not match with the Written Data @ time: %t, Address: %0d", $time, user_addr);
                    $error("ERROR Encountered: terminate the simulation at once");
                    $stop;  // stop the simulation immediately upon discovering a mismatch; as this should not happen unless intended;                     
             end            
         end
                
        $stop;
        
    end
    
endmodule
