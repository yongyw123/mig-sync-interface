# mig-sync-interface

To implement a simple synchronous wrapper around Xilinx Memory-interface-generated (MIG) interface with the DDR2 External Memory of this FPGA development board: Nexys A7-50T. This synchronous interface assumes sequential transfer: only a single write/read operation is allowed at a time for simplicity.

Information available in the Xilinx User Guide 586 and the relevant datasheets are sufficient to make use of the IP-generated interface. That said, the author lacks of background knowledge to understand to take advantage of this information. This README also aggregates the information, scribbles, note etc to compensate for this.

| **Environment** | **Description** |
|-----------------|-----------------|
| Development Board | Digilent Nexys A7-50T |
| FPGA Part Number  | XC7A50T-1CSG324I      |
| Vivado Version    | 2021.2                |
| MIG Version       | 4.2 (Device 7 Series) |

## MIG Configuration

1. PHY to controller clock ratio: 2:1
2. data width: 16-bit;
3. write and read data width: 16-bit;
4. ?? to fill up ??

### Note on MIG UI interface signals

This section is to explain the MIG configurations and the UI signals presented by the MIG interface in the context of the user application.

**Note:**

1. "wr_data_mask": This bus is the byte enable (data mask) for the data currently being written to the external memory. The byte to the memory is written when the corresponding wr_data_mask signal is deasserted.

## User Synchronous Inteface - Port Description

Figure ?? shows the block diagram; Table ?? lists the ports of the synchronous interface.

?? insert a table summarizing the signals;
The synchronous wrapper;
?? insert some picture;
?? mention; which signal requires synchronizer;
?? mention transaction complete status implies differently for write and read operation;

---

## Background on DDR2 External Memory in General

1. DDR2 is burst oriented.
2. With 4:1 clock ratio and memory data width of 16-bit, DDR2 requires 8-transactions to take place across 4-clocks. This translates to a minimum transaction of 128 bits.
3. With 2:1 clock ratio and memory data width of 16-bit, DDR requires 8-transactions to take place across 2 clocks; this translates to a minimum of 64-bit chunk per cycle. (still; 128-bit two cycles).

## Clock Domain Crossing (CDC)

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

## Write Operation

By above, when writing, it takes two clock cycles to complete the entire 128-bit data; (thus one 64-bit batch per clock cycle). The user needs to explicitly assert a data end flag to signal to the DDR2 for the second batch data.

## Read Operation

Similar to the write operation, it takes two cycles to read all 128-bit data. MIG will signal when the data is valid, and when the data is the last chunk on the data bus.

## Caution + Encountered Error

One need to push the data to the MIG write FIFO before submitting the write request; otherwise, the write operation will not match the expectation. This is by observation after several failed simulations.  Also, for each read/write request (strobe), it is safer to check for app_rdy (the ACK from the MIG UI interface for each write/read request).

## Address Mapping

1. The MIG controller presents a flat address space to the user interface and translates it to the addressing required by the SDRAM. MIG controller is configured for sequential reads, and it maps the DDR2 as rank-bank-row-column. Insert ?? image ??
2. See the DDR2 data sheet, the UI address provided by MIG is 27-bit wide:  {Rank: 1-bit; Row: 13-bit; Column: 10-bit; Bank: 3-bit}
3. Since there is only one rank, this is hard-coded as zero.
4. DDR2 native data width is 16-bit; this means that the memory could accomodate a total of 2^{27} *(or 2^{26} with one rank)* 16-bit data.
5. By above, each read/write DDR2 entire transaction is 128-bit. This corresponds to 128/16 = 8 chunks, (2^{3}), thus 3-bit. This implies that the three LSB bits of the address must be zero (the first three LSB column bits).
6. Reference: <https://support.xilinx.com/s/article/33698?language=en_US>

### Mapping between User Address and MIG UI Address

By above, the user address shall be 23-bit wide (27-1-3 = 23) where -1 is for the rank; -3 is for the column as discussed above. This representation is application-specific so that each user-address integer corresponds to one 128-bit data (one-to-one). In summary, we have the following:

```verilog
// [26:0] app_addr;      // MIG UI interface signal;
// [22:0] user_addr;     // user-created signal;
app_addr = {1'b0, user_addr, 3'b000};
```

## Data Masking

Data masking option provided by the MIG is not used. All write/read transaction will be in 128-bit. Two reasons:

1. It takes about 200ns (see the Simulation Result) to complete the entire (read/write) transaction. This is because DDR2 is burst oriented. With or without data masking, 128-bit transaction will be conducted. It is inefficient to use only, say 16-bit per transaction. Alternatively, the effective rate "will be spread across" if more data is packed within one operation.
2. Data masking could always be done on the application side.

### Application Setup

By above, 128-bit transaction for read/write is in place as not to waste the memory space. Thus, it is up to the application to adjust with the setup, or to do the necessary masking on both ends: read/write. For example, if the application write data is only 16-bit, the application needs to accumulate/pack 8 data of 16-bit before writing it.

## FSM

This user synchronous interface only allows a single read or write at a time. MIG exposes the relevant signals that allows a simple state machine. The state machine mainly involves sending the appropriate write/read request along with the address and waiting for the relevant assertion flags, such as transaction complete from the MIG.

A simplified FSM is shown below with the states defined as follows:

| **State** | **Definition** |
|-----------|----------------|
| ST_WAIT_INIT_COMPLETE | to check MIG initial PHY callibration completion status before doing everything else. |
| ST_IDLE | ready to accept user command to perform read/write operation. |
| ST_WRITE_FIRST | to push the first 64-bit batch to the MIG Write FIFO. |
| ST_WRITE_SECOND | to push the second 64-bit batch to the MIG Write FIFO. |
| ST_WRITE_SUBMIT | to submit the write request for the data in MIG Write FIFO (from these states: ST_WRITE_UPPER, LOWER). |
| ST_WRITE_DONE | to wait for MIG to acknowledge the write request to confirm it has been accepted. |
| ST_READ | to wait for MIG to signal data_valid and data_end to read the data. |

---

## Result

1. add simulation; check if it matches with the abstracted timing parameters; t_{ras}, ... etc;
2. add write and read time;
3. add testing circuit result;

## Note on the Simulation

1. When simulating with the (ip-generated) MIG interface core, one needs to import the simulation files from the IP-examples: ddr2_model.v and ddr2_model_parameters.vh
2. These simulation files provides a DDR2 model for the MIG interface to interface with.
3. Reference: <https://support.xilinx.com/s/question/0D52E00006hpsNVSAY/mig-simulation-initcalibcomplete-stays-low?language=en_US>

---

## TODO?

1. Add data masking option for different width: {64, 32, 16, 8} bits for flexibility?
2. More robust synchronizers? Currently, the implemented synchronizers assume certain conditions on the signal width and fixed clock rates on both domains.

## Reference

1. DDR2 SDRAM Memory Datasheet <https://www.micron.com/-/media/client/global/documents/products/data-sheet/dram/ddr3/2gb_1_35v_ddr3l.pdf>
2. 7 Series FPGAs Memory Interface Solutions v1.9 and v1.9a User Guide <https://docs.xilinx.com/v/u/1.9-English/ug586_7Series_MIS>
3. Article 34779 - MIG 7 Series and Virtex-6 DDR2/DDR3 - User Interface - Addressing <https://support.xilinx.com/s/article/34779?language=en_US>
4. Digilent Nexys A7 Reference Manual <https://digilent.com/reference/programmable-logic/nexys-a7/reference-manual>
5. Digilent Reference: SRAM to DDR Component https://digilent.com/reference/learn/programmable-logic/tutorials/nexys-4-ddr-sram-to-ddr-component/start
