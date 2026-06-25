# High-score save/restore — engine, per-game map, and RE notes

This is the reference for the NVRAM high-score engine (`src/fpga/core/hiscore.sv`,
sim `sim/tb_hiscore.v`). It exists so the per-game reverse-engineering below does
**not** have to be re-done from scratch. If you touch the engine or add a variant,
update this file.

## ⚠️ Read this first — the trap (it has caught every game so far)

Every single game has dragged me through the same wrong loop. Do **not** repeat it:

1. Skim the ROM, find the high-score draw gated behind a "did the player beat it?"
   compare, and conclude **"the high score is only drawn when beaten"**. This is
   almost always WRONG — the boards (Pac-Man and its variants) draw the high score
   at **boot/attract** so the player can see what to beat.
2. Decide the engine must therefore **paint the digits itself** (a custom glyph
   painter / BCD→tile renderer). This is a dead-end — it's fragile and it's not how
   any of these games actually work.
3. Burn cycles, then finally land on the real fix.

**The real fix, for every game: restore the high-score DATA at the right time and
let the GAME draw it.** The data is the value cell (and the tile row if the game
keeps a persistent one). "The right time" = *after* the game's boot clear/blank,
which is exactly what the boot-clear-wipe protection (`scan_uni`/`S_ZS`) handles.
The game's own screen-setup then paints the number from the restored data. Pac-Man
was fixed this way after the painter detour; apply it directly to the rest.

So when a game "doesn't show its high score", the question is **not** "should we
paint it?" — it's "which RAM does the boot/attract draw read, and are we restoring
exactly that, at the right time?" Find the boot draw (not just the beat draw).

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
| 10 | Ali Baba | `e88/4(00)`, `3ed/6(40/40)`, `3d1/1(48)` | redrawn from `e88` value (forced) |
| 11 | Ponpoko | `c40/3(00)`, `e5a/19(00)`, `06c/6(0f/00)`, `c53/1(02)` | `06c` tiles |
| 12 | Van-Van Car | `809/6(00)`, `c60/240(00)` | `4809` value + `c60` table (both `scan_uni`) |
| 14 | Dream Shopper | `c00/240(00/01)`, `808/6(00)`, `809/1(03)` | redrawn from `808` value (forced) |

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
- **Forced display restore (`force_disp`).** For value-redraw games (Ali Baba,
  Mr. TNT — `mod_sel` 10/7), the instant the value region (region 0) injects, the
  display-tile region (region 1) is injected too, *bypassing its own gate*. One-shot
  via `injected[1]`, so it never overwrites the live display after that first paint.
  Without this the saved number never appears until the game next redraws.
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
- **Games that redraw the digits from a value/table** — the game recomputes the
  digit tiles from a value cell, so restoring the tile row alone is futile: the
  next redraw overwrites it from the value. Restoring the *value* region (at boot)
  is what feeds the redraw. **But** if the redraw has already run once (showing 0)
  and won't run again until a coin/game, the boot screen stays 0. The engine's
  answer (see `force_disp`): the instant the value region restores, also force the
  display-tile region in — so the saved number shows immediately, and the restored
  value keeps every later redraw correct.

Which game is which (verified by ROM trace, two independent traces + reconcile):

- **Direct-tile (tile injection shows it):** Pac-Man, Pac-Man Club, Woodpecker,
  Ponpoko (`406c`), Van-Van Car (`4809`+`c60`), Dream Shopper (`4808`+`c00`). The
  displayed digits are read straight from a saved region and not recomputed before
  the draw, so the plain tile/region restore shows on reboot. No *display-side*
  handling — but their uniform value/tile regions still need the boot-clear-wipe
  protection below (Woodpecker proved it: it draws tiles directly yet its save was
  being erased by the wipe).
  - **Woodpecker save guard (`guard_disp`):** its digit row (`0x43ed`) is only
    painted when a score is beaten and the row holds uninitialised graphic tiles
    (`0x3a-0x3f`) at boot — not blank, so `scan_uni` did not treat it as cold and
    the continuous snapshot saved the garbage, then restored `?=?=?=`. The fix is
    NOT a painter (that overwrote the row and broke the in-game score): only
    *snapshot* the row when every byte is a digit (`0x30-0x39`) or blank (`0x40`),
    else keep the last valid saved row. Capture timing, not painting. (MAME avoids
    this by only saving at exit, when the digits are on screen.)
- **Value-redraw (needs `force_disp`):** **Ali Baba** and **Mr. TNT**.
  - Ali Baba: `sub_0a30 → sub_2aa7` rebuilds the `0x43ed` digit row from the BCD
    value `0x4e88-0x4e8a` on every maze build (flag `0x4dee`), which runs in attract
    too — so injected tiles get repainted from the value.
  - Mr. TNT: boot (`0x0688`) does an unconditional `ld hl,0x39BA; ld de,0x4CB3;
    ld bc,0x3C; ldir` of the ROM-default hiscore table over `0x4cb3`, then draws the
    digits from `0x4cb8` — no validity guard, so the restore is clobbered before
    display.
  - Both `cfg`s already carry the value region (Ali Baba `e88`, Mr. TNT `cb3`) and
    the tile region `3ed`; the fix is purely the forced tile restore.

## The boot-clear wipe — the recurring bug, and the general fix

This is the bug that kept reappearing (Ali Baba, then Woodpecker), so it gets its
own section. **The FPGA work RAM powers up to 0.** The high-score gate is
"first byte == sval && last byte == eval", and for a value region those are both
`0x00` — identical to the power-up state. So the engine matches the gate and
**restores the score before the game has even run its boot clear**; the clear then
runs and zeroes the cell, and the next snapshot writes those zeros back over the
`.sav`. Net result: the score never shows on reboot *and* the save gets erased.
Same story for a blank-tile display row (`0x43ed` filled with the blank tile).

**Tell-tale:** read the `.sav` on the card (see Workflow) — a wiped one reads all
defaults (value `00 00 00`, tiles all blank) with the marker still present.

**Fix (general, one mechanism — `scan_uni` / state `S_ZS` in hiscore.sv):** for any
small **uniform** region (`sval==eval`, length 2..16 — the BCD value cells and
blank-tile rows), scan **every** byte each poll instead of just first/last:

- **Re-inject** the saved bytes whenever the region reads *fully* at its default,
  so whenever the boot clear wipes it we put it right back (it stops re-injecting
  the instant a real score is present, since then it isn't fully-default).
- **Never snapshot** a region while it's fully-default → the blank/zeros can't be
  saved over a real score.
- The full scan also distinguishes `0000` from a real score like `4200`
  (`00 42 00 00`) whose first+last bytes are *also* 0 — the weak first/last gate
  can't, which is why a simple "skip if gate matches" isn't enough for value cells.

Why this doesn't need per-game work: **1-byte flag/label cells and large tables
keep the cheap first/last gate** — their markers are non-zero (`0x48`, `0x03`,
`0x02`, `0x59`, table headers), so the power-up 0 never false-matches them; they
self-protect. **Value-redraw display tiles** (Ali Baba/Mr. TNT region 1) keep
`force_disp`, not the scan. Everything else is covered by the one rule.

> The earlier static ROM audit marked these games "no fix needed" because it only
> asked *"would the digits draw?"* — it never modelled the FPGA power-up-0 / boot
> clear race, which only shows on hardware. **Do not trust a static audit to clear
> a variant; device-test each one.**

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
6. Ali Baba "doesn't save" — was a mis-diagnosis; it saves fine. Real issue was
   reboot-display: the game repaints the digits from the value, overwriting the
   injected tiles. Fix: `force_disp` (forced display restore, above). Mr. TNT had
   the same bug (boot ldir's the default table, then draws it) and the same fix.
7. `iverilog` can't bit-select a function-call result — assign `cfg()` to a wire
   first.
8. Boot-clear wipe (Ali Baba, then Woodpecker) — power-up-0 false-matches the value
   gate, restore lands before the game's clear, the clear wipes it, the snapshot
   saves the blank. Fix: general `scan_uni`/`S_ZS` full-scan re-inject + preserve
   (see the section above). Don't reintroduce a first/last-only gate for value cells.

## Workflow: diagnosing & fixing a variant's high score

The flow is the same every time — follow it in order, don't skip to a fix.

1. **Read the actual `.sav` on the card** (ground truth, not theory). The save dir is
   `<SD>/Saves/pacman/TheDiscordian.PacMan/` (variants under `_variants/`). Dump the
   region bytes from `cfg()` for that mod and byte 255:
   ```
   xxd -l <n> "<SD>/Saves/.../_variants/<Game>.sav"   # value | tiles | flag
   xxd -s 255 -l 1 "<...>.sav"                          # marker (0x5A == valid)
   ```
   - All-default bytes (value `00`, tiles blank) + marker present ⇒ **wiped save**
     (the boot-clear wipe) — apply the general fix and confirm the region is in
     `scan_uni`'s range (uniform, 2..16 bytes).
   - Real score bytes present but nothing on screen ⇒ **restore/display** problem
     (value-redraw → `force_disp`; or the displayed tiles aren't the saved region).
   - No `.sav` at all ⇒ the game never wrote our regions — suspect wrong addresses.
2. **Confirm the addresses** against MAME `plugins/hiscore/hiscore.dat` for that set,
   resolved to the `0x4000` window. If the `.sav` regions read as plausible game
   state, they're right; if they read as constant garbage, RE where the score really
   lives (next section).
3. **Reproduce in sim** (`sim/tb_hiscore.v`) — add a test that loads a saved score,
   restores, then *wipes* the regions (value→0, tiles→blank) and runs again, asserting
   the score is re-injected and the shadow is preserved. See `[8]` (Ali Baba) / `[10]`
   (Woodpecker). A fix isn't done until its sim test passes **and** all others still do.
4. **Build & deploy:** `./build.sh` (background), then copy
   `dist/Cores/TheDiscordian.PacMan/bitstream.rbf_r` to the SD core dir, `sync`, and
   verify md5 + that ROMs/saves are untouched. Don't touch `Saves/`.
5. **Device-verify** (the only verdict that counts): set a score → reboot → it shows
   on the boot screen → reboot again → it persists. A static ROM read is **not**
   verification — it missed the boot-clear wipe twice.

Input (a different failure mode — "the initials screen won't take a button"): the
game has an action button not wired in the per-mod mux in `core_top.v`. Find its bit
in the MAME `INPUT_PORTS` for that set (the `IPT_BUTTON1/2` lines) and add
`mod_xxx: pac_inN[b] = ~m_btn;`. Audited bits: Birdiy IN1 b4/b7, Ali Baba IN0 b6,
Ponpoko IN0 b4, Van-Van/Dream Shopper IN0 b4, Eeekk IN0 b7/IN1 b6, Mr. TNT &
Woodpecker IN1 b4, Glob IN1 b5/b6 (shared with start), Jump Shot IN1 b5/b6 (one per
player — no separate steal).

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
