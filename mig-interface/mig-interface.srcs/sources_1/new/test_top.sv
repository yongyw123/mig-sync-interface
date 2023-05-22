`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 22.05.2023 13:16:21
// Design Name: 
// Module Name: test_top
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

Purpose: 
This is a hw testing circuit for user_mem_ctrl module
by testing with the actual DDR2 external memory
on the fpga dev board;

Test:
1. Sequentially write to the DDR2;
2. Sequentially read from the DDR2 and display the value as the LED;
3. for simplicity, we shall restrict the data range to 2^{16} since there
    are 16 LEDs on the board;
4. for visual inspection; we shall have a timer for each LED change;

Note:
1. by above, this test is not exhaustive;
2. merely to test the communication with the real DDR2 external memory;

*/    

module test_top    
    (
        // general;
        // 100 MHz;
        input logic clk_in_100M,       
        
        // async cpu (soft core) reset button; 
        // **important; it is active low; need to invert;
        input logic CPU_RESETN,     
      
        // LEDs;
        output logic [15:0] LED
                        
    );
    /*--------------------------------------
    * signal declarations 
    --------------------------------------*/
    /////////// general;   
    logic rst_sys;
    logic clk_sys;  // 100MHz from the MMCM;
       
    /////////// MMCM;
    logic clkout_200M; // to drive the MIG;
    logic clkout_100M; // to drive the rest of the system;
    logic locked;
    
    /////////// ddr2 MIG general signals
    // user signals for the uut;
    logic user_wr_strobe;             // write request;
    logic user_rd_strobe;             // read request;
    logic [22:0] user_addr;           // address;
    
    // data;
    logic [127:0] user_wr_data;       
    logic [127:0] user_rd_data;   
    
    // status
    logic MIG_user_init_complete;        // MIG done calibarating and initializing the DDR2;
    logic MIG_user_ready;                // this implies init_complete and also other status; see UG586; app_rdy;
    logic MIG_user_transaction_complete; // read/write transaction complete?
         
    logic clk_mem;    // MIG memory clock;
    logic rst_mem_n;    // active low to reset the mig interface;
    
    /*--------------------------------------
    * application test signals 
    --------------------------------------*/    
    ///////////     
    /* 
    state:
    1. ST_CHECK_INIT: wait for the memory initialization to complete before starting everything else;
    2. ST_WRITE_SETUP: prepare the write data and the addr;
    3. ST_WRITE: write to the ddr2;     
    4. ST_WRITE_WAIT: wait for the write transaction to complete;
    5. ST_READ_SETUP: prepare the addr;
    6. ST_READ: read from the ddr2;
    7. ST_READ_WAIT: wait for the read data to be valid;
    8. ST_LED_WAIT: timer wait for led display;    
    9. ST_GEN: to generate the next test data;
    */
    typedef enum{ST_CHECK_INIT, ST_WRITE_SETUP, ST_WRITE, ST_WRITE_WAIT, ST_READ_SETUP, ST_READ, ST_READ_WAIT, ST_LED_WAIT, ST_GEN} state_type;
    state_type state_reg, state_next;    
    
    // register to filter the glitch when writing the write data;
    // there is a register within the uut for read data; so not necessary;    
    logic [127:0] wr_data_reg, wr_data_next;
    
    // register to filter addr glitch when issuing;
    logic [22:0] user_addr_reg, user_addr_next;
    
    // counter/timer;
    // 2 seconds led pause time; with 100MHz; 200MHz threshold is required;
    //localparam TIMER_THRESHOLD = 200_000_000;
    localparam TIMER_THRESHOLD = 2;
    logic [27:0] timer_reg, timer_next;
    
    // traffic generator to issue the addr;
    // here we just simply use incremental basis;
    //localparam INDEX_THRESHOLD = 65536; // wrap around; 2^{16};
    localparam INDEX_THRESHOLD = 2; // wrap around; 2^{16};
    logic [15:0] index_reg, index_next;
    
    /*--------------------------------------
    * instantiation 
    --------------------------------------*/
    // MMCM
    clk_wiz_0 mmcm_unit
       (
        // Clock out ports
        .clk_200M(clkout_200M),     // output clk_200M
        .clk_250M(),     // output clk_250M
        .clk_100M(clkout_100M),     // output clk_100M
        // Status and control signals
        .reset(rst_sys), // input reset
        .locked(locked),       // output locked
       // Clock in ports
        .clk_in1(clk_in_100M)
    );      // input clk_in1
    
    
    /*--------------------------------------
    * signal mapping; 
    --------------------------------------*/
    assign clk_sys = clkout_100M;
    assign rst_sys = ~CPU_RESETN; // active high for system reset;
        
    assign rst_mem_n = (!rst_sys) && (locked);
    assign clk_mem = clkout_200M;  
    
    ////////////////////////////////////////////////////////////////////////////////////
     // ff;
    always_ff @(posedge clk_sys, posedge rst_sys)
    //always_ff @(posedge clk_in_100M, posedge rst_sys) begin    
        if(rst_sys) begin
            wr_data_reg <= 0;
            timer_reg <= 0;
            index_reg <= 0;
            state_reg <= ST_CHECK_INIT;
            user_addr_reg <= 0;         
        end
        else begin
            wr_data_reg <= wr_data_next;
            timer_reg <= timer_next;
            index_reg <= index_next;
            state_reg <= state_next;
            user_addr_reg <= user_addr_next;
        end
    
    
    // fsm;
    always_comb begin
       // default;
        wr_data_next = wr_data_reg;
        timer_next = timer_reg;
        index_next = index_reg;
        state_next = state_reg;
        user_addr_next = user_addr_reg;
                
        user_wr_strobe = 1'b0;
        user_rd_strobe = 1'b0;
        user_addr = user_addr_reg;
        user_wr_data = wr_data_reg;
                                            
        /* 
        state:
        1. ST_CHECK_INIT: wait for the memory initialization to complete before starting everything else;
        2. ST_WRITE_SETUP: prepare the write data and the addr;
        3. ST_WRITE: write to the ddr2;     
        4. ST_WRITE_WAIT: wait for the write transaction to complete;
        5. ST_READ_SETUP: prepare the addr;
        6. ST_READ: read from the ddr2;
        7. ST_READ_WAIT: wait for the read data to be valid;
        8. ST_LED_WAIT: timer wait for led display;    
        9. ST_GEN: to generate the next test data;
        */
            
        case(state_reg)
            ST_CHECK_INIT: begin
                state_next = ST_WRITE_SETUP;
  
            end      
            
            ST_WRITE_SETUP: begin
                state_next = ST_WRITE;            
            end
            
            ST_WRITE: begin
                state_next = ST_WRITE_WAIT;
            end
        
            ST_WRITE_WAIT: begin
                state_next = ST_READ_SETUP;                                
            end
            
            ST_READ_SETUP: begin
                state_next = ST_READ;            
            end
            
            ST_READ: begin
                state_next = ST_READ_WAIT;
            end
            
            ST_READ_WAIT: begin
                state_next = ST_LED_WAIT;                                                
            end 
            
            ST_LED_WAIT: begin
                state_next = ST_GEN;                
            end
        
            ST_GEN: begin                
                state_next = ST_WRITE_SETUP;                                            
            end
            
            default: ;  // nop;
        endcase
    end     
endmodule
