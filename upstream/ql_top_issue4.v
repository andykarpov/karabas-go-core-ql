//
// Sinclair QL for the ZX Spectrum Next - KS2
//
// Copyright (c) 2024 Theodoulos Liontakis (Leon)
// Copyright (c) 2020 Victor Trucco  
// original MiST Port
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

`default_nettype none

 module ql 
(
    // Clocks
    input  wire clock_50_i,

    //SRAM (AS7C34096)
    output wire [19:0] ram_addr_o,
    inout  wire [15:0] ram_data_io,
    output wire        ram_lb_n_o,
    output wire        ram_ub_n_o,
    output wire        ram_oe_n_o,
    output wire        ram_we_n_o,
    output wire        ram_cs_n_o, // output wire [ 3:0] ram_ce_n_o,
    
    // PS2
    inout wire ps2_clk_io,
    inout wire ps2_data_io,
    inout wire ps2_pin6_io,
    inout wire ps2_pin2_io,
                        
    // SD Card
    output wire sd_cs0_n_o,
    output wire sd_cs1_n_o,
    output wire sd_sclk_o,
    output wire sd_mosi_o,
    input  wire sd_miso_i,

    // Flash
    output wire flash_cs_n_o,
    output wire flash_sclk_o,
    output wire flash_mosi_o,
    input  wire flash_miso_i,
    output wire flash_wp_o,
    output wire flash_hold_o,

    // Joystick
    input  wire joyp1_i,
    input  wire joyp2_i,
    input  wire joyp3_i,
    input  wire joyp4_i,
    input  wire joyp6_i,
    inout wire joyp7_o,
    input  wire joyp9_i,
    output wire joysel_o,

    // Audio
    output wire audioext_l_o,
    output wire audioext_r_o,
    output wire audioint_o,

    // K7
    input  wire ear_port_i,
    output wire mic_port_o,

    // Buttons
    input  wire btn_divmmc_n_i,
    input  wire btn_multiface_n_i,
    input  wire btn_reset_n_i,

    // Matrix keyboard
    output wire [7:0] keyb_row_o,
    input  wire [6:0] keyb_col_i,

    // Bus
    inout  wire bus_rst_n_io,
    output wire bus_clk35_o,
    output wire [15:0] bus_addr_o,
    inout  wire [7:0] bus_data_io,
    inout  wire bus_int_n_io,
    input  wire bus_nmi_n_i,
    input  wire bus_ramcs_i,
    input  wire bus_romcs_i,
    input  wire bus_wait_n_i,
    output wire bus_halt_n_o,
    output wire bus_iorq_n_o,
    output wire bus_m1_n_o,
    output wire bus_mreq_n_o,
    inout  wire bus_rd_n_io,
    output wire bus_wr_n_o,
    output wire bus_rfsh_n_o,
    input  wire bus_busreq_n_i,
    output wire bus_busack_n_o,
    input  wire bus_iorqula_n_i,
    output wire bus_y_o,

    // VGA
    output wire [2:0] rgb_r_o,
    output wire [2:0] rgb_g_o,
    output wire [2:0] rgb_b_o,
    output wire hsync_o,
    output wire vsync_o,
    //output wire csync_o,

    // HDMI
    output wire [3:0] hdmi_p_o,
    output wire [3:0] hdmi_n_o,

    // I2C (RTC and HDMI)
    inout  wire i2c_scl_io,
    inout  wire i2c_sda_io,

    // ESP
    inout  wire esp_gpio0_io,
    inout  wire esp_gpio2_io,
    input  wire esp_rx_i,
    output wire esp_tx_o,
    input  wire esp_rtr_n_i,
    output wire esp_cts_n_o,

    // PI GPIO
    inout  wire [27:0] accel_io,
    
    // XADC Analog to Digital Conversion
      
    input wire XADC_VP,
    input wire  XADC_VN,
      
    input wire  XADC_15P,
    input wire  XADC_15N,
      
    input wire  XADC_7P,
    input wire  XADC_7N,
      
    output wire  adc_control_o, 


    // Vacant pins
    output  wire extras_o,
    inout   wire extras_2_io,
    inout   wire extras_3_io    
);


// -------------------------------------------------------------------------
// -------------------------- clock generation -----------------------------
// -------------------------------------------------------------------------

wire pll_locked, clk11, clk325, clk325n, clk1625, clk65, clk1625n, mclk,clk22;
//reg clk22=0;
//reg [1:0] clkcnt=0;

pll pll
(
    .clk_in1   ( clock_50_i ),
    .clk_out1  ( clk22 ),               
    .clk_out2  ( clk11 ), 
	.clk_out3  ( clk325 ),
	.clk_out4  ( clk325n ), 	
	.clk_out5  ( mclk ),
    .locked    ( pll_locked )
);     

pll_hdmi pl2
(
    .clk_in1  ( clk325 ), 
	.clk_out1  ( clk65 ), 	
	.clk_out2  ( clk1625 ),
	.clk_out3  ( clk1625n )
);        

//always @(posedge mclk) //<=~clk22;
//begin
//    if (clkcnt<2'b10) clkcnt<=clkcnt+1; else clkcnt<=0; 
//    clk22 <= clkcnt[1];
//end

//reg clk10 = 1'b0; // 10.5 MHz QL pixel clock
//reg clk5 = 1'b0;  // 5.25 MHz CPU clock
//reg clk2 = 1'b0;  // 2.625 MHz bus clock

reg [2:0] clock_div = 3'b000;    
always @(posedge clk22)
begin
    clock_div = clock_div + 3'd1;   
end

wire clk10, clk5, clk2, clkin;

BUFG  BUFG_inst0 (.I (clock_div[0]), .O (clk10));
//BUFG  BUFG_inst1 (.I (clock_div[1]), .O (clk5));
BUFG  BUFG_inst2 (.I (clk2i), .O (clk2));
//BUFG  BUFG_inst3  (.I (clk325), .O (clkin));

//-------------- audio port --------------------

wire audio;
wire audioL,audioR;
assign audioext_l_o = audioL;
assign audioext_r_o = audioR;

dac #(11) audioDL 
(
    .clk_i  (clk22),
    .res_i  (reset),
    .dac_i  (pcm_audio_L[15:4]),
    .dac_o  (audioL)
);

dac #(11) audioDR 
(
    .clk_i  (clk22),
    .res_i  (reset),
    .dac_i  (pcm_audio_R[15:4]),
    .dac_o  (audioR)
);

//--------------- YM2149 -------------------------

wire [7:0] psg_do,psg_A,psg_B,psg_C,psg_a_o;
reg [7:0] psg_di,psg_a_i;
reg psg_reg=0,psg_wr=0,psg_addr=0;
wire [9:0] audio_mixed;
reg [1:0] psg_clk;
always @(posedge clk10) psg_clk<=psg_clk+2'b01; // 2,500,000    /16=156,250

YM2149 soundic
(
	.clk      (psg_clk[1]),
	.ENA      (1'b1),
	.RESET_H  (reset),
	.I_SEL_L  (1'b1),
    .I_DA     (psg_di),
    .O_DA     (psg_do),
	.I_REG    (psg_reg),
	.busctrl_addr (psg_addr),
	.busctrl_we   (psg_wr),
    .ctrl_aymode  (1'b0),
	.port_a_i (psg_a_i),
    .port_a_o (psg_a_o),
    .port_b_i (),
    .port_b_o (),
	.O_AUDIO_A   (psg_A),
    .O_AUDIO_B   (psg_B),
    .O_AUDIO_C   (psg_C),
    .out_audio_mixed (audio_mixed)
);

//------------- Digital Audio --------------

reg da_read=1'b0;
reg [15:0] da_data=16'd0;
reg [12:0] da_address=13'd0;
reg [11:0] da_cnt=12'd0;
reg [11:0] da_period=12'd500;
reg da_start=0;
reg da_playing=0;
reg da_mono=0;
reg [1:0] da_state=0;
(* ram_style = "block" *) reg [15:0] da_memory [0:8191];

always @(posedge clk11)
begin
    if (da_cnt>12'd0) begin
        da_cnt<=da_cnt-12'd1;   
    end else begin
        da_cnt<=da_period;
        case (da_state)
		2'd0: begin  
            da_data=da_memory[da_address];
            if (da_playing) da_address<=da_address+13'd1;
            da_state<=3'd2; 
            end
        2'd2: begin
            if (da_start==1'b1 && da_address==13'd0) da_playing<=1'b1; 
            if (da_start==1'b0) begin da_playing<=1'b0; da_address<=13'd0; end
            da_state<=3'd0;
        end
        endcase
    end
end

//-------------- Sprites -------------------

reg  [1:0]   sp1_wea=2'b00;
reg  [15:0]  sp1_dina;
wire [15:0]  sp1_douta;
wire [63:0]  sp1_doutb;
reg  [10:0] sp1_addra;
wire  [8:0]  sp1_addrb;

sprite_mem smem1 (
    .clka   (clk325),
    .wea    (sp1_wea),
    .addra  (sp1_addra),
    .dina   (sp1_dina),
    .clkb   (clk65),
    .addrb  (sp1_addrb),
    .doutb  (sp1_doutb)
);

wire sp1_b,sp1_g,sp1_r,sp1_f,sp1_on;

Sprites #(30) sprites1  (
    .clk     (clk65),
    .reset   (reset),
    .raddr   (sp1_addrb),
    .rq      (sp1_doutb),
    .sprb    (sp1_b),
    .sprg    (sp1_g),
    .sprr    (sp1_r),
    .sprf    (sp1_f),
    .spron   (sp1_on)
);

reg  [1:0]   sp2_wea=2'b00;
reg  [15:0]  sp2_dina;
wire [15:0]  sp2_douta;
wire [63:0]  sp2_doutb;
reg  [10:0] sp2_addra;
wire  [8:0]  sp2_addrb;

sprite_mem smem2 (
    .clka   (clk325),
    .wea    (sp2_wea),
    .addra  (sp2_addra),
    .dina   (sp2_dina),
    .clkb   (clk65),
    .addrb  (sp2_addrb),
    .doutb  (sp2_doutb)
);

wire sp2_b,sp2_g,sp2_r,sp2_f,sp2_on;

Sprites #(30) sprites2  (
    .clk     (clk65),
    .reset   (reset),
    .raddr   (sp2_addrb),
    .rq      (sp2_doutb),
    .sprb    (sp2_b),
    .sprg    (sp2_g),
    .sprr    (sp2_r),
    .sprf    (sp2_f),
    .spron   (sp2_on)
);

//reg  [1:0]   sp3_wea=2'b00;
//reg  [15:0]  sp3_dina;
//wire [15:0]  sp3_douta;
//wire [63:0]  sp3_doutb;
//reg  [10:0] sp3_addra;
//wire  [8:0]  sp3_addrb;

//sprite_mem smem3 (
//    .clka   (clk325),
//    .wea    (sp3_wea),
//    .addra  (sp3_addra),
//    .dina   (sp3_dina),
//    .clkb   (clk65),
//    .addrb  (sp3_addrb),
//    .doutb  (sp3_doutb)
//);

//wire sp3_b,sp3_g,sp3_r,sp3_f,sp3_on;

//Sprites #(15) sprites3  (
//    .clk     (clk65),
//    .reset   (reset),
//    .raddr   (sp3_addrb),
//    .rq      (sp3_doutb),
//    .sprb    (sp3_b),
//    .sprg    (sp3_g),
//    .sprr    (sp3_r),
//    .sprf    (sp3_f),
//    .spron   (sp3_on)
//);

//------------- RTC -----------------

reg i2c_ena=1'b0, i2c_rw=1'b1;
wire i2c_busy, i2c_err;
wire [7:0] i2c_din;
reg [7:0] i2c_dout;
reg [6:0] i2c_adr=7'b1101000; //DS1307 address

i2c_master #( .input_clk(11000000), .bus_clk(100000) )
rtc_i2c 
(
    .clk      (clk11),                  ///system clock
    .reset_n  (!reset),                 //active low reset
    .ena       (i2c_ena),               //latch in command
    .addr      (i2c_adr),               //address of target slave
    .rw        (i2c_rw),                //'0' is write, '1' is read
    .data_wr   (i2c_dout),              //data to write to slave
    .busy      (i2c_busy),              //indicates transaction in progress
    .data_rd   (i2c_din),               //data read from slave
    .ack_error (i2c_err),               //flag if improper acknowledge from slave
    .sda       (i2c_sda_io),            //serial data output of i2c bus
    .scl       (i2c_scl_io)             //serial clock output of i2c bus
);

// ----------- Joystick ---------------

wire joy_clock = joy_clk_div[11];  
reg [11:0] joy_clk_div;
always @(posedge clk2)
    joy_clk_div <= joy_clk_div + 12'd1;

reg [7:0] js1;
reg [7:0] js0;
reg joys=0;
reg joy7=1'bz;
reg stop_switch=0;
assign joyp7_o=joy7;
assign joysel_o=joys;

always @(posedge joy_clock)
begin
	if (!stop_switch) begin 
	    joys=~joys; 
        if (joys) begin
            js1[4]=~joyp6_i;  //button
            js1[1]=~joyp3_i;  // left
            js1[0]=~joyp4_i;  // right
            js1[3]=~joyp1_i;  // up
            js1[2]=~joyp2_i;  // down
        end else begin
            js0[4]=~joyp6_i;  //button
            js0[1]=~joyp3_i;  // left
            js0[0]=~joyp4_i;  // right
            js0[3]=~joyp1_i;  // up
            js0[2]=~joyp2_i;  // down
        end
	end else begin // stop polling both joys for NET interface
	    joys=0;
        js1[4]=~joyp6_i;  //button
        js1[1]=~joyp3_i;  // left
        js1[0]=~joyp4_i;  // right
        js1[3]=~joyp1_i;  // up
        js1[2]=~joyp2_i;  // down
	end
end           
	
// ---------------------------------------------------------------------------------
// -------------------------------------- video ------------------------------------
// ---------------------------------------------------------------------------------

reg [14:0] vaddr1;
wire [14:0] vaddr2,svaddr2,evaddr2;
wire [15:0] vdout1;
wire  [15:0] vdout2;
reg [15:0] vdin1;
reg [15:0] vdin2=16'd0;
reg [1:0] vw1,vw2=2'b00;


// dual bus video ram
vram vram (
  .clka(clk325),    // input clka
  .wea(vw1),       // input [0 : 0] wea
  .addra(vaddr1),   // input [14 : 0] addra
  .dina(vdin1),    // input [15 : 0] dina
  .douta(vdout1),   // output [15 : 0] douta
  .clkb(clk325),   // input clkb
  .web(2'b00),    // input [0 : 0] web
  .addrb(vaddr2), // input [14 : 0] addrb
  .dinb(vdin2),   // input [15 : 0] dinb
  .doutb(vdout2) // output [15 : 0] doutb
);


wire [2:0] video_r, video_g, video_b;
wire [2:0] vid_r, vid_g, vid_b;
wire sp_on =sp1_on | sp2_on;

//wire [2:0] sp_r = sp1_on ? {sp1_r,sp1_f,sp1_r} : sp2_on ? {sp2_r,sp2_f,sp2_r} : {sp3_r,sp3_f,sp3_r};
//wire [2:0] sp_g = sp1_on ? {sp1_g,sp1_f,sp1_g} : sp2_on ? {sp2_g,sp2_f,sp2_g} : {sp3_g,sp3_f,sp3_g};
//wire [2:0] sp_b = sp1_on ? {sp1_b,sp1_f,sp1_b} : sp2_on ? {sp2_b,sp2_f,sp2_b} : {sp3_b,sp3_f,sp3_b};

wire [2:0] sp_r = sp1_on ? {sp1_r,sp1_f,sp1_r} : {sp2_r,sp2_f,sp2_r}; 
wire [2:0] sp_g = sp1_on ? {sp1_g,sp1_f,sp1_g} : {sp2_g,sp2_f,sp2_g};
wire [2:0] sp_b = sp1_on ? {sp1_b,sp1_f,sp1_b} : {sp2_b,sp2_f,sp2_b};

assign video_r = sp_on ? sp_r : col256 ? vdata[7:5] : vid_r; 
assign video_g = sp_on ? sp_g : col256 ? vdata[4:2] : vid_g; 
assign video_b = sp_on ? sp_b : col256 ? {vdata[1:0],1'b0} : vid_b; 

wire video_hs, svideo_hs, evideo_hs, video_vs, svideo_vs, evideo_vs;
wire iblank,siblank,eiblank;
assign iblank = col256 ? eiblank : siblank;
assign video_hs = col256 ? evideo_hs : svideo_hs;
assign video_vs = col256 ? evideo_vs : svideo_vs;

// the zx8301 has only one write-only register at $18063
wire zx8301_cs =  cpu_io && ({cpu_addr[6:5], cpu_addr[1]} == 3'b111)&& cpu_wr && !cpu_ds[0];
	 
wire mode;
wire membase;
wire blank;
wire col16;
reg col256=0;
wire [5:0] palette;

assign col16=params[8];
assign palette=params[14:9];

zx8301min zx8301 
(
    .reset      ( reset       ),
    .clk_bus    ( clk2          ),
    .cpu_cs     ( zx8301_cs     ),
    .cpu_data   ( cpu_dout[7:0] ),
	 .mode       ( mode),
	 .membase    ( membase),
	 .blank      ( blank)
);

assign vaddr2 = col256 ? evaddr2 : svaddr2;

qlvideo  qvideo (
	.clk325(clk325),
	.reset(reset),
	.vaddress(svaddr2),
	.vdin(vdout2),
	.VSB(svideo_vs),
	.HS(svideo_hs),
	.iblank (siblank),
	.mode(mode),
	.membase(membase),
	.col16(col16),
	.palette(palette),
	.VR(vid_r),
	.VG(vid_g),
	.VB(vid_b)
	);
	
wire [7:0] vdata;	

qlvideo256  qvideo256 (
	.clk325(clk325),
	.reset(reset),
	.vaddress(evaddr2),
	.vdin(vdout2),
	.VSB(evideo_vs),
	.HS(evideo_hs),
	.iblank (eiblank),
	.mode(mode),
	.Vdata (vdata)
	);


// csync for tv15khz
// QLs vsync is positive, QLs hsync is negative
//wire vga_csync = !(!video_hs ^ video_vs);
wire vga_hsync, vga_vsync;

assign vsync_o = video_vs;
assign hsync_o = video_hs;
//assign csync_o = vga_csync;

assign rgb_r_o = blank ? 3'b000 : video_r;        
assign rgb_g_o = blank ? 3'b000 : video_g;        
assign rgb_b_o = blank ? 3'b000 : video_b;   

// ---------------------------------------------------------------------------------
// --------------------------------------- IO --------------------------------------
// ---------------------------------------------------------------------------------

wire zx8302_sel =  cpu_io && !cpu_addr[6] && cpu_enable; 
wire [1:0] zx8302_addr = {cpu_addr[5], cpu_addr[1]};
wire [15:0] zx8302_dout;

reg mdv_reverse,mdv_men=1'b0;  // mdv emulation
wire mdv_read;
wire [24:0] mdv_addr;
reg [24:0] mdv_smem=25'd5000000;
reg [24:0] mdv_emem=25'd5000000; 
reg [15:0] mdv_data;
reg mdv_ack = 1'b0;  // read acknoledge

wire [7:0] keys_s;

reg zxvs_clk = 1'b0;  // vsync for the zx8302 50hz
reg [17:0] zxvs = 18'd0;
always @(posedge clk11)
begin
   if (zxvs<18'd220000) zxvs <= zxvs + 18'd1; else begin zxvs<=18'd0; end
	if (zxvs>18'd218800) zxvs_clk=1'b1; else zxvs_clk=1'b0;
end


zx8302   
zx8302 
(
    .reset        ( reset        ),
    .init         ( !pll_locked  ),
    .clk11        ( clk11         ),
    .clk          ( clk22        ),

    .xint         ( qimi_irq     ),
    .ipl          ( cpu_ipl      ),
    .led          ( ),
    .audio        ( audio        ),
    
    // CPU connection
    .clk_bus      ( clk2         ),
    .cpu_sel      ( zx8302_sel   ),
    .cpu_wr       ( cpu_wr       ),
    .cpu_addr     ( zx8302_addr  ),
    .cpu_ds       ( cpu_ds       ),
    .cpu_din      ( cpu_dout     ),
    .cpu_dout     ( zx8302_dout  ),

    // joysticks 
    .js0          ( js0[4:0]     ),
    .js1          ( js1[4:0]     ),
	 
	 .keyb_row       (keyb_row_o),
    .keyb_col       (keyb_col_i),
	 .mbutton     (btn_multiface_n_i),
	 .gbutton     (btn_divmmc_n_i),
    
    .ps2_kbd_clk  ( ps2_key_clk   ), 
    .ps2_kbd_data ( ps2_key_data  ), 
    .keys_o       ( keys_s       ),
    
    .vs           ( zxvs_clk     ),

    // microdrive sdram interface
    .mdv_addr     ( mdv_addr    ),
    .mdv_din      ( mdv_data    ),
    .mdv_read     ( mdv_read    ),
    .mdv_men      ( mdv_ack     ),
    .mdv_reverse  ( mdv_reverse ),
	 .mdv_smem     (mdv_smem),
	 .mdv_emem     (mdv_emem)
);
     
// ---------------------------------------------------------------------------------
// --------------------------- QIMI compatible mouse -------------------------------
// ---------------------------------------------------------------------------------

// qimi is at 1bfxx

reg key_ms=1'b1;  //keyboard or mouse at ps/2 port
wire ps2_key_clk, ps2_key_data;
wire ps2_ms_clk, ps2_ms_data;
wire ps2_ms_clk_o, ps2_ms_data_o;
wire qimi_sel = cpu_io && (cpu_addr[13:4] == 10'b1111111011 || cpu_addr[13:4]== 10'b1111111001 );
wire [7:0] qimi_data;
wire [7:0] qimi_dout;
wire qimi_irq;
wire [1:0] mouse_init;
// key_ms red from configuration at init :  0 = keyboard, 1 = mouse
assign ps2_key_clk =  key_ms ? ps2_pin6_io : ps2_clk_io;
assign ps2_key_data = key_ms ? ps2_pin2_io : ps2_data_io;
assign ps2_ms_clk =   key_ms ? ps2_clk_io : ps2_pin6_io;
assign ps2_ms_data =  key_ms ? ps2_data_io : ps2_pin2_io;

assign ps2_clk_io  =key_ms ? (mouse_init[1] ?  1'bz : ps2_ms_clk_o) : 1'bz;
assign ps2_data_io =key_ms ? (mouse_init[0] ? ps2_ms_data_o : 1'bz) : 1'bz;
assign ps2_pin6_io =key_ms ? 1'bz : (mouse_init[1] ? 1'bz : ps2_ms_clk_o);
assign ps2_pin2_io =key_ms ? 1'bz : (mouse_init[0] ? ps2_ms_data_o : 1'bz);

qimi qimi
(
    .reset     ( reset          ),
    .clk       ( clk2           ),

    .cpu_sel   ( qimi_sel       ),
    .cpu_addr  ( { cpu_addr[5], cpu_addr[1] } ),
    .cpu_data  ( qimi_dout      ),
    .irq       ( qimi_irq       ),
 
    .ps2_clk   ( ps2_ms_clk ), 
    .ps2_data  ( ps2_ms_data ),
	 .ps2_clk_o   ( ps2_ms_clk_o ), 
    .ps2_data_o  ( ps2_ms_data_o ),
	 .init_flag (mouse_init)
);

// ---------------------------------------------------------------------------------
// -------------------------------------- reset ------------------------------------
// ---------------------------------------------------------------------------------

reg [14:0] reset_cnt;
wire reset = (reset_cnt != 15'h0);
always @(posedge clk2) begin
    if (!pll_locked  || !btn_reset_n_i || rom_swap) // !host_reset_n ||
        reset_cnt <= 15'h7FFE;
    else if(reset_cnt != 15'h0)
        reset_cnt <= reset_cnt - 15'h1;
end

// -------------------------------------------------------------------------
// --------- memory/io access and rom initialization ----------
// -------------------------------------------------------------------------

reg [19:0] raddr;
reg ramce=1'b1;
reg [15:0] rdata;
reg [15:0] rdout;
reg memio_go=1'b0;
reg ramwe=1'b1;
reg ramoe=1'b1;

wire [24:0] sys_addr =  { 4'd0, cpu_addr[20:1]};
wire [ 1:0] sys_ds   =  ~cpu_ds;
wire [15:0] sys_dout =  cpu_dout;
wire        sys_wr   =  (cpu_wr && cpu_ram);
wire        sys_oe   =  (cpu_rd && cpu_mem);

assign ram_addr_o = raddr;
assign ram_we_n_o = ramwe;
assign ram_cs_n_o = ramce;
assign ram_oe_n_o = ramoe;
assign ram_lb_n_o = rds[0];  
assign ram_ub_n_o = rds[1];
assign ram_data_io = ramwe ? 16'bZZZZZZZZZZZZZZZZ : rdout;
reg [2:0] estate =3'b000;
reg clk2i=1'b0;
reg steal_cycle = 1'b0;
reg [2:0] delay_cnt=3'b000;
reg [1:0] rds;
//reg cdelay=1'b0;
//wire cpu_cycle = 1'b1;//!video_cycle;

reg rom_swap = 1'b1;
reg [4:0] sstate = 5'd0;
//reg [3:0] cemask = 4'b1100;
reg [19:0] addrf;
reg [19:0] addrt;
reg [7:0] rsdata;
reg [15:0] bytecnt = 16'h7fff;

always @(posedge mclk) 
begin
	if (pll_locked)
	begin
	if (rom_swap==1'b0) begin
		case (estate)
		3'b000: begin  
			cpu_enable <= ~steal_cycle;  
			ramce <= steal_cycle ? ~mdv_read : 1'b0;
			ramoe <= steal_cycle ? ~mdv_read : ~sys_oe;
			raddr <= steal_cycle ? mdv_addr[19:0] : sys_addr[19:0];
			clk2i<=1'b0; 
			vaddr1 <=  sys_addr[14:0];  
			sp1_addra <= sys_addr[10:0]; sp2_addra <= sys_addr[10:0]; //sp3_addra <= sys_addr[9:0];
			rds <= (mdv_read & steal_cycle) ? 2'b00 : cpu_ds;
			memio_go<=1'b0;
		    if (cpu_idle & ~steal_cycle) estate<=3'b010; else estate<=3'b001; //skip cycles when cpu idle
		    if (sys_wr) rdout<=cpu_dout; ramwe <= steal_cycle ? 1'b1 : ~sys_wr;
		    estate<=3'b001;
			end
		3'b001: begin
			if (vid_mem) begin vdin1=cpu_dout; vw1 <= cpu_wr ? ~cpu_ds : 2'b00; end
			if ( steal_cycle & mdv_read ) begin mdv_data<=ram_data_io; mdv_ack=1'b1; end 
			memio_go<=1'b1; 
			if (!sys_wr) rdata <= ram_data_io; 
			if (spr_mem) begin
			     sp1_wea<= cpu_wr ? {~cpu_ds[0],~cpu_ds[1]} : 2'b00; 
			     if (sp1_addra>11'd63) sp1_dina<={cpu_dout[3:0],cpu_dout[7:4],cpu_dout[11:8],cpu_dout[15:12]}; 
			     else sp1_dina<={cpu_dout[7:0],cpu_dout[15:8]};
			end
			if (spr_mem2) begin
			     sp2_wea<= cpu_wr ? {~cpu_ds[0],~cpu_ds[1]} : 2'b00; 
			     if (sp2_addra>11'd63) sp2_dina<={cpu_dout[3:0],cpu_dout[7:4],cpu_dout[11:8],cpu_dout[15:12]}; 
			     else sp2_dina<={cpu_dout[7:0],cpu_dout[15:8]};
			end
//			if (spr_mem3) begin
//			     sp3_wea<= cpu_wr ? {~cpu_ds[0],~cpu_ds[1]} : 2'b00; 
//			     if (sp3_addra>11'd63) sp3_dina<={cpu_dout[3:0],cpu_dout[7:4],cpu_dout[11:8],cpu_dout[15:12]}; 
//			     else sp3_dina<={cpu_dout[7:0],cpu_dout[15:8]};
//			end
			if (da_mem) begin
			          if (~cpu_ds[0]) da_memory[cpu_addr[13:1]][7:0]<=cpu_dout[7:0];
			          if (~cpu_ds[1]) da_memory[cpu_addr[13:1]][15:8]<=cpu_dout[15:8];
			     end
			estate<=3'b010;
			end
		3'b010: begin
		    clk2i<=1'b1;
		    if (delay_cnt==3'b000) 
				begin delay_cnt<=params[2:0]; steal_cycle=(mdv_read & ~steal_cycle & ~cpu_idle); end //set delay  cdelay=1'b0;
			 else
				begin delay_cnt<=delay_cnt-3'b001; 
				steal_cycle=(cpu_ram | (vid_mem & ~steal_cycle) | (mdv_read & ~steal_cycle));
				//enter steal_cycle also to delay memory accesses to slow speed
			end
			ramwe <= 1'b1; vw1 <= 2'b00; sp1_wea<=2'b00; sp2_wea<=2'b00; //sp3_wea<=2'b00;
//			if ((cpu_ram | (vid_mem & ~steal_cycle) | (mdv_read & ~steal_cycle)) & mdv_read) estate<=3'b011; 
//			else begin mdv_ack<=1'b0; estate<=3'b000; end
//			end          
//		3'b011:
//		    begin 
		    mdv_ack<=1'b0;
		    estate<=3'b000;
			 end
		endcase
//		if (estate<3'b010) estate=estate+3'b001; else estate=3'b000; 
	end else begin          
		case (sstate)   //------------ initialize, read rom
			5'd0: begin
				addrf<=20'h00000; addrt<=20'h00000; bytecnt<=16'hC000;  sstate<=5'd2; 
				end
			5'd2: begin
				ramoe <= 1'b0; ramwe <= 1'b1; rds<=2'b00;
				raddr <= addrf; sstate=5'd3; ramce <= 1'b0;
				end
			5'd3: sstate<=5'd4;
			5'd4: sstate<=5'd5;
			5'd5: begin
				rdout<={ram_data_io[7:0],ram_data_io[15:8]};  sstate<=5'd6;
				end
			5'd6: begin sstate<=5'd7; ramce<=1'b1; end
			5'd7: begin
				raddr <= addrt;	
				ramce <= 1'b0; ramoe <= 1'b1; 
				sstate<=5'd8;
				end
			5'd8: begin sstate<=5'd9; ramwe <= 1'b0; end
			5'd9: sstate<=5'd10;
			5'd10: begin
				ramce<=1'b1; bytecnt<=bytecnt-16'h0001;	addrt<=addrt+20'h00001; addrf<=addrf+20'h00001;
				if (bytecnt!=0) sstate<=5'd2; else sstate<=5'd11;
				end   
			// end  loop
			5'd11: begin ramwe <= 1'b1; ramoe <= 1'b0; raddr<=20'd65537; ramce<=1'b0; sstate<=5'd12; rds<=2'b00; end //read configuration
			5'd12: sstate<=5'd13;
			5'd13: sstate<=5'd14;
			5'd14: begin sstate<=5'd31; key_ms<=ram_data_io[8]; end
			5'd31:begin rom_swap<=1'b0; estate <=3'b000; ramce<=1'b1; clk2i<=1'b0; ramoe <= 1'b1; end  //finish init
		endcase	
	end
	end else	begin cpu_enable <= 1'b0; sstate<=5'd0; estate <=3'b000; ramce<=1'b1; clk2i<=1'b0; ramoe <= 1'b1; end
end

//--------------rom----------------------------

//wire [15:0] romdata;
//reg [15:0] rom_data;
//wire [14:0] romaddr;
//assign romaddr=cpu_addr[15:1];
//reg clkrom=0;
//
//blk_mem_gen_v7_3 qlrom (
//  .clka(clk10), 
//  .addra(romaddr), 
//  .douta(romdata) 
//);

//-------------- user timer -----------------

reg [31:0] utimer=0; // 1Mhz
reg [5:0] utcnt=0;
always @(negedge clk22)
    if (utcnt<6'd21) utcnt<=utcnt+6'd1; else begin
        utimer <= utimer + 31'd1;
        utcnt<=6'd0;
    end  

reg [31:0] ntimer=0; // 22Mhz
always @(negedge clk22) ntimer <= ntimer + 31'd1;

// -------------------------------------------------------------------------
// ---------------- Leon's ql-sd + memory mapped ports ---------------------
// -------------------------------------------------------------------------

wire ql_sd_ready;
reg ql_sd_cs0_n_o=1'b1;
reg [15:0] memio_out;
reg [7:0] qlsd_din;
reg [7:0] qlsd_div = 8'd2;
reg ql_sd_w=1'b0;
wire [7:0] qlsd_data;
wire memio_rd = cpu_act && (cpu_addr[23:20] == 4'b1000);  
reg [15:0] ntimbuf,utbuf;

always @(posedge memio_go) 
begin
	if (memio_rd) begin  // read memory mapped ports
	    //--------------- ID  --------------------------------------------------
		if (cpu_addr[5:1]==5'b01111 && cpu_rd ) memio_out <= 16'h4E32;  //h 80001E
	    //--------------- QLSD --------------------------------------------------
		if (cpu_addr[5:1]==5'b00011 && cpu_rd ) memio_out <= {qlsd_data, qlsd_data };         
		if (cpu_addr[5:1]==5'b00100 && cpu_rd ) memio_out <= {7'd0, ql_sd_ready, 7'd0, ql_sd_ready};  
		//------------- RTC -------------------------------------------------------
		if (cpu_addr[5:1]==5'b10000 && cpu_rd ) memio_out <= {i2c_din,i2c_din}; //h800021
		if (cpu_addr[5:1]==5'b10001 && cpu_rd ) memio_out <= { 14'b0, i2c_err, i2c_busy }; //h800023	
		//---------------- microdrive emu
		if (cpu_addr[5:1]==5'b01010 && cpu_rd ) memio_out <= { 7'd0, mdv_smem[24:16] }; //h800015-17 microdrive start			
		if (cpu_addr[5:1]==5'b01011 && cpu_rd && !cpu_ds[0]) memio_out[7:0] <= mdv_smem[7:0];   //h800014-17 microdrive start
		if (cpu_addr[5:1]==5'b01011 && cpu_rd && !cpu_ds[1]) memio_out[15:8] <= mdv_smem[15:8]; //h800014-17 microdrive start
		//-------------- ESP UART ----------------------------------------------------------
		if (cpu_addr[5:1]==5'b10010 && cpu_rd && !cpu_ds[0]) memio_out <= {esp_dout,esp_dout}; //h800025
		if (cpu_addr[5:1]==5'b10010 && cpu_rd && !cpu_ds[1]) memio_out <= {6'b0,esp_rd,esp_dr, 6'b0,esp_rd,esp_dr}; //h800024
		//--------- AY audio ---------------------------------
		if (cpu_addr[5:1]==5'b10100 && cpu_rd && !cpu_ds[1]) memio_out[15:8] <= psg_do;  //h800028
		//------------- User timer -------------------------
		if (cpu_addr[5:1]==5'b11000 && cpu_rd) memio_out <= utimer[31:16]; utbuf<=utimer[15:0];  //h800030
		if (cpu_addr[5:1]==5'b11001 && cpu_rd) memio_out <= utbuf;  //h800032
		//------------- digital audio -----------------------------
		if (cpu_addr[5:1]==5'b11010 && cpu_rd) memio_out <= {3'd0,da_address}; //h800034 
		// ---------------- joy pins 7, 9----------------------------------------------------
		if (cpu_addr[5:1]==5'b11100 && cpu_rd && !cpu_ds[0]) begin memio_out <= {15'd0,!joyp9_i}; end //h800039 ,joyp7_o
		//------------- Net timer -------------------------		
		if (cpu_addr[5:1]==5'b11101 && cpu_rd) begin memio_out <= ntimer[31:16]; ntimbuf<=ntimer[15:0]; end  //h80003A
		if (cpu_addr[5:1]==5'b11110 && cpu_rd) memio_out <= ntimbuf;  //h80003C 
		//----------- read color mode --------------------
		if (cpu_addr[5:1]==5'b00111 && cpu_rd) memio_out <= {6'd0,col16,col256,6'd0,col16,col256};  //h80000E 
	end
end

always @(negedge memio_go) // write memory mapped ports
begin
	if (memio_rd) begin
		// ------------  ql-sd io -------------------------------------------------
		if (cpu_addr[5:1]==5'b00010 && cpu_wr ) qlsd_din <= cpu_dout[7:0];    //
		if (cpu_addr[5:1]==5'b00000 && cpu_wr ) ql_sd_w <= cpu_dout[0];       //h800001              
		if (cpu_addr[5:1]==5'b00001 && cpu_wr ) qlsd_div <= cpu_dout[7:0];    //h800003       
		if (cpu_addr[5:1]==5'b00101 && cpu_wr ) ql_sd_cs0_n_o <= cpu_dout[0]; 
      // ------------ parameters -------------------------------------------------------
		if (cpu_addr[5:1]==5'b01001 && cpu_wr && !cpu_ds[0]) params[7:0] <= cpu_dout[7:0]; //h800013 0-7 slow down 
		if (cpu_addr[5:1]==5'b01001 && cpu_wr && !cpu_ds[1]) params[15:8] <= cpu_dout[15:8]; //h800012  bit0=16 colors
		// param[2:0] slow speed 000=full
		// param[8] 0=normal flash 1=16 colors
		if (cpu_addr[5:1]==5'b00111 && cpu_wr && !cpu_ds[1]) col256 <= cpu_dout[8]; //h80000E  bit0=256 colors
		//--------------microdrive emu ---------------------------------------------------------
		if (cpu_addr[5:1]==5'b01110 && cpu_wr) mdv_reverse <= cpu_dout[0];       //h80001d microdrive sector order
		if (cpu_addr[5:1]==5'b01010 && cpu_wr && !cpu_ds[0]) mdv_smem[24:16] <= {1'b0,cpu_dout[7:0]}; //h800015-17 microdrive start
		if (cpu_addr[5:1]==5'b01011 && cpu_wr && !cpu_ds[0]) mdv_smem[7:0] <= cpu_dout[7:0];   //h800014-17 microdrive start
		if (cpu_addr[5:1]==5'b01011 && cpu_wr && !cpu_ds[1]) mdv_smem[15:8] <= cpu_dout[15:8]; //h800014-17 microdrive start
		if (cpu_addr[5:1]==5'b01100 && cpu_wr && !cpu_ds[0]) mdv_emem[24:16] <= {1'b0,cpu_dout[7:0]}; //h800018-1b microdrive end
		if (cpu_addr[5:1]==5'b01101 && cpu_wr && !cpu_ds[0]) mdv_emem[7:0] <= cpu_dout[7:0];   //h800018-1b microdrive end
		if (cpu_addr[5:1]==5'b01101 && cpu_wr && !cpu_ds[1]) mdv_emem[15:8] <= cpu_dout[15:8]; //h800018-1b microdrive end
		
		//-------------- RTC -------------------------------------------------------
		if (cpu_addr[5:1]==5'b10000 && cpu_wr ) i2c_dout <= cpu_dout[7:0]; //h800021
		if (cpu_addr[5:1]==5'b10001 && cpu_wr ) begin i2c_rw <= cpu_dout[1];  i2c_ena <= cpu_dout[0]; end //h800023
		//-------------- UART ------------------------------------------------------
		if (cpu_addr[5:1]==5'b10010 && cpu_wr && !cpu_ds[1]) begin esp_r <= cpu_dout[9]; esp_w <= cpu_dout[8]; end //h800024
		if (cpu_addr[5:1]==5'b10010 && cpu_wr && !cpu_ds[0]) begin esp_din <= cpu_dout[7:0]; end //h800025
		// ----------  AY ----------------------------------------------------
		if (cpu_addr[5:1]==5'b10100 && cpu_wr && !cpu_ds[1]) begin psg_di <= cpu_dout[15:8]; end //h800028   8388648
		if (cpu_addr[5:1]==5'b10101 && cpu_wr && !cpu_ds[1]) begin                               //h80002A   8388650
			psg_reg<= !cpu_dout[10] & cpu_dout[8]; psg_wr<= cpu_dout[10] & !cpu_dout[8]; 
			psg_addr <= cpu_dout[10] & cpu_dout[8];	end
		// ---------- esp baud rate divider  ------------------------------------------------------
		if (cpu_addr[5:1]==5'b10110 && cpu_wr ) begin esp_div <= cpu_dout[14:0]; end //h80002C   8388652
		// --------------- digitl audio -----------------------------------------------------------
		if (cpu_addr[5:1]==5'b11010 && cpu_wr ) begin da_start <= cpu_dout[0]; da_mono<= cpu_dout[8]; end //h800034  
		if (cpu_addr[5:1]==5'b11011 && cpu_wr ) begin da_period <= cpu_dout[11:0]; end //h800036   
		// ---------------- joy dissable joy2, write to pin 7 joy1 ---------------------------------------------
		if (cpu_addr[5:1]==5'b11100 && cpu_wr && !cpu_ds[0]) begin joy7 <= ~cpu_dout[7]; end //h800039
		if (cpu_addr[5:1]==5'b11100 && cpu_wr && !cpu_ds[1]) begin stop_switch<=cpu_dout[8]; end //h800038
		//------------------ CPU ------------------------------
		if (cpu_addr[5:1]==5'b11111 && cpu_wr ) begin cpu_type <= cpu_dout[1:0]; end //h80003E 8388670-1
	end
	//if (~btn_divmmc_n_i) mdv_emem<=mdv_smem; //eject mdv
end

reg [15:0] params=16'd0;

assign sd_cs0_n_o  =  ql_sd_cs0_n_o;

spi qlsdspi(
	.sclko    (sd_sclk_o),
	.mosi     (sd_mosi_o),
	.miso     (sd_miso_i),
	.clk      (clk325n),
	.reset    (reset),
	.w		  (ql_sd_w),
	.readyo   (ql_sd_ready),
	.data_in  (qlsd_din),
	.data_out (qlsd_data),
	.divider  (qlsd_div)
);

//------------------- ESP UART -----------------------------------------

reg  [7:0] esp_din;
wire [7:0] esp_dout;
reg esp_r,esp_w=0;
wire esp_rd,esp_dr;
reg  [14:0] esp_div=15'd191;  // 191 = 115200 bps

UART esp_uart (
		.Tx  (esp_tx_o),
		.Rx  (esp_rx_i),
		.clk (clk22), 
		.reset (reset), 
		.r (esp_r), 
		.w (esp_w),
		.data_ready (esp_dr),
		.ready (esp_rd),
		.data_in (esp_din),
		.data_out (esp_dout),
		.speed (esp_div) // 191 = 115200 bps
	);

// ---------------------------------------------------------------------------------
// -------------------------------------- CPU --------------------------------------
// ---------------------------------------------------------------------------------

// address decoding
wire cpu_act = cpu_rd || cpu_wr;
wire cpu_io   = cpu_act && (cpu_addr[23:14] == 10'b0000000110);   // internal IO $18000-$1bfff
wire cpu_bram = cpu_act &&(cpu_addr[23:16] == 8'b00000011);          // RAM at $20000
wire cpu_xram = cpu_act && ((cpu_addr[23:18] == 6'b000001) ||          
                            (cpu_addr[23:18] == 6'b000010) ||          
                            (cpu_addr[23:18] == 6'b000011) ||          
                            (cpu_addr[23:20] == 4'b0001));       
wire cpu_ram = cpu_bram || cpu_xram;                           // any RAM
wire cpu_rom  = cpu_act && (cpu_addr[23:16] == 8'h0 || cpu_addr[23:15] == 9'h02);   // 64k+32K ROM at $0
wire cpu_mem  = cpu_ram || cpu_rom;
wire vid_mem  = cpu_act &&(cpu_addr[23:16] == 8'b00000010);     // video ram
wire spr_mem   = cpu_wr && (cpu_addr[23:12] == 12'b110000000000); //sprite memory
wire spr_mem2  = cpu_wr && (cpu_addr[23:12] == 12'b110000000001);
//wire spr_mem3  = cpu_wr && (cpu_addr[23:12] == 12'b110000000010);
wire da_mem    = cpu_wr && (cpu_addr[23:14] == 10'b1100000001);

wire [15:0] io_dout = 
    qimi_sel?{qimi_dout, qimi_dout}:
    (!cpu_addr[6])?zx8302_dout:
    16'h0000;   

// demultiplex the various data sources
wire [15:0] cpu_din =
	memio_rd?{ memio_out}: 
    cpu_io? io_dout:	 
    cpu_mem? rdata:
	vid_mem? {vdout1} :
	//spr_mem? sp1_douta :
	//spr_mem2? sp2_douta :
	16'hffff;

wire [31:0] cpu_addr;
wire [1:0] cpu_ds;
wire [15:0] cpu_dout;
wire [1:0] cpu_ipl;
wire cpu_rw;
wire [1:0] cpu_busstate;
wire cpu_rd = (cpu_busstate == 2'b00) || (cpu_busstate == 2'b10);
wire cpu_wr = (cpu_busstate == 2'b11) && !cpu_rw;
wire cpu_idle = (cpu_busstate == 2'b01);

reg cpu_enable;
reg [1:0] cpu_type=2'b00;

TG68KdotC_Kernel #(2,2,2,2,2,2,2,1) 
tg68k (
    .clk            ( clk2           ),
    .nReset         ( ~reset         ),
    .clkena_in      ( cpu_enable     ), 
    .data_in        ( cpu_din        ),
    .IPL            ( {cpu_ipl[0], cpu_ipl[1], cpu_ipl[0]}),  // ipl 0 and 2 are tied together on 68008
    .IPL_autovector ( 1'b1           ),
    .berr           ( 1'b0           ),
    .clr_berr       ( ),                  //1'b0           ),
    .CPU            ( cpu_type       ),   // 00=68000  // 11=68020
    .addr_out       ( cpu_addr       ),
    .data_write     ( cpu_dout       ),
    .nUDS           ( cpu_ds[1]      ),
    .nLDS           ( cpu_ds[0]      ),
    .nWr            ( cpu_rw         ),
    .busstate       ( cpu_busstate   ), // 00-> fetch code 10->read data 11->write data 01->no memaccess
    .nResetOut      (                ),
    .FC             (                )
);

//------------- HDMI -------------------------------------


wire [9:0] ored,ogreen,oblue;
wire [3:0] tmds_out_p,tmds_out_n;
wire [15:0] pcm_audio_L,pcm_audio_R;

assign pcm_audio_L = da_playing ? (da_mono ? da_data : {audio, da_data[7:0], 7'd0} ) :
                                  {audio, {1'b0,psg_A}+{1'b0,psg_B}, 6'd0};
assign pcm_audio_R = da_playing ? (da_mono ? {audio, audio_mixed, 5'd0} : {audio, da_data[15:8], 7'd0}) : 
                                  {audio, {1'b0,psg_A}+{1'b0,psg_C}, 6'd0};

hdmi_out_xilinx qlhdmiqout (
	.clock_pixel_i 	(clk65),
	.clock_tmds_i  	(clk1625),
	.clock_tmds_n_i (clk1625n),
	.red_i	(ored),
	.green_i	(ogreen),
	.blue_i	(oblue),
	.tmds_out_p (hdmi_p_o),
	.tmds_out_n (hdmi_n_o)
); 

hdmi qlhdmi (
	.I_CLK_PIXEL (clk65),
	.I_R         	( {video_r, 5'd0} ),   
	.I_G         	( {video_g, 5'd0} ),
	.I_B         	( {video_b, 5'd0} ),
	.I_BLANK			( iblank ),
	.I_HSYNC			( video_hs ),
	.I_VSYNC      	( video_vs ),
	.I_AUDIO_ENABLE ( 1'b1 ),
	.I_AUDIO_PCM_L   ( pcm_audio_L ),
	.I_AUDIO_PCM_R    ( pcm_audio_R ),
	.O_RED 	(ored),
	.O_GREEN (ogreen),
	.O_BLUE	(oblue)
	);
//--------------------------------------------------------
//-- Unused outputs
//--------------------------------------------------------

// -- Interal audio (speaker, not fitted)
assign audioint_o     = 1'bZ;

//-- Spectrum Next Bus
assign bus_addr_o     = 16'bZ;
assign bus_busack_n_o = 1'bz;
assign bus_clk35_o    = 1'bz;
assign bus_data_io    = 8'bZ;
assign bus_halt_n_o   = 1'bz;
assign bus_iorq_n_o   = 1'bz;
assign bus_m1_n_o     = 1'bz;
assign bus_mreq_n_o   = 1'bz;
assign bus_rd_n_io     = 1'bz;
assign bus_rfsh_n_o   = 1'bz;
assign bus_rst_n_io   = 1'bz;
assign bus_wr_n_o     = 1'bz;
assign bus_int_n_io   = 1'bz;
//assign bus_romcs_i    = 1'bZ;
assign bus_y_o        = 1'bz;

//-- ESP 8266 module
assign esp_gpio0_io   = 1'bZ;
assign esp_gpio2_io   = 1'bZ;
assign esp_cts_n_o    =1'b0;
//assign esp_tx_o       = 1'b1;
 
assign flash_hold_o   = 1'b1;
assign flash_wp_o     = 1'b1; 
assign flash_cs_n_o   = 1'b1;
assign flash_sclk_o   = 1'b1;
assign flash_mosi_o   = 1'b1;
    
//assign i2c_scl_io     = 1'bZ;
//assign i2c_sda_io     = 1'bZ;

//-- Pin 7 on the joystick connecter. 
//assign joyp7_o        = 1'bZ;

//-- Controls a mux to select between two joystick ports
//assign joysel_o       = 1'b;

//-- Keyboard row
//assign keyb_row_o     = 8'hFF;

//-- Mic Port (output, as it connects to the mic input on cassette deck)
//assign ear_port_i     = 1'b1;
assign mic_port_o     = 1'bZ;

 //-- CS2 is for internal SD socket
assign sd_cs1_n_o     = 1'b1;
 
// PI GPIO
assign accel_io       = 28'bZZZZZZZZZZZZZZZZZZZZZZZZZZZZ;

// Vacant pins
assign extras_o      = 1'bz;
assign extras_2_io      = 1'bz;
assign extras_3_io      = 1'bz;

assign adc_control_o = 1'bz;


endmodule


