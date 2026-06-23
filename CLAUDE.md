# openFPGA Pac-Man — Dev Guide

A real HDL Analogue Pocket core. It currently wraps the BSD-licensed MiSTer Arcade-Pacman RTL in an APF (Analogue Pocket Framework) wrapper, but that is the *starting point*, not the goal — see the fidelity rule below. Roadmap and architecture live in `PLAN.md`; user-facing docs in `README.md`.

## Fidelity — board-accuracy is THE rule (read first)

The goal of this project is **original-cabinet / schematic accuracy**. Not parity with any existing core. When you implement, fix, or verify anything, the source of truth is the **Pac-Man hardware itself — the schematics, the PCB, the original board behaviour** — and contributors who have cross-checked against them (e.g. **boogerman**, who re-derived this hardware schematic-accurately).

- **Do NOT treat the MiSTer Arcade-Pacman core as the accuracy bar.** Our vendored RTL currently *is* that core (MikeJ's 2006 FPGAArcade model), and it carries known synchronization/alignment imperfections vs the real board. "Matches MiSTer" is **not** good enough. MiSTer is at most a convenience reference for the IO map (IN0/IN1/DSW bit layout) — never the timing or behaviour standard.
- When in doubt, check the **schematics** and **MAME's `pacman` driver**, and prefer a schematic-derived implementation over a ported one. Reference boogerman's work where available.
- The standing fidelity debt: re-derive/correct the base RTL's timing against the schematics (or adopt a schematic-accurate base). Until then, the core is "faithful to MiSTer", which is below the bar.

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

Shipping **v1.1.0**. The core is fully integrated and playable on hardware — Pac-Man, Ms. Pac-Man, and the same-board variants (Pac-Man Plus, Club, Birdiy, Mr. TNT, Woodpecker, Eeekk!, Ali Baba, Ponpoko, …) run with video, the 3-voice WSG sound, and DIP options.

v1.1 added (all merged to `main`):
- **Save states + sleep/wake** — the Pocket "Memories" feature. Full machine-state capture: 4 KB work RAM + the T80 register set + pacman's own timing/IRQ/control latches (`hcnt`/`vcnt`/`control_reg`/`cpu_vec_reg`/`cpu_int_l`/watchdog/sync-bus), with the free-running flops frozen (`ss_freeze`) during the walk so save/restore is coherent. See `SAVESTATES.md`.
- **Selectable low-pass filter** — OSD cutoff list (Off / 5 / 2.5 / 1.2 kHz / 600 / 300 Hz) modelling the cabinet analog stage; clean-room 10.12 rounded leaky IIR (the value is the IIR shift K).
- **Flipped-variant edge-stripe fix** and **pause-while-menu/sleep-overlay**.

Known issue: a low-frequency gameplay buzz lives in the Pocket's **analog output path** — present since 1.0.0, absent from digital captures, unaffected by even an aggressive in-core filter; it is not a core-RTL defect. See `PLAN.md`.
