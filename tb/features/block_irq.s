/* An IRQ becomes pending in the first source quad. The handler uses its own
   single-instruction loop, then restores the interrupted loop's cache. */
//! args --blocks 2 --irq-block
	r22 = (ushort24) 0x800
	r14 = (short) 0
	r13 = (ushort24) 0x100
	emr = (short) r13
	r1 = (ushort24) 0x2000
	r2 = (ushort24) 0x1234
	do 1, 15
	*r1++ = r2
	r2 = r2 + 1
	r1 = (ushort24) 0x2004
	r2 = (ushort24) 0xf000
	r2 = r2 <<| 0x5003
	doblock 11
	a0 = (*r2++ = *r1++) * a0
	nop
	nop
	nop
	r1 = (ushort24) 0xf000
	r1 = r1 <<| 0x5003
	r2 = (ushort24) 0x3000
	doblock 11
	a0 = (*r2++ = *r1++) * a0
	nop
	nop
	nop
	r7 = (ushort24) 0x1000
	*r7 = r14  //! expect 0x1000 1
	r10 = (ushort24) 0xffff0
	r11 = (ushort24) 0xd0e5
	r11 = r11 <<| 0x600d
	*r10 = r11
end: pcgoto end
	nop
//! expect 0x3000 0x1235
//! expect 0x3004 0x1236
//! expect 0x3008 0x1237
//! expect 0x300c 0x1238
//! expect 0x3010 0x1239
//! expect 0x3014 0x123a
//! expect 0x3018 0x123b
//! expect 0x301c 0x123c
//! expect 0x3020 0x123d
//! expect 0x3024 0x123e
//! expect 0x3028 0x123f
//! expect 0x302c 0x1240

.org 0x840
	pcgoto isr
	nop
isr:
	emr = (short) r0
	r14 = r14 + 1
	do 0, 3
	nop
	ireturn
