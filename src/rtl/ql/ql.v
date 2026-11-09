`timescale 1ns / 1ps
`default_nettype none

/*
 ql.v

 Sinclair QL, the machine of the ZX Spectrum Next core (ql_top_issue4.v, Theodoulos Liontakis, on
 the MiST port by Till Harbaum and Victor Trucco) without its board: one clock (32.5 MHz) with
 enables instead of the clocks made from logic of the original. GPL v3.

 A memory cycle is three clocks, the CPU (TG68K) gets one clock enable per cycle (10.83 MHz):
   ph 0: the address (and write data) go out to the SRAM / VRAM, 1: read data are taken, /WE low
   for a write, 2: ce_cpu: the CPU takes the data and moves on, /WE high.
 A steal cycle (a word of the microdrive image, or the slow down of params[2:0]) keeps the CPU
 waiting for three clocks.

 Memory map: 000000-017FFF ROM (SRAM), 018000-01BFFF I/O, 020000-02FFFF VRAM (block RAM, also the
 second QL screen), 030000-1FFFFF RAM (SRAM), 800000-80003F the ports of the Next core. The
 microdrive images are in the SRAM above 2 MB, where the CPU does not reach.

 Not ported: the sprites and PCM of the Issue 4 (no block RAM for them), the 68020 is a parameter.
*/

module ql #(
	parameter CPU_68020 = 0
) (
	input wire clk,            // 32.5 MHz
	input wire reset,

	// SRAM: a word address; lane 1 = MD[15:8], the even byte
	output reg [20:0] ram_addr = 21'd0,
	input wire [15:0] ram_din,
	output reg [15:0] ram_dout = 16'd0,
	output reg ram_oe = 1'b0,        // drive MD
	output reg [1:0] ram_we_n = 2'b11,
	output reg [1:0] ram_rd_n = 2'b11,

	// video, on clk: a clock = two pixels of 1024 x 768
	output wire [2:0] video_r,
	output wire [2:0] video_g,
	output wire [2:0] video_b,
	output wire video_hs,
	output wire video_vs,
	output wire video_de,

	output wire [15:0] audio_l,
	output wire [15:0] audio_r,

	input wire [63:0] kbd_matrix,

	// the mouse (kg_mcu)
	input wire [7:0] ms_x,
	input wire [7:0] ms_y,
	input wire [2:0] ms_b,
	input wire ms_upd,

	// the clock of the board: the DS1307 registers of kg_mcu_rtc
	output wire [7:0] rtc_a,
	input wire [7:0] rtc_do,
	output wire [7:0] rtc_di,
	output wire rtc_wr,

	// the SD cards: sd_w rising = the exchange of one byte, sd_busy until its end (as spi.vhd of the Next)
	output reg sd_cs_n = 1'b1,      // card 0, $80000B
	output reg sd_cs1_n = 1'b1,     // card 1, $80000D
	output reg sd_w = 1'b0,
	output reg [7:0] sd_div = 8'd2,
	output reg [7:0] sd_tx = 8'hFF,
	input wire [7:0] sd_rx,
	input wire sd_busy,

	// the CPU stops (not a reset) while the firmware writes a microdrive image into the SRAM
	input wire hold,

	// the microdrive image in the SRAM (word addresses): one clock of mdv_load sets them
	input wire mdv_load,
	input wire [20:0] mdv_start,
	input wire [20:0] mdv_end,
	input wire mdv_reverse_in,
	input wire mdv_fast,

	// debug
	output wire dbg_ipc_write,
	output wire dbg_comctrl,
	output wire [31:0] dbg_cpu_addr,
	output wire dbg_ce_cpu
);

// ------------------------------------------------------------------- enables

reg [1:0] ph = 2'd0;
always @(posedge clk)
	ph <= (ph == 2'd2) ? 2'd0 : ph + 2'd1;

reg cpu_en = 1'b0;
wire ce_cpu = (ph == 2'd2) && cpu_en;
wire ce_11 = (ph == 2'd2);

reg [3:0] psg_div = 4'd0;
wire ce_psg = (psg_div == 4'd12);   // 2.5 MHz
always @(posedge clk)
	psg_div <= ce_psg ? 4'd0 : psg_div + 4'd1;

// the 50 Hz interrupt of the QL, not tied to the 60 Hz of the output
reg [19:0] vs_cnt = 20'd0;
wire vs_last = (vs_cnt == 20'd649999);
always @(posedge clk)
	vs_cnt <= vs_last ? 20'd0 : vs_cnt + 20'd1;
wire zx_vs = vs_cnt > 20'd646000;

reg [4:0] us_cnt = 5'd0;   // 32.5 clocks per us, as closely as 2 x 65 / 4
reg us_half = 1'b0;
reg [31:0] utimer = 32'd0; // 1 MHz
reg [31:0] ntimer = 32'd0; // about 22 MHz in the Next core: here 21.67
reg [1:0] nt_div = 2'd0;
always @(posedge clk) begin
	if (us_cnt == (us_half ? 5'd31 : 5'd32)) begin
		us_cnt <= 5'd0;
		us_half <= !us_half;
		utimer <= utimer + 32'd1;
	end
	else
		us_cnt <= us_cnt + 5'd1;
	nt_div <= (nt_div == 2'd2) ? 2'd0 : nt_div + 2'd1;
	if (nt_div != 2'd2)
		ntimer <= ntimer + 32'd1;   // two of three clocks
end

// ------------------------------------------------------------------- CPU

wire [31:0] cpu_addr;
wire [15:0] cpu_dout;
wire [15:0] cpu_din;
wire [1:0] cpu_ds;
wire [1:0] cpu_ipl;
wire cpu_rw;
wire [1:0] cpu_busstate;

wire cpu_rd = (cpu_busstate == 2'b00) || (cpu_busstate == 2'b10);
wire cpu_wr = (cpu_busstate == 2'b11) && !cpu_rw;
wire cpu_act = cpu_rd || cpu_wr;

TG68KdotC_Kernel #(
	.SR_Read(CPU_68020 ? 2 : 0),
	.VBR_Stackframe(CPU_68020 ? 2 : 0),
	.extAddr_Mode(CPU_68020 ? 2 : 0),
	.MUL_Mode(CPU_68020 ? 2 : 0),
	.DIV_Mode(CPU_68020 ? 2 : 0),
	.BitField(CPU_68020 ? 2 : 0),
	.BarrelShifter(CPU_68020 ? 2 : 0),
	.MUL_Hardware(1)
) tg68k (
	.clk            ( clk           ),
	.nReset         ( !reset        ),
	.clkena_in      ( ce_cpu        ),
	.data_in        ( cpu_din       ),
	.IPL            ( { cpu_ipl[0], cpu_ipl[1], cpu_ipl[0] } ),  // ipl 0 and 2 are tied together on the 68008
	.IPL_autovector ( 1'b1          ),
	.berr           ( 1'b0          ),
	.CPU            ( cpu_type      ),
	.addr_out       ( cpu_addr      ),
	.data_write     ( cpu_dout      ),
	.nUDS           ( cpu_ds[1]     ),
	.nLDS           ( cpu_ds[0]     ),
	.nWr            ( cpu_rw        ),
	.busstate       ( cpu_busstate  ),
	.clr_berr       (               ),
	.nResetOut      (               ),
	.FC             (               )
);

assign dbg_cpu_addr = cpu_addr;
assign dbg_ce_cpu = ce_cpu;

// ------------------------------------------------------------------- decode

wire cpu_io   = cpu_act && (cpu_addr[23:14] == 10'b0000000110);  // internal IO $18000-$1bfff
wire cpu_bram = cpu_act && (cpu_addr[23:16] == 8'b00000011);     // RAM at $30000
wire cpu_xram = cpu_act && ((cpu_addr[23:18] == 6'b000001) ||
                            (cpu_addr[23:18] == 6'b000010) ||
                            (cpu_addr[23:18] == 6'b000011) ||
                            (cpu_addr[23:20] == 4'b0001));
wire cpu_ram  = cpu_bram || cpu_xram;
wire cpu_rom  = cpu_act && (cpu_addr[23:16] == 8'h0 || cpu_addr[23:15] == 9'h02);  // 64k + 32k ROM at $0
wire cpu_mem  = cpu_ram || cpu_rom;
wire vid_mem  = cpu_act && (cpu_addr[23:16] == 8'b00000010);     // video ram
wire memio    = cpu_act && (cpu_addr[23:20] == 4'b1000);
wire [4:0] mreg = cpu_addr[5:1];

wire sys_wr = cpu_wr && cpu_ram;
wire sys_oe = cpu_rd && cpu_mem;

// ------------------------------------------------------------------- SRAM / VRAM cycle

reg steal = 1'b0;
reg [2:0] delay_cnt = 3'd0;
reg [15:0] rdata = 16'hFFFF;
reg [14:0] vaddr1 = 15'd0;
reg [15:0] vdin1 = 16'd0;
reg [15:0] params = 16'd0;

wire [20:0] mdv_addr;
wire mdv_read;
reg mdv_ack = 1'b0;
reg [15:0] mdv_data = 16'd0;
reg mdv_cycle = 1'b0;

wire [1:0] vw1 = (ph == 2'd1 && cpu_en && vid_mem && cpu_wr) ? ~cpu_ds : 2'b00;

always @(posedge clk) begin
	mdv_ack <= 1'b0;

	case (ph)
	2'd0: begin
		cpu_en <= !steal && !hold;
		mdv_cycle <= steal && mdv_read;
		ram_addr <= (steal && mdv_read) ? mdv_addr : { 1'b0, cpu_addr[20:1] };
		ram_rd_n <= (steal ? mdv_read : sys_oe) ? (steal ? 2'b00 : cpu_ds) : 2'b11;
		ram_oe <= 1'b0;
		vaddr1 <= cpu_addr[15:1];
		if (sys_wr)
			ram_dout <= cpu_dout;
		vdin1 <= cpu_dout;
	end
	2'd1: begin
		if (mdv_cycle) begin
			mdv_data <= ram_din;
			mdv_ack <= 1'b1;
		end
		else
			rdata <= ram_din;
		if (cpu_en && sys_wr) begin
			ram_oe <= 1'b1;
			ram_we_n <= cpu_ds;
		end
	end
	2'd2: begin
		ram_we_n <= 2'b11;
		ram_rd_n <= 2'b11;
		if (delay_cnt == 3'd0) begin
			delay_cnt <= params[2:0];
			steal <= mdv_read && !steal;
		end
		else begin
			delay_cnt <= delay_cnt - 3'd1;
			steal <= cpu_ram || (vid_mem && !steal) || (mdv_read && !steal);
		end
	end
	default: ;
	endcase
end

wire [14:0] vaddr2;
wire [15:0] vdout1, vdout2;

kg_tdpram #(.DW(16), .AW(15), .WE_W(2), .WRITE_FIRST(1)) vram (
	.clka  ( clk       ),
	.ena   ( 1'b1      ),
	.wea   ( vw1       ),
	.addra ( vaddr1    ),
	.dina  ( vdin1     ),
	.douta ( vdout1    ),
	.clkb  ( clk       ),
	.enb   ( 1'b1      ),
	.web   ( 2'b00     ),
	.addrb ( vaddr2    ),
	.dinb  ( 16'd0     ),
	.doutb ( vdout2    )
);

// ------------------------------------------------------------------- ZX8301 and video

wire zx8301_cs = cpu_io && ({ cpu_addr[6:5], cpu_addr[1] } == 3'b111) && cpu_wr && !cpu_ds[0];
reg [7:0] mc_stat = 8'd0;
always @(posedge clk) begin
	if (reset)
		mc_stat <= 8'h00;
	else if (zx8301_cs && ce_cpu)
		mc_stat <= cpu_dout[7:0];
end

reg col256 = 1'b0;

ql_video video (
	.clk     ( clk          ),
	.reset   ( reset        ),
	.vaddr   ( vaddr2       ),
	.vdin    ( vdout2       ),
	.mode    ( mc_stat[3]   ),
	.membase ( mc_stat[7]   ),
	.blank   ( mc_stat[1]   ),
	.col16   ( params[8]    ),
	.col256  ( col256       ),
	.palette ( params[14:9] ),
	.r       ( video_r      ),
	.g       ( video_g      ),
	.b       ( video_b      ),
	.hs      ( video_hs     ),
	.vs      ( video_vs     ),
	.de      ( video_de     )
);

// ------------------------------------------------------------------- ZX8302, IPC

wire zx8302_sel = cpu_io && !cpu_addr[6];
wire qimi_irq;
wire zx_rtc_load;
wire [31:0] zx_rtc_value;
wire [15:0] zx8302_dout;
wire ipc_audio;

reg mdv_reverse = 1'b0;
reg [20:0] mdv_smem = 21'd0;
reg [20:0] mdv_emem = 21'd0;

zx8302 zx8302 (
	.clk         ( clk          ),
	.ce_bus      ( ce_cpu       ),
	.ce_11       ( ce_11        ),
	.reset       ( reset        ),
	.xint        ( qimi_irq     ),
	.ipl         ( cpu_ipl      ),
	.led         (              ),
	.audio       ( ipc_audio    ),
	.cpu_sel     ( zx8302_sel   ),
	.cpu_wr      ( cpu_wr       ),
	.cpu_addr    ( { cpu_addr[5], cpu_addr[1] } ),
	.cpu_ds      ( cpu_ds       ),
	.cpu_din     ( cpu_dout     ),
	.cpu_dout    ( zx8302_dout  ),
	.kbd_matrix  ( kbd_matrix   ),
	.rtc_load    ( zx_rtc_load  ),
	.rtc_value   ( zx_rtc_value ),
	.vs          ( zx_vs        ),
	.mdv_addr    ( mdv_addr     ),
	.mdv_din     ( mdv_data     ),
	.mdv_read    ( mdv_read     ),
	.mdv_men     ( mdv_ack      ),
	.mdv_reverse ( mdv_reverse || mdv_reverse_in ),
	.mdv_fast    ( mdv_fast     ),
	.mdv_smem    ( mdv_smem     ),
	.mdv_emem    ( mdv_emem     ),
	.dbg_ipc_write ( dbg_ipc_write ),
	.dbg_comctrl ( dbg_comctrl )
);

// ------------------------------------------------------------------- the mouse, the clock

wire qimi_sel = cpu_io && (cpu_addr[13:4] == 10'b1111111011 || cpu_addr[13:4] == 10'b1111111001);
wire [7:0] qimi_dout;

ql_qimi qimi (
	.clk      ( clk       ),
	.reset    ( reset     ),
	.cpu_ack  ( qimi_sel && ce_cpu && cpu_addr[5] && cpu_addr[1] ),
	.cpu_addr ( { cpu_addr[5], cpu_addr[1] } ),
	.cpu_data ( qimi_dout ),
	.irq      ( qimi_irq  ),
	.ms_x     ( ms_x      ),
	.ms_y     ( ms_y      ),
	.ms_b     ( ms_b      ),
	.ms_upd   ( ms_upd    )
);

wire [7:0] i2c_din;
wire i2c_busy;

ql_rtc rtc (
	.clk       ( clk          ),
	.reset     ( reset        ),
	.rtc_a     ( rtc_a        ),
	.rtc_do    ( rtc_do       ),
	.rtc_di    ( rtc_di       ),
	.rtc_wr    ( rtc_wr       ),
	.rtc_load  ( zx_rtc_load  ),
	.rtc_value ( zx_rtc_value ),
	.wr_data   ( ce_cpu && memio && cpu_wr && mreg == 5'b10000 ),
	.wr_ctrl   ( ce_cpu && memio && cpu_wr && mreg == 5'b10001 ),
	.cpu_d     ( cpu_dout[7:0] ),
	.i2c_din   ( i2c_din      ),
	.i2c_busy  ( i2c_busy     )
);

// ------------------------------------------------------------------- AY (QSound)

reg [7:0] psg_di = 8'd0;
reg psg_reg = 1'b0, psg_wr = 1'b0, psg_addr = 1'b0;
wire [7:0] psg_do, psg_a, psg_b, psg_c;

YM2149 ay (
	.CLK             ( clk       ),
	.ENA             ( ce_psg    ),
	.RESET_H         ( reset     ),
	.I_SEL_L         ( 1'b1      ),
	.I_DA            ( psg_di    ),
	.O_DA            ( psg_do    ),
	.I_REG           ( psg_reg   ),
	.busctrl_addr    ( psg_addr  ),
	.busctrl_we      ( psg_wr    ),
	.ctrl_aymode     ( 1'b0      ),
	.port_a_i        ( 8'hFF     ),
	.port_a_o        (           ),
	.port_b_i        ( 8'hFF     ),
	.port_b_o        (           ),
	.O_AUDIO_A       ( psg_a     ),
	.O_AUDIO_B       ( psg_b     ),
	.O_AUDIO_C       ( psg_c     ),
	.out_audio_mixed (           )
);

assign audio_l = { ipc_audio, { 1'b0, psg_a } + { 1'b0, psg_b }, 6'd0 };
assign audio_r = { ipc_audio, { 1'b0, psg_a } + { 1'b0, psg_c }, 6'd0 };

// ------------------------------------------------------------------- the ports at $800000

reg [15:0] memio_out = 16'd0;
reg [15:0] utbuf = 16'd0, ntbuf = 16'd0;
reg [1:0] cpu_type = 2'b00;


always @(posedge clk) begin
	if (ph == 2'd1 && memio && cpu_rd) begin
		case (mreg)
		5'b00011: memio_out <= { sd_rx, sd_rx };
		5'b00100: memio_out <= { 7'd0, sd_busy, 7'd0, sd_busy };
		5'b00111: memio_out <= { 6'd0, params[8], col256, 6'd0, params[8], col256 };
		5'b01010: memio_out <= { 7'd0, 4'd0, mdv_smem[20:16] };
		5'b01011: begin
			if (!cpu_ds[0]) memio_out[7:0] <= mdv_smem[7:0];
			if (!cpu_ds[1]) memio_out[15:8] <= mdv_smem[15:8];
		end
		5'b01111: memio_out <= 16'h4E32;   // the id of the core
		5'b10000: memio_out <= { i2c_din, i2c_din };
		5'b10001: memio_out <= { 15'd0, i2c_busy };
		5'b10010: memio_out <= 16'h0000;   // ESP UART: nothing (phase 5)
		5'b10100: if (!cpu_ds[1]) memio_out[15:8] <= psg_do;
		5'b11000: begin memio_out <= utimer[31:16]; utbuf <= utimer[15:0]; end
		5'b11001: memio_out <= utbuf;
		5'b11101: begin memio_out <= ntimer[31:16]; ntbuf <= ntimer[15:0]; end
		5'b11110: memio_out <= ntbuf;
		default: memio_out <= 16'h0000;
		endcase
	end

	if (ce_cpu && memio && cpu_wr) begin
		case (mreg)
		5'b00000: sd_w <= cpu_dout[0];
		5'b00001: sd_div <= cpu_dout[7:0];
		5'b00010: sd_tx <= cpu_dout[7:0];
		5'b00101: sd_cs_n <= cpu_dout[0];
		5'b00110: sd_cs1_n <= cpu_dout[0];
		5'b00111: if (!cpu_ds[1]) col256 <= cpu_dout[8];
		5'b01001: begin
			if (!cpu_ds[0]) params[7:0] <= cpu_dout[7:0];
			if (!cpu_ds[1]) params[15:8] <= cpu_dout[15:8];
		end
		5'b01010: if (!cpu_ds[0]) mdv_smem[20:16] <= cpu_dout[4:0];
		5'b01011: begin
			if (!cpu_ds[0]) mdv_smem[7:0] <= cpu_dout[7:0];
			if (!cpu_ds[1]) mdv_smem[15:8] <= cpu_dout[15:8];
		end
		5'b01100: if (!cpu_ds[0]) mdv_emem[20:16] <= cpu_dout[4:0];
		5'b01101: begin
			if (!cpu_ds[0]) mdv_emem[7:0] <= cpu_dout[7:0];
			if (!cpu_ds[1]) mdv_emem[15:8] <= cpu_dout[15:8];
		end
		5'b01110: mdv_reverse <= cpu_dout[0];
		5'b10100: if (!cpu_ds[1]) psg_di <= cpu_dout[15:8];
		5'b10101: if (!cpu_ds[1]) begin
			psg_reg <= !cpu_dout[10] && cpu_dout[8];
			psg_wr <= cpu_dout[10] && !cpu_dout[8];
			psg_addr <= cpu_dout[10] && cpu_dout[8];
		end
		5'b11111: if (CPU_68020) cpu_type <= cpu_dout[1:0];
		default: ;
		endcase
	end

	if (mdv_load) begin
		mdv_smem <= mdv_start;
		mdv_emem <= mdv_end;
	end

	if (reset) begin
		col256 <= 1'b0;
		params <= 16'd0;
		cpu_type <= 2'b00;
		sd_cs_n <= 1'b1;
		sd_cs1_n <= 1'b1;
		sd_w <= 1'b0;
		sd_div <= 8'd2;
	end
end

// ------------------------------------------------------------------- CPU data in

wire [15:0] io_dout = qimi_sel ? { qimi_dout, qimi_dout } : (!cpu_addr[6]) ? zx8302_dout : 16'h0000;

assign cpu_din =
	memio    ? memio_out :
	cpu_io   ? io_dout :
	cpu_mem  ? rdata :
	vid_mem  ? vdout1 :
	16'hFFFF;

endmodule
