`timescale 1ns / 1ps
`default_nettype wire

/*
 Sinclair QL for Karabas Go (VGA through the video DAC, PCM5102): generated from karabas_minig_top.v by tools/gen_tops.py.

 Clocks: one PLL, VCO 650 MHz (50 * 13): clk_65 65.0 MHz (/10, the OSD and HDMI, 1024 x 768 at 60 Hz),
 clk_32 32.5 MHz (/20: the machine, the SRAM, the MCU link), the HDMI serial clock 325 MHz and its
 inverse (/2), clk_8 8.125 MHz (/80, FT_CLK_OUT: the FT812 must always have its clock).

 Memory: all in the SRAM (ql.v); the machine is held in reset while the firmware loads the ROMs (the
 "roms" of core.json and the FL items), they go in byte by byte (ql_sram_loader).
 The SDRAM is not used.
*/

module karabas_go_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,
	inout wire ESP_RESET_N,
	inout wire ESP_BOOT_N,

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

	output wire [7:0] VGA_R,
	output wire [7:0] VGA_G,
	output wire [7:0] VGA_B,
	output wire VGA_HS,
	output wire VGA_VS,
	output wire V_CLK,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	output wire FT_OE_N,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	input wire FDC_INDEX,
	output wire [1:0] FDC_DRIVE,
	output wire FDC_MOTOR,
	output wire FDC_DIR,
	output wire FDC_STEP,
	output wire FDC_WDATA,
	output wire FDC_WGATE,
	input wire FDC_TR00,
	input wire FDC_WPRT,
	input wire FDC_RDATA,
	output wire FDC_SIDE_N,

	output wire TAPE_OUT,
	input wire TAPE_IN,
	output wire BEEPER,

	output wire DAC_LRCK,
	output wire DAC_DAT,
	output wire DAC_BCK,
	output wire DAC_MUTE,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	input wire MCU_SPI_FT_CS_N,
	input wire MCU_SPI_SD2_CS_N,
	inout wire [1:0] MCU_SPI_IO, // [0] INT of link v2 (firmware IO1, GPIO2), [1] unused (IO0, GPIO14)

	output wire MIDI_TX,
	output wire MIDI_CLK,
	output wire MIDI_RESET_N,

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
assign FT_OE_N = 1'b1;     // the FT812 does not drive the video DAC
assign DAC_MUTE = 1'b1;
assign BEEPER = 1'b0;
// the floppy connector: not used, its outputs 0 (high = active on the Go)
assign FDC_DRIVE = 2'b00;
assign FDC_MOTOR = 1'b0;
assign FDC_DIR = 1'b0;
assign FDC_STEP = 1'b0;
assign FDC_WDATA = 1'b0;
assign FDC_WGATE = 1'b0;
assign FDC_SIDE_N = 1'b0;

assign ESP_RESET_N = 1'bz;
assign ESP_BOOT_N = 1'bz;
assign MIDI_RESET_N = 1'b1;
assign UART_RX = 1'bz;
assign UART_TX = 1'bz;
assign UART_CTS = 1'bz;

assign FLASH_CS_N = 1'b1;
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

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
	.CLKOUT5_DIVIDE(54),
	.BUFG_MASK(6'b110001)
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
// the pixel clock of the video DAC
ODDR2 oddr_v_clk (.Q(V_CLK), .C0(clk_65), .C1(~clk_65), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

ODDR2 oddr_midi_clk (.Q(MIDI_CLK), .C0(pll_clk[5]), .C1(~pll_clk[5]), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ MCU

wire mcu_sck = MCU_SCK, mcu_sck_ibufg = MCU_SCK;  // not on a clock pin

// MCU link v2 (karabas-go-firmware docs/link_v2.md, kg_mcu2); INT on IO1
wire mcu_int;
assign MCU_SPI_IO[0] = mcu_int;   // INT of link v2 on N9 (IO1 of the firmware)
assign MCU_SPI_IO[1] = 1'bz;

// the index of an item = its position in "osd" of core.json, the F / FL items included
localparam SW_RESET = 4;
localparam SW_MDV_REV = 5;
localparam SW_SD2 = 6;
localparam SW_MDV_FAST = 7;
localparam SW_MIDI_THRU = 8;
localparam SW_N = 9;
wire [SW_N*8-1:0] sw;

wire [7:0] ps2_code;
wire ps2_kind, ps2_wr;
wire [15:0] joy_l16, joy_r16;
wire [12:0] joy_l = joy_l16[12:0], joy_r = joy_r16[12:0];
wire [31:0] port_out_data;
wire [3:0] port_out_wr;
wire [7:0] usb_midi_data = port_out_data[23:16];
wire usb_midi_wr = port_out_wr[2];
wire [7:0] ms_x, ms_y, ms_b8;
wire [2:0] ms_b = ms_b8[2:0];
wire ms_wr;
wire [7:0] rtc_a, rtc_do, rtc_di;
wire rtc_wr;
wire [23:0] matrix_cmd;
wire matrix_cmd_wr;
wire [1:0] ld_kind;
wire [7:0] ld_slot, ld_data;
wire [31:0] ld_addr;
wire ld_active, ld_wr;
wire mcu_busy;
wire dvi_only;
wire ft_cs_n, ft_mosi, ft_spi_on;
wire osd_wr, osd_en, osd_zoom;
wire [11:0] osd_waddr;
wire [7:0] osd_wdata;
wire [23:0] osd_fg, osd_bg;
wire [1:0] osd_alpha, osd_place;
wire [4:0] osd_px, osd_ph;
wire [3:0] osd_py;
wire [5:0] osd_pw;
// the SD card image (F slot 3): the mounter of kg_mcu2 (the sector interface of img_sdc)
wire [7:0] sdc_img_mounted;
wire [63:0] sdc_img_size;
wire card_rd, card_wr, sdc_busy, sdc_done, sdc_in_strobe;
wire [2:0] sdc_slot;
wire [31:0] card_lba;
wire [8:0] sdc_byte_addr;
wire [7:0] sdc_in_data, card_byte_out;

// clk_32 32.5 MHz: below 4 x the 16 MHz sck of spi_freq (the upper bound of kg_l2_link)
kg_mcu2 #(
	.CAPS(16'h0200),     // MIDI IN (port 2)
	.SW_N(SW_N),
	.CS_FILTER(3),
	.ENABLE_OSD(1),
	.ENABLE_IMG(1),      // the SD card image (F slot 3)
	.IMG_OUT_LATENCY(3),
	.ENABLE_PORTS(4'b0100), // port 2: MIDI IN of a USB keyboard
	.ENABLE_RTC(1),      // rtc_mode 1: DS1307 registers
	.RTC_SKIP_0D(0),
	.ENABLE_AUX(1),      // the audio peaks of the dot matrix
	.ENABLE_FT(1),
	.ENABLE_SD2(0)       // the second card belongs to the core: spi.vhd, card 1
) mcu (
	.CLK(clk_32),
	.N_RESET(~areset),

	.MCU_SCK(mcu_sck),
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SS(MCU_CS_N),
	.MCU_INT(mcu_int),
	.MCU_SPI_FT_SS(MCU_SPI_FT_CS_N),
	.MCU_SPI_SD2_SS(MCU_SPI_SD2_CS_N),

	.SW(sw), .SW_WR(), .SW_INDEX(), .SW_VALUE(), .HW_ID(), .DVI_ONLY(dvi_only), .CORE_BUILD(), .FW_BUILD(),
	.BUSY(mcu_busy), .BTNS(), .RELOAD_REQ(1'b0), .RELOAD_CORE(8'd0),

	.KBD(), .KBD_WR(), .PS2_CODE(ps2_code), .PS2_KIND(ps2_kind), .PS2_WR(ps2_wr),
	.MS_X(ms_x), .MS_Y(ms_y), .MS_Z(), .MS_B(ms_b8), .MS_WR(ms_wr),
	.JOY_L(joy_l16), .JOY_R(joy_r16), .JOY_WR(),
	.PS2_CMD(16'h0000), .PS2_CMD_WR(1'b0),

	.LD_KIND(ld_kind), .LD_SLOT(ld_slot), .LD_SIZE(), .LD_START(), .LD_ACTIVE(ld_active), .LD_END(),
	.LD_ADDR(ld_addr), .LD_DATA(ld_data), .LD_WR(ld_wr), .LD_READY(1'b1),

	.OSD_WR(osd_wr), .OSD_WADDR(osd_waddr), .OSD_WDATA(osd_wdata), .OSD_EN(osd_en),
	.OSD_FG(osd_fg), .OSD_BG(osd_bg), .OSD_ALPHA(osd_alpha), .OSD_PX(osd_px), .OSD_PY(osd_py),
	.OSD_PW(osd_pw), .OSD_PH(osd_ph), .OSD_PLACE(osd_place), .OSD_ZOOM(osd_zoom),

	.SDC_IMG_MOUNTED(sdc_img_mounted), .SDC_IMG_SIZE(sdc_img_size),
	.SDC_RD({ 4'd0, card_rd, 3'd0 }), .SDC_WR({ 4'd0, card_wr, 3'd0 }), .SDC_SECTOR(card_lba),
	.SDC_BUSY(sdc_busy), .SDC_DONE(sdc_done), .SDC_ERROR(), .SDC_SLOT(sdc_slot),
	.SDC_BYTE_IN_STROBE(sdc_in_strobe), .SDC_BYTE_ADDR(sdc_byte_addr),
	.SDC_BYTE_IN_DATA(sdc_in_data), .SDC_BYTE_OUT_DATA(card_byte_out),
	.IMG_WP(), .IMG_PHYS_WR(), .IMG_PHYS(), .IMG_FLUSH(), .FDD_CHNG_WR(), .FDD_CHNG(),
	.FDD_CHNG_REQ(1'b0), .FDD_CHNG_DS(2'd0), .IMG_ACTIVE(),

	.PORT_OUT_DATA(port_out_data), .PORT_OUT_WR(port_out_wr), .PORT_OUT_READY(4'b1111),
	.PORT_IN_DATA(32'd0), .PORT_IN_WR(4'd0),
	.PORT_CFG(128'd0), .PORT_IN_FULL(), .PORT_STAT(), .PORT_STAT_WR(),
	.RTC_A(rtc_a), .RTC_DI(rtc_di), .RTC_CS(rtc_wr), .RTC_WR_N(~rtc_wr), .RTC_DO(rtc_do),
	.MATRIX_CMD(matrix_cmd), .MATRIX_CMD_WR(matrix_cmd_wr), .DEBUG_ADDR(16'd0), .DEBUG_DATA(16'd0),

	.FT_SPI_ON(ft_spi_on), .FT_VGA_ON(), .FT_RESET(), .FT_SCK(), .FT_MOSI(ft_mosi), .FT_MISO(FT_SPI_MISO),
	.FT_CS_N(ft_cs_n),
	.SD2_SCK(), .SD2_MOSI(), .SD2_MISO(1'b1), .SD2_CS_N()
);

assign FT_SPI_CS_N = ft_spi_on ? ft_cs_n : 1'b1;
assign FT_SPI_SCK = ft_spi_on ? mcu_sck_ibufg : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;

// the loads of v2: LD kind 0 the ROMs of the core file, kind 2 the FL items (slot in LD_SLOT from START)
wire rom_active = ld_active && ld_kind == 2'd0;
wire rom_wr = ld_wr && ld_kind == 2'd0;
wire [31:0] rom_addr = ld_addr;
wire [7:0] rom_data = ld_data;
wire file_active = ld_active && ld_kind == 2'd2;
wire file_wr = ld_wr && ld_kind == 2'd2;
wire [31:0] file_addr = ld_addr;
wire [7:0] file_data = ld_data;
wire [7:0] file_slot = ld_slot;

// the PS/2 scancode (set 2) and the mouse as the toggles of v1 (ql_keyboard / ql_qimi take a change)
reg kb_upd_t = 1'b0, ms_upd_t = 1'b0;
reg [7:0] kb_code_r = 8'd0;
always @(posedge clk_32) begin
	if (ps2_wr && !ps2_kind) begin
		kb_code_r <= ps2_code;
		kb_upd_t <= ~kb_upd_t;
	end
	if (ms_wr) ms_upd_t <= ~ms_upd_t;
end
wire [7:0] kb_scancode = kb_code_r;
wire kb_scancode_upd = kb_upd_t;
wire ms_upd = ms_upd_t;

// ------------------------------------------------------------------ the machine

// the base addresses of the FL slots: 0 the OS ROM, 1 the back ROM, 2 the microdrive image (above the
// 2 MB of the CPU). A ROM resets the machine; for a microdrive image the CPU only waits.
wire file_mdv = file_slot == 8'd2;
wire [21:0] file_base = (file_slot == 8'd1) ? 22'h00C000 : file_mdv ? 22'h200000 : 22'h000000;
wire load_active = rom_active || file_active;
// the firmware raises file_active before it sends the slot: the CPU waits during any file, and it is
// a byte of a slot other than the microdrive that resets the machine
reg file_rst = 1'b0;
always @(posedge clk_32)
	if (!file_active)
		file_rst <= 1'b0;
	else if (file_wr && !file_mdv)
		file_rst <= 1'b1;
wire load_reset = rom_active || file_rst;

localparam [20:0] MDV_START = 21'h100000;   // a word address
reg [21:0] mdv_last = 22'd0;
reg mdv_active_d = 1'b0;
reg mdv_load = 1'b0;
always @(posedge clk_32) begin
	mdv_active_d <= file_active && file_mdv;
	mdv_load <= mdv_active_d && !(file_active && file_mdv);
	if (file_wr && file_mdv)
		mdv_last <= file_addr[21:0];
end
wire load_wr = rom_wr || file_wr;
wire [21:0] load_addr = rom_wr ? rom_addr[21:0] : (file_base + file_addr[21:0]);
wire [7:0] load_data = rom_wr ? rom_data : file_data;

reg reset_r = 1'b1;
always @(posedge clk_32)
	reset_r <= areset || sw[SW_RESET*8] || mcu_busy || load_reset;

wire sd_cs_n, sd_cs1_n, sd_w;
wire [7:0] sd_div, sd_tx, spi_rx, card_rx;
wire spi_busy;
// the OSD item SD2: off by default, the second card is not touched then (the driver can write to a card it mounts)
wire sd2_on = sw[SW_SD2*8];
wire sd2_sel = !sd_cs1_n && sd2_on;

wire [20:0] ram_addr;
wire [15:0] ram_din, ram_dout;
wire ram_oe;
wire [1:0] ram_we_n, ram_rd_n;

wire [2:0] vid_r, vid_g, vid_b;
wire vid_hs, vid_vs, vid_de;
wire [63:0] kbd_matrix;
wire [15:0] ql_l, ql_r;
wire [7:0] midi_rx_data, midi_tx_data;
wire midi_rx_avail, midi_tx_ready, midi_rd, midi_wr;

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
	.midi_rx_data(midi_rx_data),
	.midi_rx_avail(midi_rx_avail),
	.midi_tx_ready(midi_tx_ready),
	.midi_rd(midi_rd),
	.midi_tx_data(midi_tx_data),
	.midi_wr(midi_wr),
	.ms_x(ms_x),
	.ms_y(ms_y),
	.ms_b(ms_b),
	.ms_upd(ms_upd),
	.rtc_a(rtc_a),
	.rtc_do(rtc_do),
	.rtc_di(rtc_di),
	.rtc_wr(rtc_wr),
	.sd_cs_n(sd_cs_n),
	.sd_cs1_n(sd_cs1_n),
	.sd_w(sd_w),
	.sd_div(sd_div),
	.sd_tx(sd_tx),
	.sd_rx(sd2_sel ? spi_rx : card_rx),
	.sd_busy(sd_cs_n && sd2_on ? spi_busy : 1'b0),
	.hold(file_active),
	.cpu_slow(1'b0),
	.mdv_load(mdv_load),
	.mdv_start(MDV_START),
	.mdv_end(MDV_START + mdv_last[21:1]),
	.mdv_reverse_in(sw[SW_MDV_REV*8]),
	.mdv_fast(sw[SW_MDV_FAST*8]),
	.dbg_cpu_addr(),
	.dbg_ce_cpu()
);

// the SD cards. Card 0: an image of the file mounter (F slot 3), the exchange takes no time; card 1:
// the second SD slot of the board through the SPI of the Next core, which also gives the clocks a
// card needs with no card selected. Card 1 only with the OSD item SD2 on.

reg sd_w_d = 1'b0, sd_cs_d = 1'b1;
always @(posedge clk_32) begin
	sd_w_d <= sd_w;
	sd_cs_d <= sd_cs_n;
end
wire sd_exch = sd_w && !sd_w_d;
wire sd_cs_wr = sd_cs_n != sd_cs_d;

SPI sd2_spi (
	.SCLKo(SD_CLK),
	.MOSI(SD_DI),
	.MISO(SD_DO),
	.clk(clk_32),
	.reset(reset_r),
	.w(sd_w && sd2_on),
	.readyo(spi_busy),
	.data_in(sd_tx),
	.data_out(spi_rx),
	.divider(sd_div)
);
assign SD_CS_N = sd_cs1_n || !sd2_on;

ql_sd_card card (
	.clk(clk_32),
	.reset(reset_r),
	.cs_wr(sd_cs_wr),
	.d_wr(sd_exch),
	.din(sd_cs_wr ? { 7'd0, !sd_cs_n } : sd_tx),
	.dout(card_rx),
	.img_mounted(sdc_img_mounted[3]),
	.img_size(sdc_img_size[31:0]),
	.hd_rd(card_rd),
	.hd_wr(card_wr),
	.hd_lba(card_lba),
	.hd_busy(sdc_busy && sdc_slot == 3'd3),
	.hd_done(sdc_done && sdc_slot == 3'd3),
	.hd_byte_in_strobe(sdc_in_strobe && sdc_slot == 3'd3),
	.hd_byte_addr(sdc_byte_addr),
	.hd_byte_in_data(sdc_in_data),
	.hd_byte_out_data(card_byte_out)
);

ql_midi midi (
	.clk(clk_32),
	.usb_data(usb_midi_data),
	.usb_wr(usb_midi_wr),
	.thru(sw[SW_MIDI_THRU*8]),
	.rx_data(midi_rx_data),
	.rx_avail(midi_rx_avail),
	.cpu_rd(midi_rd),
	.cpu_data(midi_tx_data),
	.cpu_wr(midi_wr),
	.tx_ready(midi_tx_ready),
	.tx(MIDI_TX)
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

// the bitmap OSD of link v2 (kg_l2_osd_overlay): centred in de, the scale from its size,
// 2 clocks of latency with its syncs and de
wire [23:0] osd_rgb;
wire osd_hs, osd_vs, osd_de;
kg_l2_osd_overlay osd (
	.wclk(clk_32),
	.osd_wr(osd_wr), .osd_waddr(osd_waddr), .osd_wdata(osd_wdata), .osd_en(osd_en),
	.osd_fg(osd_fg), .osd_bg(osd_bg), .osd_alpha(osd_alpha), .osd_px(osd_px), .osd_py(osd_py),
	.osd_pw(osd_pw), .osd_ph(osd_ph), .osd_place(osd_place), .osd_zoom(osd_zoom),
	.icon_on(8'd0), .icon_act(8'd0),
	.clk(clk_65),
	.rgb_i({r8, g8, b8}), .hs_i(vid_hs), .vs_i(vid_vs), .de_i(vid_de),
	.rgb_o(osd_rgb), .hs_o(osd_hs), .vs_o(osd_vs), .de_o(osd_de)
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

wire signed [15:0] mix_l = audio_l;
wire signed [15:0] mix_r = audio_r;

kg_pcm5102 #(.DIV_BITS(2)) dac (
	.clk(clk_32),
	.reset(areset),
	.left(mix_l),
	.right(mix_r),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_LRCK)
);

// the level meters of the mcu (dot matrix)
audio_peaks peaks (
	.clk(clk_32),
	.audio_l(mix_l),
	.audio_r(mix_r),
	.cmd_wr(matrix_cmd_wr),
	.cmd(matrix_cmd)
);

// ------------------------------------------------------------------ VGA

// 1024 x 768 at 60 Hz, negative syncs (VESA): ql_video has them low in the sync
reg [23:0] vga_rgb = 24'd0;
reg vga_hs = 1'b1, vga_vs = 1'b1;
always @(posedge clk_65) begin
	vga_rgb <= osd_rgb;
	vga_hs <= osd_hs;   // the syncs of the overlay: in step with osd_rgb
	vga_vs <= osd_vs;
end
assign VGA_R = vga_rgb[23:16];
assign VGA_G = vga_rgb[15:8];
assign VGA_B = vga_rgb[7:0];
assign VGA_HS = vga_hs;
assign VGA_VS = vga_vs;

endmodule
