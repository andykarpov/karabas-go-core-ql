# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A Sinclair QL core for the Karabas Go, Mini and Mini G boards (Xilinx Spartan-6 XC6SLX25, ISE 14.7, XST): a port of the QL core of the ZX Spectrum Next (https://gitlab.com/thesmog358/qlnext).

Docs, in Russian: `docs/PLAN.md` (research, decisions, phases). Follow the phases, one branch and one PR per phase; record a changed decision in PLAN.md. Ask before every check on a board and go through `hwq` (notes: hw-queue).

The machine runs on one clock (32.5 MHz) with clock enables; the core is GPL v3. All file work goes through the firmware (OSD, `FL` / `F` items, burst, `img_sdc`). No SDRAM.

Templates: `../karabas-go-core-atarist` (68000 machine, Makefile, HID), `../karabas-go-core-bk` (1024 x 768 HDMI at 65 MHz), `../karabas-go-core-specialist` (`spec_sd.v`, an SD card on an image).

## Layout

- `src/Makefile`: `make ql-xst` = the machine alone (fit check), `make minig` etc. `src/core.json`: the core file (kgo2, `ql.kg`).
- `src/rtl/ql/`: the machine. `ql.v`, `ql_video.v` are ours; `zx8302.v`, `ipc.v`, `mdv.v` upstream rewritten to one clock (`// karabas:`). `src/rtl/tg68k`, `src/rtl/t48`, `ym2149.vhd`: upstream unchanged. Other files of `rtl/ql` are imported and not used so far.
- `upstream/`: the top and constraints of the Next core, the source commit.
- `src/sim/run_boot.sh [ms] [every ms] [rom@hexaddr...]`: verilator run of the machine, the VHDL through `ghdl --synth` (sim only); frames in `src/sim/build/*.ppm`. RAM is cut to $7FFFF there.
