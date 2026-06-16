# Third-party licenses & disclosures

This repository's own work is **MIT** (see [`LICENSE`](LICENSE)). It also bundles
HDL and helper IP from several upstream projects, each under its **own** license,
listed below. The MIT license does not relicense any of these — they are
redistributed under their original terms, with headers retained intact.

## RTL compiled into the bitstream

### Pac-Man hardware model
- **Author:** MikeJ ([fpgaarcade](https://www.fpgaarcade.com/kb/pacman/)), © 2006
- **Files:** `src/fpga/core/rtl/pacman.vhd`, `pacman_audio.vhd`, `pacman_video.vhd`, `pacman_vram_addr.vhd`, `pacman_rom_descrambler.vhd`
- **License:** BSD-style 3-clause ("Redistribution and use in source and synthesized forms…"), per the file headers.

### T80 — Z80-compatible CPU core
- **Author:** Daniel Wallner, © 2001–2002 (maintained by MikeJ / fpgaarcade)
- **Files:** `src/fpga/core/rtl/cpu/T80*.vhd`
- **License:** BSD-style 3-clause, per the file headers.

### YM2149 / AY-3-8910 PSG
- **Authors:** MikeJ © 2005; Sorgelig © 2016–2019
- **File:** `src/fpga/core/rtl/ym2149.sv`
- **License:** BSD-style 3-clause, per the file header.

### SN76489 PSG
- **Author:** Arnim Laeuger, © 2005–2006
- **Files:** `src/fpga/core/rtl/sn76489/*.vhd`
- **License:** the `.vhd` source headers grant the BSD-style 3-clause terms; the
  directory also ships a **GNU GPL v2** `COPYING`, referenced by `sn76489/README`.
  Both are retained as shipped. Compiled into the bitstream (used by the Van-Van
  Car variant).

### dpram.vhd
- **File:** `src/fpga/core/rtl/dpram.vhd` — a thin Altera `altsyncram`
  instantiation wrapper with **no copyright/license header**. Likely trivial
  vendor boilerplate; provenance unconfirmed.

## Pocket / APF scaffolding
- The `src/fpga/apf/` framework, the `mf_pllbase` PLL wrappers, and the
  `core_top` skeleton derive from Analogue's openFPGA **core-template**
  (© Analogue Enterprises Ltd.), used under Analogue's openFPGA developer terms.

## Helper IP
### analogue-pocket-utils (git submodule)
- **Author:** Adam Gastineau ([agg23](https://github.com/agg23/analogue-pocket-utils)), © 2022
- **License:** **MIT** (`libs/analogue-pocket-utils/LICENSE`)
- Provides the `data_loader`, `sync_fifo`, and `sound_i2s` IP.
