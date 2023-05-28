# mig-sync-interface

This is a simple synchronous wrapper around Xilinx Memory-interface-generated (MIG) interface with the DDR2 External Memory of this FPGA development board: Nexys A7-50T. This synchronous interface assumes sequential transfer: only a single write/read operation is allowed at a time for simplicity.

| **Environment** | **Description** |
|-----------------|-----------------|
| Development Board | Digilent Nexys A7-50T |
| FPGA Part Number  | XC7A50T-1CSG324I      |
| Vivado Version    | 2021.2                |
| MIG Version       | 4.2 (Device 7 Series) |
| Language          | System Verilog        |

## Modules

1. *user_mem_ctrl.sv* is the synchronous wrapper.
2. *test_top.sv* is the top application file (testing circuit) for *user_mem_ctrl*.

## Navigation

1. It follows Vivado structure:
    1. Source Files: ./mig-interface/mig-interface.srcs/sources_1
    2. Simulation Files: ./mig-interface/mig-interface.srcs/sim_1/new
    3. Constraint Files: ./mig-interface/mig-interface.srcs/constrs_1/
    4. DDR2 Memory Pinout: ./ddr2_memory_pinout.ucf

## Table of Content

1. [MIG Configuration](#mig-configuration)
2. [Block Diagram, Port Description and Some Comments](#block-diagram-port-description-and-some-comments)
3. [Limitation + Assumption](#summary-limitation--assumption)
4. [Construction](#construction)
    1. [Clock Domain Crossing (CDC)](#construction---clock-domain-crossing-cdc)
    2. [Write and Read Operation](#construction---write--read-operation)
    3. [Address Mapping](#construction---address-mapping)
    4. [Data Masking](#construction---data-masking)
    5. [FSM](#construction---fsm-of-user_mem_ctrlsv)
5. [Simulation](#simulation)
6. [HW Test](#hw-test)
7. [Documenting Mistakes Made, Errors Encountered and the Struggles](#documenting-mistakes-errors-and-struggles)
8. [Clock Constraint](#clock-constraint)
9. [TODO?](#todo)
10. [Reference](#reference)

---

## MIG Configuration

Table 01 shows the MIG IP configuration. Most of the configurations follow [7] Digilent Tutorial .

*Table 01: MIG Configuration*

| Parameter              | Value       | Note |
|---                        |---                |---            |
| **General**   |       |       |
|MIG Output Options    |  Create Design  | Either available option should work.     |
|Number of Controllers  |   1             | Unsure if it is supported in DDR2, Also, it is for simplicity. |
| AXI4 Interface        | Disabled          | Not used  |
| Memory Selection      | DDR2              |        |
|---                        |---                |---            |
| **Controller Options**    |                   |           |
| Clock Period              | 3333ps (300MHz)   |               |
| PHY to Controller         | 2:1               |               |
| Memory Part               |  MT47H64M16HR-25E |               |
| Data Width                | 16-bit            | Native. See the DDR2 datasheet        |
| Data Mask                 | Enabled           | Application specific  |
| Number of Bank Machines   | 4                 | Default   |
| Ordering                  | Strict            | Default |
|---                            |---                |---        |
|**Memory Options** |   |   |
| Input Clock Period        | 5000ps (200MHz)   |               |
| Burst Type                | Sequential        | Application specific  |
| Output Drive Strength     | Fullstrength      |   |
| RTT (Nominal) - ODT       | 50 Ohms           | Board specific    |
| Controller Chip Select Pin   | Enabled       | Not necessary since the memory only has one rank. |
| Memory Address Mapping Selection | BANK -> ROW -> COLUMN | Application specific.  |
|---                            |---                |---        |
| **FPGA Options**  |   |   |
| System Clock                  | No Buffer         | This clock is to supply the 200MHz as specified in the Input Clock Period Option above. User to configure MMCM to generate this clock, so no buffer |
| Reference Clock               | Use System Clock  | One less thing to worry |
| System Reset Polarity     | Active LOW        | Default |
| Debug Signals             | OFF               | Default   |
| Internal VREF             | Enabled           | Otherwise, the Pin Selection Validation (below) will be rejected. |
| IO Power Reduction        | ON            | Default   |
XADC Instantiation          | Enabled       | For convenience, otherwise one needs to configure the XADC manually. |
|---    |---    |---    |
|**The Rest**      |    |   |
| Internal Termination Impedance | 50 Ohms          | Board specific          |
| Pin Selection                 | Import "ddr2_memory_pinout.ucf"        |  This is provided by Digilent. Ensure the pinout matches with the board schematic as a sanity check.         |
| System Signals Selection      | No connection for all: {sys_rst, init_calib_complete, tg_compare_error} | SW-wired instead of being hard-wired to a board pin. |

## Block Diagram, Port Description and Some Comments

Figure 01 shows the block diagram. Table 02 summarizes the relevant port descriptions of the module: "user_mem_ctrl.sv".

There are three clocks involved, summarized below in Table 02. Primarily, only two clocks are of concern: (1) User System Clock, (2) MIG UI Clock. The Module: "user_mem_ctrl" synchronizes the MIG User Interface driven at UI Clock 150MHz with the User Own Space driven at System Clock 100MHz.

### Table 02: User Port Description

- For the MIG UI Signal Description, confer [4] UG 586.
- *There exist conditions to satisfy for certain ports; the conditions are summarized in List 01 below.

| Port                 |  IO           | Description                   |
|---                |---                |---                |
| clk_sys                  | I          | User System Clock @ 100MHz    |
| rst_sys                   | I         | User System Reset Signal. This does not reset the MIG UI, it has separate reset signal.   |
| *user_wr_strobe        | I     | Write request. **This must be at least 2 clk_sys cycle wide.** |
|  *user_rd_strobe       | I     | Read request. **This must be at least 2 clk_sys cycle wide.**|
|  *user_addr        | I | Which address of the DDR2 to read from or write into? 23-bit wide. See Section: Address Mapping. |
| *user_wr_data      | I | Data to be written. 128-bit wide.  |
| user_rd_data      | O | Data read. 128-bit wide. |
| MIG_user_init_calib_complete | O | Synchronized "init_calib_complete" signal from MIG UI interface. |
| MIG_user_ready    | O | Synchronized "app_rdy" signal from MIG UI interface. |
| *MIG_user_transaction_complete | O | Indication when read/write request is "completed". See Elaborated Section below. |
| clk_mem   | I     | This is directly mapped to sys_clk_i of MIG UI Interface. |
| *rst_mem_n | I     | This is directly mapped to sys_rst of MIG UI Interface. This is active LOW.   |

### List 01: Port (Signal) Definition and Conditions

1. "user_wr_strobe": This signal must be at least **two (2) clk_sys cycle wide** for a **single write operation**.
2. "user_rd_strobe": This signal must be at least t**wo (2) clk_sys cycle wide** for a **single read operation**.
3. "user_addr": This line must be held stable prior to submitting read/write request, and shall remain stable throughout until "MIG_user_transaction_complete" is asserted.
4. *user_wr_data": This line must be held stable prior to submitting read/write request, and shall remain stable throughout until "MIG_user_transaction_complete" is asserted.
5. "MIG_user_transaction_complete": Upon submitting read/write request, the user needs to wait for the assertion of this signal before issuing new request. This signal is only asserted for one clk_sys and cleared thereafter. It means differently for read and write request.
    1. For read operation, its assertion implies that the read request has been accepted and acknowledged by MIG **AND** the data on "user_rd_data" line is valid to read.
    2. For write operation, its assertion implies that the write request has been accepted and acknowledged by MIG. It **DOES NOT** imply that the "user_wr_data" has been written to the actual DDR2 successfully.
6. "rst_mem_n": This signal must be synchronized with clk_mem, and it must be asserted for at least 1024 clk_mem cycles. See Section: [Error Encountered](#documenting-mistakes-errors-and-struggles)

### Table 02: Clock Summary

| Designation   | Clock                         | Purpose   |
|---            |---                            |---        |
| clk_sys       | User System Clock @ 100MHz    | This is the clock user primarily bases on for the application.     |
| clk_mem       | Memory Clock @ 200MHz         | This is generated from the MMCM. This is the input to the MIG Core. It is used to derive other clocks to drive the DDR2. These are abstracted away from the MIG User Interface. |
| ui_clk        | MIG UI Clock @ 150MHz     | This is an output clock generated by the MIG UI Interface to synchronize all its MIG User signals. This value corresponds to the MIG Configuration: PHY to Controller Ratio: 2:1, where PHY Rate is 300MHz, and Controller is 300/2 = 150MHz. |

### Figure 01 : Block Diagram

![Figure 01](/doc/diagram/block_diagram.png "Figure 01: Block Diagram")

## Summary: Limitation + Assumption

1. The synchronous wrapper: "user_mem_ctrl.sv" assumes sequential transfer (no concurrent read and write transaction). User is required to check for the "MIG_user_transaction_complete" after submitting request.
2. The address and write data line must be held stable.
3. Write and Read Request: {"user_wr_strobe", "user_rd_strobe"} must be at least two user system clock (100MHz) cycles wide. This is explained in Section: [CDC](#construction---clock-domain-crossing-cdc)
4. Unlike the read operation, there is no viable MIG UI interface signal to use to reliably assert exactly when the data is written to the DDR2 external memory (?). This is reflected in the definition of "MIG_user_transaction_complete".

---

## Background on DDR2 External Memory in General

DDR2 is burst oriented. With 4:1 clock ratio and memory data width of 16-bit, DDR2 requires 8-transactions to take place across 4-clocks. This translates to a minimum transaction of 128 bits. With 2:1 clock ratio and memory data width of 16-bit, DDR requires 8-transactions to take place across 2 clocks; this translates to a minimum of 64-bit chunk per cycle. (still; 128-bit two cycles).

---

## Construction - Clock Domain Crossing (CDC)

By above, there are two clocks to be concerned with: (1) User System Clock @ 100MHz and (2) MIG UI clock @ 150MHz. The system clock is asynchronous with the MIG UI Clock. CDC Synchronizers are required. At the time of this writing, variants of Flip-flop sychronizers are considered (no handshaking, no FIFO etc) for convenience.

Denote the User System Clock as the slow clock domain, and the MIG UI Clock as the fast clock domain.

**IMPORTANT:** However, only the control signals: {write request, read request} shall be synchronized; it is the user's responsibility to hold the write data bus and the address stable upon requesting for write/read. This is usually the case since we assume sequential transfer.

### Signals to Synchronize when Crossing

1. From slow to fast:
    1. "user_write_strobe"
    2. "user_read_strobe"
2. From fast to slow:
    1. "init_calib_complete"
    2. "app_rdy"
    3. user_transaction_complete"

### Classification of CDC Signal Types

A simple double Flip-flop as the synchronizer is sufficient to "resolve/minimize" metastability issue, but it does not guarantee that a metastable signal, if occured will resolve into a valid logical level, thus a valid operation is not guaranteed.

There are three different cases to consider.

1. Case 01: from fast clock domain to slow clock domain, where the signal is a pulse (one fast-clock cycle wide).
2. Case 02: from fast to slow, where the signal is slowly varying (at least three slow-clock cycle wide)
3. Case 03: from slow to fast, where the signal is a pulse (one slow-clock cycle wide)

**Case 01**

1. Type: Signal is a pulse, one fast-clock-cycle (6.67 ns) wide.
2. Issue: Fast clock is 1.5 times faster than the slow clock. A simple double FF synchronizer is not sufficient. There will be missed events. Assuming there is no signal stretching, with MIG-clock period at 6.67 ns, a signal in one MIG-clock cycle will only be 6.67 ns wide, for which changes to the signal may happen between the rising edges of the system clock running at 10.0 ns period. The change(s) is not sampled by either of the rising edges.
3. Impacted Signal: "user_transaction_complete"
4. Solution: Toggle Synchronizer, shown in Figure 02. It consists of a multiplexer-and-FF, a double FF-synchronizer and a rising/falling edge detector. The functionality is as follows: (1) A pulse in the FF1 will toggle the signal in FF2 with the help of the multiplex in the fast clock domain; (2) which will be passed (delayed) through a double FF-synchronizer (FF2 + FF2); (3) until it reaches the final FF4 where the rising/fall detector (XOR circuit + FF4) is used to recreate the pulse with respect to the slower clock.
5. Caution: However, one needs to exercise caution when using the toggle synchronizer. There exist "traps". See Section: [Caution in Using Toggle Synchronizer](#caution-in-using-toggle-synchronizer)

*Figure 02: Toggle Synchronizer*
![Figure 02](/doc/diagram/toggle-synchronizer/toggle_synchronizer.png "Figure 02: Toggle Synchronizer")

**Case 02**

1. Type: Signal is from the fast clock domain but it is guaranteed to be at least three slow clock cycle wide.
2. Solution: A simple double FF synchronizer is sufficient to guarantee there will be no missed events [6].
2. Signals that meet this requirement.
    1. "init_calib_complete". MIG only needs to assert this once upon re-initialization, and remains unchanged throughout until a reset occurs or something goes wrong.
    2. "app_rdy". This signal will only be deasserted if one of the [4] following occurs. Otherwise, it will remain asserted (HIGH).
        - PHY/Memory initialization is not yet completed.
        - All the bank machines are occupied (can be viewed as the command buffer being full).
        - A read is requested and the read buffer is full.

**Case 03**

1. Type: Signal is a pulse, one slow-clock-cycle wide.
2. Note: Fast Clock is 1.5x faster than the slow clock. Slow clock period is 10 ns; fast clock period is 6.67 ns.
3. Timing Parameters:
    - The FPGA Part Number Speed Grade is -1.
    - From [1], Setup and Hold Times of Configurable Logic Block Flip Flops Before/After Clock, designated as "AX – DX input through MUXs and/or carry logic to CLK on A – D flip-flops" are used as the parameters. These CLB could be [2] configured as D-FF as well.
    - These CLB FF types have the highest setup/hold time compared to other CLB FF. This sets the threshold.
    - From [1], the **minimum** quoted setup and hold time are 0.81 ns and 0.11 ns (roughly, 0.9 ns and 0.2 ns), respectively.
4. Potential Problem:
    - Ideal: One slow clock cycle could accommodate 1.5 fast clock. This means that there will be at least one fast clock rising edge (maximum two fast clock rising edges) within a slow clock period. In the event of a setup or a hold time violation for the first rising fast-clock-edge, 1.5x means that there will be a second rising fast-clock-edge clock within the same slow-clock-period to sample the signal. This ensures valid operation.
    - However, there is little safe margin (?); it might be "possible" to have setup time violated in the first rising fast-clock edge AND to have the hold time violated in the second rising fast-clock edge after taking factors such as jitter, rise/fall time, skew etc into account. This means that the signal sampled might be an invalid logic level, resulting in incorrect operation.
    - See Figure 03. Consider the fast rising clock edge "lags" behind the slow rising clock edge by "1 second". This means the setup time could be violated, and also the second rising fast-clock edge will be 7.67 ns relative to the first rising fast-clock edge. With hold time of 0.2 ns, this means that there is only 10.0 - 7.87 ~= 2.0 ns before the signal changes at the next rising slow-clock edge. Is 2.0 ns margin sufficient for the hold time not to be violated?
5. Solution: For safety, stretch the signal over at least three cycle fast clock wide + double FF synchronizer. (*Stretching over two slow cycle wide also satisfies the same requirement.*)

*Figure 03: Waveform for CDC Case 03*
![Figure 03](/doc/diagram/wavedrom_synchronizer_annotated.png "Figure 03: Waveform of CDC Case 03")

### Summary of the Sychronizers

| Signal                    | From                 | To                 | Synchronizer Type                     |  Signal Condition         |
|---                        |---                   |---                 |---                                    |---                        |
| user_write_strobe         | User System Clock    | MIG UI Clock       | Double FF   | At least three (3) UI Clock cycle wide  |
| user_read_strobe          | User System Clock    | MIG UI Clock       | Double FF    | At least three (3) UI Clock cycle wide  |
| init_calib_complete       | MIG UI Clock         | User System Clock  | Double FF                             | At least three (3) user system clock wide |
| app_rdy                   | MIG UI Clock         | User System Clock  | Double FF                             | At least three (3) user system clock wide |
| user_transaction_complete | MIG UI Clock         | User System Clock  | Toggle Synchronizer                   | One UI clock cycle wide   |

## Construction - Write + Read Operation

Recall that all writing and reading are with respect to the MIG UI clock cycles.

**Write Operation:** Recall, when writing, it takes two UI clock cycles to complete the entire 128-bit data; (thus one 64-bit batch per clock cycle). The user needs to explicitly assert a data end flag to signal to the DDR2 for the second batch data during writing.

**Reading Operation:** Similar to the write operation, it takes two cycles to read all 128-bit data. MIG will signal when the first (64-bit) data is valid (in the first UI clock cycle), and whether the data is the last (64-bit) chunk on the data bus (in the second UI clock cycle).

## Construction - Address Mapping

1. The MIG controller presents [5] a flat address space to the user interface and translates it to the addressing required by the SDRAM. MIG controller is configured for sequential reads, and it maps the DDR2 as rank-bank-row-column.
2. The UI address provided by MIG is 27-bit wide: {Rank: 1-bit; Row: 13-bit; Column: 10-bit; Bank: 3-bit}
3. Since there is only one rank, this is hard-coded as zero.
4. DDR2 native data width is 16-bit; this means that the memory could accomodate a total of 2^{26} (with one rank) 16-bit data.
5. By above, each read/write DDR2 entire transaction is 128-bit. This corresponds to 128/16 = 8 chunks, (2^{3}), thus 3-bit. This implies that the three LSB bits of the address must be zero (the first three LSB column bits).
6. Reference: <https://support.xilinx.com/s/article/33698?language=en_US>

### Mapping between User Address and MIG UI Address

By above, the user address shall be 23-bit wide (27-1-3 = 23) where -1 is for the rank; -3 is for the column as discussed above. This representation is application-specific so that each user-address integer corresponds to one 128-bit data (one-to-one). In summary, we have the following:

```verilog
// [26:0] app_addr;      // MIG UI interface signal;
// [22:0] user_addr;     // user-created signal;
app_addr = {1'b0, user_addr, 3'b000};
```

## Construction - Data Masking

Data masking option provided by the MIG is not used. All write/read transaction will be in 128-bit. Two reasons:

1. It takes about 200ns (see the Simulation Result) to complete the entire (read/write) transaction. This is because, under the hood, it involves a number of operations in the PHY layer, and the DDR2 is burst-oriented (128-bit per transaction). With or without data masking, 128-bit transaction will still be conducted. It is wasteful to use only, say 16-bit per transaction. Thus, the effective rate "will be spread across" if more data is packed within one operation.
2. Data masking could always be done on the application side.

Application Setup Example:

By above, 128-bit transaction for read/write is in place as not to waste the memory space. Thus, it is up to the application to adjust with the setup, or to do the necessary masking on both ends: read/write. For example, if the application write data is only 16-bit, the application could accumulate/pack 8 data of 16-bit before writing it.

## Construction - FSM of user_mem_ctrl.sv

This user synchronous interface only allows a single read or write at a time. MIG exposes the relevant signals that allows a simple state machine. The state machine mainly involves sending the appropriate write/read request along with the address and waiting for the relevant assertion flags, such as transaction complete from the MIG.

A simplified FSM is shown in Figure 04. The FSM states are defined as follows:

| **State** | **Definition** |
|-----------|----------------|
| ST_WAIT_INIT_COMPLETE | To check MIG initial PHY callibration completion status and MIG app readiness before doing everything else. |
| ST_IDLE | Ready to accept user command to perform read/write operation. |
| ST_WRITE_FIRST | To push the first 64-bit batch to the MIG Write FIFO. |
| ST_WRITE_SECOND | To push the second 64-bit batch to the MIG Write FIFO. |
| ST_WRITE_SUBMIT | To submit the write request for the data in MIG Write FIFO (from these states: ST_WRITE_UPPER, LOWER). |
| ST_WRITE_DONE | To wait for MIG to acknowledge the write request to confirm it has been accepted. |
| ST_WRITE_RETRY | Write request is not acknowledged by the MIG or something went wrong. To retry the write operation.
| ST_READ_SUBMIT | To submit the read request. |
| ST_READ | To wait for MIG to signal "data_valid" and "data_end" to read the data. |

*Figure 04: Simplified FSM of the Synchronous Interface of MIG: user_mem_ctrl*

![Figure 04](/doc/diagram/fsm_user_mem_ctrl.png "Figure 04: FSM of user_mem_ctrl")
---

## Simulation

This section documents the following:

1. Note on the simulation.
2. Simulation Results on:
    - Set 01: Write Transaction
    - Set 02: Read Transaction
    - Set 03: Immediate Read After A Write

### Note on the Simulation

1. When simulating with the (ip-generated) MIG interface core, one needs to import the simulation files from the IP-examples: ddr2_model.v and ddr2_model_parameters.vh.
2. These simulation files provides a DDR2 model for the MIG interface to interface with. Thus, whatever the simulation result is, it is based on this DDR2 model.
3. These models could also be obtained from the DDR2 vendor website under Simulation Models: <https://www.micron.com/products/dram/ddr2-sdram/part-catalog/mt47h64m16nf-25e-aat/>
4. Reference: <https://support.xilinx.com/s/question/0D52E00006hpsNVSAY/mig-simulation-initcalibcomplete-stays-low?language=en_US>

### Set 01: Write Transaction

See Figure 05.
Simulation shows that the write operation is functional: the transaction complete flag is eventually asserted after submitting a write request.

It takes about 250 ns for the data to be written to the memory after the write request has been submitted and accepted. This is indicated by the non-High Impedance of the "ddr2_dq" line shown in Figure 05. This matches closely with the minimum write cycle time, tWC of 260ns from the Digilent Tutorial [7].

Observe that the completion flag is asserted before the data is written into the memory. This is by the construction (see limitation).

*Figure 05: Simulated Write Operation*
![Figure 05](/doc/diagram/mig-operation-simulation/write_op.png "Figure 05: Simulated Write Operation")

### Set 02: Read Transaction

See Figure 06.
Simulation shows that the read operation is functional: the assertion of the completion flag indicates that data is valid and ready to be read. The data read matches with what is written at the same address.

It takes 240ns for the completion status to be asserted after submitting the read request. This matches closely with the minimum read cycle time, tRC of 210 ns from the Digilent Tutorial [7].

*Figure 06: Simulated Read Operation*
![Figure 06](/doc/diagram/mig-operation-simulation/read_op.png "Figure 06: Simulated Read Operation")

### Set 03: Immediate Read from the Same Address as the Write After Write Transaction Completion Flag is Asserted

**Recall:**

1. For write transaction: "*MIG_user_transaction_complete*" indicates that the write request has been accepted and acknowledged by MIG. It does not imply that the actual data has been written to the memory.
2. For read transaction:  "*MIG_user_transaction_complete*" indicates that the data has already been read from the memory and it is ready/valid to read.

**Question:**
What happens a read request is immediately issued at the same write address after "*MIG_user_transaction_complete*" has been asserted for the previous write request? Would the data read actually match with what is written in the write request just before?

**Simulated:**
See Figure 07: . This figure shows the simulated process:

1. Write Request is submitted at Address 3.
2. "*MIG_user_transaction_complete*" is asserted for the write request.
3. After one system clock cyle, Read request is submitted. At this point, the write data from (1) has not been written to the memory since ddr2_dq line is still High Impedance (HiZ), yet the MIG indicates the memory is ready to accept new request.
4. After some delay, the ddr2_dq shows some ongoing activity (the start of the writing from (1) is being written).
5. After some delay, ddr2_dq shows some activity (the data is being read from the memory).
6. *MIG_user_transaction_complete* is asserted for the read request, indicating that the data is valid to read.

**Simulation Observation:**
By above, Read data actually matches with the previous write data at the same address. The PHY DQ Line is bidirectional. So, when writing is ongoing, the DQ is occupied even though the read request is already submitted at this point; data will not be read until this line is released to service this read request.

**Possible Explanation:**

1. The observation above matches with the datasheet and the support article linked below.
2. MIG controller could service concurrent transactions, but under the hood (PHY layer), these transactions are pipelined, and successive transaction will overlap but they are initiated and completed serially (not concurrently).
3. Support article: <https://support.xilinx.com/s/question/0D52E00006hpWuzSAE/simultaneous-readwrite-migddr3?language=en_US>

*Figure 07: Simulated result for Set 03 of Simulation Results.*
![Figure 07](/doc/diagram/mig-operation-simulation/annotated_figure_write_and_read_almost_concurrent.png "Figure 07: Simulated result for Set 03 of Simulation Results.")

## HW Test

### Testing Circuit

**Modules under test:**

1. user_mem_ctrl.sv: the main module under test.
2. test_top.sv is the top application module that instantiates user_mem_ctrl.sv

**Test:**
"test_top.sv" involves writing and displaying the read data as binary representation to the LED. Its FSM is shown in Figure 08. The test sequence is as follows:

1. Start from Address 0.
2. Use the address as the write data, and write it.
3. Read from the same address, and display as binary on the LED.
4. Pause for 0.5 seconds to inspect the LED display.
5. Increment the address and repeat.
6. Note that the address is wrapped around after integer 31.

**Setup:**
CPU HW reset button is used to reset the HW. There are 16 LEDs on the board. Each displays different information for debugging, summarized below:

|   LED     | Purpose   |
|---        |---        |
| LED[15]   | represents the MIG_user_init_complete" signal.    |
| LED[14]   | represent the MMCM locked status.                 |
| LED[13]   | represents the "MIG_user_ready" signal.           |
| LED[12:9] | represents the FSM integer representation of the current state of test_top.sv |
| LED[8:5]  | represents the FSM integer representation of the current state of user_mem_ctrl.sv.    |
| LED[4:0]  | represents the read data from the DDR2. |

**Test Expectation + Lookout**

1. Once initialized, the LED will be displaying the binary representation of this integer range: [0, 31] in incremental order and wraps around in a free running manner.
2. CPU HW reset button will reset the HW but it will be up and running as in (1) in a reasonable amount of time.
3. LED[15:13] should be HIGH after HW reset in a reasonable amount of time.

**Test Method:**

1. Visual inspection

**Test Limitation:**

1. By construction, it is not rigorous.
2. Not exhaustive: only 2^{5} = 32 addresses of the DDR2 are covered.
3. Not exhaustive: the test only involves sequential write->read. Might want to test burst write -> burst read (?)
4. Current test setup could not guarantee that the module under test works correctly almost all the time. That said, it is important to bear in mind that for any CDC (metastable problem), there will always be a possibility that the HW will fail, however small.

**FSM of test_top.sv**

|  State    | Definition    |
|---        |---            |
|   ST_CHECK_INIT   | Wait for the memory initialization to complete before starting everything else. |
| ST_WRITE_SETUP    | Prepare the write data and the addr.   |
| ST_WRITE          | Submit the write request. |
| ST_WRITE_EXTEND   | Ensure the write request is two system-clock-cycle wide as per the limitation. |
| ST_READ           | Submit the read request. |
| ST_READ_EXTEND    | Ensure the read request is two system-clock-cycle wide as per the limitation. |
| ST_READ_WAIT      | Wait for the read data to be valid. |
| ST_LED_WAIT       | Display the read data for N seconds.  |
| ST_GEN            | Generate the next test data. |

*Figure 08: Simplified FSM of test_top.sv*
![Figure 08](/doc/diagram/fsm_test_top_application.png "Figure 08: Simplified FSM of test_top.sv")

### Test Result

1. Test Length: Ran for one-hour, the LED continued to be free-running.
2. Test Status: OK?
3. Video Recording: Link: <https://drive.google.com/drive/folders/1jDpcOk9L0NAmC6i9KCu0XNu8hWP9ik13?usp=share_link>

---

## Documenting Mistakes, Errors and Struggles

This section is to document the mistakes committed, observations made and the struggles during development that worth jotting down.

1. **MIG UI Interface - Submitting write request**:
    1. Issue: During simulation, reading (the entire 128-bit data) does not match with what is written to the same address. It is observed that only the second 64-bit of the data is written.
    2. Cause: The user asserts "app_en" when submitting the 128-bit in two batches as discussed in the construction.
    3. Solution: One need to push both data batches to the MIG write FIFO via "app_wdf_wren" before submitting "app_en".
    4. Note: Also, for each read/write request (strobe), it is safer to check for app_rdy (the ACK from the MIG UI interface for each write/read request) when submitting and after submitting the request. Otherwise, retry, as recommended by UG586.

2. **HW DDR2 Not Coming Out of a CPU (Soft) Reset**:
    1. Issue: When testing on the actual HW, DDR2 does not "come out of reset" after a CPU Button Reset, as observed by the LEDs (MIG readiness is not asserted).
    2. Note: Soft reset is via the Board button to generate a reset signal after the FPGA has been programmed. It is not a Power-on-Reset or a HW reset (bitstream programming).
    3. Video Recording Link: <https://drive.google.com/drive/folders/1gb136PxTikKgRGXDFi2KNul3F2RPILpb?usp=share_link>
    4. Frequency: Always happen.
    5. Solution: It is unsure what is the exact cause; it takes the combination of the following actions to resolve the issue (?).
        1. Do not reset the MMCM. This will reset the 200MHz Clock driving the MIG. Simulation suggests that: (1) it will re-initialize the MIG (2) and MIG will remain in this state unless a MIG reset is further applied. This is not observed in practice. It is observed that MIG never asserts its app_ready/initialization complete flag (at least in a reasonable amount of time) after resetting the MMCM followed by a MIG reset. So, do not enable MMCM reset option for obvious reason.
        2. Synchronous reset the MIG with respect to its clock: 200MHz with the reset signal stretched (lengthened) over at least 1024 clock cycles. This number 1024 works at first try, it is not rigourous. It is unsure why this synchronous condition is required since MIG will internally synchronize the reset (?)

3. **Invalid Operation due to the Synchronization**:
    1. Issue: When testing on the real HW, it is observed that the application of "test_top.sv" eventually stuck after running for awhile, where the linked video shows the first five LEDs "stuck"; it is expected that the LEDs will display integer from 0 to 31 as binary representation in a free-running manner.
    2. Video Recording Link: <https://drive.google.com/drive/folders/1wwbxzsgrZaXu72Hj7EEqSP6sNMBk8B6M?usp=share_link>
    3. Frequency: Almost everytime (eventually), and the pattern where the LEDs stuck varies each time the issue occurs.
    4. Debugging: Use the LEDs to display the current FSM state.
    5. Observed: "user_mem_ctrl" module is in idle state waiting for read/write request; whereas the top (application) module: "test_top" is in the write-waiting state waiting for the transaction completion status. After multiple hit-and-probes, it is narrowed down to: "user_mem_ctrl" misses the write strobe from "test_top" for some reason. There is no logically explanation for this since the FSM's of both module are constructed to be in block-and-wait manner. This leaves "HW" explanation.
    6. Possible Cause: The write strobe is synchronized initially using a simple double FF synchronizer. It is suspected metastability occurs but it is resolved into an invalid logic (LOW instead of HIGH), thus resulting in invalid operation. This is discussed in Section: [CDC - Case 03](#construction---clock-domain-crossing-cdc). This cause offers the likely explanation as it matches with the observation.
    7. Solution: Extending the write and read request (strobe) to two system clock cycles, where the system clock is 100MHz seems to have resolved (minimized) the occurrence of this issue (?). See HW Testing.  In hindsight, FF-based synchronizer with hand-shaking, or dual-clock FIFO is a safer candidate to handle CDC.

## Caution in Using Toggle Synchronizer

### (Repeated) Background

Toggle synchronizer is useful to synchronize a short pulse from a fast clock domain to a slow clock domain. See Figure 09.  It consists of a multiplexer-and-FF, a double FF-synchronizer and a rising/falling edge detector. The functionality is as follows: (1) A pulse in the FF1 will toggle the signal in FF2 with the help of the multiplex in the fast clock domain; (2) which will be passed (delayed) through a double FF-synchronizer (FF2 + FF2); (3) until it reaches the final FF4 where the rising/fall detector (XOR circuit + FF4) is used to recreate the pulse with respect to the slower clock.

*Figure 09: Toggle Synchronizer*
![Figure 09](/doc/diagram/toggle-synchronizer/toggle_synchronizer.png "Figure 09: Toggle Synchronizer")

### Caution

However, there are some strict conditions when using it. If any of these conditions are violated, the synchronized pulse will not be "recreated" correctly in the slow clock domain, hence it may result in incorrect/invalid operation.

Assume the synchronization is from fast clock domain to slow clock domain in this discussion.

**Conditions:**

1. Pulse is only one fast-clock-cycle wide.
2. There should be only one fast-clock-pulse in at least three slow-clock cycles.

**Designations:** Figures shown in this section have common designated signals of interest, defined as follows:
1. "in_async" is the signal to be synchronized.
2. "clk_src" is the source clock (fast clock) of "in_async"; it is 250MHz.
3. "out_sync" is the output of the toggle synchronizer.
4. "clk_dest" is the destination clock (slow clock); it is 100MHz.

### Case Study when Conditions are violated

1. To violate condition 01, just create a static HIGH signal in the fast clock domain. The resulting synchronized signal in the slow clock domain will be a train pulse. This is shown in Figure 10. This is not desirable. This is due to this component pair: (MUX, FF1) of the toggle synchronizer. If the signal to synchronize is always HIGH, the output of the MUX will be constantly toggled at every fast clock cycle, resulting a pulse-like signal in the slow clock domain.

*Figure 10: Toggle Synchronizer Corner Case 01*
![Figure 10](/doc/diagram/toggle-synchronizer/corner-cases/case-01-not-ok-with-static-signal.png "Figure 10: Toggle Synchronizer Corner Case 01")

2. To violate condition 02, create a pulse every fast clock cycle, shown in Figure 11. Figure 11 shows that there are ten (10) one-fast-clock-cycle pulses. However, there are three (3) "pulses" in the slow clock domain. This is incorrect since it is "expected" to have ten pulses in the slow clock domain as well. This is because the toggle synchronizer consistes three registers (FFs) clocked by the slow clock, thus, it takes three slow clock cycle to flush out the "old information".

*Figure 11: Toggle Synchronizer Corner Case 02*
![Figure 11](/doc/diagram/toggle-synchronizer/corner-cases/case-02-not-ok-with-pulse-every-new-fast-clock-cycle.png "Figure 11: Toggle Synchronizer Corner Case 02")

### Case Study when Conditions are Met.

If the conditions are met, the synchronized pulse will be successfully recreated in the slow clock domain. For example, if there are ten (10) pulses in the fast clock domain, then we should expect for ten pulse synchronized with the slow clock domain. This is shown in Figure 12. 

*Figure 12: Toggle Synchronizer Condition Met*
![Figure 12](/doc/diagram/toggle-synchronizer/corner-cases/case-03-ok-with-three-slow-clock-cycles-gap.png "Figure 12: Toggle Synchronizer Condition Met")


## Clock Constraint

There exists CDC between MIG UI clock @ 150MHz and "user system clock @ 100MHz". Clock constraint is required. Currently, the timing path between these two clocks are set to false.

To identify the generated clock source, TCL commands: such as "report_CDC", "report_clocks" are useful; all information to locate the clock sources could be found in the Vivado Implementation Reports.

## TODO?

1. To add a debouncer for the HW reset button.
2. To add data masking option for different width: {64, 32, 16, 8} bits for flexibility?
3. More robust synchronizers: with Handshakers, FIFO? Currently, the implemented synchronizers assume certain conditions on the signal width and fixed clock rates on both domains.

## Reference

1. [Xilinx, "Artix-7 FPGAs Data Sheet: DC and AC Switching Characteristics (DS181)", version 1.27, February 10, 2022](https://docs.xilinx.com/v/u/en-US/ds181_Artix_7_Data_Sheet)
2. [Xilinx, "7 Series FPGAs Configurable Logic User Guide (UG474)", version 1.8, September 27, 2016](https://docs.xilinx.com/v/u/en-US/ug474_7Series_CLB)
3. [Micron, "DDR2 SDRAM MT47H64M16 – 8 Meg x 16 x 8 banks (Datasheet)",  Rev. AB 09/18 EN](https://media-www.micron.com/-/media/client/global/documents/products/data-sheet/dram/ddr2/1gb_ddr2.pdf?rev=854b480189b84d558d466bc18efe270c)
4. [Xilinx, "7 Series FPGAs Memory Interface Solutions v1.9 and v1.9a User Guide (UG586)", March 20, 2013](https://docs.xilinx.com/v/u/1.9-English/ug586_7Series_MIS)
3. [Xilinx, "Article 34779 - MIG 7 Series and Virtex-6 DDR2/DDR3 - User Interface - Addressing", September 23, 2021](https://support.xilinx.com/s/article/34779?language=en_US)
4. Digilent, "Nexys A7 Reference Manual", website, accessed 27 May 2023, <https://digilent.com/reference/programmable-logic/nexys-a7/reference-manual>
5. Digilent, "SRAM to DDR Component Reference Manual", website, accessed 27 May 2023, <https://digilent.com/reference/learn/programmable-logic/tutorials/nexys-4-ddr-sram-to-ddr-component/start>
6. [Mark Litterick, "Pragmatic Simulation-Based Verification of Clock Domain
Crossing Signals and Jitter using SystemVerilog Assertions", Verilab, 2006](http://www.verilab.com/files/sva_cdc_paper_dvcon2006.pdf)
