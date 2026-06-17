# Board-accuracy verification record

Running ledger of what has been cross-referenced against the real Pac-Man hardware,
**at what depth, against which source, with what result** — so verification isn't
repeated and so no claim is taken deeper than it was actually checked.

**Depth legend** — what a "✅" is allowed to mean:
- **geometry** — totals / active region / rates match.
- **functional** — the RTL reproduces the documented *behaviour* (not gate-for-gate).
- **gate / chip-function** — each chip on the schematic maps to its RTL equivalent. (For
  *behavioral* RTL models of a custom IC there are no discrete gates to match 1:1 — the
  honest ceiling is chip-**function** mapping; that is **not** a gate-netlist match.)
- **cycle-exact** — confirmed in a timed simulation.

Rule: never present a shallower check as a deeper one. If an item was named "remaining",
it stays remaining until actually done.

---

## Sources cross-referenced (and where they are)

| Source | What it gives | Location |
|---|---|---|
| Midway Pac-Man manual (`pac-man.pdf`) | Logic-board schematics: **p36** Z-80 sync-bus (NVC285), **p38** V-RAM addresser (NVC284), **p40** credit-multiplier, **p49–55** monitor; **p35** full BOM | archive.org `ArcadeGameManualPac-man` / `pacman-bally-midway`; local `~/Downloads/pacman-manual.pdf` |
| Midway logic-board **troubleshooting guide** | Board-derived: clock divider chain, active-low input convention, watchdog chip, sound PROM | archive.org `arcademanual_Pacman-Mspacman-Troubleshooting-Guide-Part2` (djvu text) |
| Lomont, *Pac-Man Emulation Guide* | Clock tree, colour resistor weights, WSG algorithm | lomont.org/software/games/pacman/PacmanEmulation.pdf |
| MAME `src/mame/pacman/pacman.cpp` | `set_raw` screen timing, INPUT_PORTS/DIPs, `ROT` per set, ROM maps, init/decrypt | github mamedev/mame |
| MAME `src/mame/pacman/pacman_v.cpp` | Palette resistor network, colour LUT, sprite hw | github mamedev/mame |
| MAME `src/devices/sound/namco.cpp` + WSG3 (walkofmind.com) | Namco WSG 3-voice algorithm | github / walkofmind |

The base RTL (`src/fpga/core/rtl/*.vhd`) is MikeJ/fpgaarcade's board-derived Pac-Man model
(version 004, "merge variants by Alexey Melnikov"); the V-RAM addresser / sync-bus customs are
behavioral models of the NVC284 / NVC285.

---

## Shared-core ledger (the hardware all 13 games run on)

| Subsystem | vs | Depth | Result |
|---|---|---|---|
| Clock tree (18.432 → 3.072 CPU / 6.144 pixel / 96 kHz WSG / 60.606 Hz) | troubleshooting guide + Lomont + MAME | functional | **PASS** |
| CPU clock (`CLKEN = hcnt(0) and ena_6` → 3.072 MHz) | RTL + board | functional | **PASS** |
| Sync-bus arbitration (NVC285) — 2H time-division, holding reg, WAIT, vector latch | manual **p36** schematic | chip-function map | **PASS** (function-level; behavioral RTL, **not** gate-netlist) |
| IM2 interrupt vector latch (`OUT (0)` latches vector) | Lomont/board-doc + RTL | functional | **PASS** |
| Memory map / IO decode (0x5000 ctrl/IN0, 0x5040 sound/IN1, 0x5080 DSW, 0x50C0 wdog) | board-doc + MAME | functional | **PASS** |
| V-RAM addresser (NVC284) — 3×257 + 3×157, `sel=¬((32⊕16)∨(32⊕64))`, 256H select, FLIP-XOR taps, AB0–11 out | manual **p38** schematic | structural + select + flip + I/O | **PASS at that depth** — per-pin mux-input trace **BLOCKED** by scan legibility (small rotated tap labels unreadable); per-tap correctness rests on it being MikeJ's board model + structural match |
| Video timing / geometry (HTOTAL 384, Hvis 288, VTOTAL 264, Vvis 224, 6.144 MHz) | MAME `set_raw` | geometry | **PASS** — 60.606 Hz, matches exactly |
| Colour DAC (R/G = 1k/470/220 Ω, B = 470/220 Ω resistor ladder) | Lomont + MAME `pacman_v.cpp` resistor list | computed exact, dual-source | **PASS** — `dac_rg`/`dac_b` match bit-for-bit (more accurate than MikeJ's original bit-replication) |
| WSG sound — serial freq accumulator, 5-bit waveform index, 256-byte PROM, per-voice vol/freq | WSG3 + `namco.cpp` + RTL | structural | **PASS at structural depth** — uses the real `82s126.1m` waveform PROM; 3-voice 96 kHz cycle timing **not** cycle-verified |
| 74LS259 control latch (Q0=int, Q1=sound, Q3=flip; Q4/5 lamps, Q6 lockout, Q7 counter unused) | board-doc | functional | **PASS** — every emulation-relevant Q correct; omitted Q's are physical-cabinet outputs |
| Active-low inputs (pull-ups RM7/RM8, switch-to-ground) | troubleshooting guide | functional | **PASS** |

### Deviations found
- **Watchdog — board-INACCURATE.** RTL increments `watchdog_cnt` per VBLANK and resets at `0xFF`
  → **255 unserviced frames** (~4.2 s). Real board (74LS161 @ 9C) resets at terminal count 15
  → **16 frames** (~0.26 s). Gameplay-irrelevant (the game kicks it every frame), but a genuine
  miss. Fix: trigger reset at `0x0F` (or a 4-bit count). `pacman.vhd` p_irq_req_watchdog (~line 319).

### Open in the shared core (NOT verified)
- **Sprite/tile pixel generation** (`pacman_video.vhd` char/sprite fetch + shift) — not traced
  (no schematic sheet for the video-output stage; would be vs MAME `pacman_v.cpp`).
- **Colour-LUT addressing** (256×4 `82s126.4a`: colour-index → palette entry) — DAC verified, LUT
  addressing not.
- **WSG 3-voice / 96 kHz cycle-exact sequencing** — needs a timed sim.
- The **T80 Z80 core** — generic Z80, out of scope (executes correctly).

---

## Per-variant findings (rounds 1–3 fixes; basis = MAME, no variant schematics exist)

The shared board is schematic-verifiable; the per-game boards (Sigma/Sanritsu/EPOS/Sega clones)
have **no public schematics**, so their deltas are grounded in MAME's PCB reverse-engineering.
Fixes are in PR #4 (`fix/variant-correctness`).

| Game | mod | ROT | Action button (IN bit) | DIP notes | Sound |
|---|---|---|---|---|---|
| Pac-Man / Ms / speedups | 0/5 | 90 | — | base layout | WSG |
| Pac-Man Plus | 1 | 90 | — | base | WSG; `pacplus_decode` + special 4a/7f PROMs |
| Pac-Man Club | 2 | 90 | — | own DSW1 (coin=00 invalid); live P1/P2 input mux (control_reg 5:4) → "teleport" fix | WSG |
| Birdiy | 4 | **270** | IN1 b4 (P1) / b7 (P2) | own DSW1 (cab b4, skip b5) | WSG; control_reg flip=Q3/sound=always-on; sprite X-mirror (`m_inv_spr`) |
| Mr. TNT | 7 | 90 | — (maze) | reversed lives/bonus, coin 1↔3, cab b6 | WSG; eyes gfx descramble |
| Woodpecker | 8 | 90 | — | bonus 5k/10k/15k, cab b6, service b7 | WSG; mrtnt video path |
| Eeekk! | 9 | 90 | IN0 b7 (P2) / IN1 b6 (P1) | own DSW1 (lives/diff/demo) | WSG; EPOS counter-PAL decrypt (init $09) |
| Ali Baba | 10 | 90 | **IN0 b6** (hammer) | base-like (0xC9); mystery ports 0x50c0/c1 | WSG; **giant = random "?" effect (table of 16 perms of {1,2,3,4}) — open on-device** |
| Ponpoko | 11 | **0** (landscape) | IN0 b4 | **active-HIGH** inputs; coin DSW2; lives/bonus reordered | WSG; **clean landscape needs separate core (rot0 = slot 0); secondary-slot scaling imperfect** |
| Van-Van Car | 12 | **270** | IN0 b4 | coin top nibble; DSW2=0x00 (else no collision) | **2×SN76496 @ ~1.79 MHz** (was ena_4 4.096 → fixed to ena_1m79); NMI not IRQ |
| Dream Shopper | 14 | **270** | IN0 b4 | coin top nibble; **DSW2=0x00 (else invuln→infinite-loop freeze)** | AY-3-8910 (ym2149) ports 06/07; NMI |
| Jump Shot | 16 | 90 | IN1 b5/b6 (shoot; coin-start) | DSW1 fixed 0xDD (time/skin/freeplay) | WSG |

Orientation handled by 3 video.json scaler slots (0=ROT90, 1=ROT0 Ponpoko, 2=ROT270 trio) +
the APF "Set Scaler Slot" control word, selected by mod. DIP mapping is bit-exact-checked vs MAME
and iverilog-simulated (23/23 self-checks pass).

### Variant items still open (on-device or design-decision)
- **Ali Baba giant** — **user-reported, not independently verified.** Basis is the user's
  observation only: giant never triggers on-device, and a reference video shows grabbing "?"
  triggers it reliably → a real defect by that evidence. I have **not** verified or isolated it
  (can't run the hardware). What I *did* verify came back **correct, no defect found**: button bit
  (IN0 b6, Z80 disasm @ 0xa0f8), ROM bank layout (6l→0x8000, 6m→0xa000), the "?" effect-table
  (@ 0x8040). If the defect is real, the giant-effect *application* is the only remaining suspect;
  needs on-device data or a timed sim to confirm.
- **Ponpoko** — upright now (rot0 slot) but landscape scaling imperfect; clean fix = separate core.
- **Round-3 bitstream** — built, **not yet deployed** (SD was unmounted).
- All gameplay confirmation of rounds 1–3 — hardware-pending.
