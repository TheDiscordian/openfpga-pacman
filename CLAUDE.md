# openFPGA Pac-Man — Dev Guide

A real HDL Analogue Pocket core (not an openfpgaOS software core). It ports the BSD-licensed MiSTer Arcade-Pacman RTL into an APF wrapper. Roadmap and architecture live in `PLAN.md`; user-facing docs in `README.md`. For the general Pocket porting workflow, use the `openfpga` skill.

## What this is

- Target FPGA: Intel Cyclone V **`5CEBA4F23C8`** (the Pocket's developer-accessible core FPGA).
- Core identity: author `TheDiscordian`, shortname `PacMan` → SD folder **`TheDiscordian.PacMan`**. These three must stay in lockstep (`core.json` + folder + any inventory PR) or the Pocket throws "General core error".
- Covers Pac-Man, Ms. Pac-Man, and same-board variants (identical hardware, different ROMs).

## Build

```bash
./build.sh
```

Runs Quartus (Dockerised) → reverses the bitstream → stages `dist/`. Requires Docker + Python 3. There is **no native Quartus** on this machine — it runs only via the `raetro/quartus:21.1` image (Quartus Prime 21.1.1 Lite), the same image the SNES/NES cores build with.

- Quartus output: `src/fpga/output_files/ap_core.rbf`
- Reversed for the Pocket: `tools/reverse_rbf.py` → `output/bitstream.rbf_r` (**mandatory** — a non-reversed `.rbf` will not boot).
- Deploy: copy `dist/` to the Pocket SD (mounts at `the Pocket SD card` when inserted).

## Layout

- `src/fpga/` — APF skeleton from `open-fpga/core-template` (`ap_core.qpf/qsf`, `apf/`, `core/core_top.v`, the PLL, SDC).
- `src/fpga/core/rtl/` — vendored MiSTer Pac-Man RTL (BSD). `pacman.vhd` is the core; `cpu/` is T80; `pacman_audio/video/vram*.vhd` + `pacman_rom_descrambler.vhd` + `dpram.vhd`. `sn76489/` + `ym2149.sv` are for variants with extra sound. **`hiscore.v` was removed (GPL).**
- `libs/analogue-pocket-utils/` — agg23 IP (`data_loader`, `sound_i2s`, `sync_fifo`). Don't hand-roll the bridge↔RAM glue.
- `dist/` — SD package staging (Cores/Platforms/Assets). `dist/assets/pacman/common/` ships empty.
- `mra/` — MRA ROM manifests (authored at milestone 2+).
- `_upstream/` and `reference/` — **gitignored.** Local cribbing clones (core-template, MiSTer top, superbreakout). Kept out of git so the GPL MiSTer `/sys` top never enters this BSD tree.

## Licensing discipline (important)

This repo is **BSD-3-Clause**. Keep it that way:
- Only the BSD `/rtl` is vendored; the MiSTer `/sys` framework (GPL) is replaced by the APF wrapper, never imported.
- Never copy a GPL helper (e.g. `hiscore.v`) into the tree. A per-file license audit is owed before release.
- Ship **zero ROMs**. The user supplies their own dump into `Assets/pacman/common/`.

## ROMs (local, for testing)

In `a local ROM folder/`: `pacman.zip` (clean Pac-Man — first bring-up), `pacmanf.zip` (Pac-Man fast), `mspacman.zip` (Ms. Pac-Man), `mspacmnf.zip` (Ms. Pac-Man fast). All standard MAME sets — assemble to a `.rom` blob via mra-tools-c.

## Current state

Milestone 0 (scaffold). The tree is the unmodified core-template skeleton plus the Pac-Man RTL/utils in place but **not yet wired into `core_top`**. Next: build the template to a gray screen on device (proves the toolchain), then milestone 1 (instantiate the core). See `PLAN.md`.
