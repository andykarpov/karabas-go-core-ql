`timescale 1ns / 1ps
`default_nettype wire

/*
 ql_adc.v

 The receiver of the PCM1808 ADC (I2S, the ADC a slave): only the top 16 bits of each sample.
 From clk (32 MHz): bck = clk / 16 (2 MHz), lrck = clk / 1024 (31.25 kHz), the 8 MHz of SCKI being
 256 fs. lrck changes on a falling bck; the top bit is taken at the second rising bck after it.
*/

module ql_adc (
	input wire clk,
	input wire sd,
	output wire bck,
	output wire lrck,
	output reg [15:0] l = 16'd0,
	output reg [15:0] r = 16'd0
);

reg [9:0] c = 10'd0;
assign bck = c[3];
assign lrck = c[9];

wire [4:0] b = c[8:4];      // the bit period of the half frame
reg [15:0] sh = 16'd0;

always @(posedge clk) begin
	c <= c + 10'd1;
	if (c[3:0] == 4'd8) begin
		if (b >= 5'd1 && b <= 5'd16)
			sh <= { sh[14:0], sd };
		if (b == 5'd17) begin
			if (lrck)
				r <= sh;
			else
				l <= sh;
		end
	end
end

endmodule
