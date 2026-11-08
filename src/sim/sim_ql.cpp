// The QL machine (ql.v) with the SRAM as a C++ array: a boot of the ROM, frames in PPM.
// Usage: Vql <ms of QL time> <frame every ms> rom@byte_address_hex ...
#include "Vql.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static uint16_t sram[1 << 21];
static uint8_t frame[768][512][3];

static void load(const char *arg) {
	const char *at = strchr(arg, '@');
	std::string name(arg, at - arg);
	unsigned addr = strtoul(at + 1, nullptr, 16);
	FILE *f = fopen(name.c_str(), "rb");
	if (!f) { perror(name.c_str()); exit(1); }
	int c;
	while ((c = fgetc(f)) != EOF) {
		if (addr & 1) sram[addr >> 1] = (sram[addr >> 1] & 0xFF00) | c;
		else sram[addr >> 1] = (sram[addr >> 1] & 0x00FF) | (c << 8);
		addr++;
	}
	fclose(f);
}

static void write_frame(int n) {
	char name[64];
	snprintf(name, sizeof name, "build/frame_%04d.ppm", n);
	FILE *f = fopen(name, "wb");
	fprintf(f, "P6\n512 768\n255\n");
	fwrite(frame, 1, sizeof frame, f);
	fclose(f);
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	Vql top;
	double ms = atof(argv[1]);
	double every = atof(argv[2]);
	for (int i = 3; i < argc; i++) load(argv[i]);

	const uint64_t per_ms = 32500;
	const uint64_t total = (uint64_t)(ms * per_ms);
	uint64_t next_frame = (uint64_t)(every * per_ms);
	int frames = 0, x = 0, y = 0, was_vs = 1, was_hs = 1;
	top.reset = 1;
	top.kbd_matrix = 0;
	top.sd_rx = 0xFF;
	top.sd_ready = 1;
	top.mdv_start = 0;
	top.mdv_end = 0;
	std::vector<uint32_t> pcs;
	uint32_t last_pc = 0;
	uint64_t same = 0;

	for (uint64_t t = 0; t < total; t++) {
		top.clk = 0;
		top.ram_din = sram[top.ram_addr];
		top.eval();
		top.clk = 1;
		top.eval();
		if (t == 2000) top.reset = 0;

		if (!(top.ram_we_n & 2)) sram[top.ram_addr] = (sram[top.ram_addr] & 0x00FF) | (top.ram_dout & 0xFF00);
		if (!(top.ram_we_n & 1)) sram[top.ram_addr] = (sram[top.ram_addr] & 0xFF00) | (top.ram_dout & 0x00FF);

		if (top.video_de && y < 768 && x < 512) {
			frame[y][x][0] = top.video_r << 5;
			frame[y][x][1] = top.video_g << 5;
			frame[y][x][2] = top.video_b << 5;
			x++;
		}
		if (was_hs && !top.video_hs) { if (x) y++; x = 0; }
		if (was_vs && !top.video_vs) {
			y = 0;
			x = 0;
			if (t >= next_frame) {
				write_frame(frames++);
				next_frame += (uint64_t)(every * per_ms);
				printf("%7.1f ms  pc %06x\n", t / (double)per_ms, top.dbg_cpu_addr & 0xFFFFFF);
				fflush(stdout);
			}
		}
		was_hs = top.video_hs;
		was_vs = top.video_vs;
	}
	return 0;
}
