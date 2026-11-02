/* DO loops under interrupts (7.5.1): the shadowed loop state is the state
   the interrupted cycle leaves -- no pass added or lost, whichever cycle the
   interrupt hits (the do's own included) -- and dolock 0, 0 (one pass, no
   loop) releases its lock.  A reloading timer, period 7 counts of CKI/2,
   interrupts the loops at varying phases; TISR counts in r14. */
	evtp = (ushort24) TABLE
	r2 = (ushort24) 0x1000
	r14 = (short) 0
	r6 = (short) 0x200             // TIMER
	emr = r6
	r4 = (ushort24) 0x0414
	r4 = r4 <<| 0x5003             // timer count
	r3 = r4 - 1                    // tcon
	r5 = (short) 6
	*r4 = r5
	r5 = (short) 3                 // enabled, reload, CKI/2
	*r3 = (byte) r5
	// one instruction, 1000 passes
	r7 = (short) 0
	do 0, 999
	r7 = r7 + 1
	*r2++ = r7                     //! expect 0x1000 0x000003E8
	r12 = r14                      // (the interrupts so far)
	// three instructions, 300 passes
	r7 = (short) 0
	r8 = (short) 0
	do 2, 299
	r7 = r7 + 1
	nop
	r8 = r8 + 2
	*r2++ = r7                     //! expect 0x1004 0x0000012C
	*r2++ = r8                     //! expect 0x1008 0x00000258
	// 201 short loops (200 branches taken): interrupts land on the do
	// instructions too
	r9 = (short) 0
	r10 = (short) 199
L1:	do 0, 2
	r9 = r9 + 1
	if (r10-- >= 0) pcgoto L1
	nop
	*r2++ = r9                     //! expect 0x100C 0x0000025B
	r13 = r14
	// dolock 0, 0: one pass, then interrupts again
	dolock 0, 0
	r9 = r9 + 1
	r15 = r14
	r10 = (short) 99
L2:	if (r10-- >= 0) pcgoto L2
	nop
	*r2++ = r9                     //! expect 0x1010 0x0000025C
	r5 = (short) 0
	*r3 = (byte) r5                // the timer held
	// the loops were interrupted (r12 > 0, r13 > r12), and after the
	// dolock the timer still was (r14 > r15)
	r11 = (short) 0
	r12 - 0
	if (le) pcgoto N1
	nop
	r11 = r11 + 1
N1:	r13 - r12
	if (le) pcgoto N2
	nop
	r11 = r11 + 2
N2:	r14 - r15
	if (le) pcgoto N3
	nop
	r11 = r11 + 4
N3:	*r2++ = r11                    //! expect 0x1014 0x00000007
	r10 = (ushort24) 0x0FFFF0
	r11 = (ushort24) 0x00D0E5
	r11 = r11 <<| 0x600D
	*r10 = r11
L9:	pcgoto L9
	nop

TISR:	r14 = r14 + 1
	ireturn

	.align 8
TABLE:	.long 0, 0                     // 0 reset
	.long 0, 0, 0, 0, 0, 0, 0, 0   // 1-4
	.long 0, 0, 0, 0, 0, 0         // 5-7
	.long 0, 0                     // 8
	pcgoto TISR                    // 9 timer
	nop
	.long 0, 0, 0, 0, 0, 0, 0, 0   // 10-13
	.long 0, 0, 0, 0               // 14-15
