
# AXI UART Bridge
AXI4-Lite to UART Bridge for Low-Latency Serial Communication 

## Overview
This project implements a **UART to AXI4-Lite bridge** in Verilog HDL, enabling seamless communication between an AXI4-Lite master and a UART peripheral. It supports reliable serial data transmission and reception, with fully managed AXI4-Lite write and read transactions with proper valid/ready handshakes.  


## Features
- AXI4-Lite slave interface with standard write/read channels
- UART transmitter and receiver supporting configurable baud rates
- Word-aligned register map:
  - `0x00`: TXDATA (write-only)
  - `0x04`: RXDATA (read-only)
  - `0x08`: STATUS (read-only, TX busy and RX valid flags)
- Handshake-based AXI transaction management for reliable communication
- Busy and valid flags to prevent data loss
- Supports configurable system clock and UART baud rate
- Minimal logic and efficient use of FPGA resources



## Key Design Parameters
- System clock frequency: 100 MHz (configurable - Max Clock Frequency: 330MHz)
- UART baud rate: 115200 bps (configurable)
- AXI address width: 32 bits
- AXI data width: 32 bits
- Internal data registers: 8-bit for UART data, 2-bit status flags



## Architecture
The design consists of three main modules:

- **AXI UART Bridge (`axi_uart_bridge.v`)**  
  - Interfaces between AXI4-Lite slave and UART modules
  - Manages AXI write/read transactions, address decoding, and response generation
  - Latches write and read data to synchronize with UART operations

- **UART Transmitter (`uart_tx.v`)**  
  - Implements standard 8N1 UART transmission
  - Generates start, data, and stop bits with precise timing
  - Provides `tx_busy` flag to prevent data collision

- **UART Receiver (`uart_rx.v`)**  
  - Detects start, data, and stop bits on the RX line
  - Generates `rx_valid` flag when a byte is successfully received
  - Clears `rx_valid` upon read acknowledgement



## Implementation & Tools
 
- **Hardware Description Language**: Verilog HDL (Verilog 2001)  
- **Synthesis Tool**: Xilinx Vivado Design Suite  
- **Target FPGA**: Nexys 4 DDR (Artix-7 XC7A100TCSG324-1)  
