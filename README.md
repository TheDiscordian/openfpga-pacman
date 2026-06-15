# 🕹️ openFPGA Pac-Man

A hardware-compatible FPGA core of the **Namco Pac-Man arcade board** for the [Analogue Pocket](https://www.analogue.co/pocket). One core covers **Pac-Man**, **Ms. Pac-Man**, and other same-board variants — they all run on identical 1980 Pac-Man hardware, just with different ROMs.

> Status: **early development** (v0.1.0) — APF wrapper bring-up. Not yet playable on device. See `PLAN.md` for the roadmap.

## 🎮 What it is

The core is a faithful gateware implementation of the Pac-Man hardware: a Z80 @ 3.072 MHz, the Namco tilemap + 8-sprite video, the 3-voice Namco WSG sound, and the palette PROMs. Pac-Man's vertical cabinet is handled by the Pocket's scaler (portrait rotation), not in logic.

## 📦 ROMs — bring your own

This core ships **no game ROMs**. You supply your own dump:

1. Obtain a Pac-Man / Ms. Pac-Man ROM set you are legally entitled to (e.g. the MAME `pacman` or `mspacman` set).
2. Assemble it into a single `.rom` blob with an MRA tool ([mra-tools-c](https://github.com/sebdel/mra-tools-c)).
3. Drop it in `Assets/pacman/common/` on your Pocket SD card.

## 🔧 Building

Needs Docker (for Quartus Prime Lite) and Python 3:

```bash
./build.sh
```

This compiles the FPGA project, reverses the bitstream to the Pocket's `.rbf_r` format, and stages the SD package under `dist/`. Copy `dist/` to your Pocket SD card.

## 🙏 Credits

- **MikeJ / [fpgaarcade](https://www.fpgaarcade.com/kb/pacman/)** — the Pac-Man hardware VHDL.
- **Daniel Wallner** — the T80 Z80 CPU core.
- **[MiSTer Arcade-Pacman](https://github.com/MiSTer-devel/Arcade-Pacman_MiSTer)** (Sorgelig / MiSTer-devel) — the integrated core this port derives from.
- **[agg23/analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils)** — the APF loader / I2S helper IP.

All upstream HDL is 3-clause BSD. See `LICENSE`.

## ⚖️ Notice

Independent hardware-compatible FPGA core. Pac-Man and Ms. Pac-Man are trademarks of Bandai Namco Entertainment Inc.; not affiliated or endorsed.
