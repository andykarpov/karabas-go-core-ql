`timescale 1ns / 1ps
`default_nettype wire

/*
 ql_sram_loader.v

 The SRAM pins of the board: the machine (ql.v) drives them, except while the firmware loads a ROM
 (active, the machine in reset): a byte goes in over 4 clocks, /OE off and data stable a clock on
 each side of /WE. The even byte of a word is the high one (MD[15:8], lane 1), as on the 68000.
*/

module ql_sram_loader (
	input wire clk,

	input wire active,
	input wire load_wr,            // one clock with addr and data; bytes come well over 4 clocks apart
	input wire [21:0] load_addr,   // byte address
	input wire [7:0] load_data,

	// the machine
	input wire [20:0] ram_addr,
	output wire [15:0] ram_din,
	input wire [15:0] ram_dout,
	input wire ram_oe,
	input wire [1:0] ram_we_n,
	input wire [1:0] ram_rd_n,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N,
	output wire [1:0] MRD_N
);

reg [2:0] st = 3'd0;
reg [20:0] l_addr = 21'd0;
reg [15:0] l_data = 16'd0;
reg [1:0] l_we_n = 2'b11;
reg l_oe = 1'b0;
reg lane = 1'b0;

always @(posedge clk) begin
	case (st)
	3'd0:
		if (active && load_wr) begin
			l_addr <= load_addr[21:1];
			l_data <= { load_data, load_data };
			lane <= load_addr[0];
			l_oe <= 1'b1;
			st <= 3'd1;
		end
	3'd1: begin
		l_we_n <= lane ? 2'b10 : 2'b01;
		st <= 3'd2;
	end
	3'd2: begin
		l_we_n <= 2'b11;
		st <= 3'd3;
	end
	default: begin
		l_oe <= 1'b0;
		st <= 3'd0;
	end
	endcase
end

assign MA = active ? l_addr : ram_addr;
assign MWR_N = active ? l_we_n : ram_we_n;
assign MRD_N = active ? 2'b11 : ram_rd_n;
assign MD = active ? (l_oe ? l_data : 16'bz) : (ram_oe ? ram_dout : 16'bz);
assign ram_din = MD;

endmodule
