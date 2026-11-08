`timescale 1ns / 1ps
`default_nettype wire

/*
 Sinclair QL for Karabas Mini rev.G (HDMI, PCM5102): the machine of ql.v and the board glue.

 Clocks: one PLL, VCO 650 MHz (50 * 13): clk_65 65.0 MHz (/10, the OSD and HDMI, 1024 x 768 at 60 Hz),
 clk_32 32.5 MHz (/20: the machine, the SRAM, the MCU link), the HDMI serial clock 325 MHz and its
 inverse (/2), clk_8 8.125 MHz (/80, FT_CLK_OUT: the FT812 must always have its clock).

 Memory: all in the SRAM (ql.v); the machine is held in reset while the firmware loads the ROMs (the
 "roms" of core.json and the FL items), they go in byte by byte (ql_sram_loader).
 The SDRAM is not used.
*/

module karabas_minig_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N,
	output wire [1:0] MRD_N,

	output wire [1:0] SDR_BA,
	output wire [12:0] SDR_A,
	output wire SDR_CLK,
	output wire [1:0] SDR_DQM,
	output wire SDR_WE_N,
	output wire SDR_CAS_N,
	output wire SDR_RAS_N,
	inout wire [15:0] SDR_DQ,

	output wire SD_CS_N,
	output wire SD_CLK,
	output wire SD_DI,
	input wire SD_DO,
	input wire SD_DET_N,

	input wire [7:0] VGA_R,
	input wire [7:0] VGA_G,
	input wire [7:0] VGA_B,
	input wire VGA_HS,
	input wire VGA_VS,

	output wire [3:0] TMDS_P,
	output wire [3:0] TMDS_N,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	input wire FT_DE,
	output wire FT_CLK_OUT,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	output wire TAPE_OUT,
	input wire TAPE_IN,

	output wire DAC_BCK,
	output wire DAC_WS,
	output wire DAC_DAT,

	output wire ADC_CLK,
	inout wire ADC_BCK,
	inout wire ADC_LRCK,
	input wire ADC_DOUT,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	inout wire [5:0] MCU_IO, // [0] burst cs_n, [1] burst ready, [2] sd2 cs_n, [3] ft cs_n

	output wire MIDI_TX,

	output wire ESP32_SPI_CS_N,
	input wire ESP32_PCM_BCK,
	input wire ESP32_PCM_RLCK,
	input wire ESP32_PCM_DAT,

	output wire FLASH_CS_N,
	input wire FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N
);

// ------------------------------------------------------------------ unused

assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b1;
assign WD = 16'bz;

assign ESP32_SPI_CS_N = 1'b1;
assign MIDI_TX = 1'b1;
assign UART_RX = 1'bz;
assign UART_TX = 1'bz;
assign UART_CTS = 1'bz;

assign FLASH_CS_N = 1'b1;
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

assign ADC_CLK = 1'b0;
assign ADC_BCK = 1'bz;
assign ADC_LRCK = 1'bz;

assign TAPE_OUT = 1'b0;

// the SDRAM is idle
assign SDR_BA = 2'b00;
assign SDR_A = 13'd0;
assign SDR_CLK = 1'b0;
assign SDR_DQM = 2'b11;
assign SDR_WE_N = 1'b1;
assign SDR_CAS_N = 1'b1;
assign SDR_RAS_N = 1'b1;
assign SDR_DQ = 16'bz;

// ------------------------------------------------------------------ clocks

wire clk_65, clk_ser, clk_ser_n, clk_8, clk_32;
wire locked;
wire [5:0] pll_clk;
kg_pll #(
	.CLKIN_PERIOD(20.0),
	.DIVCLK_DIVIDE(1),
	.CLKFBOUT_MULT(13),
	.CLKOUT0_DIVIDE(10),
	.CLKOUT1_DIVIDE(2),
	.CLKOUT2_DIVIDE(2), .CLKOUT2_PHASE(180.0),
	.CLKOUT3_DIVIDE(80),
	.CLKOUT4_DIVIDE(20),
	.BUFG_MASK(6'b011111)
) pll (
	.clk_in(CLK_50MHZ),
	.rst(1'b0),
	.clk_out(pll_clk),
	.locked(locked)
);
assign clk_65 = pll_clk[0];
assign clk_ser = pll_clk[1];
assign clk_ser_n = pll_clk[2];
assign clk_8 = pll_clk[3];
assign clk_32 = pll_clk[4];
wire areset = ~locked;

// the clock of the FT812: it must always have one (karabas-go-notes ft-clk-out-required)
ODDR2 oddr_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8), .C1(~clk_8), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ MCU

wire mcu_sck_ibufg, mcu_sck;
IBUFG ibufg_mcu_sck (.I(MCU_SCK), .O(mcu_sck_ibufg));
BUFG bufg_mcu_sck (.I(mcu_sck_ibufg), .O(mcu_sck));

wire mcu_burst_ready;
assign MCU_IO[1] = mcu_burst_ready;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[5:2] = 4'bzzzz;

wire [7:0] kb_scancode;
wire kb_scancode_upd;
wire [12:0] joy_l, joy_r;
wire [7:0] ms_x, ms_y;
wire [2:0] ms_b;
wire ms_upd;
wire [7:0] rtc_a, rtc_do, rtc_di;
wire rtc_wr;
wire [23:0] matrix_cmd;
wire matrix_cmd_wr;
wire rom_active, rom_wr;
wire [31:0] rom_addr;
wire [7:0] rom_data;
wire file_active, file_wr;
wire [31:0] file_addr;
wire [7:0] file_data, file_slot;
wire [15:0] softsw_command, osd_command;
wire mcu_busy;
wire dvi_only;
wire ft_cs_n, ft_mosi, ft_spi_on, sd2_cs_n, sd2_mosi;

kg_mcu #(
	.BURST_MAX_MHZ(32),  // Rev.G has MCU_SCK on a global clock pin
	.CS_FILTER(3),
	.ENABLE_RTC(1),      // rtc_mode 1: DS1307 registers
	.RTC_SKIP_0D(0),
	.ENABLE_UART(0),
	.ENABLE_MATRIX(1),   // the audio peaks
	.ENABLE_DEBUG(0),
	.ENABLE_IMG(0),      // Ф3
	.ENABLE_FILE(1),
	.FILE_CMDS(0),       // the ioctl commands of the FL items
	.FILE_WR_EACH(1),
	.FILE_TO_ROM(0),
	.ENABLE_FT(1),
	.ENABLE_SD2(1)
) mcu (
	.CLK(clk_32),
	.N_RESET(~areset),

	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SCK(mcu_sck),
	.MCU_SS(MCU_CS_N),
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),
	.MCU_BURST_CS_N(MCU_IO[0]),
	.MCU_BURST_READY(mcu_burst_ready),

	.KB_SCANCODE(kb_scancode),
	.KB_SCANCODE_UPD(kb_scancode_upd),
	.JOY_L(joy_l),
	.JOY_R(joy_r),
	.MS_X(ms_x),
	.MS_Y(ms_y),
	.MS_Z(),
	.MS_B(ms_b),
	.MS_UPD(ms_upd),

	.ROMLOADER_ACTIVE(rom_active),
	.ROMLOAD_ADDR(rom_addr),
	.ROMLOAD_DATA(rom_data),
	.ROMLOAD_WR(rom_wr),

	.FILELOAD_ACTIVE(file_active),
	.FILELOAD_ADDR(file_addr),
	.FILELOAD_DATA(file_data),
	.FILELOAD_WR(file_wr),
	.FILELOAD_SLOT(file_slot),

	.SOFTSW_COMMAND(softsw_command),
	.OSD_COMMAND(osd_command),
	.BUSY(mcu_busy),

	.FT_SPI_ON(ft_spi_on),
	.FT_CS_N(ft_cs_n),
	.FT_MOSI(ft_mosi),
	.FT_MISO(FT_SPI_MISO),
	.FT_SCK(),
	.SD2_CS_N(sd2_cs_n),
	.SD2_MOSI(sd2_mosi),
	.SD2_MISO(SD_DO),
	.SD2_SCK(),

	.DVI_ONLY(dvi_only),

	// not used in this phase
	.RTC_A(rtc_a),
	.RTC_DI(rtc_di),
	.RTC_DO(rtc_do),
	.RTC_CS(rtc_wr),
	.RTC_WR_N(~rtc_wr),
	.IMG_MOUNTED(),
	.IMG_SIZE(),
	.IMG_WP(),
	.IMG_DATA_WR(),
	.IMG_DATA_ADDR(),
	.IMG_DATA(),
	.IMG_RESULT_WR(),
	.IMG_RESULT(),
	.IMG_SUM(),
	.IMG_Q_WR(1'b0),
	.IMG_Q_DI(24'd0),
	.IMG_Q_ACK(),
	.PS2_COMMAND(16'h0000),
	.PS2_COMMAND_WR(1'b0),
	.UART_RX_DATA(),
	.UART_RX_IDX(),
	.UART_TX_DATA(8'h00),
	.UART_TX_WR(1'b0),
	.UART_TX_MODE(1'b0),
	.UART_DLM(8'h00),
	.UART_DLL(8'h00),
	.UART_DLM_WR(1'b0),
	.UART_DLL_WR(1'b0),
	.MATRIX_CMD(matrix_cmd),
	.MATRIX_CMD_WR(matrix_cmd_wr),
	.DEBUG_ADDR(16'h0000),
	.DEBUG_DATA(16'h0000),
	.ESP_UART_RX_DATA(8'h00),
	.ESP_UART_RX_WR(1'b0),
	.FLASHBOOT_START(1'b0),
	.FLASHBOOT_COREID(5'd0)
);

assign FT_SPI_CS_N = ft_spi_on ? ft_cs_n : 1'b1;
assign FT_SPI_SCK = ft_spi_on ? mcu_sck_ibufg : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;
assign SD_CS_N = sd2_cs_n;
assign SD_DI = sd2_mosi;
assign SD_CLK = mcu_sck_ibufg;

// ------------------------------------------------------------------ soft switches

// the index of an item = its position in "osd" of core.json, the F / FL items included
localparam SW_RESET = 2;
localparam SW_N = 3;
wire [SW_N*8-1:0] sw;
kg_soft_switches #(.N(SW_N)) soft_switches (
	.clk(clk_32),
	.command(softsw_command),
	.regs(sw),
	.upd()
);

// ------------------------------------------------------------------ the machine

// the base addresses of the FL slots: 0 the OS ROM, 1 the back ROM
wire [21:0] file_base = (file_slot == 8'd1) ? 22'h00C000 : 22'h000000;
wire load_active = rom_active || file_active;
wire load_wr = rom_wr || file_wr;
wire [21:0] load_addr = rom_wr ? rom_addr[21:0] : (file_base + file_addr[21:0]);
wire [7:0] load_data = rom_wr ? rom_data : file_data;

reg reset_r = 1'b1;
always @(posedge clk_32)
	reset_r <= areset || sw[SW_RESET*8] || mcu_busy || load_active;

wire [20:0] ram_addr;
wire [15:0] ram_din, ram_dout;
wire ram_oe;
wire [1:0] ram_we_n, ram_rd_n;

wire [2:0] vid_r, vid_g, vid_b;
wire vid_hs, vid_vs, vid_de;
wire [63:0] kbd_matrix;
wire [15:0] ql_l, ql_r;

ql ql (
	.clk(clk_32),
	.reset(reset_r),
	.ram_addr(ram_addr),
	.ram_din(ram_din),
	.ram_dout(ram_dout),
	.ram_oe(ram_oe),
	.ram_we_n(ram_we_n),
	.ram_rd_n(ram_rd_n),
	.video_r(vid_r),
	.video_g(vid_g),
	.video_b(vid_b),
	.video_hs(vid_hs),
	.video_vs(vid_vs),
	.video_de(vid_de),
	.audio_l(ql_l),
	.audio_r(ql_r),
	.kbd_matrix(kbd_matrix),
	.ms_x(ms_x),
	.ms_y(ms_y),
	.ms_b(ms_b),
	.ms_upd(ms_upd),
	.rtc_a(rtc_a),
	.rtc_do(rtc_do),
	.rtc_di(rtc_di),
	.rtc_wr(rtc_wr),
	.sd_cs_n(),
	.sd_start(),
	.sd_tx(),
	.sd_rx(8'hFF),
	.sd_ready(1'b1),
	.mdv_start(21'd0),
	.mdv_end(21'd0),
	.dbg_cpu_addr(),
	.dbg_ce_cpu()
);

ql_keyboard keyboard (
	.clk(clk_32),
	.reset(reset_r),
	.scancode(kb_scancode),
	.scancode_upd(kb_scancode_upd),
	.js0({ joy_r[6] | joy_r[7], joy_r[1], joy_r[2], joy_r[3], joy_r[4] }),   // the second port: F1..F5
	.js1({ joy_l[6] | joy_l[7], joy_l[1], joy_l[2], joy_l[3], joy_l[4] }),   // the first: cursors, space
	.matrix(kbd_matrix)
);

ql_sram_loader sram (
	.clk(clk_32),
	.active(load_active),
	.load_wr(load_wr),
	.load_addr(load_addr),
	.load_data(load_data),
	.ram_addr(ram_addr),
	.ram_din(ram_din),
	.ram_dout(ram_dout),
	.ram_oe(ram_oe),
	.ram_we_n(ram_we_n),
	.ram_rd_n(ram_rd_n),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N),
	.MRD_N(MRD_N)
);

// ------------------------------------------------------------------ OSD

wire [7:0] r8 = { vid_r, vid_r, vid_r[2:1] };
wire [7:0] g8 = { vid_g, vid_g, vid_g[2:1] };
wire [7:0] b8 = { vid_b, vid_b, vid_b[2:1] };

// as core-bk: 1024 x 768, the counters start at the leading edge of the syncs
wire [23:0] osd_rgb;
kg_osd_overlay #(.H_OFFSET(276), .V_OFFSET(105), .H_DIV4_WIDTH(1400), .V_DIV4_HEIGHT(900)) osd (
	.clk(clk_65),
	.rgb_i({r8, g8, b8}),
	.rgb_o(osd_rgb),
	.hsync_i(~vid_hs),
	.vsync_i(~vid_vs),
	.v_offset(11'd0),
	.h_offset(11'd0),
	.osd_command(osd_command)
);

// ------------------------------------------------------------------ audio

// 48 kHz of clk_32: the samples of the DAC and HDMI, and the rate of the DC filter
reg [15:0] smp_acc = 16'd0;
wire smp_ce = (smp_acc >= 16'd32500 - 16'd48);
always @(posedge clk_32)
	smp_acc <= smp_ce ? smp_acc + 16'd48 - 16'd32500 : smp_acc + 16'd48;

wire signed [15:0] audio_l, audio_r;
ql_audio audio (
	.clk(clk_32),
	.ce(smp_ce),
	.in_l(ql_l),
	.in_r(ql_r),
	.out_l(audio_l),
	.out_r(audio_r)
);

kg_pcm5102 #(.DIV_BITS(2)) dac (
	.clk(clk_32),
	.reset(areset),
	.left(audio_l),
	.right(audio_r),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_WS)
);

// the level meters of the mcu (dot matrix)
audio_peaks peaks (
	.clk(clk_32),
	.audio_l(audio_l),
	.audio_r(audio_r),
	.cmd_wr(matrix_cmd_wr),
	.cmd(matrix_cmd)
);

// ------------------------------------------------------------------ HDMI

reg [16:0] aud_acc = 17'd0;
reg aud_stb = 1'b0;
always @(posedge clk_65) begin
	aud_stb <= 1'b0;
	if (aud_acc >= 17'd65000 - 17'd48) begin
		aud_acc <= aud_acc + 17'd48 - 17'd65000;
		aud_stb <= 1'b1;
	end
	else
		aud_acc <= aud_acc + 17'd48;
end

// the output of the OSD is registered once more before the TMDS encoder (19 levels of logic in one clock
// otherwise); the syncs and de go with it: the OSD is a clock behind its input, this register another
reg [23:0] hdmi_rgb = 24'd0;
reg hdmi_hs_d = 1'b0, hdmi_vs_d = 1'b0, hdmi_de_d = 1'b0;
reg hdmi_hs = 1'b0, hdmi_vs = 1'b0, hdmi_de = 1'b0;
always @(posedge clk_65) begin
	hdmi_rgb <= osd_rgb;
	hdmi_hs_d <= vid_hs;   // negative syncs (VESA): ql_video has them low in the sync
	hdmi_vs_d <= vid_vs;
	hdmi_de_d <= vid_de;
	hdmi_hs <= hdmi_hs_d;
	hdmi_vs <= hdmi_vs_d;
	hdmi_de <= hdmi_de_d;
end

hdmi_tx #(.SAMPLE_FREQ(48000)) hdmi (
	.clk(clk_65),
	.sclk(clk_ser),
	.sclk_n(clk_ser_n),
	.reset(areset),
	.rgb(hdmi_rgb),
	.vsync(hdmi_vs),
	.hsync(hdmi_hs),
	.de(hdmi_de),
	.audio_en(~dvi_only),
	.audio_l({ audio_l, 8'd0 }),
	.audio_r({ audio_r, 8'd0 }),
	.audio_clk(aud_stb),
	.tx_clk_n(TMDS_N[3]),
	.tx_clk_p(TMDS_P[3]),
	.tx_d_n(TMDS_N[2:0]),
	.tx_d_p(TMDS_P[2:0])
);

endmodule
