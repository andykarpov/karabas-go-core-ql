`timescale 1ns / 1ps
`default_nettype wire

/*
 ql_keyboard.v

 The QL keyboard matrix from the PS/2 scancodes (set 2) of the USB keyboard, which kg_mcu hands
 over: kb_scancode, each new byte toggles kb_scancode_upd. The table, the special keys and their
 delay are those of keyboard.v (Till Harbaum, MiST; GPL v3); one clock, no PS/2 receiver.

 Matrix (a row is a bit of P1 of the IPC 8049):
         0      1      2      3      4      5      6      7
 0|     F4     F1      5     F2     F3     F5      4      7
 1|    Ret   Left     Up    Esc  Right      \  Space   Down
 2|      ]      z      .      c      b  Pound      m      '
 3|      [   Caps      k      s      f      =      g      ;
 4|      l      3      h      1      a      p      d      j
 5|      9      w      i    Tab      r      -      y      o
 6|      8      2      6      q      e      0      t      u
 7|  Shift   Ctrl    Alt      x      v      /      n      ,
*/

module ql_keyboard (
	input wire clk,          // 32.5 MHz
	input wire reset,

	input wire [7:0] scancode,
	input wire scancode_upd,

	input wire [4:0] js0,    // F-keys joystick: right, left, down, up, fire
	input wire [4:0] js1,    // cursor joystick

	output wire [63:0] matrix
);

reg [63:0] ql_matrix = 64'd0;
reg [11:0] special = 12'd0;   // keys that also press a modifier

// the main key of such a combination comes about 1.4 ms after its modifier, or the QL misses it:
// a tick of about 95 us, 15 ticks
reg [11:0] tick_cnt = 12'd0;
wire tick = (tick_cnt == 12'd3071);
always @(posedge clk)
	tick_cnt <= tick ? 12'd0 : tick_cnt + 12'd1;

reg [3:0] delay_cnt [1:11];
reg [11:1] special_d = 11'd0;
integer i;
initial for (i = 1; i <= 11; i = i + 1) delay_cnt[i] = 4'd0;

always @(posedge clk) begin
	for (i = 1; i <= 11; i = i + 1) begin
		if (reset || !special[i])
			delay_cnt[i] <= 4'd0;
		else if (tick && delay_cnt[i] != 4'd15)
			delay_cnt[i] <= delay_cnt[i] + 4'd1;
		special_d[i] <= (delay_cnt[i] == 4'd15);
	end
end

wire x_shift = special[0] || special[3] || special[4] || special[7] ||
               special[8] || special[9] || special[10] || special[11];
wire x_ctrl  = special[1] || special[2];
wire x_alt   = special[5] || special[6];

wire x_left  = special_d[1] || special_d[5] || js1[1];
wire x_right = special_d[2] || special_d[6] || js1[0];
wire x_up    = special_d[3] || js1[3];
wire x_down  = special_d[4] || js1[2];
wire x_space = js1[4];

wire x_f1 = special_d[7]  || js0[1];
wire x_f2 = special_d[8]  || js0[2];
wire x_f3 = special_d[9]  || js0[0];
wire x_f4 = special_d[10] || js0[3];
wire x_f5 = special_d[11] || js0[4];

wire [63:0] special_matrix = {
	5'b00000, x_alt, x_ctrl, x_shift,
	8'b00000000,
	8'b00000000,
	8'b00000000,
	8'b00000000,
	8'b00000000,
	x_down, x_space, 1'b0, x_right, 1'b0, x_up, x_left, 1'b0,
	2'b00, x_f5, x_f3, x_f2, 1'b0, x_f1, x_f4
};

assign matrix = ql_matrix | special_matrix;

reg upd_d = 1'b0;
reg released = 1'b0;
wire make = !released;

always @(posedge clk) begin
	upd_d <= scancode_upd;
	if (reset) begin
		released <= 1'b0;
		ql_matrix <= 64'd0;
		special <= 12'd0;
	end
	else if (scancode_upd != upd_d) begin
		if (scancode == 8'hE0)
			;   // an extended code is treated as the plain one
		else if (scancode == 8'hF0)
			released <= 1'b1;
		else begin
			released <= 1'b0;
			case (scancode)
			// modifiers
			8'h12: ql_matrix[8*7+0] <= make; // SHIFT
			8'h14: ql_matrix[8*7+1] <= make; // CTRL
			8'h11: ql_matrix[8*7+2] <= make; // ALT
			// function keys
			8'h05: ql_matrix[8*0+1] <= make; // F1
			8'h06: ql_matrix[8*0+3] <= make; // F2
			8'h04: ql_matrix[8*0+4] <= make; // F3
			8'h0c: ql_matrix[8*0+0] <= make; // F4
			8'h03: ql_matrix[8*0+5] <= make; // F5
			// cursor
			8'h75: ql_matrix[8*1+2] <= make; // Up
			8'h72: ql_matrix[8*1+7] <= make; // Down
			8'h6b: ql_matrix[8*1+1] <= make; // Left
			8'h74: ql_matrix[8*1+4] <= make; // Right

			8'h1c: ql_matrix[8*4+4] <= make; // a
			8'h32: ql_matrix[8*2+4] <= make; // b
			8'h21: ql_matrix[8*2+3] <= make; // c
			8'h23: ql_matrix[8*4+6] <= make; // d
			8'h24: ql_matrix[8*6+4] <= make; // e
			8'h2b: ql_matrix[8*3+4] <= make; // f
			8'h34: ql_matrix[8*3+6] <= make; // g
			8'h33: ql_matrix[8*4+2] <= make; // h
			8'h43: ql_matrix[8*5+2] <= make; // i
			8'h3b: ql_matrix[8*4+7] <= make; // j
			8'h42: ql_matrix[8*3+2] <= make; // k
			8'h4b: ql_matrix[8*4+0] <= make; // l
			8'h3a: ql_matrix[8*2+6] <= make; // m
			8'h31: ql_matrix[8*7+6] <= make; // n
			8'h44: ql_matrix[8*5+7] <= make; // o
			8'h4d: ql_matrix[8*4+5] <= make; // p
			8'h15: ql_matrix[8*6+3] <= make; // q
			8'h2d: ql_matrix[8*5+4] <= make; // r
			8'h1b: ql_matrix[8*3+3] <= make; // s
			8'h2c: ql_matrix[8*6+6] <= make; // t
			8'h3c: ql_matrix[8*6+7] <= make; // u
			8'h2a: ql_matrix[8*7+4] <= make; // v
			8'h1d: ql_matrix[8*5+1] <= make; // w
			8'h22: ql_matrix[8*7+3] <= make; // x
			8'h35: ql_matrix[8*5+6] <= make; // y
			8'h1a: ql_matrix[8*2+1] <= make; // z

			8'h45: ql_matrix[8*6+5] <= make; // 0
			8'h16: ql_matrix[8*4+3] <= make; // 1
			8'h1e: ql_matrix[8*6+1] <= make; // 2
			8'h26: ql_matrix[8*4+1] <= make; // 3
			8'h25: ql_matrix[8*0+6] <= make; // 4
			8'h2e: ql_matrix[8*0+2] <= make; // 5
			8'h36: ql_matrix[8*6+2] <= make; // 6
			8'h3d: ql_matrix[8*0+7] <= make; // 7
			8'h3e: ql_matrix[8*6+0] <= make; // 8
			8'h46: ql_matrix[8*5+0] <= make; // 9

			8'h5a: ql_matrix[8*1+0] <= make; // Enter
			8'h29: ql_matrix[8*1+6] <= make; // Space
			8'h0d: ql_matrix[8*5+3] <= make; // Tab
			8'h76: ql_matrix[8*1+3] <= make; // Esc
			8'h58: ql_matrix[8*3+1] <= make; // Caps

			8'h4e: ql_matrix[8*5+5] <= make; // -
			8'h55: ql_matrix[8*3+5] <= make; // =
			8'h61: ql_matrix[8*2+5] <= make; // Pound
			8'h5d: ql_matrix[8*1+5] <= make; // backslash
			8'h54: ql_matrix[8*3+0] <= make; // [
			8'h5b: ql_matrix[8*2+0] <= make; // ]
			8'h4c: ql_matrix[8*3+7] <= make; // ;
			8'h52: ql_matrix[8*2+7] <= make; // '
			8'h41: ql_matrix[8*7+7] <= make; // ,
			8'h49: ql_matrix[8*2+2] <= make; // .
			8'h4a: ql_matrix[8*7+5] <= make; // /

			// keys that include a modifier
			8'h59: special[0]  <= make; // right SHIFT
			8'h66: special[1]  <= make; // Backspace -> CTRL+LEFT
			8'h71: special[2]  <= make; // Delete -> CTRL+RIGHT
			8'h7d: special[3]  <= make; // PageUp -> SHIFT+UP
			8'h7a: special[4]  <= make; // PageDown -> SHIFT+DOWN
			8'h6c: special[5]  <= make; // Home -> ALT+LEFT
			8'h69: special[6]  <= make; // End -> ALT+RIGHT
			8'h0b: special[7]  <= make; // F6 -> SHIFT+F1
			8'h83: special[8]  <= make; // F7 -> SHIFT+F2
			8'h0a: special[9]  <= make; // F8 -> SHIFT+F3
			8'h01: special[10] <= make; // F9 -> SHIFT+F4
			8'h09: special[11] <= make; // F10 -> SHIFT+F5
			default: ;
			endcase
		end
	end
end

endmodule
