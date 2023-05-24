`timescale 1ns / 1fs
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
        //TIMER_THRESHOLD = 200_000_000,
        TIMER_THRESHOLD = 50_000_000,  // 0.5 second;
        
        // traffic generator to issue the addr;
        // here we just simply use incremental basis;
        INDEX_THRESHOLD = 1024 // wrap around; 2^{10};
    )     
    (
        // general;
        // 100 MHz;
        input logic clk_in_100M,       
        
        // async cpu (soft core) reset button; 
        // **important; it is active low; need to invert;
        input logic CPU_RESETN,     
      
        // LEDs;
        output logic [15:0] LED,
                
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
        output logic [0:0] ddr2_odt // output [0:0]                       ddr2_odt
        
        /*-----------------------------------
        * debugging interface
        * to remove for synthesis;
        *-----------------------------------*/
        //output logic debug_wr_strobe,
        //output logic debug_rd_strobe
                        
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
    
    //// register to filter out reset signals;
    logic rst_sys_raw;    // to invert the input reset;
    logic rst_sys_01_reg;
    logic rst_sys_02_reg;
    logic rst_sys_sync;          
    logic rst_mmcm;
    
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
    
    ///// debugging state;
    // to display which state the FSM is in on the led
    // to debug whether the FSM stuck at some point ...
    // enumerate the FSM from 1 to 8;
    logic [3:0] debug_FSM_reg, debug_FSM_next;
    
    // register to filter the glitch when writing the write data;
    // there is a register within the uut for read data; so not necessary;    
    logic [127:0] wr_data_reg, wr_data_next;
    
    // register to filter addr glitch when issuing;
    logic [22:0] user_addr_reg, user_addr_next;
    
    // register to filter the write and read request;
    logic user_wr_strobe_reg, user_wr_strobe_next;
    logic user_rd_strobe_reg, user_rd_strobe_next;
    
    // counter/timer;
    // 2 seconds led pause time; with 100MHz; 200MHz threshold is required;
    //localparam TIMER_THRESHOLD = 200_000_000;
    //localparam TIMER_THRESHOLD = 100_000_000; // one second;
    //localparam TIMER_THRESHOLD = 10;
    logic [27:0] timer_reg, timer_next;
    
    // traffic generator to issue the addr;
    // here we just simply use incremental basis;
    //localparam INDEX_THRESHOLD = 65536; // wrap around; 2^{16};
    //localparam INDEX_THRESHOLD = 2; // wrap around; 2^{16};
    logic [16:0] index_reg, index_next;
    
    /* -------------------------------------------------------------------
    // power on reset generator;          
    -------------------------------------------------------------------*/
     logic [15:0] por_counter = 16'hFFFF;
     always @ (posedge clk_sys) begin
        if(por_counter) begin
            por_counter <= por_counter - 1 ;
       end
     end           
     
    /*--------------------------------------
    * signal mapping; 
    --------------------------------------*/
    assign clk_sys = clkout_100M;
    //assign rst_sys = (!CPU_RESETN) && (!locked); // active high for system reset;
    //assign rst_sys_raw = (!CPU_RESETN) && (!locked); // active high for system reset;
    assign rst_sys_raw = ((!CPU_RESETN) && (!locked) && !(por_counter == 0)); // active high for system reset;
    
    assign rst_mmcm = (!CPU_RESETN);
           
    //assign rst_mem_n = (!rst_sys) && (locked);
    assign rst_mem_n = (!rst_sys);
    assign clk_mem = clkout_200M;  
    
    /*-----------------------------------
    * debugging interface
    * to remove for synthesis;
    *-----------------------------------*/
    //assign debug_wr_strobe = user_wr_strobe;    
    //assign debug_rd_strobe = user_rd_strobe; 
    
      
    /* -------------------------------------------------------------------
    * Synchronize the reset signals;
    * currently; it is asynchronous
    * implementation error encountered: LUT drives async reset alert
    * implementation: use two registers (synchronizer) instead of one to
    * filter out any glitch;
    -------------------------------------------------------------------*/
    
    //always_ff @(posedge clk_sys) begin
    always_ff @(posedge clk_mem) begin
        rst_sys_01_reg  <= rst_sys_raw;
        rst_sys_02_reg  <= rst_sys_01_reg; 
        rst_sys         <= rst_sys_02_reg;  // triple-synchronizer; oh well...
    end
    
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
        .reset(rst_mmcm), // input reset
        .locked(locked),       // output locked
       // Clock in ports
        .clk_in1(clk_in_100M)
    );      // input clk_in1
            
    user_mem_ctrl uut
    (
        //  from the user system
        // general, 
        .clk_sys(clk_sys),    // 100MHz,
        //.rst_sys(rst_sys),    // asynchronous system reset,
        
        // use a common reset (whichever is longer);
        .rst_sys(~rst_mem_n),
        
        //  MIG interface 
        // memory system,
        .clk_mem(clk_mem),        // 200MHz to drive MIG memory clock,
        .rst_mem_n(rst_mem_n),      // active low to reset the mig interface,
        
        
        //interface between the user system and the memory controller,
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
        .ddr2_dm(ddr2_dm),  // output [1:0]                        ddr2_dm
        .ddr2_odt(ddr2_odt),  // output [0:0]                       ddr2_odt
       
        //  debugging interface (not used)            
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
        .debug_app_rd_data(),        
        .debug_user_wr_strobe_sync(),
        .debug_user_rd_strobe_sync()
    );
    
    
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
            user_wr_strobe_reg <= 1'b0;
            user_rd_strobe_reg <= 1'b0;   
                        
            /// debugging;
            debug_FSM_reg <= 1; 
             
        end
        else begin
            wr_data_reg <= wr_data_next;
            timer_reg <= timer_next;
            index_reg <= index_next;
            state_reg <= state_next;
            user_addr_reg <= user_addr_next;
            user_wr_strobe_reg <= user_wr_strobe_next;
            user_rd_strobe_reg <= user_rd_strobe_next;
            
            /// debugging;
            debug_FSM_reg <= debug_FSM_next; 

        end

    // fsm;
    always_comb begin
       // default;
        wr_data_next = wr_data_reg;
        timer_next = timer_reg;
        index_next = index_reg;
        state_next = state_reg;
        user_addr_next = user_addr_reg;
                
        //user_wr_strobe = 1'b0;
        //user_rd_strobe = 1'b0;
        
        user_wr_strobe = user_wr_strobe_reg;
        user_rd_strobe = user_rd_strobe_reg;
        
        user_wr_strobe_next = 1'b0;
        user_rd_strobe_next = 1'b0;
        
        user_addr = user_addr_reg;
        user_wr_data = wr_data_reg;
        
        /// debugging;
        debug_FSM_next = debug_FSM_reg;
                                            
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
        
        /* NOTE
        Some states defined above are redundant;
        In fact, the states could be combined to reduce the 
        number of states;...        
        */
            
        case(state_reg)
            ST_CHECK_INIT: begin
                // important to wait for the memory to be initialized/calibrated;
                // block until it finishes;
                if(MIG_user_init_complete) begin
                    state_next = ST_WRITE_SETUP;
                    
                    
                    // debugging;
                    debug_FSM_next = 2;
                end
            end      
            
            ST_WRITE_SETUP: begin
                // prepare the write data and address and hold them
                // stable for the upcoming write request;
                wr_data_next = index_reg;
                user_addr_next = index_reg;
                
                user_wr_strobe_next = 1'b1;
                
                state_next = ST_WRITE;       
                
                // debugging;
                debug_FSM_next = 3;     
            end
            
            ST_WRITE: begin
                // MIG is ready to accept new request?
                if(MIG_user_ready) begin
                
                    //user_wr_strobe = 1'b1;
                
                    state_next = ST_WRITE_WAIT;
                    
                    // debugging;
                    debug_FSM_next = 4;
                end
            end
        
            ST_WRITE_WAIT: begin
                if(MIG_user_transaction_complete) begin 
                    state_next = ST_READ_SETUP;
                    
                    // debugging;
                    debug_FSM_next = 5;
                end                                
            end
            
            ST_READ_SETUP: begin
                 
                // note that the the address line is already
                // stable in the default section above; for the upcoming read request;
                state_next = ST_READ;
                user_rd_strobe_next = 1'b1;
                
                
                // debugging;
                debug_FSM_next = 6;
            end
            
            ST_READ: begin
                // MIG is ready to accept new request?
                if(MIG_user_ready) begin
                    
                    //user_rd_strobe = 1'b1;
                    
                    state_next = ST_READ_WAIT;
                    
                    // debugging;
                    debug_FSM_next = 7;
                end
            end
            
            ST_READ_WAIT: begin               
                if(MIG_user_transaction_complete) begin
                    timer_next = 0; // load the timer;
                    state_next = ST_LED_WAIT;
                    
                    
                    // debugging;
                    debug_FSM_next = 8;
                end                                                
            end 
            
            ST_LED_WAIT: begin
                // do not move on after the timer has expired;
                if(timer_reg == (TIMER_THRESHOLD-1)) begin
                    state_next = ST_GEN;
                    
                    // debugging;
                    debug_FSM_next = 9;     
                end 
                else begin
                    timer_next = timer_reg + 1;
                end           
            end
        
            ST_GEN: begin
                // for now; incremental based;
                index_next = index_reg + 1;
                
                // free running;
                state_next = ST_WRITE_SETUP;
                
                // debugging;
                debug_FSM_next = 1;
                
                // wraps around after certain threshold;                
                if(index_reg == (INDEX_THRESHOLD-1)) begin
                    index_next = 0;
                end                                            
            end
            
            // should not reach this state;
            default: begin
                state_next = ST_CHECK_INIT;
                
                // debugging;
                debug_FSM_next = 1;
            end  // nop;
        endcase
    end     
    
        
    // led output;   
    // LED[15]; MSB stores the MIG init calibration status;    
    // LED[14] stores the MMCM locked status;
    // LED[13:10] stores the FSM integer representation of the current state; 
    assign LED =  {MIG_user_init_complete, locked, debug_FSM_reg, user_rd_data[9:0]};
endmodule
