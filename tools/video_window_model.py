#!/usr/bin/env python3
"""Cycle model of core_top.v's video reconstruction (DE/window/RGB-gate) driven
by the Pac-Man core's exact raster timing (pacman.vhd p_hvcnt/p_sync). No HW.

Goal: see whether the displayed DE window and the core-active (picture) region
line up cleanly, or whether DE admits a pixel 1px beyond the active edge."""

import os
BORDER = 1
DE_ACTIVE = os.environ.get("DE_ACTIVE", "0") == "1"   # 1 = DE == active (no border)
SYM       = os.environ.get("SYM", "0") == "1"          # 1 = corrected symmetric border

def vsync_of(vcnt):          # vsync <= not vcnt_offset(8), v_offset=0
    return 0 if ((vcnt >> 8) & 1) else 1

def simulate(border=BORDER, frames=8):
    # ---- core regs (pacman.vhd) ----
    hcnt, vcnt = 0x080, 0x0F8
    O_HBLANK, hsync, vblank = 0, 0, 0
    # ---- wrapper regs (core_top.v) ----
    whcnt = wvcnt = 0
    hs_d = vs_d = hb_d = vb_d = 0
    h_start, h_end, v_start, v_end = 0, 0x3ff, 0, 0x3ff

    grid = {}                # (wvcnt, whcnt) -> (in_window, picture)
    record_after = (frames - 2) * 384 * 264
    steps = frames * 384 * 264

    for step in range(steps):
        # current core outputs seen by the wrapper
        cs_hsync  = hsync
        cs_vsync  = vsync_of(vcnt)
        cs_hblank = O_HBLANK
        cs_vblank = vblank

        # wrapper combinational
        picture = (cs_hblank == 0 and cs_vblank == 0)
        if DE_ACTIVE:
            in_window = picture        # DE is exactly the active region (no border)
        elif SYM:
            # symmetric BORDER ring: latches give h_end = first-blank (last_active+1)
            # and v_start one line early, so right/top subtract 1 to stay symmetric.
            in_window = ((whcnt + border >= h_start) and (whcnt + 1 <= h_end + border) and
                         (wvcnt + border >= v_start + 1) and (wvcnt <= v_end + border))
        else:
            in_window = ((whcnt + border >= h_start) and (whcnt <= h_end + border) and
                         (wvcnt + border >= v_start) and (wvcnt <= v_end + border))
        if step >= record_after:
            grid[(wvcnt, whcnt)] = (in_window, picture)

        # wrapper next-state
        if cs_hsync and not hs_d: nwh = 0
        else:                     nwh = whcnt + 1
        if   cs_vsync and not vs_d: nwv = 0
        elif cs_hsync and not hs_d: nwv = wvcnt + 1
        else:                       nwv = wvcnt
        nh_start = whcnt if ((not cs_hblank) and hb_d) else h_start
        nh_end   = whcnt if (cs_hblank and not hb_d)   else h_end
        nv_start = wvcnt if ((not cs_vblank) and vb_d) else v_start
        nv_end   = wvcnt if (cs_vblank and not vb_d)   else v_end
        nhs, nvs, nhb, nvb = cs_hsync, cs_vsync, cs_hblank, cs_vblank

        # core next-state (pacman.vhd p_hvcnt / p_sync, mod_ponp=0)
        do_vcnt = (hcnt == 0x0AF)
        nO, nhsy, nvb_blank = O_HBLANK, hsync, vblank
        if   hcnt == 0x097: nO = 1
        elif hcnt == 0x0F7: nO = 0
        if   hcnt == 0x0AF: nhsy = 1
        elif hcnt == 0x0CF: nhsy = 0
        if do_vcnt:
            if   vcnt == 0x1EF: nvb_blank = 1
            elif vcnt == 0x10F: nvb_blank = 0
        nhc = 0x080 if hcnt == 0x1FF else hcnt + 1
        nvc = vcnt
        if do_vcnt:
            nvc = 0x0F8 if vcnt == 0x1FF else vcnt + 1

        # commit
        whcnt, wvcnt = nwh, nwv
        hs_d, vs_d, hb_d, vb_d = nhs, nvs, nhb, nvb
        h_start, h_end, v_start, v_end = nh_start, nh_end, nv_start, nv_end
        hcnt, vcnt = nhc, nvc
        O_HBLANK, hsync, vblank = nO, nhsy, nvb_blank

    return grid, (h_start, h_end, v_start, v_end)


def span(pred_vals):
    xs = [x for x, ok in pred_vals if ok]
    return (min(xs), max(xs)) if xs else (None, None)

grid, (hs, he, vs_, ve) = simulate()
print(f"settled latches: h_start={hs} h_end={he} v_start={vs_} v_end={ve}  BORDER={BORDER}")

# pick a representative active line and column from recorded steady frame
vals_v = sorted({v for (v, h) in grid})
vals_h = sorted({h for (v, h) in grid})

# active (picture) bounding box and DE bounding box
pic = [(v, h) for (v, h), (dew, p) in grid.items() if p]
de  = [(v, h) for (v, h), (dew, p) in grid.items() if dew]
def bbox(pts):
    if not pts: return None
    vs2 = [v for v, h in pts]; hs2 = [h for v, h in pts]
    return (min(vs2), max(vs2), min(hs2), max(hs2))
print("picture bbox (vmin,vmax,hmin,hmax):", bbox(pic))
print("DE      bbox (vmin,vmax,hmin,hmax):", bbox(de))

# per-edge: take a mid line, show picture vs DE hcnt spans
bb = bbox(pic)
midv = (bb[0] + bb[1]) // 2
line = [(h, grid[(midv, h)]) for h in vals_h if (midv, h) in grid]
pic_h = span([(h, p) for h, (d, p) in line])
de_h  = span([(h, d) for h, (d, p) in line])
print(f"\nmid line v={midv}:  picture hcnt span={pic_h}   DE hcnt span={de_h}")
print(f"   left margin (pic.h0 - DE.h0)  = {pic_h[0]-de_h[0]}")
print(f"   right margin (DE.h1 - pic.h1) = {de_h[1]-pic_h[1]}")

# mid column
midh = (bb[2] + bb[3]) // 2
col = [(v, grid[(v, midh)]) for v in vals_v if (v, midh) in grid]
pic_v = span([(v, p) for v, (d, p) in col])
de_v  = span([(v, d) for v, (d, p) in col])
print(f"\nmid col  h={midh}:  picture vcnt span={pic_v}   DE vcnt span={de_v}")
print(f"   top margin (pic.v0 - DE.v0)    = {pic_v[0]-de_v[0]}")
print(f"   bottom margin (DE.v1 - pic.v1) = {de_v[1]-pic_v[1]}")

# the key check: any DE-on pixel that is ALSO picture but sits at the extreme
# edge of the picture bbox (candidate for a 1px-beyond-the-window line)?
print("\n--- edge audit: DE-on AND picture pixels on the bbox boundary ---")
for name, sel in [
    ("top row    v=vmin", [(bb[0], h) for h in vals_h]),
    ("bottom row v=vmax", [(bb[1], h) for h in vals_h]),
    ("left col   h=hmin", [(v, bb[2]) for v in vals_v]),
    ("right col  h=hmax", [(v, bb[3]) for v in vals_v]),
]:
    n = sum(1 for k in sel if k in grid and grid[k][0] and grid[k][1])
    print(f"  {name}: {n} pixels are DE-on AND picture")
