#!/bin/sh
# The peripheral bench: tb_peripherals.s (the CPU's command loop) assembled
# into obj_peripherals/prog.hex, loaded by tb_peripherals.sv into its memory.
set -eu
cd "$(dirname "$0")"
mkdir -p obj_peripherals
PYTHONDONTWRITEBYTECODE=1 python3 -c '
import struct, sys
sys.path.insert(0, ".")
import asm3210
try:
    out = asm3210.Asm().assemble(open("tb_peripherals.s").read())
except asm3210.AsmError as e:
    sys.exit(f"tb_peripherals.s: {e}")
b = asm3210.image(out, 0)
words = struct.unpack(">%dI" % (len(b) // 4), b)
open("obj_peripherals/prog.hex", "w").write("".join("%08x\n" % w for w in words))
'
verilator --binary --timing -j 8 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
  --top-module tb_peripherals -Mdir obj_peripherals -I../rtl \
  ../rtl/a3kp_dsp_pkg.sv ../rtl/a3kp_dsp_rf.sv ../rtl/a3kp_dsp_sio.sv \
  ../rtl/a3kp_dsp3210.sv tb_peripherals.sv > obj_peripherals_build.log 2>&1 || {
    tail -40 obj_peripherals_build.log; exit 1;
  }
./obj_peripherals/Vtb_peripherals
