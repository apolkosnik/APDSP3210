/* With ENABLE_LITTLE_ENDIAN=0, clearing PCW.B/LN retains big-endian lanes. */
	r1 = (ushort24) 0x2000
	r2 = (ushort24) 0x3344
	r2 = r2 <<| 0x1122
	*r1 = r2
	r3 = pcw
	nop
	r4 = (short) 0x100
	r3 = r3 &~ r4
	pcw = r3
	r5 = (byte) *r1
	nop
	r6 = (ushort24) 0x1000
	*r6++ = r5                     //! expect 0x1000 0x11
	r5 = (ushort) *r1
	nop
	*r6++ = r5                     //! expect 0x1004 0x1122
	r5 = (short) 0xaa
	*r1 = (byte) r5
	r5 = *r1
	nop
	*r6++ = r5                     //! expect 0x1008 0xaa223344
	r10 = (ushort24) 0xffff0
	r11 = (ushort24) 0xd0e5
	r11 = r11 <<| 0x600d
	*r10 = r11
end: pcgoto end
	nop
