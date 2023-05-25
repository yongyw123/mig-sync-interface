# mig-sync-interface

?? to do ??
to change to use PLL instead of MMCM for the MIG clock;
see UG586; Section: System Clock, PLL Location, and Constraints??


To implement a simple synchronous wrapper around Xilinx Memory-interface-generated (MIG) interface with the DDR2 External Memory of this FPGA development board: Nexys A7-50T. This synchronous interface assumes sequential transfer: only a single write/read operation is allowed at a time for simplicity.

| **Environment** | **Description** |
|-----------------|-----------------|
| Development Board | Digilent Nexys A7-50T |
| FPGA Part Number  | XC7A50T-1CSG324I      |
| Vivado Version    | 2021.2                |
| MIG Version       | 4.2 (Device 7 Series) |
| Language          | System Verilog        |

## Table of Content
1. [Background on DDR2 External Memory](#background-on-ddr2-external-memory-in-general)
2. [MIG Configuration](#mig-configuration)
3. [User Synchronous Interface - Port Description](#user-synchronous-interface---port-description)
4. [Limitation + Assumption](#limitation--assumption)
5. [Construction](#construction)
    1. [Clock Domain Crossing (CDC)](#clock-domain-crossing-cdc)
    2. [Write Operation](#write-operation)
    3. [Read Operation](#read-operation)
    4. [Caution + Encountered Error](#caution--encountered-error)
    5. [Address Mapping](#address-mapping)
    6. [Data Masking](#data-masking)
    7. [FSM](#fsm)
6. [Simulation Results](#simulation-results)
7. [HW Test](#hw-test)
8. [Note on Simulation](#note-on-the-simulation)
9. [Clock Constraint](#clock-constraint)
10. [TODO?](#todo)
11. [Reference](#reference)

## Background on DDR2 External Memory in General

DDR2 is burst oriented. With 4:1 clock ratio and memory data width of 16-bit, DDR2 requires 8-transactions to take place across 4-clocks. This translates to a minimum transaction of 128 bits. With 2:1 clock ratio and memory data width of 16-bit, DDR requires 8-transactions to take place across 2 clocks; this translates to a minimum of 64-bit chunk per cycle. (still; 128-bit two cycles).

---

## MIG Configuration

1. PHY to controller clock ratio: 2:1
2. data width: 16-bit;
3. write and read data width: 16-bit;
4. ?? to fill up ??
5. DDR2 is on Bank 34; (see the schematics);

### Note on MIG UI interface signals

This section is to explain the MIG configurations and the UI signals presented by the MIG interface in the context of the user application.

1. "wr_data_mask": This bus is the byte enable (data mask) for the data currently being written to the external memory. Each bit represents a byte. There are 8 bits, hence 64-bit which matches the 128-bit transaction split into two cycles as noted above. It is active low. The byte to the memory is written when the corresponding wr_data_mask signal is deasserted.

---

## User Synchronous Interface - Port Description

Figure ?? shows the block diagram; Table ?? lists the ports of the synchronous interface.

?? insert a table summarizing the signals;
The synchronous wrapper;
?? insert some picture;
?? mention; which signal requires synchronizer;
?? mention transaction complete status implies differently for write and read operation;

## Limitation + Assumption

1. sequential transfer (no concurrent read and write transaction)
2. must hold addr and write data stable;2
3. criteria on the write request, and read request;
4. Unlike the read operation, there is no viable MIG UI interface signal to use to reliably assert exactly when the data is written to the DDR2 external memory. 
??

---

## Construction

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

### Caution + Encountered Error

One need to push the data to the MIG write FIFO before submitting the write request; otherwise, the write operation will not match the expectation. This is by observation after several failed simulations.  Also, for each read/write request (strobe), it is safer to check for app_rdy (the ACK from the MIG UI interface for each write/read request).

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

1. It takes about 200ns (see the Simulation Result) to complete the entire (read/write) transaction. This is because DDR2 is burst oriented. With or without data masking, 128-bit transaction will still be conducted. It is inefficient to use only, say 16-bit per transaction. In other words, the effective rate "will be spread across" if more data is packed within one operation.
2. Data masking could always be done on the application side.

Application Setup Example:

By above, 128-bit transaction for read/write is in place as not to waste the memory space. Thus, it is up to the application to adjust with the setup, or to do the necessary masking on both ends: read/write. For example, if the application write data is only 16-bit, the application needs to accumulate/pack 8 data of 16-bit before writing it.

### FSM

This user synchronous interface only allows a single read or write at a time. MIG exposes the relevant signals that allows a simple state machine. The state machine mainly involves sending the appropriate write/read request along with the address and waiting for the relevant assertion flags, such as transaction complete from the MIG.

The FSM states are defined as follows:

| **State** | **Definition** |
|-----------|----------------|
| ST_WAIT_INIT_COMPLETE | to check MIG initial PHY callibration completion status before doing everything else. |
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
2. That is, MIG controller could service concurrent transactions, but under the hood (PHY layer), these transactions are pipelined, and successive transaction will overlap but they are initiated and completed serially (not concurrently). 
3. Support article: <https://support.xilinx.com/s/question/0D52E00006hpWuzSAE/simultaneous-readwrite-migddr3?language=en_US>
5. DDR2 datasheet: <https://media-www.micron.com/-/media/client/global/documents/products/data-sheet/dram/ddr2/1gb_ddr2.pdf?rev=854b480189b84d558d466bc18efe270c*/>

*Figure ?? : Simulated result for Set 03 of Simulation Results.*
![Figure ?](/doc/diagram/simulation/annotated_figure_write_and_read_almost_concurrent.png "Figure ?? : Simulated result for Set 03 of Simulation Results.")

## HW Test

Test Involved: ?? communicate with the actual DDR2 memory;

add testing circuit result;

## Note on the Simulation

1. When simulating with the (ip-generated) MIG interface core, one needs to import the simulation files from the IP-examples: ddr2_model.v and ddr2_model_parameters.vh
2. These simulation files provides a DDR2 model for the MIG interface to interface with.
3. Reference: <https://support.xilinx.com/s/question/0D52E00006hpsNVSAY/mig-simulation-initcalibcomplete-stays-low?language=en_US>

---

## Clock Constraint

??

## TODO?

1. To add a debouncer for HW reset button.
2. To add data masking option for different width: {64, 32, 16, 8} bits for flexibility?
3. More robust synchronizers? Currently, the implemented synchronizers assume certain conditions on the signal width and fixed clock rates on both domains.

## Reference

1. DDR2 SDRAM Memory Datasheet <https://www.micron.com/-/media/client/global/documents/products/data-sheet/dram/ddr3/2gb_1_35v_ddr3l.pdf>
2. 7 Series FPGAs Memory Interface Solutions v1.9 and v1.9a User Guide <https://docs.xilinx.com/v/u/1.9-English/ug586_7Series_MIS>
3. Article 34779 - MIG 7 Series and Virtex-6 DDR2/DDR3 - User Interface - Addressing <https://support.xilinx.com/s/article/34779?language=en_US>
4. Digilent Nexys A7 Reference Manual <https://digilent.com/reference/programmable-logic/nexys-a7/reference-manual>
5. Digilent Reference: SRAM to DDR Component <https://digilent.com/reference/learn/programmable-logic/tutorials/nexys-4-ddr-sram-to-ddr-component/start>
