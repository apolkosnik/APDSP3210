`timescale 1ns/1ps
// Peripheral bench: the real core, running tb_peripherals.s from external
// memory.  Every register write and every software-visible check goes through
// a CAU store or load made by that program (address decode, byte lanes,
// pipeline); the bench only drives pins, owns the external memory and the
// mailbox, and wakes the CPU from waiti with IR0.  No core state is forced.
// Internal state is only observed: dut.waiting (to know the CPU sleeps) and
// dut.dma_start/dma_active (to time DMA cycles).
module tb_peripherals;
reg clk = 0;
always #5 clk = ~clk;
reg ce = 1, reset = 1;
reg [7:0] bio_in = 8'h40;
wire [7:0] bio_out, bio_oe;
reg di = 0, ick = 0, ild = 1, ock = 0, old = 1, sy = 1;
wire dout, ick_out, ild_out, ock_out, old_out, sy_out;
wire ick_oe, ild_oe, ock_oe, old_oe, sy_oe;
wire req, we;
reg ack = 0;
wire [31:2] addr;
wire [3:0] be;
wire [31:0] wd;
reg [31:0] rd = 0;
reg berr = 0;
reg grant = 1;
reg ir0_n = 1;
wire dma_request;
reg [31:0] mem [0:16383];               // 64 KB at 0, bus errors at 0x80000000 and up
integer waits = 0, countdown = 0;
integer dma_clocks = 0;
reg busy = 0;
a3kp_dsp3210 #(.ENABLE_LITTLE_ENDIAN(1), .ENABLE_DOBLOCK(1)) dut (
	.clk(clk), .ce(ce), .reset(reset), .m_req(req), .m_ack(ack),
	.m_addr(addr), .m_be(be), .m_we(we), .m_wdata(wd), .m_rdata(rd), .m_berr(berr),
	.m_hold(), .m_lock(), .m_block(), .m_block_first(), .m_grant(grant), .m_dma_request(dma_request),
	.iack0(), .iack1(), .dbg_pc(), .dbg_retire(), .dbg_halted(),
	.ir0_n(ir0_n), .ir1_n(1'b1), .bio_in(bio_in), .bio_out(bio_out), .bio_oe(bio_oe),
	.sio_di(di), .sio_ick_in(ick), .sio_ild_in(ild), .sio_ock_in(ock), .sio_old_in(old), .sio_sy_in(sy),
	.sio_do(dout), .sio_ick_out(ick_out), .sio_ild_out(ild_out), .sio_ock_out(ock_out),
	.sio_old_out(old_out), .sio_sy_out(sy_out), .sio_ick_oe(ick_oe), .sio_ild_oe(ild_oe),
	.sio_ock_oe(ock_oe), .sio_old_oe(old_oe), .sio_sy_oe(sy_oe)
);
always @(posedge clk) begin
	if (!reset && ce && (dut.dma_start || dut.dma_active)) dma_clocks <= dma_clocks + 1;
	if (reset) begin ack <= req; busy <= 0; end
	else if (!busy && req != ack) begin busy <= 1; countdown <= waits;
		if ($test$plusargs("trace") && (we || addr[15:8] == 8'h7F)) $display("[bus] %0t %s %08x be %b wd %08x rd %08x", $time, we ? "W" : "R", {addr, 2'b00}, be, wd, mem[addr[15:2]]);
	end
	else if (busy && countdown != 0) countdown <= countdown - 1;
	else if (busy) begin
		busy <= 0; ack <= req; berr <= addr[31]; rd <= mem[addr[15:2]];
		if (we && !addr[31]) for (int b = 0; b < 4; b++) if (be[b]) mem[addr[15:2]][8*b +: 8] <= wd[8*b +: 8];
	end
end

// the mailbox and the log (tb_peripherals.s)
localparam integer MB_SEQ = 32'h7F00 >> 2, MB_OP = 32'h7F04 >> 2, MB_ADDR = 32'h7F08 >> 2,
                   MB_DATA = 32'h7F0C >> 2, MB_RES = 32'h7F10 >> 2, MB_DONE = 32'h7F14 >> 2,
                   LOG = 32'h7E00 >> 2;
localparam [31:0] OP_SW = 1, OP_SB = 2, OP_SH = 3, OP_LW = 4, OP_LB = 5, OP_LH = 6,
                  OP_PS = 7, OP_RPCW = 8, OP_WPCW = 9, OP_EMR = 10;
localparam [31:0] MMIO = 32'h50030400, EXT_BUF = 32'h00008000;
localparam [15:0] EMR_EXT0 = 16'h0100, EMR_IFRM = 16'h2000, EMR_OFRM = 16'h4000;
localparam integer PS_IBF = 8, PS_OBE = 9, PS_SY = 10, PS_FB = 11;
integer seq = 0, commands = 0;

task automatic tick(input integer n = 1);
	repeat (n) begin @(posedge clk); #1; @(negedge clk); end
endtask
task automatic check(input bit ok, input string what);
	if (!ok) $fatal(1, "%s", what);
endtask
// The CPU is in waiti with no bus access outstanding.
task automatic wait_sleep;
	automatic integer n = 0;
	while (!(dut.waiting && req == ack)) begin
		tick(); n++;
		if (n > 20000) $fatal(1, "CPU does not return to waiti");
	end
endtask
// One command through the CPU; returns RESULT.
task automatic cpu(input [31:0] op, input [31:0] a, input [31:0] d, output [31:0] result);
	automatic integer n = 0;
	wait_sleep();
	seq++; commands++;
	mem[MB_OP] = op; mem[MB_ADDR] = a; mem[MB_DATA] = d; mem[MB_SEQ] = seq;
	ir0_n = 0; tick(4); ir0_n = 1;
	while (mem[MB_DONE] != seq) begin
		tick(); n++;
		if (n > 20000) $fatal(1, "CPU command %0d (op %0d at %08x) not done", seq, op, a);
	end
	result = mem[MB_RES];
	wait_sleep();
endtask
// MMIO register a (word index, Figure 3-5) written / read by CAU word accesses.
task automatic wr(input [9:2] a, input [31:0] data);
	reg [31:0] r;
	cpu(OP_SW, MMIO | {a, 2'b00}, data, r);
endtask
task automatic rdw(input [31:0] a, output [31:0] v);
	cpu(OP_LW, a, 0, v);
endtask
function automatic [31:0] mmio(input [9:2] a); return MMIO | {a, 2'b00}; endfunction
task automatic set_emr(input [15:0] v);
	reg [31:0] r;
	cpu(OP_EMR, 0, {16'd0, v | EMR_EXT0}, r);   // EXT0 stays enabled to wake waiti
endtask
task automatic ps_bit(input integer b, output bit v);
	reg [31:0] r;
	cpu(OP_PS, 0, 0, r); v = r[b];
endtask
task automatic restart;
	reset = 1; ce = 1;
	mem[MB_DONE] = 32'hFFFFFFFF; mem[MB_SEQ] = 0; seq = 0;
	for (int i = 0; i < 64; i++) mem[LOG + i] = 0;
	tick(4); reset = 0;
	begin
		automatic integer n = 0;
		while (mem[MB_DONE] != 0) begin
			tick(); n++;
			if (n > 20000) $fatal(1, "command loop does not start");
		end
	end
	wait_sleep();
endtask
task automatic input_bit(input bit value);
	di = value; ick = 0; tick(3); ick = 1; tick(3); ick = 0; tick(3);
endtask
task automatic receive_word(input [31:0] value, input integer n, input bit msb);
	ild = 1; input_bit(0); ild = 0; input_bit(0);
	for (int i = 0; i < n; i++) input_bit(msb ? value[n-1-i] : value[i]);
	ild = 1;
endtask
task automatic transmit_word(input [31:0] value, input integer n, input bit msb);
	old = 1; ock = 1; tick(3); ock = 0; tick(3); old = 0;
	for (int i = 0; i < n; i++) begin
		ock = 1; tick(3);
		check(dout == (msb ? value[n-1-i] : value[i]), "serial output bit/order");
		ock = 0; tick(3);
	end
	old = 1;
endtask

initial begin
	reg [31:0] v, v2;
	bit f;
	$readmemh("obj_peripherals/prog.hex", mem);
	tick();
	for (int mode = 0; mode < 2; mode++) begin
		for (int size = 1; size <= 3; size++) begin
			automatic integer n = size == 1 ? 8 : size == 2 ? 16 : 32;
			automatic reg [31:0] mask = 32'hffffffff >> (32-n);
			restart();
			wr(8'h03, (32'(mode) << 16) | (32'(size) << 6) | (32'(mode) << 17) | (32'(size) << 10));
			rdw(mmio(8'h03), v); check(v == ((32'(mode) << 16) | (32'(size) << 6) | (32'(mode) << 17) | (32'(size) << 10)), "IOC read back");
			ps_bit(PS_IBF, f); check(!f, "IBF clear before input");
			receive_word(32'h9182e7a5, n, 1'(mode));
			ps_bit(PS_IBF, f); check(f, "IBF on completed input");
			rdw(mmio(8'h01), v);
			check((mode ? v & mask : v >> (32-n)) == (32'h9182e7a5 & mask), "serial input data/order");
			ps_bit(PS_IBF, f); check(!f, "IBUF read clears IBF");
			wr(8'h02, 32'h9182e7a5);
			ps_bit(PS_OBE, f); check(!f, "OBE cleared by write");
			transmit_word(32'h9182e7a5, n, 1'(mode));
			ps_bit(PS_OBE, f); check(f, "OBE on shift-register load");
		end
	end
	// ILEN=00 captures the word preceding ILD, with an inverted input clock.
	restart(); wr(8'h03, 32'h00014000);
	ild = 1;
	for (int i = 31; i > 0; i--) input_bit(1'(32'h9182e7a5 >> i));
	ild = 0; input_bit(1);
	ps_bit(PS_IBF, f); rdw(mmio(8'h01), v);
	check(f && v == 32'h9182e7a5, "preceding-word input and inverted clock");
	// The last bit of a 32-bit frame coincides with the next frame's load.
	restart(); wr(8'h03, 32'h000100c0);
	ild = 1; input_bit(0); ild = 0; input_bit(0); ild = 1;
	for (int i = 31; i > 0; i--) input_bit(1'(32'h9182e7a5 >> i));
	ild = 0; input_bit(1);
	rdw(mmio(8'h01), v); check(v == 32'h9182e7a5, "continuous input frame boundary");
	ild = 1;
	for (int i = 31; i >= 0; i--) input_bit(1'(32'h12345678 >> i));
	rdw(mmio(8'h01), v); check(v == 32'h12345678, "continuous input second frame");
	// Twenty-four-bit output is LSB first and consumes a full DMA word.
	restart(); wr(8'h03, 32'h00001000); wr(8'h02, 32'h12e7a5);
	transmit_word(32'h12e7a5, 24, 0);
	// DMA byte/halfword/word transfers, both byte orders, on/off-chip and
	// external wait states. Counts are byte offsets of the final transfer.
	// PCW.B is written by the CPU; DMAC and ICNT/OCNT are written with byte
	// and halfword stores at the byte order's addresses (Figure 3-5 gives the
	// big-endian ones: DMAC 0x433, ICNT 0x42A, OCNT 0x42E).
	for (int endian = 0; endian < 2; endian++)
	for (int ext = 0; ext < 2; ext++)
	for (int size = 1; size <= 3; size++) begin
		automatic integer n = size == 1 ? 8 : size == 2 ? 16 : 32;
		automatic integer step = n / 8;
		automatic reg [31:0] base = ext ? EXT_BUF : 32'h5003f000;
		automatic reg [31:0] want = n == 8 ? (endian ? 32'ha55a0000 : 32'h00005aa5) : n == 16 ? (endian ? 32'he7a51234 : 32'h1234e7a5) : 32'h9182e7a5;
		automatic reg [31:0] dmac_a = endian ? 32'h50030433 : 32'h50030430;
		automatic reg [31:0] icnt_a = endian ? 32'h5003042a : 32'h50030428;
		automatic reg [31:0] ocnt_a = endian ? 32'h5003042e : 32'h5003042c;
		restart(); waits = ext ? 5 : 0;
		cpu(OP_RPCW, 0, 0, v);
		cpu(OP_WPCW, 0, endian ? v | 32'h100 : v & ~32'h100, v2);
		cpu(OP_RPCW, 0, 0, v2); check(v2[8] == 1'(endian), "PCW.B written");
		mem[EXT_BUF >> 2] = 0; cpu(OP_SW, 32'h5003f000, 0, v2);
		set_emr(EMR_IFRM | EMR_OFRM);
		wr(8'h03, 32'h000d0000 | (32'(size) << 6) | (32'(size) << 10));
		wr(8'h08, base);
		cpu(OP_SH, icnt_a, 32'(step), v2);
		rdw(mmio(8'h0A), v2); check(v2 == step, "ICNT halfword store lane");
		cpu(OP_SB, dmac_a, 32'h30, v2);
		rdw(mmio(8'h0C), v2); check(v2 == 32'h20, "DMAC byte store lane");
		receive_word(32'h9182e7a5, n, 1);
		receive_word(n == 8 ? 32'h5a : 32'h1234, n, 1); tick(40);
		rdw(mmio(8'h0C), v2);
		check(!v2[5] && mem[LOG] == 13 && mem[LOG+1] == 0, "input DMA frame completed");
		if (ext) v = mem[EXT_BUF >> 2]; else rdw(32'h5003f000, v);
		check(v == want, "input DMA data/lane/count");
		wr(8'h09, base);
		cpu(OP_SH, ocnt_a, 0, v2);
		cpu(OP_SB, dmac_a, 3, v2); tick(40);
		rdw(mmio(8'h0C), v2); ps_bit(PS_OBE, f);
		check(!v2[1] && mem[LOG+1] == 14 && !f, "output DMA frame completed");
		rdw(mmio(8'h02), v);
		check(v == (n == 8 ? 32'ha5 : n == 16 ? 32'he7a5 : 32'h9182e7a5), "output DMA subword extension");
	end
	waits = 0;
	// Both pending channels share one four-CKI DMA cycle, input before output.
	restart(); grant = 0;
	wr(8'h03, 32'h00010040);
	cpu(OP_SW, 32'h5003f004, 32'hdeadbeef, v);
	wr(8'h08, 32'h5003f000); wr(8'h0a, 0);
	wr(8'h09, 32'h5003f004); wr(8'h0b, 0);
	set_emr(EMR_IFRM | EMR_OFRM);
	wr(8'h0c, 32'hbb);
	receive_word(32'ha5, 8, 1);
	check(dma_request, "DMA requests ownership in IRB/ORB mode");
	begin
		automatic integer before_dma = dma_clocks;
		grant = 1; tick(12);
		check(dma_clocks - before_dma == 4, "paired DMA is four CKI states");
	end
	wait_sleep();
	// The two frame interrupts, as the CPU took them: IFRM has priority.
	check(mem[LOG] == 13 && mem[LOG+1] == 14 && mem[LOG+2] == 0, "input frame interrupt precedes output frame");
	rdw(32'h5003f000, v); rdw(mmio(8'h02), v2);
	check(v[7:0] == 8'ha5 && v2 == 32'hdeadbeef, "paired DMA data");
	// Reload mode double-buffers the NEXT pointer/count while a frame runs.
	restart(); wr(8'h03, 32'h00010040); // 8-bit MSB input, 32-bit DMA
	wr(8'h08, 32'h5003f000); wr(8'h0a, 0); wr(8'h0c, 32'h70);
	wr(8'h08, 32'h5003f010); wr(8'h0a, 4);
	rdw(mmio(8'h08), v); rdw(mmio(8'h0A), v2);
	check(v == 32'h5003f000 && v2 == 0, "DMA reload writes next registers");
	receive_word(32'ha5, 8, 1); tick(16);
	rdw(mmio(8'h08), v); rdw(mmio(8'h0A), v2);
	check(v == 32'h5003f010 && v2 == 4, "input DMA reload at frame end");
	rdw(mmio(8'h0C), v); check(v[5], "input DMA stays enabled on reload");
	receive_word(32'h5a, 8, 1); receive_word(32'h3c, 8, 1); tick(16);
	rdw(32'h5003f010, v); rdw(32'h5003f014, v2);
	check(v[7:0] == 8'h5a && v2[7:0] == 8'h3c, "reloaded DMA frame data");
	wr(8'h0c, 32'h10);
	rdw(mmio(8'h0C), v); check(v[6:5] == 2'b00, "input DMA disabled by ICS write");
	// Bus-ownership mode requests ownership without stalling the sleeping CPU.
	restart(); grant = 0; mem[EXT_BUF >> 2] = 32'h12345678;
	wr(8'h09, EXT_BUF); wr(8'h0b, 0); wr(8'h0c, 11); tick(24);
	ps_bit(PS_OBE, f); rdw(mmio(8'h02), v);
	check(dma_request && f && v != 32'h12345678, "DMA waits for ownership in ORB mode");
	grant = 1; tick(40);
	ps_bit(PS_OBE, f); rdw(mmio(8'h02), v);
	check(!f && v == 32'h12345678, "DMA resumes on grant");
	// A bus fault disables the channel so it cannot monopolize the CPU; the
	// CPU takes the bus error (vector 1), not an OFRM.
	restart(); set_emr(EMR_OFRM);
	wr(8'h09, 32'h80000000); wr(8'h0b, 0); wr(8'h0c, 3); tick(40);
	wait_sleep();
	rdw(mmio(8'h0C), v); ps_bit(PS_OBE, f);
	check(!v[1] && f, "failed DMA disables its channel");
	check(mem[LOG] == 1 && mem[LOG+1] == 0, "failed DMA is a bus error, not a completed frame");
	// Timer output mux, pulse polarities, toggle, and both external edges.
	restart(); wr(8'h06, 2); wr(8'h05, 2); wr(8'h04, 8'h99); // BIO0 rising, active high
	bio_in[0] = 1; tick(2); bio_in[0] = 0; tick(2);
	check(!bio_out[1], "timer idle low");
	rdw(mmio(8'h05), v); check(v == 1, "timer first external tick");
	bio_in[0] = 1; tick(); check(bio_out[1], "timer active high pulse");
	tick(); check(!bio_out[1], "timer pulse is one CKI");
	rdw(mmio(8'h05), v); check(v == 0, "timer count reaches zero");
	wr(8'h04, 8'h91); check(bio_out[1], "timer active low idle");
	wr(8'h05, 1); bio_in[0] = 0; tick(2); bio_in[0] = 1; tick();
	check(!bio_out[1], "timer active low pulse"); tick(); check(bio_out[1], "timer active low recovery");
	wr(8'h05, 1); wr(8'h04, 8'hb5); // falling, toggle
	check(!bio_out[1], "timer toggle output after two terminal counts");
	bio_in[0] = 0; tick(2);
	check(bio_out[1], "timer toggle output after three terminal counts");
	rdw(mmio(8'h05), v); check(v == 0, "timer falling edge source");
	// BIO1's own register (set through the bio pair write) when the timer lets go
	cpu(OP_SH, 32'h5003041e, 32'h0008, v); check(bio_out[1], "timer still drives BIO1");
	cpu(OP_SH, 32'h5003041e, 32'h0004, v); check(bio_out[1], "timer still drives BIO1");
	wr(8'h04, 0); check(!bio_out[1], "BIO1 software output restored (clear)");
	cpu(OP_SH, 32'h5003041e, 32'h0008, v); check(bio_out[1], "BIO1 software output restored (set)");
	cpu(OP_LH, 32'h5003041e, 0, v); check(v[3:2] == 2'b11, "BIO1 register and pin read back");
	// Internal SIO clock division and direction enables.
	restart(); wr(8'h03, 32'h00100331);
	check(ick_oe && ock_oe && ild_oe && old_oe && sy_oe, "internal serial pin directions");
	begin
		automatic integer edges = 0;
		automatic bit last_clk = ick_out;
		repeat (80) begin tick(); if (ick_out && !last_clk) edges++; last_clk = ick_out; end
		check(edges == 20, "internal serial clock CKI/4");
	end
	// Frame-boundary flag follows the first full OBUF after external SY,
	// and SAN clears it. These are the flags tested by CAU SY/FB conditions.
	restart(); wr(8'h03, 0);
	ps_bit(PS_SY, f); check(f, "SY flag follows the SY pin (high)");
	sy = 0; input_bit(0);
	ps_bit(PS_SY, f); check(!f, "SY flag follows the SY pin (low)");
	ps_bit(PS_FB, f); check(!f, "no frame boundary while OBUF is empty");
	wr(8'h02, 32'ha5);
	ps_bit(PS_FB, f); check(f, "frame boundary flag");
	wr(8'h03, 32'h8000);
	ps_bit(PS_FB, f); check(!f, "SAN clears frame boundary");
	sy = 1;
	$display("tb_peripherals PASS (%0d CPU commands)", commands); $finish;
end
initial begin #50000000; $fatal(1, "peripheral test timeout"); end
endmodule
