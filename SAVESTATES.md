# Save states — design + implementation plan 💾

How the Analogue Pocket save-state feature maps onto this core, what state has to
be captured, and the staged plan to get there. This is the spec the implementation
follows; it does **not** describe a shipped feature yet (`savestate_supported` is
still 0 — see Status).

## Status

**Not implemented.** The APF host-side handshake is already present and wired
(`core_top.v` ↔ `apf/core_bridge_cmd.v`), but every `savestate_*` input the core is
meant to drive is undriven, so `savestate_supported` floats to 0 and the Pocket
reports "no save states". Nothing behind the handshake exists yet. We do **not**
flip `savestate_supported` to 1 until a full, on-device-validated save+restore round
works — a half-built state blob that restores RAM but not the CPU just crashes on
load.

## How the Pocket save-state API works

From `apf/core_bridge_cmd.v` (host commands `0x00A0` save, `0x00A4` load):

- The core advertises three values to the host: `savestate_supported`,
  `savestate_addr` (a bridge-accessible memory region holding the state blob) and
  `savestate_size` / `savestate_maxloadsize`.
- **Save** (`0xA0`): host pulses `savestate_start`; the core serialises its entire
  machine state into the region at `savestate_addr`, pulses `savestate_start_ack`,
  holds `savestate_start_busy` while working, then `savestate_start_ok` (or `_err`).
  The host then copies `savestate_size` bytes from that region into the `.sav` file.
- **Load** (`0xA4`): the host has already filled the region from the file; it pulses
  `savestate_load`; the core reads the region and restores its state, with the same
  `_ack` / `_busy` / `_ok` / `_err` handshake.

So the core owns two jobs: (1) expose a buffer to the bridge, and (2) move every
piece of machine state in/out of that buffer, coherently, with the machine paused.

## Transport — reuse the high-score path

`core/hiscore.sv` + the `save_loader` / `save_unloader` (`data_loader` /
`data_unloader`, bridge window `0x2`) already demonstrate everything the transport
needs: pause the core in vblank, reach into work RAM, and stream a shadow buffer to
/ from SD across the `clk_74a` ↔ `clk_sys` domains. Save states are the same shape
at larger scale: a bigger shadow buffer (block RAM) behind the `savestate_addr`
window, filled/drained by a serialisation FSM instead of the single-value hiscore
controller. No new bridge plumbing has to be invented.

## State inventory

What defines the Pac-Man machine, from the actual RTL. ROM `dpram` blocks
(`char_rom_5ef`, `col_rom_4a`, `col_rom_7f`, `audio_rom_1m`) are **not** state — they
reload from `dn_addr` and are skipped.

| State | Source | Size |
|---|---|---|
| Main RAM (VRAM 0x4000–43FF, CRAM 0x4400–47FF, work 0x4C00–4FFF) | `pacman.vhd` `u_rams` `dpram(12,8)` | 4096 B |
| Aux RAM (variant boards) | `pacman.vhd` `u_ram2` `dpram(10,8)` | 1024 B |
| Sprite position RAM | `pacman_video.vhd` `sprite_xy_ram` `dpram(4,8)` | 16 B |
| WSG volume + frequency regs | `pacman_audio.vhd` `vol_ram`/`frq_ram` `dpram(4,4)` ×2 | 16 B |
| WSG phase accumulators (3 voices × 20-bit) | `pacman_audio.vhd` internal | ~8 B |
| 74LS259 control latch (irq/sound/flip/lamps/lockout/counter) | `pacman.vhd` `control_reg` | 1 B |
| IM2 interrupt vector latch | `pacman.vhd` | 1 B |
| Watchdog counter | `pacman.vhd` | 1 B |
| Variant sound — 2×SN76489 (Van-Van) / AY-3-8910 (Dream Shopper) | `sn76489/`, `ym2149.sv` | ~32 B |
| **Z80 CPU register file** — AF/BC/DE/HL + alts, IX/IY/SP/PC, I/R, IM, IFF1/2 | `cpu/T80*.vhd` | ~28 B |

Total blob ≈ **6 KB**, RAM-dominated. The line-buffer `u_sprite_ram` (`dpram(8,6)`)
regenerates every scanline and is **not** saved.

## The hard part — the CPU 🧱

Our T80 is MikeJ's FPGAArcade ver 0247/300 (`cpu/T80.vhd`, `T80_Reg.vhd`,
`T80sed.vhd`). It exposes only the Z80 bus — **no** register read-out or load-in
ports. Save states are impossible without getting the CPU's full register set out
and back in at an instruction boundary. Two routes:

1. **Port a savestate-enabled T80** (recommended) — Robert Peip's T80 variant used
   in the MiSTer SMS / Genesis cores adds `ss_*` register export/import ports. Drop
   it in for our `T80sed`, thread the ss bus to the serialiser. Biggest single piece;
   the risk is a CPU-behaviour regression, so it gets its own PR gated on a
   *games-still-run* on-device pass before any state work rides on it.
2. **Add register dump/restore to our T80** — touch `T80.vhd` + `T80_Reg.vhd` to
   surface the register file and the AF/working/alt set. Smaller diff, but modifying
   a 20-year-old hand-tuned core is its own correctness risk.

## Staged plan (one PR each)

1. **CPU savestate-capable** — integrate route 1, verify every game still runs
   on-device (pure regression; no save behaviour yet).
2. **Serialisation buffer + FSM** — block-RAM shadow behind `savestate_addr`, pause
   in vblank (hiscore pattern), FSM that walks the RAM blocks in/out. RAM-only,
   still `savestate_supported = 0`.
3. **Full state** — add CPU regs + latches + sound state to the FSM; flip
   `savestate_supported = 1`. Validate save→reload→continue on-device for a spread of
   games (base, a flipped variant, Van-Van/Dream Shopper for the extra sound chips).
4. **Docs** — user-facing line in `README.md`; finalise this file's layout table.

## Notes

- **Accuracy is unaffected.** Save states are a Pocket-host feature layered on top
  of the running machine; nothing here changes emulation timing or behaviour.
- **On-device validation is mandatory** and iterative — save states fail in ways
  (mid-instruction snapshots, missed flip-flops, sound chip desync) that only show
  when you save, reload and keep playing on real hardware.
