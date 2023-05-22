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
    #(parameter
        // counter/timer;
        // 2 seconds led pause time; with 100MHz; 200MHz threshold is required;
        TIMER_THRESHOLD = 200_000_000,
        
        
        // traffic generator to issue the addr;
        // here we just simply use incremental basis;
        INDEX_THRESHOLD = 65536 // wrap around; 2^{16};
    )
    
    (
        // general;
        // 100 MHz;
        input logic clk_in_100M,       
        
        // async cpu (soft core) reset button; 
        // **important; it is active low; need to invert;
        input logic CPU_RESETN,     
      
        // LEDs;
         output[15:0] LED, 
                
        // ddr2 sdram memory interface (defined by the imported ucf file);
        output logic [12:0] ddr2_addr,   // address; 
        output logic [2:0]  ddr2_ba,    
        output logic ddr2_cas_n,  // output                                       ddr2_cas_n
        output logic [0:0] ddr2_ck_n,  // output [0:0]                        ddr2_ck_n
        output logic [0:0] ddr2_ck_p,  // output [0:0]                        ddr2_ck_p
        output logic [0:0] ddr2_cke,  // output [0:0]                       ddr2_cke
        output logic ddr2_ras_n,  // output                                       ddr2_ras_n
        output logic ddr2_we_n,  // output                                       ddr2_we_n
        inout tri [15:0] ddr2_dq,  // inout [15:0]                         ddr2_dq
        inout tri [1:0] ddr2_dqs_n,  // inout [1:0]                        ddr2_dqs_n
        inout tri [1:0] ddr2_dqs_p,  // inout [1:0]                        ddr2_dqs_p      
        output logic [0:0] ddr2_cs_n,  // output [0:0]           ddr2_cs_n
        output logic [1:0] ddr2_dm,  // output [1:0]                        ddr2_dm
        output logic [0:0] ddr2_odt  // output [0:0]                       ddr2_odt
        
    );
    /*--------------------------------------
    * signal declarations 
    --------------------------------------*/
    /////////// general;   
    logic rst_sys;
    logic clk_sys;  // 100MHz from the MMCM;
    
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
       
    /////////// MMCM;
    logic clk_200M; // to drive the MIG;
    logic clk_100M; // to drive the rest of the system;
    logic locked;
    
    /*--------------------------------------
    * signal mapping; 
    --------------------------------------*/
    assign clk_sys = clk_100M;
    assign rst_sys = ~CPU_RESETN; // active high for system reset;
    
    assign rst_mem_n = (!rst_sys) && (locked);
    assign clk_mem = clk_200M;  
    
    
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
    typedef enum {ST_CHECK_INIT, ST_WRITE_SETUP, ST_WRITE, ST_WRITE_WAIT, ST_READ_SETUP, ST_READ, ST_READ_WAIT, ST_LED_WAIT, ST_GEN} state_type;
    state_type state_reg, state_next;
    
    // register to filter the glitch when writing the write data;
    // there is a register within the uut for read data; so not necessary;    
    logic [127:0] wr_data_reg, wr_data_next;
    
    // register to filter addr glitch when issuing;
    logic [22:0] user_addr_reg, user_addr_next;
    
    // counter/timer;
    // 2 seconds led pause time; with 100MHz; 200MHz threshold is required;
    //localparam TIMER_THRESHOLD = 200_000_000;
    logic [27:0] timer_reg, timer_next;
    
    // traffic generator to issue the addr;
    // here we just simply use incremental basis;
    //localparam INDEX_THRESHOLD = 65536; // wrap around; 2^{16};
    logic [15:0] index_reg, index_next;
    
    /*--------------------------------------
    * instantiation 
    --------------------------------------*/
    // MMCM
    clk_wiz_0 mmcm_unit
       (
        // Clock out ports
        .clk_200M(clk_200M),     // output clk_200M
        .clk_250M(),     // output clk_250M
        .clk_100M(clk_100M),     // output clk_100M
        // Status and control signals
        .reset(rst_sys), // input reset
        .locked(locked),       // output locked
       // Clock in ports
        .clk_in1(clk_in_100M)
        );      // input clk_in1


    // uut;
         
    user_mem_ctrl
        #(
        .CLOCK_RATIO(2),    // PHY to controller clock ratio;
        .DATA_WIDTH(128),  // ddr2 native data width;
        .TRANSACTION_WIDTH_PER_CYCLE(64),   // per clock; so 128 in two clocks;
        .DATA_MASK_WIDTH(8),    // masking for write data; see UG586 for the formulae;
        .USER_ADDR_WIDTH(23) // discussed in the note section above;                
        )
        
        uut
        (
            /* -----------------------------------------------------
            *  from the user system
            ------------------------------------------------------*/
            // general, 
            .clk_sys(clk_sys),    // 100MHz,
            .rst_sys(rst_sys),    // asynchronous system reset,
            
            /* -----------------------------------------------------
            *  interface between the user system and the memory controller,
            ------------------------------------------------------*/
            .user_wr_strobe(user_wr_strobe),             // write request,
            .user_rd_strobe(user_rd_strobe),             // read request,
            .user_addr(user_addr),           // address,
            
            // data,
            .user_wr_data(user_wr_data),   
            .user_rd_data(user_rd_data),         
            
            // status
            .MIG_user_init_complete(MIG_user_init_complete),        // MIG done calibarating and initializing the DDR2,
            .MIG_user_ready(MIG_user_ready),                // this implies init_complete and also other status, see UG586, app_rdy,
            .MIG_user_transaction_complete(MIG_user_transaction_complete), // read/write transaction complete?
            
            /* -----------------------------------------------------
            *  MIG interface 
            ------------------------------------------------------*/
            // memory system,
            .clk_mem(clk_mem),        // to drive MIG memory clock,
            .rst_mem_n(rst_mem_n),      // active low to reset the mig interface,
            
            // ddr2 sdram memory interface (defined by the imported ucf file),
            .ddr2_addr(ddr2_addr),   // address, 
            .ddr2_ba(ddr2_ba),    
            .ddr2_cas_n(ddr2_cas_n),  // output                                       ddr2_cas_n
            .ddr2_ck_n(ddr2_ck_n),  // output [0:0]                        ddr2_ck_n
            .ddr2_ck_p(ddr2_ck_p),  // output [0:0]                        ddr2_ck_p
            .ddr2_cke(ddr2_cke),  // output [0:0]                       ddr2_cke
            .ddr2_ras_n(ddr2_ras_n),  // output                                       ddr2_ras_n
            .ddr2_we_n(ddr2_we_n),  // output                                       ddr2_we_n
            .ddr2_dq(ddr2_dq),  // inout [15:0]                         ddr2_dq
            .ddr2_dqs_n(ddr2_dqs_n),  // inout [1:0]                        ddr2_dqs_n
            .ddr2_dqs_p(ddr2_dqs_p),  // inout [1:0]                        ddr2_dqs_p
            
            // not used;
            .init_calib_complete(),  // output                                       init_calib_complete
            
            .ddr2_cs_n(ddr2_cs_n),  // output [0:0]           ddr2_cs_n
            .dr2_dm(dr2_dm),  // output [1:0]                        ddr2_dm
            .ddr2_odt(ddr2_odt),  // output [0:0]                       ddr2_odt
           
            /* -----------------------------------------------------
            *  debugging interface (not used)
            ------------------------------------------------------*/
            .debug_app_rd_data_valid(),
            .debug_app_rd_data_end(),
            .debug_ui_clk(),
            .debug_ui_clk_sync_rst(),
            .debug_app_rdy(),
            .debug_app_wdf_rdy(),
            .debug_app_en(),
            .debug_app_wdf_data(),
            .debug_app_wdf_end(),
            .debug_app_wdf_wren(),
            .debug_init_calib_complete(),
            .debug_transaction_complete_async(),
            .debug_app_cmd(),
            .debug_app_rd_data()
        );
        
    
    ////////////////////////////////////////////////////////////////////////////////////
    // ff;
    always_ff @(posedge clk_sys, posedge rst_sys) begin
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
            //.MIG_user_init_complete(MIG_user_init_complete),        // MIG done calibarating and initializing the DDR2,
    //.MIG_user_ready(MIG_user_ready),                // this implies init_complete and also other status, see UG586, app_rdy,
    //.MIG_user_transaction_complete(MIG_user_transaction_complete), // read/write transaction complete?
    
    /*
    
    .user_wr_strobe(user_wr_strobe),             // write request,
            .user_rd_strobe(user_rd_strobe),             // read request,
            .user_addr(user_addr),           // address,
            
            // data,
            .user_wr_data(user_wr_data),   
            .user_rd_data(user_rd_data),         
            
    */
        case(state_reg)
            ST_CHECK_INIT: begin
                if(MIG_user_init_complete) begin
                    state_next = ST_WRITE_SETUP;
                end  
            end      
            
            ST_WRITE_SETUP: begin
                user_addr_next = index_reg;
                wr_data_next = index_reg;
                state_next = ST_WRITE;            
            end
            
            ST_WRITE: begin
                // check if the memory is ready;
                if(MIG_user_ready) begin            
                    user_addr = user_addr_reg;
                    user_wr_data = wr_data_reg;
                    // submit the write request;
                    user_wr_strobe = 1'b1;
                    
                    state_next = ST_WRITE_WAIT;
                end
            end
        
            ST_WRITE_WAIT: begin
                if(MIG_user_transaction_complete) begin
                    state_next = ST_READ_SETUP;                                
                end
            end
            
            ST_READ_SETUP: begin
                user_addr_next = index_reg;
                state_next = ST_READ;            
            end
            
            ST_READ: begin
                if(MIG_user_ready)begin
                    user_addr = user_addr_reg;
                    user_rd_strobe = 1'b1;
                    state_next = ST_READ_WAIT;
                end            
            end
            
            ST_READ_WAIT: begin
                if(MIG_user_transaction_complete) begin
                    // set up the time;
                    timer_next = 0;
                    state_next = ST_LED_WAIT;                                                
                end            
            end 
            
            ST_LED_WAIT: begin
                // timer expired? generate next test index;
                if(timer_reg == (TIMER_THRESHOLD-1)) begin
                    state_next = ST_GEN;
                 end
                else begin
                    timer_next = timer_reg + 1;
                end
            end
        
            ST_GEN: begin
                // generate the test index; and wrap around after 2^{16};
                if(index_reg == (INDEX_THRESHOLD-1)) begin
                    // reset;
                    index_next = 0; 
                    // free-running from the start;
                    state_next = ST_WRITE_SETUP;
                end
                else begin
                    index_next = index_reg + 1;
                end                            
            end
            default: ;  // nop;
        endcase
    end
    
    // led output;   
    assign LED =  user_rd_data[15:0];
endmodule
