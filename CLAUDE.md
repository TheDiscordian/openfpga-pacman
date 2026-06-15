# openFPGA Pac-Man — Dev Guide

A real HDL Analogue Pocket core. It ports the BSD-licensed MiSTer Arcade-Pacman RTL into an APF (Analogue Pocket Framework) wrapper. Roadmap and architecture live in `PLAN.md`; user-facing docs in `README.md`.

## What this is

- Target FPGA: Intel Cyclone V **`5CEBA4F23C8`** (the Pocket's developer-accessible core FPGA).
- Core identity: author `TheDiscordian`, shortname `PacMan` → SD folder **`TheDiscordian.PacMan`**. These three must stay in lockstep (`core.json` + folder + any inventory PR) or the Pocket throws "General core error".
- Covers Pac-Man, Ms. Pac-Man, and same-board variants (identical hardware, different ROMs).

## Build

```bash
./build.sh
```

Compiles the FPGA project, reverses the bitstream, and stages the SD package under `dist/`. Requires Docker (the build runs Quartus Prime Lite in a container) and Python 3.

- Quartus output: `src/fpga/output_files/ap_core.rbf`
- Reversed for the Pocket: `tools/reverse_rbf.py` → `output/bitstream.rbf_r` (**mandatory** — a non-reversed `.rbf` will not boot).
- Deploy: copy `dist/` onto the Pocket SD card (the `Cores/`, `Platforms/`, `Assets/` trees).

## Layout

- `src/fpga/` — APF skeleton from `open-fpga/core-template` (`ap_core.qpf/qsf`, `apf/`, `core/core_top.v`, the PLL, SDC).
- `src/fpga/core/rtl/` — vendored MiSTer Pac-Man RTL (BSD). `pacman.vhd` is the core; `cpu/` is T80; `pacman_audio/video/vram*.vhd` + `pacman_rom_descrambler.vhd` + `dpram.vhd`. `sn76489/` + `ym2149.sv` are for variants with extra sound. **`hiscore.v` was removed (GPL).**
- `libs/analogue-pocket-utils/` — agg23 IP (`data_loader`, `sound_i2s`, `sync_fifo`). Don't hand-roll the bridge↔RAM glue.
- `dist/` — SD package staging (Cores/Platforms/Assets). `dist/assets/pacman/common/` ships empty.
- `mra/` — MRA ROM manifests (for reference; the core loads loose files, see below).
- `_upstream/` and `reference/` — **gitignored** local reference clones. Kept out of git so the GPL MiSTer `/sys` framework never enters this BSD tree.

## Licensing discipline (important)

This repo is **BSD-3-Clause**. Keep it that way:
- Only the BSD `/rtl` is vendored; the MiSTer `/sys` framework (GPL) is replaced by the APF wrapper, never imported.
- Never copy a GPL helper (e.g. `hiscore.v`) into the tree. A per-file license audit is owed before release.
- Ship **zero ROMs**. The user supplies their own dump into `Assets/pacman/common/`.

## ROM loading (per-file, no MRA tool)

`data.json` declares one data slot per ROM file (fixed `filename`, fixed bridge `address`), so the user just unzips their MAME set and copies the loose files into `Assets/pacman/common/`; the Pocket auto-loads each into the core's `dn_addr` map. Slot addresses follow the Ms. Pac-Man MRA's sequential layout (program `0x0000`, aux `u5`/`u6`/`u7` `0x4000`, gfx `5e`/`5f` `0x8000`, PROMs `0xC000`), with `u5`/`u7`/`5f` mirrored to multiple slots exactly as the MRA duplicates them. The internal decoders in `pacman_rom_descrambler.vhd` / `pacman_video.vhd` / the audio module pick up their regions from `dn_addr`.

## Current state

Milestone 1 (core integration). Milestone 0 done: toolchain proven (clean Quartus build, timing closed), repo + public release + per-file `data.json`. Next in `core_top.v`: regenerate the PLL to ≈24.576 MHz `clk_sys` + native 6.144 MHz pixel clock (matching the MiSTer reference, `ENA_6`=÷4); instantiate `PACMAN` + `data_loader` + `sound_i2s`; map `O_VIDEO` 3:3:2 → `video_rgb`, `O_AUDIO[9:0]` → I2S, `cont1_key` → `in0/in1`; hardcode `mod_ms=1`. See `PLAN.md`.
