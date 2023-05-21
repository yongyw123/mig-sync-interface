# mig-sync-interface

To implement a synchronous wrapper around Xilinx Memory-interface-generated (MIG) interface with the DDR2 External Memory of this FPGA development board: Nexys A7-50T. 

## MIG Setup

1. PHY to controller clock ratio: 2:1
2. data width: 16-bit;
3. write and read data width: 16-bit;
4. ?? to fill up ??

## Scribbles/Background on DDR2 External Memory

1. Refer to the Xilinx UG586.
2. DDR2 is burst oriented.
3. With 4:1 clock ratio and memory data width of 16-bit, DDR2 requires 8-transactions to take place across 4-clocks. This translates to a minimum transaction of 128 bits.
4. With 2:1 clock ratio and memory data width of 16-bit, DDR requires 8-transactions to take place across 2 clocks; this translates to a minimum of 64-bit chunk per cycle. (still; 128-bit two cycles).

## Note on MIG UI interface signals

1. "wr_data_mask": This bus is the byte enable (data mask) for the data currently being written to the external memory. The byte to the memory is written when the corresponding wr_data_mask signal is deasserted.

## General Construction

1. This is cross-domain clock because 
2. the MIG UI provides its own clock to drive the MIG interface with DDR2;
2.1 the MIG interface has its own clock to drive the read and write operation;
3. we use synchronizers to handle the CDC;
4. however, only the control signals shall be synchronized;
5. by above, address and data must remain stable from the user request to the complete flag;
6. this is usually the case since we assume sequential transfer;

## CDC

1. by above, we need to becareful; as there are two CDC cases;
2. case 01: from fast clock domain to slow clock domain;
3. case 02: from slow clock domain to fast clock domain;
4. if the signal to sample is sufficiently wide, then a simple double FF synchronizer
    is sufficient for both cases as log as the input is at least 3-clock cycle wides with respect to the sampling clock;
    this criteria is so that there willl be no missed events; 
5. if the signal to sample is a pulse generated from the fast clock domain, and the fast clock rate is at least 1.5 times 
    faster than slow clock rate, then a toggle synchronizer is needed; otherwise, there will be missed events; 

## Write Construction

1. By above, when writing, two clock cycles are required to complete the entire 128-bit data;
2. one 64-bit batch per clock cycle;
3. depending on the application, masking is required to mask out those bytes that are not required to be written;
4. by above, the user needs to explicitly assert a data end flag to signal to the DDR2 for the second batch data;
5. Also, one need to push the data to the MIG write FIFO before submitting the write request; otherwise, the write operation will not match the expectation (this is observed after some experimentation); 

## Read Construction

1. similar to th write operation, it takes two cycles to read all 128-bit data;
2. MIG will signal when the data is valid, and when the data is the last chunk on the data bus;

## Address Mapping

1. The MIG controller presents a flat address space to the user interface and translates it to the addressing required by the SDRAM.
2. MIG controller is configured for sequential reads;
3. MIG is configured to map the DDR2 as rank-bank-row-column;
4. see the data sheet, the address is 27-bit wide (including the rank); 
5. since there is only one rank, this is hard-coded as zero; not important;
6. DDR2 native data width i 16-bit; that means each address bit represents 16-bit; (see the datasheet);
7. by above, each read/write DDR2 transaction is 128-bit;
8. this corresponds to 128/16 = 8 address bits;
9. by above, it implies that the three LSB bits of the address must be zero (the first three LSB column bits);
10. This is because 3-bit corresponds to eight (8) 16-bit data for the DDR2;
11. reference: https://support.xilinx.com/s/article/33698?language=en_US

## User Setup

1. by above, we have the write and read data to be 128-bit wide;
2. we could always do the masking outside of the mig; so not critical;
3. by above, the user address shall be 23-bit wide (27-1-3 = 23) where -1 is for the rank; -3 is for the column as discussed above;

## Application Setup

1. by above, 128-bit transaction is in place as not to waste the space;
2. as such, the application needs to adjust with the setup;
3. for example, if the application write data is only 16-bit, the application needs to accumulate 8 data before writing it;


## Reference

1. DDR2 SDRAM Memory Datasheet https://www.micron.com/-/media/client/global/documents/products/data-sheet/dram/ddr3/2gb_1_35v_ddr3l.pdf
2. 7 Series FPGAs Memory Interface Solutions v1.9 and v1.9a User Guide https://docs.xilinx.com/v/u/1.9-English/ug586_7Series_MIS
3. 34779 - MIG 7 Series and Virtex-6 DDR2/DDR3 - User Interface - Addressing https://support.xilinx.com/s/article/34779?language=en_US
4. Digilent Nexys A7 Reference Manual https://digilent.com/reference/programmable-logic/nexys-a7/reference-manual


