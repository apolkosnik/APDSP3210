// The DSP3210 bench: the real core (a3kp_dsp3210) on an external memory of
// 1 MB at 0x00000000 (big-endian, the core's bus handshake answered after
// `waits` clocks), bus errors at 0x40000000 and up; the bench (sim_dsp.cpp)
// loads the program, drives the interrupt pins and reads the memory back.
module tb_dsp
#(parameter bit ENABLE_LITTLE_ENDIAN = 1'b0, parameter bit ENABLE_DOBLOCK = 1'b0)
(
	input             clk,
	input             reset,
	input             ce,
	input       [3:0] waits,
	input             ir0_n,
	input             ir1_n,
	input       [7:0] bio_in,
	output            iack0,
	output            iack1,
	output     [31:0] pc,
	output            retire,
	output            halted,
	output            hold
);

wire        m_req, m_we, m_berr;
reg         m_ack = 1'b0;
wire [31:2] m_addr;
wire  [3:0] m_be;
wire [31:0] m_wdata;
reg  [31:0] m_rdata;
reg         berr_r = 1'b0;
wire [7:0]  bio_out, bio_oe;
wire m_block, m_block_first, m_lock;
reg [31:0] block_groups /*verilator public_flat_rw*/ = 0;
reg [31:0] block_words /*verilator public_flat_rw*/ = 0;
reg [2:0] block_left = 0;
reg [31:2] block_next;
reg block_write;

a3kp_dsp3210 #(.ENABLE_LITTLE_ENDIAN(ENABLE_LITTLE_ENDIAN), .ENABLE_DOBLOCK(ENABLE_DOBLOCK)) dsp
(
	.clk(clk), .ce(ce), .reset(reset),
	.m_req(m_req), .m_ack(m_ack), .m_addr(m_addr), .m_be(m_be), .m_we(m_we),
	.m_wdata(m_wdata), .m_rdata(m_rdata), .m_berr(berr_r), .m_hold(hold),
	.m_block(m_block), .m_block_first(m_block_first), .m_lock(m_lock),
	.m_grant(1'b1), .m_dma_request(),
	.ir0_n(ir0_n), .ir1_n(ir1_n), .iack0(iack0), .iack1(iack1),
	.sio_di(1'b0), .sio_ick_in(1'b1), .sio_ild_in(1'b1),
	.sio_ock_in(1'b1), .sio_old_in(1'b1), .sio_sy_in(1'b1),
	.sio_do(), .sio_ick_out(), .sio_ild_out(), .sio_ock_out(), .sio_old_out(), .sio_sy_out(),
	.sio_ick_oe(), .sio_ild_oe(), .sio_ock_oe(), .sio_old_oe(), .sio_sy_oe(),
	.bio_in(bio_in), .bio_out(bio_out), .bio_oe(bio_oe),
	.dbg_pc(pc), .dbg_retire(retire), .dbg_halted(halted)
);

reg [31:0] mem [0:262143] /*verilator public_flat_rw*/;
reg  [3:0] wcnt = 4'd0;
reg        busy = 1'b0;

always @(posedge clk) begin
	if (reset) begin
		busy <= 1'b0;
		m_ack <= m_req;
	end
	else if (!busy && m_req != m_ack) begin
		if (m_block) begin
			block_words <= block_words + 1;
			if (!m_lock) $fatal(1, "block transfer without lock");
			if (m_block_first) begin
				if (block_left != 0 || m_addr[3:2] != 0) $fatal(1, "bad quad-word start");
				block_groups <= block_groups + 1;
				block_left <= 3; block_next <= m_addr + 1; block_write <= m_we;
			end
			else begin
				if (block_left == 0 || m_addr != block_next || m_we != block_write)
					$fatal(1, "nonconsecutive quad-word transfer: %08x expected %08x left %0d write %0d expected %0d", {m_addr,2'b00}, {block_next,2'b00}, block_left, m_we, block_write);
				block_left <= block_left - 1; block_next <= m_addr + 1;
			end
		end
		else if (block_left != 0) $fatal(1, "quad-word interrupted by unrelated access");
		busy <= 1'b1;
		wcnt <= waits;
	end
	else if (busy) begin
		if (wcnt != 4'd0) wcnt <= wcnt - 1'd1;
		else begin
			busy   <= 1'b0;
			berr_r <= m_addr[31:30] != 2'b00;
			if (m_addr[31:30] == 2'b00) begin
				m_rdata <= mem[m_addr[19:2]];
				if (m_we) for (int b = 0; b < 4; b++)
					if (m_be[3 - b]) mem[m_addr[19:2]][31 - 8*b -: 8] <= m_wdata[31 - 8*b -: 8];
			end
			else m_rdata <= 32'hFFFFFFFF;
			m_ack <= m_req;
		end
	end
end

assign m_berr = berr_r;

endmodule
