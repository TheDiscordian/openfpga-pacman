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

        --variants            also assemble the roadmap variants from
                              tools/variant_recipes.json (Pac-Man Plus, Mr. TNT,
                              Ponpoko, ...) and emit a picker instance JSON for each.
        --instances DIR       where to write the variant instance JSONs
                              (default: the dist _variants picker folder).
"""
import argparse, json, os, sys, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
RECIPES = os.path.join(HERE, "variant_recipes.json")
INSTANCES_DEFAULT = os.path.join(
    HERE, "..", "dist", "Assets", "pacman", "TheDiscordian.PacMan", "_variants"
)

# A recipe's mame_zip names the MAME *set*; in a merged ROM collection the clone's
# files live inside its parent zip. Map clone-set -> the zip that actually holds them.
ZIP_ALIASES = {"eeekkp": "eeekk"}

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


def assemble_variant(v, zipdir, outdir):
    """Assemble one variant .rom from its variant_recipes.json entry."""
    name = v["name"]
    zipname = ZIP_ALIASES.get(v["mame_zip"], v["mame_zip"]) + ".zip"
    zpath = os.path.join(zipdir, zipname)
    if not os.path.exists(zpath):
        print(f"  - skip {name}: {zipname} not found in {zipdir}")
        return False
    blob = bytearray()
    with zipfile.ZipFile(zpath) as z:
        members = {os.path.basename(n): n for n in z.namelist()}
        for part in v["parts"]:
            fname, size = part["file"], part.get("size")
            if fname not in members:
                print(f"  ! {name}: missing {fname} in {zipname} — aborting this game")
                return False
            data = z.read(members[fname])
            if size and len(data) != size:
                print(f"  ! {name}: {fname} is {len(data)}B, expected {size}B — aborting")
                return False
            blob += data
    exp = v.get("total_bytes")
    if exp and len(blob) != exp:
        print(f"  ! {name}: assembled {len(blob)}B, recipe says {exp}B — aborting")
        return False
    out = os.path.join(outdir, v["rom_file"])
    with open(out, "wb") as f:
        f.write(blob)
    print(f"  ok mod {v['mod']:<2} {name:30s} -> {v['rom_file']:18s} ({len(blob)} bytes)")
    return True


def write_instance(v, instdir):
    """Emit the Pocket picker instance JSON for a variant (carries no ROM data)."""
    inst = {
        "instance": {
            "magic": "APF_VER_1",
            "data_path": "",
            "core_select": {"id": 0, "select": False},
            "data_slots": [{"id": 1, "filename": v["rom_file"]}],
            "memory_writes": [{"address": "0x50000000", "data": "0x%08x" % v["mod"]}],
        }
    }
    os.makedirs(instdir, exist_ok=True)
    path = os.path.join(instdir, v["name"] + ".json")
    with open(path, "w") as f:
        json.dump(inst, f, indent=4)
        f.write("\n")
    return path


def main():
    ap = argparse.ArgumentParser(description="Assemble Pac-Man core .rom files from MAME zips.")
    ap.add_argument("--zipdir", default=os.path.expanduser("~/Downloads"))
    ap.add_argument("--out", default=".")
    ap.add_argument("--variants", action="store_true",
                    help="also build roadmap variants from variant_recipes.json")
    ap.add_argument("--recipes", default=RECIPES, help="variant recipe JSON")
    ap.add_argument("--instances", default=INSTANCES_DEFAULT,
                    help="dir for variant picker instance JSONs")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    print(f"Assembling from {a.zipdir} -> {a.out}")
    n = sum(assemble(name, spec, a.zipdir, a.out) for name, spec in GAMES.items())
    total = len(GAMES)

    if a.variants:
        recipes = json.load(open(a.recipes))
        buildable = [v for v in recipes["variants"] if v.get("confirmed") and v.get("mame_zip")]
        print(f"\nVariants ({len(buildable)} confirmed recipes) -> {a.out}")
        vn = 0
        for v in buildable:
            if assemble_variant(v, a.zipdir, a.out):
                write_instance(v, a.instances)
                vn += 1
        print(f"  instances -> {a.instances}")
        n += vn
        total += len(buildable)

    print(f"Done: {n}/{total} games assembled.")
    sys.exit(0 if n else 1)


if __name__ == "__main__":
    main()
