# 🕹️ openFPGA Pac-Man

A hardware-compatible FPGA core of the **Namco Pac-Man arcade board** for the [Analogue Pocket](https://www.analogue.co/pocket). One core covers **Pac-Man**, **Ms. Pac-Man**, and other same-board variants — they all run on identical 1980 Pac-Man hardware, just with different ROMs.

> Status: **playable on hardware** (v0.1.0) — Pac-Man, Ms. Pac-Man, and their speed-hack variants run on the Pocket, with sound.

## 🎮 What it is

The core is a faithful gateware implementation of the Pac-Man hardware: a Z80 @ 3.072 MHz, the Namco tilemap + 8-sprite video, the 3-voice Namco WSG sound, and the palette PROMs. Pac-Man's vertical cabinet is handled by the Pocket's scaler (portrait rotation), not in logic.

## 🎮 Games

One core, four games — pick which to run from the Pocket's core menu:

- **Pac-Man** and **Ms. Pac-Man**
- **Pac-Man (speedup)** and **Ms. Pac-Man (speedup)** (under `_speedhacks`)

They all run on the same 1980 Pac-Man board; the core applies the per-variant byte for whichever you select.

## 📦 ROMs — bring your own

This core ships **no game ROMs**. Supply your own MAME sets (`pacman`, `mspacman`, `pacmanf`, `mspacmnf`) and assemble the per-game images:

```bash
python3 tools/build_roms.py --zipdir /path/to/your/mame/zips
```

This writes `pacman.rom`, `mspacman.rom`, `pacmanf.rom`, and `mspacmnf.rom`. Copy them into `Assets/pacman/TheDiscordian.PacMan/` on your Pocket SD card, alongside the game-select files, then launch the core and pick a game.

## 🔧 Building

Needs Docker (for Quartus Prime Lite) and Python 3. Clone with submodules (or just run the build — it initialises them):

```bash
git clone --recursive https://github.com/TheDiscordian/openfpga-pacman
./build.sh
```

This compiles the FPGA project, reverses the bitstream to the Pocket's `.rbf_r` format, and stages the SD package under `dist/`. Copy `dist/` to your Pocket SD card.

## 🙏 Credits

- **MikeJ / [fpgaarcade](https://www.fpgaarcade.com/kb/pacman/)** — the Pac-Man hardware VHDL (and the YM2149 model).
- **Daniel Wallner** — the T80 Z80 CPU core.
- **Arnim Laeuger** — the SN76489 PSG.
- **Sorgelig / [MiSTer Arcade-Pacman](https://github.com/MiSTer-devel/Arcade-Pacman_MiSTer)** — the integrated core this port derives from.
- **[agg23/analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils)** — the APF loader / I2S helper IP (MIT).

This project's own work is **MIT** (`LICENSE`). Bundled upstream HDL retains its own licenses — see [`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md) for the per-component disclosure.

## ⚖️ Notice

Independent hardware-compatible FPGA core. Pac-Man and Ms. Pac-Man are trademarks of Bandai Namco Entertainment Inc.; not affiliated or endorsed.
