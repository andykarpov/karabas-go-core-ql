//
// zx8302.v
//
// ZX8302 for Sinclair QL for the MiST
// https://github.com/mist-devel
//
// Copyright (c) 2015 Till Harbaum <till@harbaum.org>
// adapted for Next keyboard-joystick 2024 Theodoulos Liontakis (Leon)
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
// karabas: everything on clk (32.5 MHz) with enables: ce_bus is the clock enable of the CPU and
// qualifies its writes; no derived clocks, no asynchronous sets. The keyboard matrix comes from
// the board.

`default_nettype wire

module zx8302 (
	input          clk,
	input          ce_bus,
	input          ce_11,
	input          reset,

	// interrupts
	output [1:0]   ipl,
	input          xint,

	// the SRAM interface of the microdrive emulation
	output [20:0]  mdv_addr,
	input [15:0]   mdv_din,
	output         mdv_read,
	input          mdv_men,
	input          mdv_reverse,
	input [20:0]   mdv_smem,
	input [20:0]   mdv_emem,

	output         led,
	output         audio,

	// vertical sync (a rising edge = the frame interrupt)
	input          vs,

	input [63:0]   kbd_matrix,

	// the time of the board, seconds since 1961: one clock of rtc_load
	input          rtc_load,
	input [31:0]   rtc_value,

	// bus interface
	input          cpu_sel,
	input          cpu_wr,
	input [1:0]    cpu_addr,      // a[5,1]
	input [1:0]    cpu_ds,
	input [15:0]   cpu_din,
	output [15:0]  cpu_dout,

	output         dbg_ipc_write,
	output         dbg_comctrl
);

// ---------------------------------------------------------------------------------
// ----------------------------- CPU register write --------------------------------
// ---------------------------------------------------------------------------------

reg [7:0] mctrl = 8'd0;
reg [7:0] mdv_sel = 8'd0;
reg [2:0] irq_mask = 3'd0;
reg [4:0] irq_ack = 5'd0;

reg ipc_write = 1'b0;
reg [3:0] ipc_write_data = 4'd0;
reg [47:0] rtc = 48'd0;
reg clk32k = 1'b0;

// the RTC counts 65536 ticks per second: a phase accumulator of the 32.5 MHz clock
localparam [25:0] RTC_CLK = 26'd32500000;
localparam [25:0] RTC_INC = 26'd65536;
reg [25:0] rtc_acc = 26'd0;
wire rtc_tick = (rtc_acc >= RTC_CLK - RTC_INC);

wire reg_wr = cpu_sel && cpu_wr && ce_bus;

always @(posedge clk) begin
	irq_ack <= 5'd0;
	ipc_write <= 1'b0;

	rtc_acc <= rtc_tick ? rtc_acc + RTC_INC - RTC_CLK : rtc_acc + RTC_INC;

	if (rtc_tick) begin
		clk32k <= ~clk32k;
		if (!(reg_wr && cpu_addr == 2'b00))
			rtc <= rtc + 48'd1;
	end

	// cpu writes to 0x18XXX area
	if (reg_wr) begin
		// even addresses have cpu_ds[1]=0 and use the higher 8 data bus bits
		if (!cpu_ds[1]) begin
			// cpu writes microdrive control register
			if (cpu_addr == 2'b10)
				mctrl <= cpu_din[15:8];
		end
		// rtc
		if (cpu_addr == 2'b00) begin
			if (!cpu_ds[1])
				rtc[47:16] <= 32'd0;
			else if (!cpu_ds[0]) begin
				if (!cpu_din[4]) rtc[47:40] <= rtc[47:40] + 8'd1;
				if (!cpu_din[3]) rtc[39:32] <= rtc[39:32] + 8'd1;
				if (!cpu_din[2]) rtc[31:24] <= rtc[31:24] + 8'd1;
				if (!cpu_din[1]) rtc[23:16] <= rtc[23:16] + 8'd1;
			end
		end

		// odd addresses have cpu_ds[0]=0 and use the lower 8 data bus bits
		if (!cpu_ds[0]) begin
			// 18003 - IPCWR: the host sends a single bit to the ipc, data is ----XEDS
			if (cpu_addr == 2'b01) begin
				ipc_write <= 1'b1;
				ipc_write_data <= cpu_din[3:0];
			end

			// cpu writes interrupt register
			if (cpu_addr == 2'b10) begin
				irq_mask <= cpu_din[7:5];
				irq_ack <= cpu_din[4:0];
			end
		end
	end

	if (rtc_load)
		rtc <= { rtc_value, 16'd0 };
end

// ---------------------------------------------------------------------------------
// -------------------------------------- IPC --------------------------------------
// ---------------------------------------------------------------------------------

wire ipc_comctrl;
wire ipc_comdata_out;
assign dbg_ipc_write = ipc_write;
assign dbg_comctrl = ipc_comctrl;

// comdata shift register
reg [3:0] comdata_reg = 4'd0;
reg [1:0] comdata_cnt = 2'd0;
reg comctrl_d = 1'b1;
wire ipc_comdata_in = comdata_reg[0];

// 8302 sees its own comdata as well as the one from the ipc
wire zx8302_comdata_in = ipc_comdata_in && ipc_comdata_out;

always @(posedge clk) begin
	comctrl_d <= ipc_comctrl;
	if (reset) begin
		comdata_reg <= 4'b0000;
		comdata_cnt <= 2'd0;
	end
	else if (ipc_write) begin
		comdata_reg <= ipc_write_data;
		comdata_cnt <= 2'd2;
	end
	else if (comctrl_d && !ipc_comctrl) begin
		comdata_reg <= { 1'b0, comdata_reg[3:1] };
		if (comdata_cnt != 0)
			comdata_cnt <= comdata_cnt - 2'd1;
	end
end

// comdata is busy until two bits have been shifted out
wire ipc_busy = (comdata_cnt != 0);

wire [1:0] ipc_ipl;

ipc ipc (
	.reset       ( reset           ),
	.clk         ( clk             ),
	.ce_11       ( ce_11           ),
	.comctrl     ( ipc_comctrl     ),
	.comdata_in  ( ipc_comdata_in  ),
	.comdata_out ( ipc_comdata_out ),
	.audio       ( audio           ),
	.ipl         ( ipc_ipl         ),
	.kbd_matrix  ( kbd_matrix      )
);

// ---------------------------------------------------------------------------------
// ----------------------------------- microdrive ----------------------------------
// ---------------------------------------------------------------------------------

wire mdv_gap;
wire mdv_tx_empty;
wire mdv_rx_ready;
wire [7:0] mdv_byte;

assign led = !mdv_sel[0];

mdv mdv (
	.clk      ( clk          ),
	.reset    ( reset        ),
	.sel      ( mdv_sel[0]   ),
	.reverse  ( mdv_reverse  ),
	.gap      ( mdv_gap      ),
	.tx_empty ( mdv_tx_empty ),
	.rx_ready ( mdv_rx_ready ),
	.dout     ( mdv_byte     ),
	.mem_ena  ( mdv_men      ),
	.mem_addr ( mdv_addr     ),
	.mem_read ( mdv_read     ),
	.mem_din  ( mdv_din      ),
	.mdv_smem ( mdv_smem     ),
	.mdv_end  ( mdv_emem     )
);

// the microdrive control register mctrl generates the drive selection
reg mctrl1_d = 1'b0;

always @(posedge clk) begin
	mctrl1_d <= mctrl[1];
	if (mctrl1_d && !mctrl[1])
		mdv_sel <= { mdv_sel[6:0], mctrl[0] };
end

// ---------------------------------------------------------------------------------
// -------------------------------------- IRQs -------------------------------------
// ---------------------------------------------------------------------------------

reg vs_d = 1'b0;
reg vsync_irq = 1'b0;
// toggling the mask will also trigger irqs ...
wire gap_irq_in = mdv_gap && irq_mask[0];
reg gap_in_d = 1'b0;
reg gap_irq = 1'b0;
wire xint_irq_in = xint && irq_mask[2];
reg xint_in_d = 1'b0;
reg xint_irq = 1'b0;

wire [7:0] irq_pending = { 1'b0, (mdv_sel == 0), clk32k,
		xint_irq, vsync_irq, 1'b0, 1'b0, gap_irq };

// any pending irq raises ipl to 2 and the ipc can control both ipl lines
assign ipl = { ipc_ipl[1] && (irq_pending[4:0] == 0), ipc_ipl[0] };

always @(posedge clk) begin
	vs_d <= vs;
	gap_in_d <= gap_irq_in;
	xint_in_d <= xint_irq_in;

	if (reset || irq_ack[3]) vsync_irq <= 1'b0;
	else if (vs && !vs_d) vsync_irq <= 1'b1;

	if (reset || irq_ack[0]) gap_irq <= 1'b0;
	else if (gap_irq_in && !gap_in_d) gap_irq <= 1'b1;

	if (reset || irq_ack[4]) xint_irq <= 1'b0;
	else if (xint_irq_in && !xint_in_d) xint_irq <= 1'b1;
end

// ---------------------------------------------------------------------------------
// ----------------------------- CPU register read ---------------------------------
// ---------------------------------------------------------------------------------

// status register read
// bit 0       Network port
// bit 1       Transmit buffer full
// bit 2       Receive buffer full
// bit 3       Microdrive GAP
// bit 4       SER1 DTR
// bit 5       SER2 CTS
// bit 6       IPC busy
// bit 7       COMDATA

wire [7:0] io_status = { zx8302_comdata_in, ipc_busy, 2'b00,
		mdv_gap, mdv_rx_ready, mdv_tx_empty, 1'b0 };

assign cpu_dout =
	// 18020/18021 and 18022/18023
	(cpu_addr == 2'b10) ? { io_status, irq_pending } :
	(cpu_addr == 2'b11) ? { mdv_byte, mdv_byte } :
	// 18000/18001 and 18002/18003
	(cpu_addr == 2'b00) ? rtc[47:32] :
	(cpu_addr == 2'b01) ? rtc[31:16] :
	16'h0000;

endmodule
