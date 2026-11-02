/* Little-endian data lanes; instruction words keep their numeric encoding.
   Exercise external memory, on-chip RAM, and the little-endian MMIO byte. */
	r1 = (ushort24) 0x2000
	r2 = (ushort24) 0xf000
	r2 = r2 <<| 0x5003
	r3 = (ushort24) 0x3344
	r3 = r3 <<| 0x1122
	*r1 = r3
	*r2 = r3
	r4 = pcw
	nop
	r5 = (short) 0x100
	r4 = r4 &~ r5
	pcw = r4
	r6 = (byte) *r1
	nop
	r7 = (ushort24) 0x1000
	*r7++ = r6                     //! expect 0x1000 0x44
	r6 = (ushort) *r2
	nop
	*r7++ = r6                     //! expect 0x1004 0x3344
	r6 = (short) 0xaa
	*r1 = (byte) r6
	*r2 = (byte) r6
	r6 = *r1
	nop
	*r7++ = r6                     //! expect 0x1008 0x112233aa
	r6 = *r2
	nop
	*r7++ = r6                     //! expect 0x100c 0x112233aa
	r8 = (ushort24) 0x410
	r8 = r8 <<| 0x5003
	r6 = (short) 0x12
	*r8 = (byte) r6
	nop
	r6 = (byte) *r8
	nop
	*r7++ = r6                     //! expect 0x1010 0x12
	r10 = (ushort24) 0xffff0
	r11 = (ushort24) 0xd0e5
	r11 = r11 <<| 0x600d
	*r10 = r11
end: pcgoto end
	nop
