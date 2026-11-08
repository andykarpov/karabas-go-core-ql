#!/bin/bash
# The QL machine in verilator (the VHDL through ghdl --synth): boots a ROM, writes frames to build/.
# Usage: run_boot.sh [ms of QL time, default 1500] [ms between frames, default 500] [rom@hex ...]
set -e
cd "$(dirname "$0")"
MS=${1:-1500}; EVERY=${2:-500}; shift 2 2>>build/ghdl.log || true
ROMS=("$@"); [ ${#ROMS[@]} -gt 0 ] || ROMS=(../roms/min198a1.rom@0)
RTL=../rtl
B=build/ghdl; mkdir -p "$B"
G="--std=08 -frelaxed -fsynopsys --workdir=$B"

ghdl -a $G $RTL/tg68k/TG68K_Pack.vhd $RTL/tg68k/TG68K_ALU.vhd $RTL/tg68k/TG68KdotC_Kernel.vhd 2>>build/ghdl.log
ghdl --synth $G --out=verilog -gSR_Read=0 -gVBR_Stackframe=0 -gextAddr_Mode=0 -gMUL_Mode=0 -gDIV_Mode=0 \
	-gBitField=0 -gBarrelShifter=0 -gMUL_Hardware=1 tg68kdotc_kernel 2>>build/ghdl.log > build/tg68k.v
T=$RTL/t48
for f in t48_pack-p t48_tb_pack-p alu_pack-p cond_branch_pack-p decoder_pack-p dmem_ctrl_pack-p pmem_ctrl_pack-p t48_comp_pack-p \
	t48_core_comp_pack-p alu bus_mux clock_ctrl cond_branch db_bus decoder dmem_ctrl int opc_table opc_decoder \
	p1 p2 pmem_ctrl psw timer t48_core; do ghdl -a $G $T/$f.vhd 2>>build/ghdl.log; done
for f in generic_ram_ena t48_rom-e t49_rom-e t48_system_comp_pack-p rom_t49; do ghdl -a $G $T/system/$f.vhd 2>>build/ghdl.log; done
ghdl -a $G $T/t8049_notri.vhd 2>>build/ghdl.log
ghdl --synth $G --out=verilog -ggate_port_input_g=0 t8049_notri 2>>build/ghdl.log > build/t8049.v
ghdl -a $G $RTL/ql/ym2149.vhd 2>>build/ghdl.log
ghdl --synth $G --out=verilog ym2149 2>>build/ghdl.log > build/ym2149.v
sed -i 's/^module tg68kdotc_kernel/module TG68KdotC_Kernel/' build/tg68k.v
sed -i 's/^module ym2149/module YM2149/' build/ym2149.v

# ghdl --synth has fixed the generics: the instances lose theirs
# and the RAM ends at $7FFFF: Minerva tests all of it at boot, 2 MB would take minutes of simulation
sed -e '/^TG68KdotC_Kernel #(/,/^) tg68k (/c\TG68KdotC_Kernel tg68k (' \
	-e "/(cpu_addr\[23:18\] == 6'b000010) ||/d" -e "/(cpu_addr\[23:18\] == 6'b000011) ||/d" \
	-e "s/(cpu_addr\[23:18\] == 6'b000001) ||/(cpu_addr[23:18] == 6'b000001));/" \
	-e "/^ *(cpu_addr\[23:20\] == 4'b0001));/d" $RTL/ql/ql.v > build/ql_sim.v
sed 's/t8049_notri #(.gate_port_input_g(0)) t8049/t8049_notri t8049/' $RTL/ql/ipc.v > build/ipc_sim.v

verilator --cc --exe --build -j 8 -O3 --x-assign fast --x-initial fast --noassert -Wno-fatal -Wno-lint -Wno-style \
	--top-module ql --Mdir build/v -CFLAGS -O2 -o Vql \
	build/tg68k.v build/t8049.v build/ym2149.v \
	build/ql_sim.v $RTL/ql/ql_video.v $RTL/ql/zx8302.v build/ipc_sim.v $RTL/ql/mdv.v ../../modules/rtl/mem/kg_tdpram.v \
	$PWD/sim_ql.cpp > build/verilate.log 2>&1 || { tail -30 build/verilate.log; exit 1; }
time build/v/Vql "$MS" "$EVERY" "${ROMS[@]}"
