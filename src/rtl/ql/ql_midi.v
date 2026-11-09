`timescale 1ns / 1ps
`default_nettype wire

/*
 ql_midi.v

 MIDI of the QL core, the ports at $800026 (ql.v):
 - IN: the bytes of a USB MIDI keyboard (kg_mcu, CMD_MIDI) go into a fifo of 64 bytes; a read of the
   byte register by the CPU takes one off. A byte that finds the fifo full is dropped;
 - OUT: a byte written by the CPU goes to kg_midi_tx, 31250 baud on MIDI_TX: the SAM2695 synth of the
   board. tx_ready is low when the 64 byte fifo of kg_midi_tx is nearly full: a byte takes 320 us on
   the line and the transmitter has no full flag of its own, so the bytes are counted here;
 - thru: the bytes of the USB keyboard go straight to MIDI_TX as well, so that it plays the synth
   without any software on the QL.
*/

module ql_midi (
	input wire clk,          // 32.5 MHz

	// the USB keyboard
	input wire [7:0] usb_data,
	input wire usb_wr,
	input wire thru,

	// the CPU
	output wire [7:0] rx_data,
	output wire rx_avail,
	input wire cpu_rd,
	input wire [7:0] cpu_data,
	input wire cpu_wr,
	output wire tx_ready,

	output wire tx
);

// ------------------------------------------------------------------- IN

reg [7:0] rx_mem [0:63];
reg [5:0] wp = 6'd0;
reg [5:0] rp = 6'd0;

assign rx_avail = wp != rp;
assign rx_data = rx_mem[rp];

wire [5:0] wp_next = wp + 6'd1;

always @(posedge clk) begin
	if (usb_wr && wp_next != rp) begin
		rx_mem[wp] <= usb_data;
		wp <= wp_next;
	end
	if (cpu_rd && rx_avail)
		rp <= rp + 6'd1;
end

// ------------------------------------------------------------------- OUT

reg [7:0] tx_d = 8'd0;
reg tx_w = 1'b0;

// a byte of the keyboard that comes in the same clock as a byte of the CPU waits for the next clock
reg hold_v = 1'b0;
reg [7:0] hold_d = 8'd0;
wire thru_wr = usb_wr && thru;

always @(posedge clk) begin
	tx_w <= 1'b0;
	if (cpu_wr) begin
		tx_d <= cpu_data;
		tx_w <= 1'b1;
		if (thru_wr) begin
			hold_d <= usb_data;
			hold_v <= 1'b1;
		end
	end
	else if (hold_v) begin
		tx_d <= hold_d;
		tx_w <= 1'b1;
		hold_v <= thru_wr;
		hold_d <= usb_data;
	end
	else if (thru_wr) begin
		tx_d <= usb_data;
		tx_w <= 1'b1;
	end
end

// the bytes waiting in the transmitter: one more with each write, one less per 320 us
localparam [13:0] BYTE_CLOCKS = 14'd10400;   // 32.5 MHz / 31250 * 10
reg [6:0] tx_cnt = 7'd0;
reg [13:0] tx_timer = 14'd0;
wire tx_done = (tx_cnt != 7'd0) && (tx_timer == BYTE_CLOCKS - 14'd1);

always @(posedge clk) begin
	if (tx_cnt == 7'd0)
		tx_timer <= 14'd0;
	else
		tx_timer <= tx_done ? 14'd0 : tx_timer + 14'd1;

	if (tx_w && !tx_done)
		tx_cnt <= tx_cnt + 7'd1;
	else if (!tx_w && tx_done)
		tx_cnt <= tx_cnt - 7'd1;
end

assign tx_ready = tx_cnt < 7'd60;

kg_midi_tx #(.CLK_HZ(32500000), .AW(6)) midi_out (
	.clk(clk),
	.data(tx_d),
	.wr(tx_w),
	.overflow(),
	.tx(tx)
);

endmodule
