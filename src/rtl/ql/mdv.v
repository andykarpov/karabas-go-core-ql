//
// mdv.v - Microdrive
//
// Sinclair QL for the MiST
// https://github.com/mist-devel
//
// Copyright (c) 2015 Till Harbaum <till@harbaum.org>
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// karabas: one clock with enables (no derived clocks / asynchronous sets); the bit clock is that of
// the Next core (clk_bus / 14 = 727 kHz), here 32.5 MHz / 45 = 722 kHz.

`default_nettype wire

module mdv
(
	input clk,
	input reset,

	input reverse,
	input fast,      // the bit clock: 0 = 200 kHz of a real drive, 1 = 722 kHz of the Next core
	input sel,
	input cpu_read,  // one clock: the CPU read the byte register

	// control bits
	output gap,
	output tx_empty,
	output rx_ready,
	output [7:0] dout,

	// ram interface to read image: mem_read stays high until the one clock of mem_ena
	input mem_ena,
	output reg mem_read = 1'b0,
	output reg [20:0] mem_addr = 21'd0,
	input [15:0] mem_din,
	input [20:0] mdv_smem,
	input [20:0] mdv_end
);

reg [3:0] mdv_bit_cnt = 4'd0;
reg [9:0] mdv_gap_cnt = 10'd0;
reg mdv_gap_state = 1'b0;
reg mdv_gap_active = 1'b0;
reg [15:0] mdv_data = 16'd0;
reg mdv_data_valid = 1'b0;
reg mdv_gap = 1'b0;
reg [15:0] mdv_din = 16'd0;

wire mdv_present = (sel == 1'b1) && (mdv_end > mdv_smem);

// a gap is permanently present if no mdv is inserted or if there's a gap on the inserted one
assign gap = (!mdv_present) || mdv_gap;

// karabas: rx_ready stays up until the CPU reads the byte (or the next byte comes). In MiST it was a
// short window of the bit counter, which a fast CPU saw twice for one byte
reg rx_ready_l = 1'b0;
assign rx_ready = mdv_present && mdv_data_valid && rx_ready_l;
assign tx_empty = 1'b0;

assign dout = mdv_bit_cnt[3] ? mdv_data[7:0] : mdv_data[15:8];

// karabas: the bit clock as an enable
reg [7:0] bit_div = 8'd0;
wire bit_tick = (bit_div == (fast ? 8'd44 : 8'd161));
always @(posedge clk)
	bit_div <= bit_tick ? 8'd0 : bit_div + 8'd1;

always @(posedge clk) begin
	if (mem_ena) begin
		mdv_din <= mem_din;
		mem_read <= 1'b0;
	end

	if (cpu_read)
		rx_ready_l <= 1'b0;

	if (bit_tick) begin
		mdv_bit_cnt <= mdv_bit_cnt + 4'd1;
		if (mdv_bit_cnt[2:0] == 3'b010)
			rx_ready_l <= 1'b1;
		else if (mdv_bit_cnt[2:0] == 3'b001)
			rx_ready_l <= 1'b0;   // the byte was not taken: it is gone
		if (mdv_bit_cnt == 15) begin
			mdv_data <= mdv_din;
			mdv_data_valid <= !mdv_gap_active && (mdv_gap_cnt > 5) &&
				!(mdv_gap_state && (mdv_gap_cnt > 7) && (mdv_gap_cnt < 12));
			mem_read <= 1'b1;

			// reset counters when address is out of range
			if ((mem_addr > mdv_end) || (mem_addr < mdv_smem)) begin
				mem_addr <= mdv_smem;

				// assume we start at the end of a post-sector/pre-header gap
				mdv_gap_cnt <= 10'd0;
				mdv_gap_state <= 1'b1;
				mdv_gap_active <= 1'b1;
				mdv_gap <= 1'b1;
			end
			else begin
				mdv_gap_cnt <= mdv_gap_cnt + 10'd1;
				if (mdv_gap_active) begin
					// stop sending gap after 35 words = 70 bytes = 2800us
					if (mdv_gap_cnt == 34) begin
						mdv_gap_cnt <= 10'd0;
						mdv_gap_active <= 1'b0;
						mdv_gap_state <= !mdv_gap_state;
						mdv_gap <= 1'b0;
					end
				end
				else begin
					mem_addr <= mem_addr + 21'd1;

					if ((!mdv_gap_state) && (mdv_gap_cnt == 13)) begin
						// done reading 14 words header data
						mdv_gap_cnt <= 10'd0;
						mdv_gap_active <= 1'b1;
						mdv_gap <= 1'b1;
					end
					else if (mdv_gap_state && (mdv_gap_cnt == 328)) begin
						// done reading 330 words sector data
						mdv_gap_cnt <= 10'd0;
						mdv_gap_active <= 1'b1;
						mdv_gap <= 1'b1;

						if (reverse) begin
							// The sectors on cartridges are written in descending order.
							// Some images have them ascending: replay those backwards
							if (mem_addr == mdv_smem + 343 - 1)
								mem_addr <= mdv_end - 343 + 1;
							else
								mem_addr <= mem_addr - 2 * 343 + 1;
						end
					end
				end
			end
		end
	end

	if (reset)
		mem_read <= 1'b0;
end

endmodule
