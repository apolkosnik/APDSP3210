# APDSP3210

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
- Serial I/O: external or generated clocks and loads, 8/16/32-bit input,
  8/16/24/32-bit output, both bit orders (24-bit output is LSB first), continuous and burst output,
  SY/FB status and buffer interrupts. The two DMA channels support byte,
  halfword and word transfers, stop/reload modes and frame interrupts.
- The timer: CKI/2, CKI/4 or either BIO0 edge, one-shot or reload counting,
  interrupt generation, and active-high/low pulses or toggle output on BIO1.
- Exceptions (7.5): interrupts IR0/IR1 with the shadow registers and
  `ireturn`, the error levels, `sftrst`, the double error (the processor
  stops with IACK0 and IACK1 both up), reset, `waiti`.

Two independent synthesis parameters default to zero for the AA3000:

| Parameter | When set to 1 | When set to 0 |
| --- | --- | --- |
| `ENABLE_LITTLE_ENDIAN` | `pcw[8]` selects big/little-endian byte and halfword lanes, including MMIO and DMA | Always big-endian lanes |
| `ENABLE_DOBLOCK` | `doblock` signals atomic quad-word transfers between external and on-chip memory | `doblock` runs as `do`, with ordinary accesses |

Single-instruction loops cache their instruction in either configuration.
The external bus still uses one request/acknowledge handshake per word;
`doblock` adds grouping and ownership signals for the board's arbiter.

## Layout

```
rtl/a3kp_dsp3210.sv   the processor: pipeline, CAU, DAU, on-chip memories, MMIO, exceptions
rtl/a3kp_dsp_pkg.sv   the DSP32 floating-point arithmetic (multiply, add, normalise, round)
rtl/a3kp_dsp_conv.svh the conversion special functions (ic, oc, float16, int16, float32, int32, ieee, dsp)
rtl/a3kp_dsp_rf.sv    the CAU register file in MLABs (two write ports, a live value table)
rtl/a3kp_dsp_sio.sv   serial input/output shifters and the clock/frame generator
rtl/a3kp_dsp_rom.svh  the boot ROM contents
tb/tb_dsp.sv          the bench: the core on a 1 MB external memory with wait states, bus errors above 0x40000000
tb/sim_dsp.cpp        the Verilator driver: loads the image, drives IR0/IR1, dumps memory
tb/asm3210.py         an assembler for the manual's syntax (chapter 4) and encodings (chapter 10)
tb/asm_check.py       the assembler's encodings against the manual's tables
tb/run.py             runs tests/*.s and checks their '//! expect' lines
tb/gen_dau_stress.py  generates tests/dau_stress.s
tb/tests/*.s          the core's tests
tb/tb_peripherals.sv  serial, DMA and timer bench: the core on its pins, configured by the CPU
tb/tb_peripherals.s   the CPU's command loop for it (real CAU stores and loads, woken from waiti by IR0)
tb/features/*.s       byte-order and doblock parameter tests
```

## Interface

```
module a3kp_dsp3210 #(
    parameter bit ENABLE_LITTLE_ENDIAN = 0,
    parameter bit ENABLE_DOBLOCK = 0
) (
    input         clk,
    input         ce,          // one CKI state
    input         reset,       // RESTN asserted
    // the bus: a request toggles m_req, the answer toggles m_ack back
    output        m_req,  input m_ack,
    output [31:2] m_addr, output [3:0] m_be, output m_we,
    output [31:0] m_wdata, input [31:0] m_rdata, input m_berr,
    output        m_hold,      // the DSP wants the bus between its accesses
    output        m_block, m_block_first, m_lock,
    input         m_grant = 1'b1,
    output        m_dma_request,
    input         ir0_n, ir1_n,
    output        iack0, iack1,
    input  [7:0]  bio_in, output [7:0] bio_out, output [7:0] bio_oe,
    input         sio_di, sio_ick_in, sio_ild_in, sio_ock_in, sio_old_in, sio_sy_in,
    output        sio_do, sio_ick_out, sio_ild_out, sio_ock_out, sio_old_out, sio_sy_out,
    output        sio_ick_oe, sio_ild_oe, sio_ock_oe, sio_old_oe, sio_sy_oe,
    output [31:0] dbg_pc, output dbg_retire, output dbg_halted
);
```

A state whose access goes to external memory lasts until the bus has
answered, so any memory or bus arbiter can sit behind the handshake. In the
AA3000+ the external bus is the DSP master of the local bus arbiter, and the
Amiga side reaches the DSP through the DMAC+'s control latch.

`m_block` marks each of the four word requests in a quad-word group;
`m_block_first` marks its aligned first word. They remain stable through
the acknowledgement. `m_lock` holds ownership across the group, and
through a `dolock` loop. Unaligned prefixes and short tails use ordinary
word requests. The final pipelined writes of an outbound block also use
ordinary requests, as described in manual section 6.6.3.

`m_dma_request` requests ownership for a pending serial DMA transfer.
For the DMA IRB/ORB modes, connect `m_grant` to the arbiter's ownership
indication; tying it high preserves the original handshake interface.
DMA freezes the CPU pipeline for four CKI states (plus memory waits),
servicing input before output when both are pending.

The serial bidirectional pins use separate input, output and enable
signals; each `*_oe` is high when IOC selects internal generation. Connect
these through the board's I/O cells. Unused serial clock/load/SY inputs
should be tied high, and DI low. Serial inputs and BIO0 are sampled on
`ce`; the timer and serial clocks continue while the CPU waits for memory
or sleeps in `waiti`. Include `rtl/a3kp_dsp_sio.sv` in the synthesis fileset.

## Running the tests

Requirements: Verilator 5.x, Python 3.

```
cd tb
sh run.sh              # the assembler check, then every test, then every test with 3 wait states
python3 run.py da_basic int_basic
sh run_peripherals.sh  # serial protocols, DMA sizes/reload/grant/errors, timer outputs
sh run_features.sh     # all four combinations of the two synthesis parameters
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
