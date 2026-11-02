/* pcsh (7.5.1): "when examined during the interrupt routine it points to
   the memory location to be fetched when exiting the interrupt routine;
   when examined during base-level processing it contains the same value as
   the pc" -- also after a base-level write; the return still uses the
   address interrupt entry saved. */
//! args --irq0 200
	evtp = (ushort24) TABLE
	r2 = (ushort24) 0x1000
	r1 = pcsh                      // at 0x0008: 0x0010, as the pc reads
	r3 = pc                        // at 0x000C: 0x0014
	*r2++ = r1                     //! expect 0x1000 0x00000010
	r4 = r3 - r1
	*r2++ = r4                     //! expect 0x1004 0x00000004
	r5 = (ushort24) 0x1234
	pcsh = r5                      // a base-level write: reads still follow the pc
	nop
	r1 = pcsh
	r3 = pc
	r4 = r3 - r1
	*r2++ = r4                     // (read one instruction apart) //! expect 0x1008 0x00000004
	// in the interrupt routine: the address the return fetches.  Leaving
	// waiti, the instruction after it runs first (7.4) while AFTER is
	// fetched into the instruction shadow: ireturn executes AFTER from irsh
	// and fetches AFTER + 4, pcsh.
	r8 = (short) 0
	r6 = (ushort24) 0x100          // EXT0
	emr = r6
	waiti
	r8 = r8 + 1
AFTER:	r8 = r8 + 2
	r5 = (ushort24) AFTER
	r4 = r7 - r5
	*r2++ = r4                     // the routine's pcsh - AFTER  //! expect 0x100C 0x00000004
	*r2++ = r8                     // both instructions, once each  //! expect 0x1010 0x00000003
	r1 = pcsh                      // the base level again
	r3 = pc
	r4 = r3 - r1
	*r2++ = r4                     //! expect 0x1014 0x00000004
	r10 = (ushort24) 0x0FFFF0
	r11 = (ushort24) 0x00D0E5
	r11 = r11 <<| 0x600D
	*r10 = r11
L9:	pcgoto L9
	nop

ISR0:	r7 = pcsh
	emr = r0
	ireturn

	.align 8
TABLE:	.long 0, 0                     // 0 reset
	.long 0, 0, 0, 0, 0, 0, 0, 0   // 1-4
	.long 0, 0, 0, 0, 0, 0         // 5-7
	pcgoto ISR0                    // 8 EXT0
	nop
	.long 0, 0, 0, 0, 0, 0, 0, 0   // 9-12
	.long 0, 0, 0, 0, 0, 0         // 13-15
