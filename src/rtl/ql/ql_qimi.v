`timescale 1ns / 1ps
`default_nettype wire

/*
 ql_qimi.v

 QIMI, the QL mouse interface at $1BFxx: the movement counters and registers of qimi.v (Till Harbaum,
 MiST; GPL v3), fed by the USB mouse of the firmware instead of a PS/2 port. A report of kg_mcu
 (ms_x, ms_y deltas, ms_b, ms_upd toggles) adds to the counters; the CPU takes them step by step,
 one interrupt per step.
*/

module ql_qimi (
	input wire clk,          // 32.5 MHz
	input wire reset,

	input wire cpu_ack,      // one clock: the CPU accessed $1BF9C, the end of one reported step
	input wire [1:0] cpu_addr,   // a5, a1
	output wire [7:0] cpu_data,
	output reg irq = 1'b0,

	input wire [7:0] ms_x,
	input wire [7:0] ms_y,
	input wire [2:0] ms_b,
	input wire ms_upd
);

reg [1:0] b = 2'b00;
reg [9:0] x_pos = 10'd0;
reg [9:0] y_pos = 10'd0;
reg upd_d = 1'b0;
reg [13:0] irq_holdoff = 14'd0;   // limits the rate of the interrupts: 12000 clocks, as 4000 at 10 MHz

wire x_dir = !x_pos[9];
wire y_dir = !y_pos[9];
wire x_mov = (x_pos != 0);
wire y_mov = (y_pos != 0);

assign cpu_data =
	(cpu_addr == 2'b00) ? { 2'b00, !b[0], !b[1], 4'b0000 } :                  // 1bf9c buttons
	(cpu_addr == 2'b10) ? { 2'b00, y_mov, x_dir, 1'b0, x_mov, 1'b0, y_dir } : // 1bfbc movement
	8'h00;

always @(posedge clk) begin
	upd_d <= ms_upd;
	if (reset) begin
		x_pos <= 10'd0;
		y_pos <= 10'd0;
		irq <= 1'b0;
		irq_holdoff <= 14'd0;
	end
	else begin
		if (irq_holdoff != 0) begin
			irq_holdoff <= irq_holdoff - 14'd1;
			if (irq_holdoff == 1 && (x_mov || y_mov))
				irq <= 1'b1;
		end

		if (ms_upd != upd_d) begin
			b <= ms_b[1:0];
			x_pos <= x_pos + { {2{ms_x[7]}}, ms_x };
			y_pos <= y_pos - { {2{ms_y[7]}}, ms_y };   // USB: down is positive, the PS/2 of qimi.v: up
			if (irq_holdoff == 0)
				irq_holdoff <= 14'd1;
		end
		else if (cpu_ack) begin
			if (x_pos != 0)
				x_pos <= x_pos[9] ? x_pos + 10'd1 : x_pos - 10'd1;
			if (y_pos != 0)
				y_pos <= y_pos[9] ? y_pos + 10'd1 : y_pos - 10'd1;
			irq <= 1'b0;
			irq_holdoff <= 14'd12000;
		end
	end
end

endmodule
