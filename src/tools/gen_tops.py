#!/usr/bin/env python3
"""Makes rtl/karabas_go_top.v and rtl/karabas_mini_top.v from rtl/karabas_minig_top.v: the board ports come
from the tops of ../../karabas-go-core-bk (same boards), the differences as in that core.
Run after a change of the Mini G top. usage (from src/): python3 tools/gen_tops.py
"""
import re
BK = '../../karabas-go-core-bk/src/rtl/karabas_%s_top.v'
top = open('rtl/karabas_minig_top.v').read()

def sub(s, a, b):
    assert a in s, a
    return s.replace(a, b, 1)

def header(board):
    t = open(BK % board).read()
    return t[t.index('module karabas_%s_top' % board):t.index(');', t.index('module karabas_%s_top' % board)) + 2]

def common(s, board, doc):
    s = s[:s.index('module karabas_minig_top')] + header(board) + s[s.index(');', s.index('module karabas_minig_top')) + 2:]
    s = sub(s, ' Sinclair QL for Karabas Mini rev.G (HDMI, PCM5102): the machine of ql.v and the board glue.', doc)
    s = sub(s, '.BURST_MAX_MHZ(32),  // Rev.G has MCU_SCK on a global clock pin', '.BURST_MAX_MHZ(0),   // MCU_SCK is not on a clock pin: bursts at the link clock')
    s = sub(s, 'assign ESP32_SPI_CS_N = 1\'b1;\n', "assign ESP_RESET_N = 1'bz;\nassign ESP_BOOT_N = 1'bz;\nassign MIDI_RESET_N = 1'b1;\n")
    # the SAM2695 has its clock from the FPGA on these boards (650 MHz / 54 = 12.04 MHz)
    s = sub(s, '.CLKOUT4_DIVIDE(20),', '.CLKOUT4_DIVIDE(20),\n\t.CLKOUT5_DIVIDE(54),')
    s = sub(s, '// ------------------------------------------------------------------ MCU\n', "ODDR2 oddr_midi_clk (.Q(MIDI_CLK), .C0(pll_clk[5]), .C1(~pll_clk[5]), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));\n\n// ------------------------------------------------------------------ MCU\n")
    # the ADC of the synth is on Mini G only
    a = s.index('// synth begin')
    b = s.index('// synth end')
    s = s[:a] + ('assign ADC_CLK = 1\'b0;\nassign ADC_BCK = 1\'bz;\nassign ADC_LRCK = 1\'bz;\n' if board == 'mini' else '') + 'wire signed [15:0] mix_l = audio_l;\nwire signed [15:0] mix_r = audio_r;\n' + s[b + len('// synth end\n'):]
    a = s.index('wire mcu_sck_ibufg, mcu_sck;')
    b = s.index('BUFG bufg_mcu_sck')
    b = s.index('\n', b) + 1
    s = s[:a] + 'wire mcu_sck = MCU_SCK, mcu_sck_ibufg = MCU_SCK;  // not on a clock pin\n' + s[b:]
    return s

# ------------------------------------------------------------- Mini
s = common(top, 'mini', ' Sinclair QL for Karabas Mini before rev.G (HDMI, sigma-delta audio): generated from karabas_minig_top.v by tools/gen_tops.py.')
s = sub(s, "assign MCU_IO[5:2] = 4'bzzzz;", "assign MCU_IO[3:2] = 2'bzz;")
s = sub(s, "assign MIDI_RESET_N = 1'b1;\n", "assign MIDI_RESET_N = 1'b1;\nassign FT_RESET = 1'b1;\n")
s = sub(s, ".BUFG_MASK(6'b011111)", ".BUFG_MASK(6'b111111)")
a = s.index('kg_pcm5102 #(.DIV_BITS(2)) dac (')
b = s.index(');', a) + 3
s = s[:a] + "kg_sigma_delta_dac dac_l (.clk(clk_32), .reset(areset), .din(audio_l ^ 16'h8000), .dout(AUDIO_L));\nkg_sigma_delta_dac dac_r (.clk(clk_32), .reset(areset), .din(audio_r ^ 16'h8000), .dout(AUDIO_R));\n" + s[b:]
open('rtl/karabas_mini_top.v', 'w').write(s)

# ------------------------------------------------------------- Go
s = common(top, 'go', ' Sinclair QL for Karabas Go (VGA through the video DAC, PCM5102): generated from karabas_minig_top.v by tools/gen_tops.py.')
s = sub(s, "assign MCU_IO[1] = mcu_burst_ready;\nassign MCU_IO[0] = 1'bz;\nassign MCU_IO[5:2] = 4'bzzzz;\n", "assign MCU_SPI_IO[0] = mcu_burst_ready;\nassign MCU_SPI_IO[1] = 1'bz;\n")
s = sub(s, '.MCU_SPI_FT_SS(MCU_IO[3]),', '.MCU_SPI_FT_SS(MCU_SPI_FT_CS_N),')
s = sub(s, '.MCU_SPI_SD2_SS(MCU_IO[2]),', '.MCU_SPI_SD2_SS(MCU_SPI_SD2_CS_N),')
s = sub(s, '.MCU_BURST_CS_N(MCU_IO[0]),', '.MCU_BURST_CS_N(MCU_SPI_IO[1]),')
s = sub(s, "assign WD = 16'bz;\n", """assign WD = 16'bz;
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
""")
s = sub(s, ".BUFG_MASK(6'b011111)", ".BUFG_MASK(6'b110001)")
s = sub(s, "ODDR2 oddr_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8), .C1(~clk_8), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));\n",
        "// the pixel clock of the video DAC\nODDR2 oddr_v_clk (.Q(V_CLK), .C0(clk_65), .C1(~clk_65), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));\n")
s = sub(s, '.lrck(DAC_WS)', '.lrck(DAC_LRCK)')
a = s.index('// ------------------------------------------------------------------ HDMI')
b = s.rindex('endmodule')
s = s[:a] + """// ------------------------------------------------------------------ VGA

// 1024 x 768 at 60 Hz, negative syncs (VESA): ql_video has them low in the sync
reg [23:0] vga_rgb = 24'd0;
reg vga_hs = 1'b1, vga_vs = 1'b1;
always @(posedge clk_65) begin
	vga_rgb <= osd_rgb;
	vga_hs <= vid_hs;
	vga_vs <= vid_vs;
end
assign VGA_R = vga_rgb[23:16];
assign VGA_G = vga_rgb[15:8];
assign VGA_B = vga_rgb[7:0];
assign VGA_HS = vga_hs;
assign VGA_VS = vga_vs;

""" + s[b:]
open('rtl/karabas_go_top.v', 'w').write(s)
