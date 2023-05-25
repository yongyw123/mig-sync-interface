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
        output logic rst_sys,
        
        
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
    //localparam TEST_ARRAY_SIZE = 1000;
    localparam TEST_ARRAY_SIZE = 2;
    bit[TEST_ARRAY_SIZE-1:0][127:0] TEST_ARRAY;
    logic [127:0] random_data_set_01 = {127{$random}};
    
    initial
    begin        
        /* initial reset pulse */
        rst_sys = 1'b1;
        #(100);
        rst_sys = 1'b0;
        #(100);
 
        /* setting up logging system 
        * created file could be located under ./sim_1/behav/xsim
        */
        
        /*
        int fd; // file descriptor;
        fd = $fopen("./simulation_logging_user_mem_ctrl_tb.txt", "a");
        if(fd) 
            $display("File was opened successfully: %0d", fd);
        else begin        
            $display("File was NOT opened successfully: %0d", fd);
            $display("Something went wrong. Terminate the simulation at once");
            $fclose(fd);
        end
        */
        /* test 01: first write */
        @(posedge clk_sys);
        user_wr_strobe <= 1'b0;
        user_rd_strobe <= 1'b0;        
        user_addr <= addr01;
        user_wr_data = {64'hFFFF_EEEE_DDDD_CCCC, 64'hBBBB_AAAA_9999_8888};        
               
        wait(MIG_user_init_complete == 1'b1);
        #(100);
        
        
        /* test 01.5: reset after MIG finishes calibrated */
        rst_sys = 1'b1;
        #(100);
        rst_sys = 1'b0;
        #(100);
        
        
        wait(MIG_user_init_complete == 1'b0);
        @(posedge clk_sys);
        
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
        
        /* test 04: sequential: one write immediately followed by one read 
        expectation: not sure;
        because even though one write request is submitted and write transaction complete
        is asserted, it does not imply that the data is already written to the memory ...
        
        observation:
        1. read data actually matches with the previous write data!
        2. the dqs line is bidirectional;
        3. so, when writing is ongoing, the dqs is occupied even though the read request
            may have already submitted at this point; data will not be read until this
            line is released to service this read request;        
        
        Explanation:
        1. the observation above confirms the datasheet and the support article linked below;
        2. that is, MIG controller could service concurrent transactions; BUT;
        3. these transactions are pipelined, and successive transaction will overlap BUT
            they are initiated and completed serially (not concurrently);
        4. support article: https://support.xilinx.com/s/question/0D52E00006hpWuzSAE/simultaneous-readwrite-migddr3?language=en_US
        5. ddr2 datasheet: https://media-www.micron.com/-/media/client/global/documents/products/data-sheet/dram/ddr2/1gb_ddr2.pdf?rev=854b480189b84d558d466bc18efe270c*/
        // setup;
        @(posedge clk_sys);
        user_wr_strobe <= 1'b0;                    
        user_addr <= 3;
        
        user_wr_data <= random_data_set_01;        
        
        // submit the write request;
        @(posedge clk_sys);
        user_wr_strobe <= 1'b1;                                            
        @(posedge clk_sys);
        user_wr_strobe <= 1'b0; // disable write;
                    
        // wait for the transaction to complete
        @(posedge clk_sys);
        wait(MIG_user_transaction_complete == 1'b1);
    
        // submit the read request;
        @(posedge clk_sys);
        user_rd_strobe <= 1'b1;                                            
        @(posedge clk_sys);
        user_rd_strobe <= 1'b0; 
                    
        // wait for the transaction to complete
        @(posedge clk_sys);
        wait(MIG_user_transaction_complete == 1'b1);
        
        assert(user_rd_data == random_data_set_01) $display("Time; %t, Status: OK, read data matches with the written data at Address: %0d", $time, user_addr);  
             else begin 
                    $error("Read Data does not match with the Written Data @ time: %t, Address: %0d", $time, user_addr);
                    $error("ERROR Encountered: terminate the simulation at once");
                    $stop;  // stop the simulation immediately upon discovering a mismatch; as this should not happen unless intended;                     
             end            
        
        #(1000);
        
        /* test 05: burst write's then only burst read's */
        
        // prepare an array of random data to write;
        for(int i = 0; i < TEST_ARRAY_SIZE; i++) begin
            TEST_ARRAY[i] = {128{$random}};        
        end
        
        // burst write;
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
        
        // burst read;
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
             assert(user_rd_data == TEST_ARRAY[i]) 
             begin
                //$fdisplay(fd, "Test index: %0d, Time; %t, Status: OK, read data matches with the written data at Address: %0d", i, $time, user_addr);
                $display("Test index: %0d, Time; %t, Status: OK, read data matches with the written data at Address: %0d", i, $time, user_addr);
             end  
             else begin 
                    $error("Read Data does not match with the Written Data @ time: %t, Address: %0d", $time, user_addr);
                    $error("ERROR Encountered: terminate the simulation at once");
                                    
                    // log it;                    
                    //$fdisplay(fd, "ERROR: Read Data does not match with the Written Data @ time: %t, Address: %0d", $time, user_addr);
                    //$fdisplay(fd, "ERROR Encountered: terminate the simulation at once");
                    
                    $stop;  // stop the simulation immediately upon discovering a mismatch; as this should not happen unless intended;                     
             end            
         end
        
        $display("completed all %0d test; status: OK", TEST_ARRAY_SIZE);
        
        
        
        //$fdisplay(fd, "completed all %0d test; status: OK", TEST_ARRAY_SIZE);
        //$fclose(fd);   
        $stop;
        
               
        
    end
    
endmodule
