`timescale 1ns / 1ps
`default_nettype wire

/*
 ql_rtc.v

 The clock of the board for the QL (registers of a DS1307 in the RAM of kg_mcu_rtc, rtc_mode 1):
 - after a reset, the time goes into the ZX8302 counter as seconds since 1961-01-01 (the QL has no
   clock that survives a power off, so without this it would start at 1961);
 - the DS1307 of the Next core on the registers $800021 (data) and $800023 (control / status) as
   its I2C master looks to the CPU: a byte takes 90 us (busy); while ena stays up the next byte
   follows. After ena comes up the first byte written is the register pointer.
*/

module ql_rtc (
	input wire clk,
	input wire reset,

	// the registers of the mcu: rtc_a -> rtc_do a clock later
	output wire [7:0] rtc_a,
	input wire [7:0] rtc_do,
	output reg [7:0] rtc_di = 8'd0,
	output reg rtc_wr = 1'b0,

	// the ZX8302
	output reg rtc_load = 1'b0,
	output reg [31:0] rtc_value = 32'd0,

	// the CPU
	input wire wr_data,
	input wire wr_ctrl,
	input wire [7:0] cpu_d,
	output reg [7:0] i2c_din = 8'd0,
	output wire i2c_busy
);

function [7:0] bcd(input [7:0] v);
	bcd = { 4'd0, v[3:0] } + { 1'b0, v[7:4], 3'd0 } + { 3'd0, v[7:4], 1'b0 };
endfunction

// ------------------------------------------------------------------- the time, once after a reset

reg [3:0] st = 4'd0;
reg [2:0] idx = 3'd0;
reg reset_d = 1'b1;
reg [7:0] t_s = 0, t_m = 0, t_h = 0, t_d = 0, t_mo = 0, t_y = 0;
reg [16:0] days = 17'd0;

localparam S_IDLE = 0, S_ADDR = 1, S_READ = 2, S_DAYS = 3, S_HOURS = 4, S_MIN = 5, S_SEC = 6, S_LOAD = 7;

reg [9:0] mdays;
always @* case (t_mo)
	8'd1:  mdays = 10'd0;
	8'd2:  mdays = 10'd31;
	8'd3:  mdays = 10'd59;
	8'd4:  mdays = 10'd90;
	8'd5:  mdays = 10'd120;
	8'd6:  mdays = 10'd151;
	8'd7:  mdays = 10'd181;
	8'd8:  mdays = 10'd212;
	8'd9:  mdays = 10'd243;
	8'd10: mdays = 10'd273;
	8'd11: mdays = 10'd304;
	default: mdays = 10'd334;
endcase

// the years from 1961 to 2000 + y
wire [7:0] years = t_y + 8'd39;
wire [16:0] y_days = { 1'b0, years, 8'd0 } + { 3'd0, years, 6'd0 } + { 4'd0, years, 5'd0 } +
                     { 6'd0, years, 3'd0 } + { 7'd0, years, 2'd0 } + { 9'd0, years };
// leap days before 2000 + y since 1961: (1999 + y) / 4 - 490
wire [10:0] y_full = 11'd1999 + { 3'd0, t_y };
wire [8:0] leaps = y_full[10:2] - 9'd490;
wire leap_now = (t_mo > 8'd2) && (t_y[1:0] == 2'd0);

wire [31:0] v60 = { rtc_value[25:0], 6'd0 } - { rtc_value[29:0], 2'd0 };   // * 60

// ------------------------------------------------------------------- the I2C of the Next core

reg [7:0] ptr = 8'd0;
reg [7:0] i2c_dout = 8'd0;
reg ena = 1'b0, rw = 1'b1;
reg first = 1'b1;
reg [11:0] busy_cnt = 12'd0;
reg [7:0] gap = 8'd0;
wire busy = (busy_cnt != 12'd0);
assign i2c_busy = busy;
reg op_rw = 1'b1;

assign rtc_a = (st != S_IDLE) ? { 5'd0, idx } : ptr;

always @(posedge clk) begin
	reset_d <= reset;
	rtc_load <= 1'b0;
	rtc_wr <= 1'b0;

	case (st)
	S_IDLE:
		if (reset_d && !reset) begin
			idx <= 3'd0;
			st <= S_ADDR;
		end
	S_ADDR:
		st <= S_READ;     // the RAM answers a clock later
	S_READ: begin
		case (idx)
			3'd0: t_s <= bcd({ 1'b0, rtc_do[6:0] });
			3'd1: t_m <= bcd(rtc_do);
			3'd2: t_h <= bcd({ 2'b00, rtc_do[5:0] });
			3'd4: t_d <= bcd(rtc_do);
			3'd5: t_mo <= bcd({ 3'b000, rtc_do[4:0] });
			3'd6: t_y <= bcd(rtc_do);
			default: ;
		endcase
		if (idx == 3'd6)
			st <= S_DAYS;
		else begin
			idx <= idx + 3'd1;
			st <= S_ADDR;
		end
	end
	S_DAYS: begin
		days <= y_days + { 8'd0, leaps } + { 7'd0, mdays } + { 16'd0, leap_now } + { 9'd0, t_d } - 17'd1;
		st <= (t_mo == 8'd0 || t_mo > 8'd12) ? S_IDLE : S_HOURS;   // the mcu gave no date
	end
	S_HOURS: begin
		rtc_value <= { 11'd0, days, 4'd0 } + { 12'd0, days, 3'd0 } + { 24'd0, t_h };   // * 24
		st <= S_MIN;
	end
	S_MIN: begin
		rtc_value <= v60 + { 24'd0, t_m };
		st <= S_SEC;
	end
	S_SEC: begin
		rtc_value <= v60 + { 24'd0, t_s };
		st <= S_LOAD;
	end
	S_LOAD: begin
		rtc_load <= 1'b1;
		st <= S_IDLE;
	end
	default: st <= S_IDLE;
	endcase

	// the registers of the master
	if (wr_data)
		i2c_dout <= cpu_d;
	if (wr_ctrl) begin
		ena <= cpu_d[0];
		rw <= cpu_d[1];
	end
	if (!ena)
		first <= 1'b1;

	if (busy_cnt != 12'd0) begin
		busy_cnt <= busy_cnt - 12'd1;
		if (busy_cnt == 12'd1) begin
			// the end of a byte
			if (op_rw) begin
				i2c_din <= rtc_do;
				ptr <= ptr + 8'd1;
			end
			else if (first) begin
				ptr <= i2c_dout;
				first <= 1'b0;
			end
			else begin
				rtc_di <= i2c_dout;
				rtc_wr <= 1'b1;
				ptr <= ptr;
			end
			gap <= 8'd100;
		end
	end
	else if (gap != 8'd0)
		gap <= gap - 8'd1;
	else if (ena && st == S_IDLE) begin
		busy_cnt <= 12'd2925;
		op_rw <= rw;
	end

	// a write takes effect, then the pointer moves
	if (rtc_wr)
		ptr <= ptr + 8'd1;

	if (reset) begin
		ena <= 1'b0;
		busy_cnt <= 12'd0;
		gap <= 8'd0;
	end
end

endmodule
