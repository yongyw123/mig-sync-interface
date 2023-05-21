`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 21.05.2023 15:50:10
// Design Name: 
// Module Name: user_mem_ctrl
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


/*----------------------------------------
CONSTRUCTION + BACKGROUND
-------------
Setup:
1. PHY to controller clock ratio: 2:1
2. data width: 16-bit;
3. write and read data width: 16-bit;

Note:
0. Refer to the Xilinx UG586;
1. DDR2 is burst oriented;
2. With 4:1 clock ratio and memory data width of 16-bit; DDR2 requires 8-transactions to take place across 4-clocks. This translates to a minimum transaction of 128 bits;
3. With 2:1 clock ratio and memory data width of 16-bit; DDR requires 8-transactions to take place across 2 clocks; this translates to a minimum of 64-bit chunk per cycle; (still; 128-bit two cycles);
3. wr_data_mask This bus is the byte enable (data mask) for the data currently being written to the external memory. The byte to the memory is written when the corresponding wr_data_mask signal is deasserted. 

General Construction:
1. this is cross-domain clock by nature;
2. MIG interface has its own clock to drive the read and write operation;
3. we use synchronizers to handle the CDC;
4. however, only the control signals shall be synchronized;
5. by above, address and data must remain stable from the user request to the complete flag;
6. this is usually the case since we assume sequential transfer;

Write Construction:
1. By above, when writing, two clock cycles are required;
2. since we only concern with 16-bit; we only need to deal with the first 64-bit chunk;
3. we could ignore the seoond 64-bit chunk by masking it off;
4. Also, one need to push the data to the MIG write FIFO before submitting the write request; 

Write Address:
1. ??

Read Construction:
1. similar t th write operation, it takes two cycles to read all 128-bit data;
2. MIG will signal when the data is valid, and when the data is the last chunk on the data bus;
3. since we are only dealing with 16-bit, ???

Read Address:
1. ??
----------------------------------------*/

module user_mem_ctrl
    #(parameter
        CLOCK_RATIO = 2,            // PHY to controller clock ratio;
        DATA_WIDTH = 16,            // ddr2 native data width;
        TRANSACTION_WIDTH = 64,     // per clock; so 128 in two clocks;
        DATA_MASK_WIDTH = 8         // masking for write data; see UG586 for the formulae;
        
    )
    (
        /* -----------------------------------------------------
        *  from the user system
        ------------------------------------------------------*/
        // general; 
        input logic clk_sys,    // 100MHz;
        input logic rst_sys,    // asynchronous system reset;
        
        /* -----------------------------------------------------
        *  interface between the user system and the memory controller;
        ------------------------------------------------------*/
        input logic user_wr_strobe,             // write request;
        input logic user_rd_strobe,             // read request;
        input logic [26:0] user_addr,           // address;
        
        // data;
        input logic [DATA_WIDTH-1:0] user_wr_data,   
        //output logic [DATA_WIDTH-1:0] user_rd_data,
        output logic [63:0] user_rd_data,   // temporary;
        
        // status
        output logic MIG_user_init_complete,        // MIG done calibarating and initializing the DDR2;
        output logic MIG_user_ready,                // this implies init_complete and also other status; see UG586; app_rdy;
        output logic MIG_user_transaction_complete, // read/write transaction complete?
        
        /* -----------------------------------------------------
        *  MIG interface 
        ------------------------------------------------------*/
        // memory system;
        input logic clk_mem,        // to drive MIG memory clock;
        input logic rst_mem_n,      // active low to reset the mig interface;
        
        // ddr2 sdram memory interface (defined by the imported ucf file);
        output logic [12:0] ddr2_addr,   // address; 
        output logic [2:0]  ddr2_ba,    
        output logic ddr2_cas_n,  // output                                       ddr2_cas_n
        output logic [0:0] ddr2_ck_n,  // output [0:0]                        ddr2_ck_n
        output logic [0:0] ddr2_ck_p,  // output [0:0]                        ddr2_ck_p
        output logic [0:0] ddr2_cke,  // output [0:0]                       ddr2_cke
        output logic ddr2_ras_n,  // output                                       ddr2_ras_n
        output logic ddr2_we_n,  // output                                       ddr2_we_n
        inout tri [DATA_WIDTH-1:0] ddr2_dq,  // inout [15:0]                         ddr2_dq
        inout tri [1:0] ddr2_dqs_n,  // inout [1:0]                        ddr2_dqs_n
        inout tri [1:0] ddr2_dqs_p,  // inout [1:0]                        ddr2_dqs_p
        output logic init_calib_complete,  // output                                       init_calib_complete
        output logic [0:0] ddr2_cs_n,  // output [0:0]           ddr2_cs_n
        output logic [1:0] ddr2_dm,  // output [1:0]                        ddr2_dm
        output logic [0:0] ddr2_odt,  // output [0:0]                       ddr2_odt
        
        /* -----------------------------------------------------
        *  debugging interface 
        ------------------------------------------------------*/
        // MIG signals read data is valid;
        output logic debug_app_rd_data_valid,
           
        // MIG signals that the data on the app_rd_data[] bus in the current cycle is the 
        // last data for the current request
        output logic debug_app_rd_data_end,
        
        // mig own driving clock; 
        output logic debug_ui_clk,
        
        // mig own synhcronous reset wrt to ui_clk;
        output logic debug_ui_clk_sync_rst,
        
        // mig ready signal;
        output logic debug_app_rdy,
        output logic debug_app_wdf_rdy,
        output logic debug_app_en,
        output logic [63:0] debug_app_wdf_data,
        output logic debug_app_wdf_end,
        output logic debug_app_wdf_wren,
        output logic debug_init_calib_complete,
        output logic debug_transaction_complete_async,
        output logic [2:0] debug_app_cmd
    );
    
    /* -----------------------------------------------
    * constants;
    *-----------------------------------------------*/
    localparam MIG_CMD_READ     = 3'b001;     // this is fixed; see UG586 docuemenation;
    localparam MIG_CMD_WRITE    = 3'b000;    // this is fixed; see UG586 docuemenation;
    //localparam MIG_CMD_NOP      = 3'b100;     // other value is reserved, so do not use them;

    /* -----------------------------------------------
    * signal declarations
    *-----------------------------------------------*/
    // application interface from the MIG port
    logic [26:0] app_addr;  // input [26:0]                       app_addr
    logic [2:0] app_cmd;  // input [2:0]                                  app_cmd
    logic app_en;  // input                                        app_en
    
    logic [TRANSACTION_WIDTH-1:0] app_wdf_data;  // input [63:0]    app_wdf_data
    logic app_wdf_end;  // input                                        app_wdf_end
    logic app_wdf_wren;  // input                                        app_wdf_wren
    
    logic [TRANSACTION_WIDTH-1:0] app_rd_data;  // output [63:0]   app_rd_data
    logic app_rd_data_end;  // output                                       app_rd_data_end
    logic app_rd_data_valid;  // output                                       app_rd_data_valid
    logic app_rdy;  // output                                       app_rdy
    logic app_wdf_rdy;  // output                                       app_wdf_rdy
    
    logic ui_clk;  // output                                       ui_clk
    logic ui_clk_sync_rst;  // output                                       ui_clk_sync_rst
    logic [DATA_MASK_WIDTH-1:0] app_wdf_mask;  // input [7:0]  app_wdf_mask

    // synchronization signals for CDC;
    logic user_wr_strobe_sync;          // input; user to request write operation;
    logic user_rd_strobe_sync;          // input; user to request read operation;
    logic init_calib_complete_async;    // output;
    logic app_rdy_async;
    logic transaction_complete_async;   // output; 
    
    /* -----------------------------------------------
    * state;
    * ST_WAIT_INIT_COMPLETE: to check MIG initialization complete status before doing everything else;
    * ST_IDLE: ready to accept user command to perform read/write operation;
    * ST_WRITE_FIRST: to push the first 64-bit batch to the MIG Write FIFO, by the note above;
    * ST_WRITE_SECOND: to push the second 64-bit batch to the MIG Write FIFO; 
    * ST_WRITE_SUBMIT: to submit the write request for the data in MIG Write FIFO (from these states: ST_WRITE_UPPER, LOWER;)    
    * ST_WRITE_DONE: wait for the mig to acknowledge the write request to confirm it has been accepted;
    * ST_READ: to read from the memory;
    *-----------------------------------------------*/
    
    typedef enum {ST_WAIT_INIT_COMPLETE, ST_IDLE, ST_WRITE_FIRST, ST_WRITE_SECOND, ST_WRITE_SUBMIT, ST_WRITE_DONE, ST_READ} state_type;
    state_type state_reg, state_next;
    
    always_ff @(posedge ui_clk) begin
        // synchronous reset signal from the MIG interface;
        if(ui_clk_sync_rst) begin
            state_reg <= ST_WAIT_INIT_COMPLETE;
        end
        else begin
            state_reg <= state_next;      
        end
    end 
    
    /* -----------------------------------------------
    * instantiation
    *-----------------------------------------------*/
    /* synchronizers; */
    //> from MIG to user;
    // MIG status:
    // 1. memory initialization compete status;
    // 2. app_rdy;
    // 3. transaction complete status;
    assign init_calib_complete_async = init_calib_complete;
    assign  app_rdy_async = app_rdy;

    FF_synchronizer_fast_to_slow
    #(.WIDTH(2))
    FF_synchronizer_fast_to_slow_status_unit
    (
        // destination; slow domain;
        .clk_dest(clk_sys),  
        .rst_dest(rst_sys),  
        
        // source; from fast domain
        .in_async({init_calib_complete_async, app_rdy_async}),
        
        // to slow domain
        .out_sync({MIG_user_init_complete, MIG_user_ready})
    );
        
    // transaction_complete is a short pulse with respect to the UI clock;
    // a double FF synchronizer would miss it;
    // use a toggle synchronizer instead;
    toggle_synchronizer
    toggle_synchronizer_status_complete_unit 
    (
        // src;
        .clk_src(ui_clk),
        .rst_src(ui_clk_sync_rst),
        .in_async(transaction_complete_async),
        
        // dest;
        .clk_dest(clk_sys),
        .rst_dest(rst_sys),
        .out_sync(MIG_user_transaction_complete)
    );
    
    //> from user to mig;
    // write request;
    FF_synchronizer_slow_to_fast
    FF_synchronizer_wr_unit
    (
        // from slow domain        
        .s_clk(clk_sys),
        .s_rst_n(~rst_sys),
        .in_async(user_wr_strobe),
        
        // from fast domain;        
        .f_clk(ui_clk),
        .f_rst_n(~ui_clk_sync_rst),
        .out_sync(user_wr_strobe_sync)
    );
    
    // read request;
    FF_synchronizer_slow_to_fast
    FF_synchronizer_rd_unit
    (
        // from slow domain        
        .s_clk(clk_sys),
        .s_rst_n(~rst_sys),
        .in_async(user_rd_strobe),
        
        // from fast domain;        
        .f_clk(ui_clk),
        .f_rst_n(~ui_clk_sync_rst),
        .out_sync(user_rd_strobe_sync)
    );
    
    /* mig interface unit */
    mig_7series_0 mig_unit (

    // Memory interface ports
    .ddr2_addr                      (ddr2_addr),  // output [12:0]                       ddr2_addr
    .ddr2_ba                        (ddr2_ba),  // output [2:0]                      ddr2_ba
    .ddr2_cas_n                     (ddr2_cas_n),  // output                                       ddr2_cas_n
    .ddr2_ck_n                      (ddr2_ck_n),  // output [0:0]                        ddr2_ck_n
    .ddr2_ck_p                      (ddr2_ck_p),  // output [0:0]                        ddr2_ck_p
	.ddr2_cke                       (ddr2_cke),  // output [0:0]                       ddr2_cke
    .ddr2_ras_n                     (ddr2_ras_n),  // output                                       ddr2_ras_n
    .ddr2_we_n                      (ddr2_we_n),  // output                                       ddr2_we_n
    .ddr2_dq                        (ddr2_dq),  // inout [15:0]                         ddr2_dq
    .ddr2_dqs_n                     (ddr2_dqs_n),  // inout [1:0]                        ddr2_dqs_n
    .ddr2_dqs_p                     (ddr2_dqs_p),  // inout [1:0]                        ddr2_dqs_p
    .init_calib_complete            (init_calib_complete),  // output                                       init_calib_complete
	.ddr2_cs_n                      (ddr2_cs_n),  // output [0:0]           ddr2_cs_n
    .ddr2_dm                        (ddr2_dm),  // output [1:0]                        ddr2_dm
    .ddr2_odt                       (ddr2_odt),  // output [0:0]                       ddr2_odt

     // Application interface ports
    .app_addr                       (app_addr),  // input [26:0]                       app_addr
    .app_cmd                        (app_cmd),  // input [2:0]                                  app_cmd
    .app_en                         (app_en),  // input                                        app_en
    .app_wdf_data                   (app_wdf_data),  // input [63:0]    app_wdf_data
    .app_wdf_end                    (app_wdf_end),  // input                                        app_wdf_end
    .app_wdf_wren                   (app_wdf_wren),  // input                                        app_wdf_wren
    .app_rd_data                    (app_rd_data),  // output [63:0]   app_rd_data
    .app_rd_data_end                (app_rd_data_end),  // output                                       app_rd_data_end
    .app_rd_data_valid              (app_rd_data_valid),  // output                                       app_rd_data_valid
    .app_rdy                        (app_rdy),  // output                                       app_rdy
    .app_wdf_rdy                    (app_wdf_rdy),  // output                                       app_wdf_rdy

	// not used; 
	.app_sr_req                     (1'b0),  // input                                        app_sr_req
    .app_ref_req                    (1'b0),  // input                                        app_ref_req
    .app_zq_req                     (1'b0),  // input                                        app_zq_req
    .app_sr_active                  (),  // output                                       app_sr_active
    .app_ref_ack                    (),  // output                                       app_ref_ack
    .app_zq_ack                     (),  // output                                       app_zq_ack
  
    // application interface drivers;
    .ui_clk                         (ui_clk),  // output                                       ui_clk
    .ui_clk_sync_rst                (ui_clk_sync_rst),  // output                                       ui_clk_sync_rst
    
    // write data mask;
    .app_wdf_mask                   (app_wdf_mask),  // input [7:0]  app_wdf_mask

    // System Clock Ports
    .sys_clk_i                       (clk_mem),  // input                                        sys_clk_i

    // Reference Clock Ports
    .clk_ref_i                      (clk_mem),  // input                                        clk_ref_i
    .sys_rst                        (rst_mem_n) // input  sys_rst

    );
   
    /* -----------------------------------------------------
    *  debugging interface 
    ------------------------------------------------------*/
    // MIG signals read data is valid;
    assign debug_app_rd_data_valid = app_rd_data_valid;
       
    // MIG signals that the data on the app_rd_data[] bus in the current cycle is the 
    // last data for the current request
    assign debug_app_rd_data_end = app_rd_data_end;
    
    // mig own driving clock; 
    assign debug_ui_clk = ui_clk;
        
    // mig own synhcronous reset wrt to ui_clk;
    assign debug_ui_clk_sync_rst    = ui_clk_sync_rst; 
    assign debug_app_rdy            = app_rdy;
    assign debug_app_wdf_rdy        = app_wdf_rdy;
    assign debug_app_en             = app_en;
    assign debug_app_wdf_data       = app_wdf_data;
    assign debug_app_wdf_end        = app_wdf_end;
    assign debug_app_wdf_wren       = app_wdf_wren;
    assign debug_init_calib_complete = init_calib_complete;
    assign debug_transaction_complete_async = transaction_complete_async;
    assign debug_app_cmd = app_cmd;
    /* -----------------------------------------------
    * FSM
    *-----------------------------------------------*/
    always_comb begin
        // default;
        state_next = state_reg;
        transaction_complete_async = 1'b0;
        
        app_cmd         = MIG_CMD_READ;        
        app_en          = 1'b0;
        app_wdf_wren    = 1'b0;
        app_wdf_end     = 1'b0;
        app_wdf_mask    = 8'hFF; // active low
        
        // direct mapping;
        // the address conversion shall be done outside of this module;
        app_addr        = {user_addr[26:3], 3'b000};
        
        user_rd_data    = 0;
        //user_rd_data = app_rd_data;
        
        /* -----------------------------------------------
        * state;
        * ST_WAIT_INIT_COMPLETE: to check MIG initialization complete status before doing everything else;
        * ST_IDLE: ready to accept user command to perform read/write operation;
        * ST_WRITE_FIRST: to push the first 64-bit batch to the MIG Write FIFO, by the note above;
        * ST_WRITE_SECOND: to push the second 64-bit batch to the MIG Write FIFO; 
        * ST_WRITE_SUBMIT: to submit the write request for the data in MIG Write FIFO (from these states: ST_WRITE_UPPER, LOWER;)    
        * ST_WRITE_DONE: wait for the mig to acknowledge the write request to confirm it has been accepted;
        * ST_READ: to read from the memory;
        *-----------------------------------------------*/
    
        case(state_reg) 
            ST_WAIT_INIT_COMPLETE: begin
                if(init_calib_complete) begin
                    state_next = ST_IDLE;                
                end
            end
            
            ST_IDLE: begin
                // only if memory says so;
                /* see UG586; app rdy is NOT asserted if:
                1. init_cal_complete is not complete;
                2. a read is requested and the read buffer is full;
                3. a write is requested and no write buffer pointers are available;
                4. a periodic read is being inserted;
                */
                if(app_rdy) begin
                    if(user_wr_strobe_sync) begin
                        state_next = ST_WRITE_FIRST;
                    
                    end
                    else if(user_rd_strobe_sync) begin
                        // submit the read request here
                        // because it is up to the MIG to signal
                        // when the read data is ready;                        
                        app_cmd = MIG_CMD_READ;
                        app_en = 1'b1;          // submit the read request;              
                        state_next = ST_READ;   // check for the read dara;
                        
                    end
                 end
            end
            
            ST_WRITE_FIRST: begin
                // wait until the write fifo has space;                
                if(app_wdf_rdy) begin
                    
                    // prepare the write data with masking;
                    /*
                    This bus is the byte enable (data mask) for the data currently being written to the external memory.
                    The byte to the memory is written when the corresponding wr_data_mask signal is deasserted.
                    each bit represents a byte;
                    there are 8-bits; hence 64-bit chunk;
                    */
                    //app_wdf_mask = 8'b1111_1100;
                    //app_wdf_data = {48'h0, user_wr_data};
                    
                    // test write data;
                    app_wdf_mask = 8'hFF;
                    app_wdf_data = {16'h4444, 16'h3333, 16'h2222, 16'h1111};
                    
                    // push it to the MIG write fifo;
                    app_wdf_wren = 1'b1;    
                    
                    // prepare the signal;
                    //app_cmd = MIG_CMD_WRITE;                                            
                    //app_wdf_wren = 1'b1;

                    /*
                    // submit the request only when it is ready;
                    // otherwise hold it;
                    if(app_rdy) begin
                        app_cmd = MIG_CMD_WRITE;   
                        
                        // write it into the write MIG fifo                                         
                        app_wdf_wren = 1'b1;
                        
                        // submit the request;                        
                        app_en = 1'b1;
                        
                        // next chunk to complete a total of 128-bit write transaction;
                        state_next = ST_WRITE_LOWER;                       
                   end                                     
                   */
                   // next chunk to complete a total of 128-bit write transaction;
                   state_next = ST_WRITE_SECOND;
                end
            end
            
            ST_WRITE_SECOND: begin
                // need to check app_rdy here so that it acknowledges
                // the write request from ST_WRITE_UPPER;
                if(app_rdy && app_wdf_rdy) begin
                    // prepare the signal;
                    //app_cmd = MIG_CMD_WRITE;                                            
                    //app_wdf_wren = 1'b1;
                                        
                    // prepare the write dummy data with masking;
                    //app_wdf_mask = 8'hFF;   // mask all bytes;
                    //app_wdf_data = 64'h0;
                
                    // test write data;
                    app_wdf_mask = 8'h00;
                    app_wdf_data = {16'hFFFF, 16'hEEEE, 16'hDDDD, 16'hCCCC};
                    
                    // indicate that the data on the app_wdf_data[] bus in the current cycle is the last 
                    // data for the current request.
                    app_wdf_end = 1'b1; 
                    
                    // push it into the write MIG fifo                                            
                    app_wdf_wren = 1'b1;                      
                        
                    /*
                    if(app_rdy) begin
                        app_cmd = MIG_CMD_WRITE;                        
                        
                        // write it into the write MIG fifo                                            
                        app_wdf_wren = 1'b1;                      
                        
                        // submit the request;
                        app_en = 1'b1;
                                                
                        // wait for the acknowledge for the write request;
                        // to confirm the write request has been accepted;
                        state_next = ST_WRITE_DONE;
                    end        
                    */
                   state_next = ST_WRITE_SUBMIT; 
                end                
            end
            ST_WRITE_SUBMIT: begin
                if(app_rdy) begin
                    // submit the write request;
                    app_cmd = MIG_CMD_WRITE;    
                    app_en = 1'b1;
                    
                    // wait for ack from the mig;
                    state_next = ST_WRITE_DONE;
                end
            
            end
                       
            ST_WRITE_DONE: begin
                // wait for the acknowledge for the write request;
                // to confirm the write request has been accepted;
                //app_en = 1'b1;  // maintain;
                if(app_rdy) begin
                    transaction_complete_async = 1'b1;  // write transaction done;
                    state_next = ST_IDLE;
                end
            end
            
            ST_READ: begin
                // check whether the read request has been acknowledged via app_rdy;
                if(app_rdy) begin
                    // wait for the MIG to put valid data on the bus;
                    if(app_rd_data_valid) begin
                        // ??? to do some masking here ??                        
                        user_rd_data = app_rd_data;                
                
                        // wait for the mig to flag the end of the data;
                        if(app_rd_data_end) begin
                            // ??? to do some masking here ??                        
                            user_rd_data = app_rd_data;                
                                        
                            transaction_complete_async = 1'b1;  // signal to the user;
                            state_next = ST_IDLE;
                        end
                    end
                end
            end
        
           default: ;  //nop;
        endcase
    end

endmodule
