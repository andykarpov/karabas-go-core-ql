# Sinclair QL core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

The **Sinclair QL** home computer for the Karabas Go board family (Xilinx Spartan-6 XC6SLX25). A port of the [QL core of the ZX Spectrum Next](https://gitlab.com/thesmog358/qlnext) by Theodoulos Liontakis, based on the MiST core by Till Harbaum and Victor Trucco. One core file, `ql.kg`, for all three boards.

| Board | Video | Sound | Synth in the mix |
|---|---|---|---|
| Karabas Go | VGA 1024 x 768 60 Hz | I2S DAC (PCM5102) | no |
| Karabas Mini | HDMI 1024 x 768 60 Hz | HDMI, analog output (sigma-delta) | no |
| Karabas Mini G | HDMI 1024 x 768 60 Hz | HDMI, I2S DAC (PCM5102) | yes |

Status: build 26110908. Checked on Mini G: Minerva, video, keyboard, mouse buttons and movement, the clock, the sound, SD card images (read and write). **The microdrive does not work yet.** The Go and Mini builds have not been run on a board, and MIDI has not been checked on any board.

A detailed guide in Russian: [docs/GUIDE.md](docs/GUIDE.md). Open issues: [docs/BACKLOG.md](docs/BACKLOG.md).

## The machine

The Sinclair QL (1984) has a Motorola 68008 processor, the QDOS multitasking operating system and the SuperBASIC language. The screen is 512 x 256 in 4 colours or 256 x 256 in 8 colours.

This core has:

- **CPU:** TG68K in 68000 mode at 10.83 MHz, much faster than a real QL.
- **Memory:** 1920 KB.
- **OS:** Minerva 1.98a1 is built in. Another OS can be loaded from the SD card.
- **Video:** the QL modes 4 and 8, plus the 16 and 256 colour modes of the Next core.
- **Sound:** the IPC beeper and the AY of the Next core.
- **Storage:** an SD card image through the QLFAT32 driver, which is built in. Read and write.
- **Mouse:** USB, seen as a QIMI interface.
- **Joysticks:** USB. The first works as the cursor keys and Space, the second as F1 to F5.
- **Clock:** the date and time come from the clock of the board at each start.
- **MIDI:** a USB MIDI keyboard, and MIDI OUT to the SAM2695 synth of the board.

## What goes where

| File | Where | What for |
|---|---|---|
| `ql.kg` (in `src/`) | root of the SD card | the core |
| `*.img` | `/ql` | SD card images for the QL |
| `*.rom`, `*.bin` | `/ql` | another OS or an extension ROM (optional) |

Create the `/ql` folder yourself. The core starts without any files: the ROMs it needs are inside `ql.kg`.

## First start

1. Copy `ql.kg` to the SD card and choose **Sinclair QL** in the core menu.
2. After the memory test (5 to 8 seconds) Minerva asks for the display mode. Press **F1** for the monitor mode (85 columns, the right choice for HDMI) or **F2** for the TV mode (40 columns). F3 and F4 are the same with two screens. With no key for about 10 seconds Minerva chooses TV by itself.
3. The SuperBASIC prompt appears. Try:

```
print date$
beep 20000,10
mode 8
```

## OSD menu

Open it with **Menu+Esc**. "Menu" is the Windows key of the keyboard.

| Item | Values | Hotkey |
|---|---|---|
| OS ROM | 48 KB or 64 KB file; restarts the machine | Menu+F1 |
| Back ROM | ROM at $C000, replaces the built-in QLFAT32 | Menu+F2 |
| MDV1 | `.mdv` image, 174930 bytes (not readable by QDOS yet) | Menu+F3 |
| SD card | `.img` image | Menu+F4 |
| Reset | resets the machine | F12 |
| MDV order | Normal / Reverse | |
| SD2 card | Off (default) / On | |
| MDV speed | Normal / Fast (default) | |
| MIDI thru | Off / On (default) | |

**SD2 card = On** gives the real card of the second slot to the driver as `sdb1_`. The driver writes to the card it sees, so leave this off if the card holds anything important. This mode has not been checked on a board.

## Keyboard

Most keys work as on a PC. The special ones:

| PC | QL |
|---|---|
| Backspace | Ctrl+Left: delete to the left |
| Delete | Ctrl+Right: delete to the right |
| Page Up, Page Down | Shift+Up, Shift+Down |
| Home, End | Alt+Left, Alt+Right |
| F6 to F10 | Shift+F1 to Shift+F5 |
| Esc | Esc (to break a BASIC program: Ctrl+Space) |

## SD card images

The QL sees an image as a real SD card, so it needs an MBR partition table and a FAT32 partition. An image taken from a real card works too. The driver names the partitions `sda1_`, `sda2_` and so on.

On Linux (packages `mtools`, `util-linux`):

```sh
dd if=/dev/zero of=sd.img bs=1M count=64
printf 'label: dos\nstart=2048, type=c\n' | sfdisk sd.img
mformat -i sd.img@@1M -F -c 1 -v QLCARD ::
mcopy -i sd.img@@1M MYFILE.TXT ::
```

FAT32 needs at least about 33 MB. Put `sd.img` in `/ql`, select it in the OSD (Menu+F4) and press F12. Then:

```
dir sda1_
copy "sda1_hello.txt" to "sda1_new.txt"
```

Write a file name with a dot in quotes in `COPY`. The driver prints `SDA:y` at the start when it has found the card.

`QXL.WIN` containers (QPC2, QemuLator) need the `qlwa_rext` driver, which is not in the core. This has not been tried.

## MIDI

Connect a USB MIDI keyboard. While **MIDI thru** is on it plays the synth of the board directly.

The QL has no MIDI port and no ready-made software for this one. Programs can use these ports:

| Address | Read | Write |
|---|---|---|
| $800026 (8388646) | bit 0: a byte has arrived; bit 1: ready to send | |
| $800027 (8388647) | the next received byte, taken from a 64 byte queue | a byte to the synth |

A note from BASIC (channel 1, note 60, velocity 100):

```
poke 8388647,144
poke 8388647,60
poke 8388647,100
```

## Software and games

- [Dilwyn Jones: Sinclair QL Pages](https://www.sinclairql.net/): the largest archive of operating systems, games, utilities and documentation.
- [The Sinclair QL Forum](https://theqlforum.com/).
- [ZX Next distribution, `machines/ql`](https://gitlab.com/thesmog358/tbblue): the ROMs and drivers of this core, images in `mdvs/`.
- [QL on MiSTer](https://www.kilgus.net/ql/mister/) by Marcel Kilgus: operating systems and a demo `QXL.WIN` image.

Most software comes as microdrive or floppy images. While the microdrive does not work, the files have to be moved to an SD image. Executable QDOS files need a header that a plain copy loses.

## Limitations

- The microdrive does not work: the image loads, but `dir mdv1_` answers `not found`. The cause has not been found.
- There is no mode with the speed of a real QL, so some old games may run too fast.
- Not supported: the QLNet network, serial ports, the sprites and the PCM sound of the Next core.
- No QDOS driver for the MIDI ports.
- The sound of the synth reaches the common output only on Mini G.

## Build

Clone with `--recursive` (the `modules` submodule). ISE 14.7: `cd src && make` for all boards or `make minig` (`go`, `mini`) for one; the result is `src/ql.kg`. The tops of Go and Mini are generated from the Mini G top by `src/tools/gen_tops.py`.

Simulation of the machine (ghdl and Verilator): `src/sim/run_boot.sh`. The plan and the design decisions are in [docs/PLAN.md](docs/PLAN.md), in Russian.

## Authors

- **QL core of the ZX Spectrum Next:** Theodoulos Liontakis ([qlnext](https://gitlab.com/thesmog358/qlnext)).
- **MiST core of the QL:** Till Harbaum, Victor Trucco.
- **TG68K:** Tobias Gubener. **T48 (the IPC):** Arnim Läuger. **YM2149:** MikeJ.
- **Minerva, QLFAT32:** their authors; the files come from the ZX Spectrum Next distribution.
- **The port to Karabas** and the [board modules](https://github.com/andykarpov/karabas-go-modules): Andy Karpov and contributors.

## License

GPL v3 ([LICENSE](LICENSE)). Each source file keeps its own header. The ROMs in `src/roms` are unchanged data of their authors.
