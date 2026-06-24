# High-score save/restore — engine, per-game map, and RE notes

This is the reference for the NVRAM high-score engine (`src/fpga/core/hiscore.sv`,
sim `sim/tb_hiscore.v`). It exists so the per-game reverse-engineering below does
**not** have to be re-done from scratch. If you touch the engine or add a variant,
update this file.

## What it does

The original boards keep the high score in battery-free work RAM (0x4000–0x4FFF),
so it is lost at power-off. We persist it to the Pocket save slot (`.sav`) instead:

- On boot, once the game has set up its default high-score table, **inject** the
  saved bytes back into RAM (restore).
- While running, **snapshot** the RAM regions back out to the `.sav` (save).

The `.sav` is one 256-byte slot per game (variants get their own files under
`_variants/`). Byte 255 holds a validity marker `MAGIC = 0x5A`; a slot without it
is treated as a fresh card and is **not** injected (injecting zeros once printed
`HIG0` / `000000` on Pac-Man — see Bugs).

## Per-game region table

Source of truth is MAME `plugins/hiscore/hiscore.dat` (cross-checked vs MiSTer
MRAs), resolved to the 0x4000 work-RAM window. This is the `cfg()` table in
`hiscore.sv`. `mod` is the MiSTer mod number (`mod_sel`); games with no table
(Eeekk!, Jump Shot) stay idle.

| mod | game | regions: `addr/len (sval/eval)` | on-screen digits |
|----:|------|--------------------------------|------------------|
| 0/5/1 | Pac-Man / Ms. / Plus | `e88/4(00)`, `3ed/6(40/40)`, `3d1/1(48)` | `3ed` tiles |
| 2 | Pac-Man Club | `e88/4(00)`, `3ed/6(40/40)`, `3d1/1(59)`, `3cb/10(4f/4d)` | `3ed` tiles |
| 4 | Birdiy | `c29/30(00)`, `3ed/6(30/20)`, `d03/3(00)` | redrawn from `c29` table |
| 7 | Mr. TNT | `cb3/60(4c/01)`, `3ed/6(00/40)` | `3ed` tiles |
| 8 | Woodpecker | `e88/3(00)`, `3ed/6(40/40)`, `dda/1(03)` | `3ed` tiles |
| 10 | Ali Baba | `e88/4(00)`, `3ed/6(40/40)`, `3d1/1(48)` | **see Ali Baba note** |
| 11 | Ponpoko | `c40/3(00)`, `e5a/19(00)`, `06c/6(0f/00)`, `c53/1(02)` | `06c` tiles |
| 12 | Van-Van Car | `809/6(00)`, `c60/240(00)` | redrawn from `c60` table |
| 14 | Dream Shopper | `c00/240(00/01)`, `808/6(00)`, `809/1(03)` | redrawn from `c00` table |

`sval/eval` = the **gate**: a region's saved bytes are injected only once the live
RAM shows `first byte == sval && last byte == eval` (the game's default/blank
state). For the score value, default is 0 — true the instant RAM clears at boot.
For the displayed digit tiles, default is the blank tile (0x40 on Pac-Man-class
video, 0x00 on some) — true only once the game paints the blank high-score row.

## How the engine walks (FSM)

`S_IDLE → S_ARM → S_WALK` (per region: `S_G1/S_G2` gate-check → `S_RINJ` inject)
`→ S_SN/S_SN_L` (snapshot all regions) `→ S_HOLD → S_WALK …`

Key properties, each earned by a bug (see below):

- **Per-region one-shot restore.** Each region injects independently the moment
  *its own* gate holds (`injected[ri]` latch). The score value restores at boot
  even if the displayed tiles aren't painted yet. This is what fixed Birdiy.
- **Save is decoupled from restore.** `S_WALK` always proceeds to snapshot; the
  engine does not wait for every region to be restorable before it will save.
  When not fresh it **skips snapshotting a region that hasn't been restored yet**,
  so an un-restorable display region can't clobber good saved bytes. A fresh card
  snapshots everything.
- **Marker gate.** Fresh card (`shadow[255] != 0x5A`) ⇒ never inject.
- **Savestate interlock.** `ss_busy` (a Pocket Memories op owns the RAM tap)
  stalls snapshotting so no garbage is latched.
- **Save-slot size.** The core writes the slot size word in the `datatable`
  (`core_top.v`, index 5) — it must be **256**, not 4. A wrong size makes the
  Pocket flush a truncated slot and the marker is lost ⇒ "doesn't save".

## The reboot-display trap (Birdiy / Ali Baba class)

Saving the value is easy; making the number **appear on reboot** is the hard part,
and it is per-game:

- **Games that show their saved digit tiles directly** (Pac-Man, Club, Woodpecker,
  Mr. TNT) — we restore `3ed`, the game doesn't repaint it, the number shows.
- **Games that redraw the digits from a value/table** (Birdiy `c29`, Van-Van
  `c60`, Dream Shopper `c00`) — restoring the tile row isn't enough or isn't even
  saved; the game recomputes the digits from the table, and if it only does that
  **after a coin/game start** the boot/attract screen shows 0 until you play once.
  Restoring the *value/table* region (per-region, at boot) is what makes the next
  redraw show the real number.

> **Ali Baba is the sharp case:** its `cfg` is byte-for-byte identical to Pac-Man
> (`e88`/`3ed`/`3d1`) and it **saves** correctly (verified: `.sav` held value
> `e88 = 00 42 00 00` = 4200, tiles `3ed = "4200"`, label `3d1 = 0x48`), yet the
> score does not display on reboot. So "has a `3ed` tile region" does **not**
> guarantee it shows — Ali Baba must repaint `3ed` from its value at attract, or
> its tile gate never matches at boot. Root cause + fix: see the open trace
> (`alibaba-hiscore-restore-trace` workflow) — fill in here when it lands.

## Bugs already fixed (don't reintroduce)

1. `HIG0` / `000000` on Pac-Man — fresh-detect keyed on 0xFF but the Pocket gives
   0x00 ⇒ injected zeros. Fix: `MAGIC` marker at `shadow[255]`.
2. 4-region wedge (Club/Ponpoko) — `ri` selected with `[1:0]` wrapped at 4 regions.
   Fix: `ri[2:0]`.
3. "Doesn't save" — `datatable` reported slot size 4 ⇒ Pocket truncated the slot.
   Fix: 256.
4. Birdiy top line clipped — obsolete `h_edge_col` blanking. Removed.
5. Birdiy boot showed 0 — restore was gated on **all** regions being restorable.
   Fix: per-region one-shot restore (value injects at boot).
6. Ali Baba "doesn't save" — was a mis-diagnosis; it does save. Real issue is
   reboot-display (open).
7. `iverilog` can't bit-select a function-call result — assign `cfg()` to a wire
   first.

## How to RE a variant's high score (so you don't guess)

1. `unzip ~/Downloads/<set>.zip`; assemble the program per `tools/variant_recipes.json`
   `parts` order (program at 0x0000; Pac-Man-class aux ROMs at 0x8000/0xa000 per
   MAME `src/mame/pacman/pacman.cpp` `ROM_START`).
2. `z80dasm -a -t [-o 0xORG] prog.bin`. It loses sync on data tables — follow
   control flow from entry points, verify suspect spots from raw bytes.
3. Anchor on the value address from `hiscore.dat` (e.g. Ali Baba `ld de,0x4e88`
   at 0x2b9e; Pac-Man's high-score compare sits near 0x2a9b — variants are close
   relatives). Find the routine that converts the BCD value to digit tiles and
   writes the 0x43e8..0x43f2 row (usually via a computed HL, so it won't grep as a
   literal `43ed`), and note **when** it runs (attract vs post-coin).
4. The question is always: *what RAM do the on-screen digits derive from at
   boot/attract, and does our save cover it?* If the digits come from a
   value/table only filled at game-start, add that region to `cfg()`.

The two background workflows that produced the per-game findings here:
`alibaba-hiscore-restore-trace` and `variant-hiscore-restore-audit` (two
independent traces + reconcile each, to avoid single-pass disassembly errors).
