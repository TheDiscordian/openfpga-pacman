# 🎯 openFPGA Pac-Man — Project Plan

Port `MiSTer-devel/Arcade-Pacman_MiSTer` to the Analogue Pocket as a new openFPGA core. Headline target is **Ms. Pac-Man**; plain **Pac-Man** is the first bring-up ROM (simplest — no daughterboard), and the other ~13 same-board variants come along for free. This is a **true port** (no classic Pac-Man Pocket core exists today), and the work is almost entirely in the **APF wrapper** — the proven VHDL core stays untouched, exactly like the existing SNES/NES Pocket builds.

## 1. 🧩 Base core & why

**Base: `MiSTer-devel/Arcade-Pacman_MiSTer`** (VHDL Pac-Man model by MikeJ + Daniel Wallner's T80 Z80, both **3-clause BSD** → freely releasable with attribution). Ms. Pac-Man is a first-class variant. It already ships as a Quartus project, so the hard VHDL-on-Quartus work (Xilinx `UNISIM` removal) is already done.

- **GPL kept out:** the MiSTer `/sys` framework is GPL — we drop it entirely and replace it with the APF bridge. We also dropped `rtl/hiscore.v` (GPL). Only the BSD `/rtl` is vendored, so the tree stays BSD.
- **Rejected:** raw fpgaarcade source (Xilinx-targeted, re-solves what MiSTer fixed); jtcores (GPLv3, and has no classic Pac-Man core); `openFPGA-Druaga` (wrong Super Pac-Man 6809 hardware, no Ms. Pac-Man, no LICENSE).

**ROM-set strategy:** target the **flattened bootleg images** (MAME `pacman` / `mspacman` via MRA assembly). This avoids reimplementing the genuine GCC daughterboard (patch-traps + aux-ROM bit-flip de-scramble) — explicitly **out of scope for v1**.

## 2. 🎛️ Target & fit — Cyclone V `5CEBA4F23C8`

484-pin FBGA, speed grade 8, ~49K LE / 18,480 ALMs, ~3.4 Mb block RAM, 132 multipliers. **Fit is trivial:** Pac-Man is a single 3.072 MHz Z80, an 8×8 tilemap, 8 sprites, a 3-voice WSG, ~5 KB RAM, and uses no multipliers. (For scale: the local SNES core fills 99% of ALMs on this same part — Pac-Man uses a fraction.) Max internal clock is the 6.144 MHz pixel clock — closes easily.

## 3. 🔌 Architecture mapping — arcade core → APF bridge

Top entity `core_top` (`src/fpga/core/core_top.v`), instantiated by `apf/apf_top.v`. Wrap the VHDL core inside it.

- **Clocks/PLL:** host gives `clk_74a/clk_74b` @ 74.25 MHz. Regenerate `mf_pllbase` to emit **≈24.576 MHz `clk_sys`** + a **native 6.144 MHz pixel clock** (+90° for `video_rgb_clock`), matching the MiSTer reference exactly: `ENA_6`=÷4 (6.144 MHz), `ENA_4`=÷6, `ENA_1M79`=÷13. This keeps the core on its known-good clock structure (no raw-`CLK`-rate deviation) and avoids pixel-doubling in video. Sync PLL `locked` into `clk_74a`. **Gate the clock-enables until both PLL-lock AND `dataslot_allcomplete`.**
- **ROM load:** `data.json` ROM slot at bridge `0x00000000`; instantiate `data_loader` (analogue-pocket-utils) → its `write_en/addr/data` stream wires straight to the MiSTer core's `dn_wr/dn_addr/dn_data` download port (1:1, which is why MiSTer cores port cleanly). **Verify the MRA blob offsets match the core's program/gfx (5e,5f)/three-PROM regions — a wrong offset loads garbage silently.**
- **Video (portrait):** the FPGA scans the **native 288×224 raster** and never rotates; portrait is set in `video.json` (`rotation: 270`). Decode RGB through the 82s123 palette + 82s126 lookup PROMs into `video_rgb[23:0]`. `video.json` `width`/`height` must equal the `video_de` window — **add a scaler acceptance check at ~60.6 Hz portrait, using `video_skip` as the lever.**
- **Audio (I2S):** WSG PCM → `sound_i2s` → `audio_mclk/dac/lrck`. WSG runs 96 kHz internally; resample to the 48 kHz I2S rate.
- **Input:** `cont1_key` D-pad → IN0 bits 0–3 (active-low, invert); `face_select`→Coin, `face_start`→Start1. DIP switches (DSW1: coinage/lives/bonus/difficulty) via `interact.json` → config registers.
- **IRQ:** reproduce Z80 IM2 — vector latched via `OUT` to port `0x00`, one IRQ per VBLANK gated by 74LS259 Q0 (already in the core — **add a milestone-2 "IRQ fires" check**, and read `rtl/cpu/T80*` to confirm the BSD header / IM2 fidelity rather than assume).
- **Watchdog:** the board resets after ~16 unserviced VBLANKs — **decide servicing** (feed it, or hold it disabled during bring-up).

## 4. 🪜 Milestones

| # | Phase | Done-criterion |
|---|-------|----------------|
| **0** | Scaffold | Template renamed to `TheDiscordian.PacMan`, utils vendored, build harness wired. Build the **unmodified template → gray test screen on the Pocket** (proves Docker-Quartus + reverse + packaging + folder-naming). ⬅️ *repo is here now* |
| **1** | Core integration | Drop the Pac-Man VHDL + T80 into `core_top`; wire PLL clocks + reset. **Quartus compile succeeds, timing closes, produces `ap_core.rbf`.** |
| **2** | ROM load | `data_loader` → core `dn_*`; author the **MRA** for plain Pac-Man. **`dataslot_allcomplete` asserts, reset releases, the Z80 boots** (attract/self-test runs even if video is wrong). |
| **3** | Video | Palette/lookup PROM decode + tile/sprite raster on the APF bus; `rotation:270`. **Pac-Man attract + maze render correctly in portrait, correct colours.** |
| **4** | Audio | WSG → `sound_i2s`. **Coin jingle, siren, waka, death sound correct on device.** |
| **5** | Input | `cont1_key` → joystick/coin/start. **A full game of Pac-Man is playable.** Then add Ms. Pac-Man MRA + variant. |
| **6** | Polish | `interact.json` DIPs verified; per-variant instance JSON (Ms. Pac-Man et al.); `icon.bin`, platform banner (no trademarked art); per-file license audit; release zip. |

A→Z test each phase on-device before advancing.

## 5. 📦 Repo & deploy

Layout: `src/fpga/` (template skeleton + `core/rtl/` Pac-Man HDL), `libs/analogue-pocket-utils/`, `dist/` (Cores/Platforms/Assets staging), `mra/`, `tools/reverse_rbf.py`, `build.sh`. SD package deploys to `/Cores/TheDiscordian.PacMan/`, `/Platforms/pacman.json`, `/Assets/pacman/common/` (empty).

**Identity (must match exactly across SD folder, `core.json`, and any inventory PR):** author `TheDiscordian`, shortname `PacMan` → folder `TheDiscordian.PacMan`. A mismatch yields "General core error" (check `/System/Logs/`).

**Build/test loop:** `build.sh` → Quartus Prime Lite (Dockerised, `quartus_sh --flow compile ap_core`) → `reverse_rbf.py` → `output/bitstream.rbf_r` → stage `dist/` → copy onto the Pocket SD card.

## 6. ⚖️ ROM handling

Ship zero ROM bytes. The repo carries HDL/bitstream + JSON only. `data.json` declares one data slot per ROM file, so the user just unzips their own MAME set and copies the loose files into `Assets/pacman/common/`; `data_loader` streams each into the core at boot — no MRA tool. BSD `LICENSE` with attribution; descriptive repo name, no trademarked logo/art.

## 7. ⚠️ Risks

- **Scaler geometry (med):** DE window must match `video.json`; ~60.6 Hz + portrait must be configured right or video is garbled. Crib [ericlewis/openfpga-superbreakout](https://github.com/ericlewis/openfpga-superbreakout).
- **WSG 96 kHz → 48 kHz resample (low-med):** pitch/mix may need iteration.
- **GPL contamination (med if careless):** never pull a MiSTer `/sys` helper back in. `/_upstream/` and `/reference/` are gitignored so GPL framework files never enter the published tree.
- **Genuine daughterboard decode is out of scope** for v1 (flattened ROMs only).
- **Per-file license audit** owed before release (confirm every retained `rtl/` file is BSD).

### 📎 References
- Base core: [MiSTer-devel/Arcade-Pacman_MiSTer](https://github.com/MiSTer-devel/Arcade-Pacman_MiSTer)
- APF template: [open-fpga/core-template](https://github.com/open-fpga/core-template)
- Pocket IP: [agg23/analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils)
- Vertical-arcade reference: [ericlewis/openfpga-superbreakout](https://github.com/ericlewis/openfpga-superbreakout)
