# FIFO and UART

SystemVerilog implementation of a synchronous FIFO, a UART transmitter/receiver,
and a simple memory controller that lets a host read and write on-chip memory
over a serial link. Built on the standard EECS151 register/memory library.

## Structure

```
src/
  EECS151.sv          Standard course library: REGISTER/REGISTER_CE/REGISTER_R/
                       REGISTER_R_CE and single/dual-port ROM/RAM primitives
  fifo.sv              Parameterized synchronous FIFO (depth, width configurable)
  uart_transmitter.sv  Shift-register based UART TX
  uart_receiver.sv     Shift-register based UART RX with mid-bit sampling
  uart.sv              Top-level UART wrapper (TX + RX + serial line sync regs)
  mem_controller.sv    FSM that decodes read/write commands off a FIFO and
                       drives a synchronous RAM, echoing results back out
  async_ram.sv         Standalone RAM module (not currently wired into the
                       rest of the design -- see Known Issues)

sim/
  fifo_tb.sv               Testbench for fifo.sv
  uart_transmitter_tb.sv   Testbench for uart_transmitter.sv
  uart2uart_tb.sv          Loopback testbench: TX -> RX round trip
  mem_controller_tb.sv     Testbench for mem_controller.sv
```

## Design notes

- **FIFO** (`fifo.sv`): standard dual-pointer FIFO. `full`/`empty` are
  disambiguated with a `last_was_write` flag rather than an extra pointer bit.
  Read data (`dout`) is registered, so there is one cycle of read latency.
- **UART** (`uart_transmitter.sv` / `uart_receiver.sv`): 8N1 framing
  (1 start bit, 8 data bits, 1 stop bit), parameterized by `CLOCK_FREQ` and
  `BAUD_RATE`. The receiver samples at the midpoint of each bit period for
  noise margin.
- **Memory controller** (`mem_controller.sv`): a small FSM that reads a
  command byte and address byte off an RX FIFO, then either writes a
  following data byte to memory or reads memory and pushes the result to a
  TX FIFO. Accounts for the one-cycle read latency of the synchronous RAM
  with a dedicated `READ_MEM_VAL` state before echoing data out.

## Simulation

These testbenches are written for a standard Verilog/SystemVerilog simulator
(e.g. Icarus Verilog or Verilator). Example with Icarus:

```bash
iverilog -g2012 -o fifo_tb.vvp src/EECS151.sv src/fifo.sv sim/fifo_tb.sv
vvp fifo_tb.vvp
```

Repeat similarly for `uart_transmitter_tb.sv`, `uart2uart_tb.sv`, and
`mem_controller_tb.sv`, adding whatever source files each testbench depends
on. No `Makefile` is included yet -- consider adding one that builds/runs all
four testbenches in one step.

## Known issues / TODO

- `src/async_ram.sv` is not instantiated anywhere in the current design
  (`mem_controller.sv` uses `SYNC_RAM_WBE` from `EECS151.sv` instead). Despite
  its name, it also has a registered (synchronous) output, not an
  asynchronous one. Either remove it or wire it in and rename it.
- Line endings are inconsistent across the repo (most files are CRLF,
  `uart_transmitter.sv` is LF). Worth normalizing with a `.gitattributes`
  (`* text=auto`) or a one-time `dos2unix` pass.
- All four testbenches should be run and confirmed passing before relying on
  this as a verified design; this README is based on a static code read, not
  a simulation run.
