# mig-sync-interface

This is a simple synchronous wrapper around Xilinx Memory-interface-generated (MIG) interface with the DDR2 External Memory of this FPGA development board: Nexys A7-50T. This synchronous interface assumes sequential transfer: only a single write/read operation is allowed at a time for simplicity.

| **Environment** | **Description** |
|-----------------|-----------------|
| Development Board | Digilent Nexys A7-50T |
| FPGA Part Number  | XC7A50T-1CSG324I      |
| Vivado Version    | 2021.2                |
| MIG Version       | 4.2 (Device 7 Series) |
| Language          | System Verilog        |

**Modules**

1. *user_mem_ctrl.sv* is the synchronous wrapper.
2. *test_top.sv* is the top application file (testing circuit) for *user_mem_ctrl*.

**Navigation**

?? to fill up ??
1. Follow Vivado structure:
    1. source file
    2. simulation file
    3. constraint file

## Table of Content
1. [Background on DDR2 External Memory](#background-on-ddr2-external-memory-in-general)
2. [MIG Configuration](#mig-configuration)
3. [User Synchronous Interface - Port Description](#user-synchronous-interface---port-description)
4. [Limitation + Assumption](#limitation--assumption)
5. [Construction](#construction)
    1. [Clock Domain Crossing (CDC)](#clock-domain-crossing-cdc)
    2. [Write Operation](#write-operation)
    3. [Read Operation](#read-operation)
    4. [Address Mapping](#address-mapping)
    5. [Data Masking](#data-masking)
    6. [FSM](#fsm)
6. [Simulation Results](#simulation-results)
7. [HW Test](#hw-test)
8. [Note on Simulation](#note-on-the-simulation)
9. [Documenting Mistakes and Errors](#documenting-mistakes-and-errors)
9. [Clock Constraint](#clock-constraint)
10. [TODO?](#todo)
11. [Reference](#reference)

---

## MIG Configuration
Most of the configurations follow Digilent Tutorial [?].

| General               | Parameter      	| Note | 
|---	                |---	            |--- |
|MIG Output Options   	|  Create Design 	| Either available option should work.     |
|Number of Controllers  |   1	            | Unsure if it is supported in DDR2, Also, it is for simplicity. |
| AXI4 Interface        | Disabled          | Not used  |
| Memory Selection      | DDR2              |        |
  
|**Controller Options**     | Parameter         | Note          |
|---                        |---                |---            |
| Clock Period              | 3333ps (300MHz)   |               |
| PHY to Controller         | 2:1               | See ?? below  |
| Memory Part               |  MT47H64M16HR-25E |               | 
| Data Width                | 16-bit            | Native. See the DDR2 datasheet        |
| Data Mask                 | Enabled           | Application specific  |
| Number of Bank Machines   | 4                 | Default   |
| Ordering                  | Strict            | Default |


| **Memory Options**        | Parameter         | Note          |
|---                        |---                |---            |
| Input Clock Period        | 5000ps (200MHz)   |               |
| Burst Type                | Sequential        | Application specific  |
| Output Drive Strength     | Fullstrength      |   |
| RTT (Nominal) - ODT       | 50 Ohms           | Board specific    |
| Controlleer Chip Select Pin   | Enabled       | Not necessary since the memory only has one rank. |
| Memory Address Mapping Selection | BANK -> ROW -> COLUMN | Application specific. See ?? |


| **FPGA Options**              | Parameter         | Note      |
|---                            |---                |---        |
| System Clock                  | No Buffer         | This clock is to supply the 200MHz as specified in the Input Clock Period Option above. User to configure MMCM to generate this clock, so no buffer |
| Reference Clock               | Use System Clock  | One less thing to worry |
| System Reset Polarity     | Active LOW        | Default |
| Debug Signals             | OFF               | Default   |
| Internal VREF             | Enabled           | Otherwise, the Pin Selection Validation (below) will be rejected. |
| IO Power Reduction        | ON            | Default   |
XADC Instantiation          | Enabled       | For convenience, otherwise one needs to configure the XADC manually. |

| **The Rest**                  | Parameter         | Note      |
|---                            |---                |---        |
| Internal Termination Impedance | 50 Ohms          | Board specific          |
| Pin Selection                 | Import "ddr2_memory_pinout.ucf"        |  This is provided by Digilent. Ensure the pinout matches with the board schematic as a sanity check.         |
| System Signals Selection      | No connection for all: {sys_rst, init_calib_complete, tg_compare_error} | SW-wired instead of being hard-wired to a board pin. | 

## Background on MIG UI Interface

???

## User Setup: Synchronous Interface, Port Description

MMCM configuration: ??

This section discusses about the synchronous wrapper around the MIG UI interface.

Figure ?? shows the block diagram; Table ?? lists the ports of the synchronous interface.

?? insert a table summarizing the signals;
The synchronous wrapper;
?? insert some picture;
?? mention; which signal requires synchronizer;
?? mention transaction complete status implies differently for write and read operation;

## Limitation + Assumption

1. Sequential transfer (no concurrent read and write transaction)
2. Must hold the address and write data line stable.
3. Write and Read Request: {} must be at least two user system clock (100MHz) cycles wide. See Section: ?? 
4. Unlike the read operation, there is no viable MIG UI interface signal to use to reliably assert exactly when the data is written to the DDR2 external memory (?).

---

## Background on DDR2 External Memory in General

DDR2 is burst oriented. With 4:1 clock ratio and memory data width of 16-bit, DDR2 requires 8-transactions to take place across 4-clocks. This translates to a minimum transaction of 128 bits. With 2:1 clock ratio and memory data width of 16-bit, DDR requires 8-transactions to take place across 2 clocks; this translates to a minimum of 64-bit chunk per cycle. (still; 128-bit two cycles).

--- 

## Construction

### Block Diagram

### Clock Domain Crossing (CDC)

The system clock is asynchronous with the MIG UI Clock. The MIG interface has its own clock to drive the read and write operation; Thus, we have Clock Domain Crossing (CDC). Synchronizers are needed to handle the CDC.

**IMPORTANT:** However, only the control signals: {write request, read request} shall be synchronized; it is the user's responsibility to hold the write data bus and the address stable upon requesting for write/read. This is usually the case since we assume sequential transfer.

There are two CDC cases:

1. Case 01: from fast clock domain to slow clock domain;
2. Case 02: from slow clock domain to fast clock domain;
3. Dual-clock FIFO is a potential solution, but at the time of this writing, variants of Flip-flop sychronizers are considered.
4. If the signal to sample is sufficiently wide, then a simple double FF synchronizer
    is sufficient for both cases as log as the input is at least 3-clock cycle wides with respect to the sampling clock;
    this criteria is so that there willl be no missed events;
5. if the signal to sample is a pulse generated from the fast clock domain, and the fast clock rate is at least 1.5 times
    faster than slow clock rate, then a toggle synchronizer is needed; otherwise, there will be missed events;

?? mention the conditions/criteria for the cdc cases above; ??

### Write Operation

By above, when writing, it takes two clock cycles to complete the entire 128-bit data; (thus one 64-bit batch per clock cycle). The user needs to explicitly assert a data end flag to signal to the DDR2 for the second batch data.

### Read Operation

Similar to the write operation, it takes two cycles to read all 128-bit data. MIG will signal when the data is valid, and when the data is the last chunk on the data bus.

### Address Mapping

1. The MIG controller presents a flat address space to the user interface and translates it to the addressing required by the SDRAM. MIG controller is configured for sequential reads, and it maps the DDR2 as rank-bank-row-column. Insert ?? image ??
2. See the DDR2 data sheet, the UI address provided by MIG is 27-bit wide:  {Rank: 1-bit; Row: 13-bit; Column: 10-bit; Bank: 3-bit}
3. Since there is only one rank, this is hard-coded as zero.
4. DDR2 native data width is 16-bit; this means that the memory could accomodate a total of 2^{27} *(or 2^{26} with one rank)* 16-bit data.
5. By above, each read/write DDR2 entire transaction is 128-bit. This corresponds to 128/16 = 8 chunks, (2^{3}), thus 3-bit. This implies that the three LSB bits of the address must be zero (the first three LSB column bits).
6. Reference: <https://support.xilinx.com/s/article/33698?language=en_US>

#### Mapping between User Address and MIG UI Address

By above, the user address shall be 23-bit wide (27-1-3 = 23) where -1 is for the rank; -3 is for the column as discussed above. This representation is application-specific so that each user-address integer corresponds to one 128-bit data (one-to-one). In summary, we have the following:

```verilog
// [26:0] app_addr;      // MIG UI interface signal;
// [22:0] user_addr;     // user-created signal;
app_addr = {1'b0, user_addr, 3'b000};
```

### Data Masking

Data masking option provided by the MIG is not used. All write/read transaction will be in 128-bit. Two reasons:

1. It takes about 200ns (see the Simulation Result) to complete the entire (read/write) transaction. This is because DDR2 is burst oriented. With or without data masking, 128-bit transaction will still be conducted. It is wasteful to use only, say 16-bit per transaction. The effective rate "will be spread across" if more data is packed within one operation.
2. Data masking could always be done on the application side.

Application Setup Example:

By above, 128-bit transaction for read/write is in place as not to waste the memory space. Thus, it is up to the application to adjust with the setup, or to do the necessary masking on both ends: read/write. For example, if the application write data is only 16-bit, the application could accumulate/pack 8 data of 16-bit before writing it.

### FSM

This user synchronous interface only allows a single read or write at a time. MIG exposes the relevant signals that allows a simple state machine. The state machine mainly involves sending the appropriate write/read request along with the address and waiting for the relevant assertion flags, such as transaction complete from the MIG.

The FSM states are defined as follows:

| **State** | **Definition** |
|-----------|----------------|
| ST_WAIT_INIT_COMPLETE | to check MIG initial PHY callibration completion status and MIG app readiness before doing everything else. |
| ST_IDLE | ready to accept user command to perform read/write operation. |
| ST_WRITE_FIRST | to push the first 64-bit batch to the MIG Write FIFO. |
| ST_WRITE_SECOND | to push the second 64-bit batch to the MIG Write FIFO. |
| ST_WRITE_SUBMIT | to submit the write request for the data in MIG Write FIFO (from these states: ST_WRITE_UPPER, LOWER). |
| ST_WRITE_DONE | to wait for MIG to acknowledge the write request to confirm it has been accepted. |
| ST_READ | to wait for MIG to signal "data_valid" and "data_end" to read the data. |

---

## Simulation Results

1. add simulation; check if it matches with the abstracted timing parameters; t_{ras}, ... etc;
2. add write and read time;

### Set 01: Write Transaction

See Figure ??, simulation shows it takes about ?? ns for the data to be written to the memory after the write request has been submitted and accepted. This is asserted by the "ddr2_dq" line shown in Figure ??. This confirms that:

1. 


### Set 02: Read Transaction


### Set 03: Immediate Read from the Same Address as the Write After Write Transaction Completion Flag is Asserted

**Recall:**

1. For write transaction: "*MIG_user_transaction_complete*" indicates that the write request has been accepted and acknowledged by MIG. It does not imply that the actual data has been written to the memory.
2. For read transaction:  "*MIG_user_transaction_complete*" indicates that the data has already been read from the memory and it is ready/valid to read.

**Question:**
What happens a read request is immediately issued at the same write address after "*MIG_user_transaction_complete*" has been asserted for the previous write request? Would the data read actually match with what is written in the write request just before?

**Simulated:**
See Figure ??: . This figure shows the simulated process: 

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
2. That is, [?] MIG controller could service concurrent transactions, but under the hood (PHY layer), these transactions are pipelined, and successive transaction will overlap but they are initiated and completed serially (not concurrently). 
3. Support article: <https://support.xilinx.com/s/question/0D52E00006hpWuzSAE/simultaneous-readwrite-migddr3?language=en_US>
5. DDR2 datasheet: <https://media-www.micron.com/-/media/client/global/documents/products/data-sheet/dram/ddr2/1gb_ddr2.pdf?rev=854b480189b84d558d466bc18efe270c*/>

*Figure ?? : Simulated result for Set 03 of Simulation Results.*
![Figure ?](/doc/diagram/simulation/annotated_figure_write_and_read_almost_concurrent.png "Figure ?? : Simulated result for Set 03 of Simulation Results.")

## HW Test

Test Involved: ?? communicate with the actual DDR2 memory;

add testing circuit result;

mention about the limitation: could not guarantee it works at all times...;
especially true when sychronizer is involved ..

## Note on the Simulation

1. When simulating with the (ip-generated) MIG interface core, one needs to import the simulation files from the IP-examples: ddr2_model.v and ddr2_model_parameters.vh
2. These simulation files provides a DDR2 model for the MIG interface to interface with.
3. Reference: <https://support.xilinx.com/s/question/0D52E00006hpsNVSAY/mig-simulation-initcalibcomplete-stays-low?language=en_US>

---

## Documenting Mistakes and Errors

This section is to document the mistakes committed, observations made and  note during development that worth noting down.

1. **MIG UI Interface - Submitting write request**:
    1. Issue: During simulation, reading (the entire 128-bit data) does not match with what is written to the same address. It is observed that only the second 64-bit of the data is written.
    2. Cause: The user asserts "app_en" when submitting the 128-bit in two batches as discussed in the construction.
    3. Solution: One need to push both data batches to the MIG write FIFO via "app_wdf_wren" before submitting "app_en".
    4. Note: Also, for each read/write request (strobe), it is safer to check for app_rdy (the ACK from the MIG UI interface for each write/read request) when submitting and after submitting the request. Otherwise, retry, as recommended by UG586.

2. **HW DDR2 Not Coming Out of a CPU (Soft) Reset**:
    1. Issue: When testing on the actual HW, DDR2 does not "come out of reset" after a CPU Button Reset, as observed by the LEDs (MIG readiness is not asserted).
    2. Note: Soft reset is via the Board button to generate a reset signal after the FPGA has been programmed. It is not a Power-on-Reset or a HW reset (bitstream programming).
    3. Frequency: Always happen. 
    4. Solution (Possible Cause): It is unsure what is the exact cause; it takes the combination of the following to resolve the issue (?).
        1. Do not reset the MMCM. This will reset the 200MHz Clock driving the MIG. Simulation suggests that: (1) it will re-initialize the MIG (2) and MIG will remain in this state unless a MIG reset is further applied. This is not observed in practice. It is observed that MIG never asserts its app_ready/initialization complete flag (at least in a reasonable amount of time) after resetting the MMCM followed by a MIG reset. So, do not enable MMCM reset option for obvious reason.
        2. Synchronous reset the MIG with respect to its clock: 200MHz with the reset signal is stretched (lengthened) over at least 1024 clock cycles. It is unsure why this is required since MIG will internally synchronize the reset (?)

3. **Invalid Operation due to the Synchronization**: 
    1. Issue: It is observed that the application module eventually stuck after running for awhile as observed in video here: ??, where it shows the first five LEDs "stuck"; it is expected that the LEDs will display integer from 0 to 32 as binary representation in a free-running manner.
    2. Frequency: Almost everytime (eventually), and the pattern where the LEDs stuck varies each time the issue occurs.
    3. Debugging: Use the LEDs to display the current FSM state.
    4. Observed: "user_mem_ctrl" module is in idle state waiting for read/write request; whereas the top (application) module: "test_top" is in the write-waiting state waiting for the transaction completion status. After multiple hit-and-probes, it is narrowed down to: "user_mem_ctrl" misses the write strobe for some reason.
    5. Possible Cause: The write strobe is synchronized initially using a simple double FF synchronizer. It is suspected metastability occurs but it is resolved into an invalid logic (LOW instead of HIGH), thus resulting in invalid operation. This is discussed in Section: ?? This cause offers the likely explanation as it matches with the observation.
    6. Solution: Extending the write and read request (strobe) to two system clock cycles, where the system clock is 100MHz seems to have resolved (minimized) the occurrence of this issue (?). See HW Testing.  This is discussed in Section: ?? In hindsight, FF-based synchronizer with hand-shaking, or dual-clock FIFO is a safer candidate to handle CDC.

## Clock Constraint

??

## TODO?

1. To add a debouncer for HW reset button.
2. To add data masking option for different width: {64, 32, 16, 8} bits for flexibility?
3. More robust synchronizers: with Handshakers, FIFO? Currently, the implemented synchronizers assume certain conditions on the signal width and fixed clock rates on both domains.

## Reference

0. ?? include fpga IO datasheet for the setup and hold time specs;
1. DDR2 SDRAM Memory Datasheet <https://www.micron.com/-/media/client/global/documents/products/data-sheet/dram/ddr3/2gb_1_35v_ddr3l.pdf>
2. 7 Series FPGAs Memory Interface Solutions v1.9 and v1.9a User Guide <https://docs.xilinx.com/v/u/1.9-English/ug586_7Series_MIS>
3. Article 34779 - MIG 7 Series and Virtex-6 DDR2/DDR3 - User Interface - Addressing <https://support.xilinx.com/s/article/34779?language=en_US>
4. Digilent Nexys A7 Reference Manual <https://digilent.com/reference/programmable-logic/nexys-a7/reference-manual>
5. Digilent Reference: SRAM to DDR Component <https://digilent.com/reference/learn/programmable-logic/tutorials/nexys-4-ddr-sram-to-ddr-component/start>
