#!/usr/bin/env python3
"""Assemble per-game .rom files for the openFPGA Pac-Man core from MAME zips.

This is the run-once, dev/testing helper. For a public release, ship the .mra
recipes instead and let the standard Pocket updaters (Pocket Sync /
openFPGA-instance-packager) assemble these from the user's ROM collection.

Each game's .rom is the dn_addr image the core's data_loader streams in:
    0x0000  program        (16 KB)
    0x4000  aux / program-mirror (16 KB)   <- Ms. Pac-Man daughterboard ROMs, or
                                              the Pac-Man program mirrored
    0x8000  gfx            (16 KB; only the first 8 KB is read)
    0xC000  PROMs          (1m wavetable, 4a colour-LUT, 3m timing, 7f palette)
The per-game variant (mod) byte is NOT in the .rom — it is delivered by the
instance JSON's memory_write to bridge 0x50000000; mod numbers are MiSTer's
(0 = Pac-Man, 5 = Ms. Pac-Man).

Usage:  python3 build_roms.py [--zipdir DIR] [--out DIR]
        zips expected in --zipdir (default: ~/Downloads): pacman.zip,
        pacmanf.zip, mspacman.zip, mspacmnf.zip
"""
import argparse, os, sys, zipfile

# Each game: the ordered list of (zip-member, expected_size) concatenated to
# form the .rom. None size = accept whatever the file is.
PROMS = [("82s126.1m", 256), ("82s126.4a", 256), ("82s126.3m", 256), ("82s123.7f", 32)]

GAMES = {
    # mspacman: exact part order from the MiSTer "Ms. Pac-Man.mra" (index 0).
    "Ms. Pac-Man": {
        "zip": "mspacman.zip", "mod": 5, "rom": "mspacman.rom",
        "parts": [("pacman.6e",4096),("pacman.6f",4096),("pacman.6h",4096),("pacman.6j",4096),
                  ("u5",2048),("u5",2048),("u6",4096),("u7",4096),("u7",4096),
                  ("5e",4096),("5f",4096),("5f",4096),("5f",4096)] + PROMS,
    },
    "Ms. Pac-Man (speedup)": {
        "zip": "mspacmnf.zip", "mod": 5, "rom": "mspacmnf.rom",
        "parts": [("pacman.6e",4096),("pacfast.6f",4096),("pacman.6h",4096),("pacman.6j",4096),
                  ("u5",2048),("u5",2048),("u6",4096),("u7",4096),("u7",4096),
                  ("5e",4096),("5f",4096),("5f",4096),("5f",4096)] + PROMS,
    },
    # pacman (Midway): program mirrored into the 0x4000 region (matching the
    # Puck Man MRA structure), gfx 5e/5f padded to fill 0x8000-0xBFFF.
    "Pac-Man": {
        "zip": "pacman.zip", "mod": 0, "rom": "pacman.rom",
        "parts": [("pacman.6e",4096),("pacman.6f",4096),("pacman.6h",4096),("pacman.6j",4096),
                  ("pacman.6e",4096),("pacman.6f",4096),("pacman.6h",4096),("pacman.6j",4096),
                  ("pacman.5e",4096),("pacman.5f",4096),("pacman.5e",4096),("pacman.5f",4096)] + PROMS,
    },
    "Pac-Man (speedup)": {
        "zip": "pacmanf.zip", "mod": 0, "rom": "pacmanf.rom",
        "parts": [("pacman.6e",4096),("pacfast.6f",4096),("pacman.6h",4096),("pacman.6j",4096),
                  ("pacman.6e",4096),("pacfast.6f",4096),("pacman.6h",4096),("pacman.6j",4096),
                  ("pacman.5e",4096),("pacman.5f",4096),("pacman.5e",4096),("pacman.5f",4096)] + PROMS,
    },
}


def assemble(name, spec, zipdir, outdir):
    zpath = os.path.join(zipdir, spec["zip"])
    if not os.path.exists(zpath):
        print(f"  - skip {name}: {spec['zip']} not found in {zipdir}")
        return False
    blob = bytearray()
    with zipfile.ZipFile(zpath) as z:
        members = {os.path.basename(n): n for n in z.namelist()}
        for fname, size in spec["parts"]:
            if fname not in members:
                print(f"  ! {name}: missing {fname} in {spec['zip']} — aborting this game")
                return False
            data = z.read(members[fname])
            if size and len(data) != size:
                print(f"  ! {name}: {fname} is {len(data)}B, expected {size}B — aborting")
                return False
            blob += data
    out = os.path.join(outdir, spec["rom"])
    with open(out, "wb") as f:
        f.write(blob)
    print(f"  ok {name:24s} -> {spec['rom']:16s} ({len(blob)} bytes, mod={spec['mod']})")
    return True


def main():
    ap = argparse.ArgumentParser(description="Assemble Pac-Man core .rom files from MAME zips.")
    ap.add_argument("--zipdir", default=os.path.expanduser("~/Downloads"))
    ap.add_argument("--out", default=".")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    print(f"Assembling from {a.zipdir} -> {a.out}")
    n = sum(assemble(name, spec, a.zipdir, a.out) for name, spec in GAMES.items())
    print(f"Done: {n}/{len(GAMES)} games assembled.")
    sys.exit(0 if n else 1)


if __name__ == "__main__":
    main()
