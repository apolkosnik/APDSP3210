/* The CPU side of tb_peripherals.sv: a command loop.  Every MMIO register
   access the bench makes is a real CAU store or load from this program,
   through the core's address decode, byte lanes and pipeline.

   The CPU sleeps in waiti (DMA, serial and timer keep running); the bench
   puts a command in the mailbox, bumps SEQ and pulses IR0.  The loop
   performs the command, writes RESULT, then DONE = SEQ, and sleeps again.

   Mailbox (external memory):
     0x7F00 SEQ   0x7F04 OP   0x7F08 ADDR   0x7F0C DATA
     0x7F10 RESULT            0x7F14 DONE
   OP: 1 *ADDR = DATA        2 (byte) store     3 (short) store
       4 RESULT = *ADDR      5 (byte) load      6 (ushort) load
       7 RESULT = ps         8 RESULT = pcw     9 pcw = DATA
      10 emr = DATA
   The bench clears LOG (0x7E00); the interrupt and error routines append
   their vector numbers there (IFRM 13, OFRM 14, bus error 1). */
	evtp = (ushort24) TABLE
	r1 = (ushort24) 0x7F00         // SEQ
	r8 = (ushort24) 0x7F10         // RESULT
	r9 = (ushort24) 0x7F14         // DONE
	r15 = (ushort24) 0x7E00        // LOG
	r2 = (short) 0                 // the last command done
	r6 = (ushort24) 0x100          // EXT0 wakes waiti
	emr = r6
	*r9 = r2                       // ready
IDLE:	waiti
	nop
	r10 = *r1
	nop
	r10 - r2
	if (eq) pcgoto IDLE            // another interrupt woke the CPU
	nop
	r2 = r10
	r11 = (ushort24) 0x7F04
	r3 = *r11++                    // OP
	r4 = *r11++                    // ADDR
	r5 = *r11++                    // DATA
	nop
	r3 - 1
	if (eq) pcgoto SW
	nop
	r3 - 2
	if (eq) pcgoto SB
	nop
	r3 - 3
	if (eq) pcgoto SH
	nop
	r3 - 4
	if (eq) pcgoto LW
	nop
	r3 - 5
	if (eq) pcgoto LB
	nop
	r3 - 6
	if (eq) pcgoto LH
	nop
	r3 - 7
	if (eq) pcgoto RPS
	nop
	r3 - 8
	if (eq) pcgoto RPCW
	nop
	r3 - 9
	if (eq) pcgoto WPCW
	nop
	r3 - 10
	if (eq) pcgoto WEMR
	nop
	r7 = (ushort24) 0xBAD0         // an unknown command
	*r8 = r7
	pcgoto DONE
	nop
SW:	*r4 = r5
	pcgoto DONE
	nop
SB:	*r4 = (byte) r5
	pcgoto DONE
	nop
SH:	*r4 = (short) r5
	pcgoto DONE
	nop
LW:	r7 = *r4
	nop
	*r8 = r7
	pcgoto DONE
	nop
LB:	r7 = (byte) *r4
	nop
	*r8 = r7
	pcgoto DONE
	nop
LH:	r7 = (ushort) *r4
	nop
	*r8 = r7
	pcgoto DONE
	nop
RPS:	r7 = ps
	nop
	*r8 = r7
	pcgoto DONE
	nop
RPCW:	r7 = pcw
	nop
	*r8 = r7
	pcgoto DONE
	nop
WPCW:	pcw = r5
	nop
	pcgoto DONE
	nop
WEMR:	emr = r5
	nop
DONE:	*r9 = r2
	pcgoto IDLE
	nop

IFRM:	r16 = (short) 13
	*r15++ = r16
	ireturn
OFRM:	r16 = (short) 14
	*r15++ = r16
	ireturn
	// a bus error (a faulting DMA access): the instruction executing is
	// aborted, possibly the command's own DONE store
BERR:	r16 = (short) 1
	*r15++ = r16
	*r9 = r2
	sftrst
	pcgoto IDLE
	nop

	.align 8
TABLE:	.long 0, 0                     // 0 reset
	pcgoto BERR                    // 1 bus error
	nop
	.long 0, 0, 0, 0, 0, 0         // 2-4
	.long 0, 0, 0, 0, 0, 0         // 5-7
	nop                            // 8 EXT0: a quick routine, only to wake waiti
	ireturn
	.long 0, 0, 0, 0, 0, 0, 0, 0   // 9-12
	pcgoto IFRM                    // 13 IFRM
	nop
	pcgoto OFRM                    // 14 OFRM
	nop
	.long 0, 0                     // 15
