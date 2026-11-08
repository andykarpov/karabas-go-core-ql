`timescale 1ns / 1ps
`default_nettype wire

/*
 ql_video.v

 The picture of the QL for a 1024 x 768 @ 60 output, one process on clk (32.5 MHz): a clock is a
 column of two output pixels, so the 512 columns of the QL fill the 1024 of the mode; each line
 of the QL is shown three times (768 = 3 * 256). Replaces qlvideo.vhd + qlvideo256.vhd of the
 Next core (both clock edges and shared variables, which XST does not take); the colour logic of
 the four modes is theirs:
 - mode 4 (mode = 0): 512 x 256, 4 colours, with the palette tweaks of params[14:9];
 - mode 8 (mode = 1): 256 x 256, 8 colours + flash, or 16 colours with col16;
 - col256: 8 bits per pixel, the 64 KB of the VRAM as one screen.

 vaddr goes straight to port B of the VRAM (read latency one clock); the outputs and the
 syncs are registered and two clocks behind h / v.
*/

module ql_video (
	input wire clk,
	input wire reset,

	output wire [14:0] vaddr,
	input wire [15:0] vdin,

	input wire mode,
	input wire membase,
	input wire blank,
	input wire col16,
	input wire col256,
	input wire [5:0] palette,

	output reg [2:0] r = 3'd0,
	output reg [2:0] g = 3'd0,
	output reg [2:0] b = 3'd0,
	output reg hs = 1'b1,
	output reg vs = 1'b1,
	output reg de = 1'b0
);

// VESA 1024 x 768 @ 60 in clocks of two pixels
localparam H_SYNC = 10'd68, H_START = 10'd148, H_END = 10'd660, H_TOTAL = 10'd672;
localparam V_SYNC = 10'd6, V_START = 10'd35, V_END = 10'd803, V_TOTAL = 10'd806;

reg [9:0] h = 10'd0;
reg [9:0] v = 10'd0;
reg [8:0] ln = 9'd0;     // line of the QL (0..255) inside the window
reg [1:0] ln3 = 2'd0;    // the three output lines of it
reg [6:0] fcnt = 7'd0;   // frames, for the flash

wire h_active = h >= H_START && h < H_END;
wire v_active = v >= V_START && v < V_END;
wire active = h_active && v_active;
wire [9:0] hx = h - H_START;
wire [8:0] px = hx[8:0];

always @(posedge clk) begin
	if (reset) begin
		h <= 10'd0;
		v <= 10'd0;
		ln <= 9'd0;
		ln3 <= 2'd0;
	end
	else if (h == H_TOTAL - 10'd1) begin
		h <= 10'd0;
		if (v == V_TOTAL - 10'd1) begin
			v <= 10'd0;
			fcnt <= fcnt + 7'd1;
		end
		else
			v <= v + 10'd1;
		if (v == V_START - 10'd1) begin
			ln <= 9'd0;
			ln3 <= 2'd0;
		end
		else if (v_active) begin
			if (ln3 == 2'd2) begin
				ln3 <= 2'd0;
				ln <= ln + 9'd1;
			end
			else
				ln3 <= ln3 + 2'd1;
		end
	end
	else
		h <= h + 10'd1;
end

assign vaddr = col256 ? { ln[7:0], px[8:2] } : { membase, ln[7:0], px[8:3] };

// a clock behind h: the word on vdin is the one of this column
reg [8:0] px_d = 9'd0;
reg active_d = 1'b0, hs_d = 1'b1, vs_d = 1'b1;

reg fon = 1'b0, fr = 1'b0, fg = 1'b0, fb = 1'b0;

wire [1:0] p4 = px_d[2:1];
wire [2:0] i8 = px_d[2:0];
wire flash = vdin[14 - 2 * p4];
wire bb8 = vdin[6 - 2 * p4];
wire gg8 = vdin[15 - 2 * p4];
wire rr8 = vdin[7 - 2 * p4];
wire gg4 = vdin[15 - i8];
wire rr4 = vdin[7 - i8];

reg [7:0] d256;
always @* begin
	if (mode)
		d256 = px_d[1] ? vdin[7:0] : vdin[15:8];
	else case (px_d[1:0])
		2'd0: d256 = { vdin[14], vdin[15], 1'b0, vdin[13], vdin[15], 1'b0, vdin[12], vdin[15] };
		2'd1: d256 = { vdin[10], vdin[11], 1'b0, vdin[9], vdin[11], 1'b0, vdin[8], vdin[11] };
		2'd2: d256 = { vdin[6], vdin[7], 1'b0, vdin[5], vdin[7], 1'b0, vdin[4], vdin[7] };
		2'd3: d256 = { vdin[2], vdin[3], 1'b0, vdin[1], vdin[3], 1'b0, vdin[0], vdin[3] };
	endcase
end

always @(posedge clk) begin
	px_d <= px;
	active_d <= active;
	hs_d <= h >= H_SYNC;
	vs_d <= v >= V_SYNC;

	hs <= hs_d;
	vs <= vs_d;
	de <= active_d;

	if (!active_d) begin
		r <= 3'd0;
		g <= 3'd0;
		b <= 3'd0;
		fon <= 1'b0;
	end
	else if (blank) begin
		r <= 3'd0;
		g <= 3'd0;
		b <= 3'd0;
	end
	else if (col256) begin
		r <= d256[7:5];
		g <= d256[4:2];
		b <= { d256[1:0], 1'b0 };
	end
	else if (mode) begin
		// the colour under a flash is the one of the pixel that switched it on
		if (!fon) begin
			fb <= bb8;
			fg <= gg8;
			fr <= rr8;
		end
		if (flash && !px_d[0])
			fon <= !fon;

		if ((fon || flash) && fcnt[6] && !col16) begin
			r[2:1] <= { fr, fr };
			g[2:1] <= { fg, fg };
			b[2:1] <= { fb, fb };
		end
		else if (col16) begin
			if (palette[3]) begin
				b <= { rr8, gg8, bb8 };
				r[0] <= flash;
				g[0] <= flash;
			end
			else if (palette[4]) begin
				g <= { rr8, gg8, bb8 };
				b[0] <= flash;
				r[0] <= flash;
			end
			else if (palette[5]) begin
				r <= { rr8, gg8, bb8 };
				b[0] <= flash;
				g[0] <= flash;
			end
			else if (!rr8 && !bb8 && !gg8 && palette[2:0] == 3'b000 && flash) begin
				r[2:1] <= 2'b11;
				g[2:1] <= 2'b10;
				b[2:1] <= 2'b00;
			end
			else begin
				r[2:1] <= { rr8, flash && !palette[2] };
				g[2:1] <= { gg8, flash && !palette[1] };
				b[2:1] <= { bb8, flash && !palette[0] };
			end
		end
		else begin
			r[2:1] <= { rr8, rr8 };
			g[2:1] <= { gg8, gg8 };
			b[2:1] <= { bb8, bb8 };
		end
	end
	else begin
		case (palette[2:0])
			3'b111: begin r[2:1] <= { rr4, gg4 }; g[2:1] <= { gg4, gg4 }; b[2:1] <= { gg4 && rr4, gg4 && rr4 }; end
			3'b110: begin r[2:1] <= { rr4, rr4 }; g[2:1] <= { gg4, rr4 }; b[2:1] <= { gg4 && rr4, gg4 && rr4 }; end
			3'b101: begin r[2:1] <= { rr4, rr4 }; g[2:1] <= { rr4, rr4 }; b[2:1] <= { gg4, gg4 }; end
			3'b100: begin r[2:1] <= { rr4, rr4 }; g[2:1] <= { gg4, gg4 }; b[2:1] <= { rr4, rr4 }; end
			3'b011: begin r[2:1] <= { rr4, rr4 }; g[2:1] <= { gg4, gg4 }; b[2:1] <= { gg4, gg4 }; end
			3'b010: begin r[2:1] <= { gg4 && rr4, gg4 && rr4 }; g[2:1] <= { gg4, gg4 }; b[2:1] <= { rr4, rr4 }; end
			3'b001: begin r[2:1] <= { rr4, rr4 }; g[2:1] <= { gg4 && rr4, gg4 && rr4 }; b[2:1] <= { gg4, gg4 }; end
			default: begin r[2:1] <= { rr4, rr4 }; g[2:1] <= { gg4, gg4 }; b[2:1] <= { gg4 && rr4, gg4 && rr4 }; end
		endcase
	end
end

endmodule
