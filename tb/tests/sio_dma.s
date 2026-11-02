/* Actual CAU MMIO accesses and interrupt entry/return for OBE, OFRM, IBF,
   IFRM. The serial input pin is tied low; internally generated input frames
   receive zeros. DMA steals cycles from the running CPU. */
	r22 = (ushort24) 0x800
	r1 = (ushort24) 0x40c
	r1 = r1 <<| 0x5003           // IOC
	r2 = (ushort24) 0x408
	r2 = r2 <<| 0x5003           // OBUF
	r3 = (ushort24) 0x430
	r3 = r3 <<| 0x5003           // DMAC word write
	r4 = (ushort24) 0x404
	r4 = r4 <<| 0x5003           // IBUF
	r14 = (short) 0
	r5 = (ushort24) 0x2000
	r5 = r5 <<| 0x0010          // ICN=1, burst OLD, internal OCK
	r6 = (ushort24) 0x700
	r5 = r5 | r6                // 8-bit output (OLEN=1 plus AOL/AOC)
	*r1 = r5
	r6 = (short) 0xa5
	*r2 = r6
	r6 = (ushort24) 0x1000
	emr = (short) r6
	do 0, 100
	nop
	// OFRM from a single external word read.
	r7 = (ushort24) 0x424
	r7 = r7 <<| 0x5003
	r6 = (ushort24) 0x2000
	*r7 = r6                    // ODP
	r7 = r7 + 8
	*r7 = r0                    // OCNT = 0
	r6 = (ushort24) 0x4000
	emr = (short) r6
	r6 = (short) 3
	*r3 = r6
	do 0, 100
	nop
	// IBF interrupt, servicing the buffer through a CAU memory load.
	r5 = (ushort24) 0x70
	r5 = r5 <<| 0x0011          // 8-bit MSB input, internal ICK/ILD
	*r1 = r5
	r6 = (ushort24) 0x800
	emr = (short) r6
	do 0, 200
	nop
	// Clear any old input, then enable input DMA and its frame interrupt.
	r6 = *r4
	nop
	r7 = (ushort24) 0x420
	r7 = r7 <<| 0x5003
	r6 = (ushort24) 0x2100
	*r7 = r6
	r7 = r7 + 8
	*r7 = r0                    // ICNT = 0
	r6 = (ushort24) 0x2000
	emr = (short) r6
	r6 = (short) 0x30
	*r3 = r6
	do 0, 200
	nop
	r7 = (ushort24) 0x1000
	*r7 = r14                   //! expect 0x1000 15
	r6 = *r3
	nop
	r7 = r7 + 4
	*r7 = r6                    //! expect 0x1004 0
	r10 = (ushort24) 0xffff0
	r11 = (ushort24) 0xd0e5
	r11 = r11 <<| 0x600d
	*r10 = r11
end: pcgoto end
	nop

.org 0x858
	pcgoto ibfisr
	nop
	pcgoto obeisr
	nop
	pcgoto ifrmisr
	nop
	pcgoto ofrmisr
	nop
ibfisr:
	emr = (short) r0
	r6 = *r4
	r14 = r14 | 4
	ireturn
obeisr:
	emr = (short) r0
	r14 = r14 | 1
	ireturn
ifrmisr:
	emr = (short) r0
	r14 = r14 | 8
	ireturn
ofrmisr:
	emr = (short) r0
	r14 = r14 | 2
	ireturn
