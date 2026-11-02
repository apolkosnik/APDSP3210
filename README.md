# DSP3210

A synthesisable AT&T WE DSP3210 in SystemVerilog, written from the
*WE DSP3210 Information Manual* (AT&T, September 1991) for the AA3000+
machine of the [Maximig](https://github.com/apolkosnik/Maximig-AGA_MiSTer/tree/AA3000)
MiSTer core, where it sits on the motherboard as on the Commodore AA3000.

What is in it:

- The CAU (control arithmetic unit): the 24/16-bit integer instructions, the
  register file `r0`-`r22`, branches with their latent instruction, calls,
  `do`/`dolock` loops, `ior` and the I/O and memory moves of every size.
- The DAU (data arithmetic unit): the four 40-bit accumulators, multiply,
  accumulate and the DSP32 floating-point format with the manual's
  precision (8.2), the special functions (`ic`, `oc`, `float16`, `int16`,
  `float32`, `int32`, `ieee`, `dsp`, `round`, `seed`, `ifalt`/`ifaeq`/`ifagt`)
  and the conversion modes of `dauc`.
- The pipeline as the manual times it: four states of CKI an instruction
  cycle (X, Y, I, Z), with the manual's latencies (4.4.2): a Z write seen
  four instructions later, the accumulator as a multiplier input three
  instructions after it is computed, the DAU flags a CA instruction tests
  being the ones from four instructions before.
- On chip: RAM0 and RAM1 (1K x 32 each), the 256-word boot ROM and the
  MMIO registers, in either memory map (Computer or Processor mode, `pcw[10]`).
- Exceptions (7.5): interrupts IR0/IR1 with the shadow registers and
  `ireturn`, the error levels, `sftrst`, the double error (the processor
  stops with IACK0 and IACK1 both up), reset, `waiti`.

Not yet: the serial I/O's shifting and its DMA (the registers are there),
the timer's BIO1 output, and `doblock`, which runs as `do` (the AA3000's
logic never answers a burst). Byte order is big-endian only (`pcw[8] = 1`,
as the AA3000 straps it).

## Layout

```
rtl/a3kp_dsp3210.sv   the processor: pipeline, CAU, DAU, on-chip memories, MMIO, exceptions
rtl/a3kp_dsp_pkg.sv   the DSP32 floating-point arithmetic (multiply, add, normalise, round)
rtl/a3kp_dsp_conv.svh the conversion special functions (ic, oc, float16, int16, float32, int32, ieee, dsp)
rtl/a3kp_dsp_rf.sv    the CAU register file in MLABs (two write ports, a live value table)
rtl/a3kp_dsp_rom.svh  the boot ROM contents
tb/tb_dsp.sv          the bench: the core on a 1 MB external memory with wait states, bus errors above 0x40000000
tb/sim_dsp.cpp        the Verilator driver: loads the image, drives IR0/IR1, dumps memory
tb/asm3210.py         an assembler for the manual's syntax (chapter 4) and encodings (chapter 10)
tb/asm_check.py       the assembler's encodings against the manual's tables
tb/run.py             runs tests/*.s and checks their '//! expect' lines
tb/gen_dau_stress.py  generates tests/dau_stress.s
tb/tests/*.s          the core's tests
```

## Interface

```
module a3kp_dsp3210 (
    input         clk,
    input         ce,          // one CKI state
    input         reset,       // RESTN asserted
    // the bus: a request toggles m_req, the answer toggles m_ack back
    output        m_req,  input m_ack,
    output [31:2] m_addr, output [3:0] m_be, output m_we,
    output [31:0] m_wdata, input [31:0] m_rdata, input m_berr,
    output        m_hold,      // the DSP wants the bus between its accesses
    input         ir0_n, ir1_n,
    output        iack0, iack1,
    input  [7:0]  bio_in, output [7:0] bio_out, output [7:0] bio_oe,
    output [31:0] dbg_pc, output dbg_retire, output dbg_halted
);
```

A state whose access goes to external memory lasts until the bus has
answered, so any memory or bus arbiter can sit behind the handshake. In the
AA3000+ the external bus is the DSP master of the local bus arbiter, and the
Amiga side reaches the DSP through the DMAC+'s control latch.

## Running the tests

Requirements: Verilator 5.x, Python 3.

```
cd tb
sh run.sh              # the assembler check, then every test, then every test with 3 wait states
python3 run.py da_basic int_basic
```

Each test is a program whose expected memory contents follow from the
manual (`//! expect ADDR VALUE`). The bench ends a run when the program writes
its done mark, `0x600DD0E5`, to `0x000FFFF0`.

## Sources

- *WE DSP3210 Digital Signal Processor Information Manual*, AT&T Microelectronics, 1991.
- The boot ROM's first 112 words are the silicon's, as WinUAE's DSP3210
  emulation (`dsp3210/DSP3210_emulation.cpp`) carries them; the manual's
  Listing A-1 is an earlier revision of the same code.

## Licence

Copyright (C) 2026 Adam Polkosnik

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, see <https://www.gnu.org/licenses/>.
