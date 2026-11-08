`timescale 1ns / 1ps
`default_nettype wire

/*
 ql_audio.v

 The sound of the machine as signed samples without DC: the beeper and the AY of ql.v are unsigned
 and the idle level of the beeper line is constant, which would show on the level meters of the
 mcu and shift the DAC. A one-pole high pass of about 30 Hz at the rate of ce (48 kHz): a slow
 average of the input is subtracted from it.
*/

module ql_audio (
	input wire clk,
	input wire ce,                  // 48 kHz

	input wire [15:0] in_l,         // unsigned
	input wire [15:0] in_r,

	output reg signed [15:0] out_l = 16'd0,
	output reg signed [15:0] out_r = 16'd0
);

// 16 bits of average + 8 of fraction
reg [23:0] avg_l = 24'd0;
reg [23:0] avg_r = 24'd0;

// halved, so that the difference fits in 16 signed bits
wire [14:0] h_l = in_l[15:1];
wire [14:0] h_r = in_r[15:1];

wire [15:0] mean_l = avg_l[23:8];
wire [15:0] mean_r = avg_r[23:8];

always @(posedge clk)
	if (ce) begin
		avg_l <= avg_l + { 9'd0, h_l } - { 8'd0, mean_l };
		avg_r <= avg_r + { 9'd0, h_r } - { 8'd0, mean_r };
		out_l <= { 1'b0, h_l } - mean_l;
		out_r <= { 1'b0, h_r } - mean_r;
	end

endmodule
