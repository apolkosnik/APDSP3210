/* DAU edge cases: a sum of -1 in the last place (its normalization: no bit
   differs from the sign), the float-to-integer conversion of values below
   2^-33 under each rounding mode, and oc() of the largest exponent (the
   companded path doubles the value: exponent 255 must not wrap to zero). */
	r2 = (ushort24) 0x1000
	r1 = (ushort24) VALS
	// (1 + 2^-15) - (1 + 2^-16)^2 = -2^-32, exactly (the product's 32
	// fraction bits): -2 x 2^-33
	r4 = r1 + 4
	a0 = *r1
	nop
	nop
	nop
	*r2++ = a0 = a0 - *r4 * *r4    //! expect 0x1000 0x8000005F
	nop
	nop
	nop
	// the mirror: -(1 + 2^-15) + (1 + 2^-16)^2 = +2^-32
	r5 = r1 + 8
	a1 = *r5
	nop
	nop
	nop
	*r2++ = a1 = a1 + *r4 * *r4    //! expect 0x1004 0x00000060
	nop
	nop
	nop
	// int32(-2^-40) and int32(+2^-40): nearest, toward -inf, toward 0
	r6 = r1 + 12                   // -2^-40
	r7 = r1 + 16                   // +2^-40
	*r2++ = a0 = int32(*r6)        //! expect 0x1008 0x00000000
	*r2++ = a0 = int32(*r7)        //! expect 0x100C 0x00000000
	nop
	nop
	r3 = (short) 0x10              // toward -inf
	dauc = r3
	*r2++ = a0 = int32(*r6)        //! expect 0x1010 0xFFFFFFFF
	*r2++ = a0 = int32(*r7)        //! expect 0x1014 0x00000000
	nop
	nop
	r3 = (short) 0x30              // toward 0
	dauc = r3
	*r2++ = a0 = int32(*r6)        //! expect 0x1018 0x00000000
	*r2++ = a0 = int32(*r7)        //! expect 0x101C 0x00000000
	nop
	nop
	// oc(): 2^126 and 2^127, -2^127 and -2^128 saturate alike (G.711
	// extremes: mu-law 0x80 / 0x00, A-law 0xAA / 0x2A)
	r3 = (short) 0                 // mu-law
	dauc = r3
	r8 = r1 + 20
	*r2++ = a0 = oc(*r8++)         // 2^126
	*r2++ = a0 = oc(*r8++)         // 2^127
	*r2++ = a0 = oc(*r8++)         // -2^127
	*r2++ = a0 = oc(*r8++)         // -2^128  //! expect 0x1020 0x80800000
	nop
	nop
	r3 = (short) 2                 // A-law
	dauc = r3
	r8 = r1 + 20
	*r2++ = a0 = oc(*r8++)
	*r2++ = a0 = oc(*r8++)
	*r2++ = a0 = oc(*r8++)
	*r2++ = a0 = oc(*r8++)         //! expect 0x1024 0xAAAA2A2A
	nop
	nop
	nop
	nop
	r10 = (ushort24) 0x0FFFF0
	r11 = (ushort24) 0x00D0E5
	r11 = r11 <<| 0x600D
	*r10 = r11
L9:	pcgoto L9
	nop

	.align 4
VALS:	.long 0x00010080               // 1 + 2^-15
	.long 0x00008080               // 1 + 2^-16
	.long 0xFFFF0080               // -(1 + 2^-15)
	.long 0x80000057               // -2^-40
	.long 0x00000057               // +2^-40
	.long 0x000000FE, 0x000000FF   // 2^126, 2^127
	.long 0x800000FE, 0x800000FF   // -2^127, -2^128
