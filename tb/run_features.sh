#!/bin/sh
set -eu
cd "$(dirname "$0")"
sh build.sh
python3 run.py ../features/endian_disabled
DSPARGS="--blocks 0" python3 run.py ../features/block
OBJ=obj_features DEFS="-GENABLE_LITTLE_ENDIAN=1 -GENABLE_DOBLOCK=1" sh build.sh
DSPBIN=./obj_features/Vtb_dsp python3 run.py ../features/endian ../features/block ../features/block_irq
DSPBIN=./obj_features/Vtb_dsp DSPARGS="--waits 3" python3 run.py ../features/endian ../features/block ../features/block_irq
OBJ=obj_le DEFS="-GENABLE_LITTLE_ENDIAN=1 -GENABLE_DOBLOCK=0" sh build.sh
DSPBIN=./obj_le/Vtb_dsp python3 run.py ../features/endian
DSPBIN=./obj_le/Vtb_dsp DSPARGS="--blocks 0" python3 run.py ../features/block
OBJ=obj_block DEFS="-GENABLE_LITTLE_ENDIAN=0 -GENABLE_DOBLOCK=1" sh build.sh
DSPBIN=./obj_block/Vtb_dsp python3 run.py ../features/endian_disabled ../features/block ../features/block_irq
