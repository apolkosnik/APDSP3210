// DSP3210 serial port and clock generator (Information Manual, section 9.1).
// Pins are sampled on ce (CKI). Bidirectional pins have separate input,
// output and output-enable signals; connect them through the board's I/O cells.
module a3kp_dsp_sio (
	input clk, ce, reset,
	input [31:0] ioc, obuf,
	input obe,
	input di, ick_in, ild_in, ock_in, old_in, sy_in,
	output reg dout = 1'b0,
	output ick_out, ild_out, ock_out, old_out, sy_out,
	output ick_oe, ild_oe, ock_oe, old_oe, sy_oe,
	output rx_valid, tx_take,
	output [31:0] rx_data,
	output sy, fb
);
reg intclk = 1'b0;
reg [4:0] divider = 5'd0;
reg [4:0] bitcount = 5'd0, framecount = 5'd0;
reg ick_d = 1'b0, ock_d = 1'b0, source_d = 1'b0;
reg ild_d = 1'b1, old_d = 1'b1, sy_d = 1'b1;
reg [31:0] isr = 32'd0, osr = 32'd0;
reg [5:0] ileft = 6'd0, oleft = 6'd0;
reg fb_armed = 1'b0;
wire ick = ioc[4] ? intclk : ick_in;
wire ock = ioc[8] ? intclk : ock_in;
wire source_clk = ioc[1] ? ock : (ick ^ ioc[14]);
wire input_clk = ick ^ ioc[14];
wire input_edge = input_clk && !ick_d;
wire output_edge = ock && !ock_d;
wire source_edge = source_clk && !source_d;
wire intload = bitcount[4];
wire intsy = ioc[3:2] == 2'd1 ? framecount[2] :
             ioc[3:2] == 2'd2 ? framecount[3] : framecount[4];
wire ild = ioc[5] ? intload : ild_in;
wire burst_load = obe || (oleft != 6'd0);
wire old = ioc[9] ? (ioc[13] ? burst_load : intload) : old_in;
wire iload = ild_d && !ild;
wire oload = old_d && !old;
wire [5:0] ilen = ioc[7:6] == 2'd1 ? 6'd8 : ioc[7:6] == 2'd2 ? 6'd16 : 6'd32;
wire [5:0] olen = ioc[12:10] == 3'd1 ? 6'd8 : ioc[12:10] == 3'd2 ? 6'd16 :
                         ioc[12:10] == 3'd4 ? 6'd24 : 6'd32;
wire [31:0] shifted_in = ioc[16] ? {isr[30:0], di} : {di, isr[31:1]};
// Figure 9-3: ILEN=00 samples the last bit on the edge detecting ILD low.
// Other lengths sample their first bit on the NEXT input clock edge.
assign rx_valid = input_edge && ((ioc[7:6] == 2'd0 && iload) ||
                  (ioc[7:6] != 2'd0 && ileft == 6'd1));
assign rx_data = shifted_in;
assign tx_take = output_edge && oload;
assign ick_out = intclk;
assign ock_out = intclk;
assign ild_out = intload;
assign old_out = ioc[13] ? burst_load : intload;
assign sy_out = intsy;
assign ick_oe = ioc[4];
assign ild_oe = ioc[5];
assign ock_oe = ioc[8];
assign old_oe = ioc[9];
assign sy_oe = ioc[0];
assign sy = ioc[0] ? intsy : sy_in;
assign fb = fb_armed && !ioc[15] && !obe;

always @(posedge clk) begin
	if (reset) begin
		intclk <= 1'b0; divider <= 5'd0;
		bitcount <= 5'd0; framecount <= 5'd0;
		ick_d <= 1'b0; ock_d <= 1'b0; source_d <= 1'b0;
		ild_d <= 1'b1; old_d <= 1'b1; sy_d <= 1'b1;
		isr <= 32'd0; osr <= 32'd0;
		ileft <= 6'd0; oleft <= 6'd0; dout <= 1'b0; fb_armed <= 1'b0;
	end
	else if (ce) begin
		if (ioc[23:20] == 4'd0) begin intclk <= 1'b0; divider <= 5'd0; end
		else if (divider == {ioc[23:20], 1'b0} - 1'b1) begin
			divider <= 5'd0; intclk <= ~intclk;
		end
		else divider <= divider + 1'b1;
		ick_d <= input_clk; ock_d <= ock; source_d <= source_clk;
		if (ioc[15]) fb_armed <= 1'b0;
		if (source_edge) begin
			sy_d <= sy;
			bitcount <= bitcount + 1'b1;
			if (bitcount == 5'd31) begin
				if (framecount == (ioc[3:2] == 2'd1 ? 5'd7 : ioc[3:2] == 2'd2 ? 5'd15 : 5'd31))
					framecount <= 5'd0;
				else framecount <= framecount + 1'b1;
			end
			if (sy_d && !sy) begin
				if (!ioc[0]) begin bitcount <= 5'd0; framecount <= 5'd0; end
				if (!ioc[15]) fb_armed <= 1'b1;
			end
		end
		if (input_edge) begin
			ild_d <= ild;
			isr <= shifted_in;
			if (iload && ioc[7:6] != 2'd0) ileft <= ilen;
			else if (ileft != 6'd0) ileft <= ileft - 1'b1;
		end
		if (output_edge) begin
			old_d <= old;
			if (oload) begin
				dout <= ioc[17] ? obuf[olen - 1'b1] : obuf[0];
				osr <= ioc[17] ? obuf << 1 : obuf >> 1;
				oleft <= olen - 1'b1;
			end
			else if (oleft != 6'd0) begin
				dout <= ioc[17] ? osr[olen - 1'b1] : osr[0];
				osr <= ioc[17] ? osr << 1 : osr >> 1;
				oleft <= oleft - 1'b1;
			end
		end
	end
end
endmodule
