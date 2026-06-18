#!/usr/bin/env bash
# Build + run the T80 save-state testbenches under GHDL (docker, mcode, --std=08).
#
#   ./sim/run_t80_ss.sh            # export + restore round-trip TBs
#   ./sim/run_t80_ss.sh export     # just the export read-out TB
#   ./sim/run_t80_ss.sh restore    # just the save+restore (export+import) TB
#   ./sim/run_t80_ss.sh repro      # BUGGY core_top sequence -> EXPECTED to FAIL
#                                   #   (mid-instruction async save) at 1207..1212
#   ./sim/run_t80_ss.sh fixed      # FIXED core_top sequence -> PASSES the same
#                                   #   offsets (boundary-armed, ss_load held op-wide)
#   ./sim/run_t80_ss.sh sweep      # sweep repro (FAIL) vs fixed (PASS) over 1207..1212
#
# Run from the repo root. The save+restore TB drives the import ports
# (ss_din/ss_wr/ss_load) on T80/T80sed and the SSWE*/SSDI* restore path on
# T80_Reg. The repro models core_top's BUGGY drive (snapshot mid-instruction);
# the fixed TB models the corrected drive (arm on ss_cpu_bndry, hold ss_cpu_load
# for the whole op) and passes the offsets the repro fails.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMG="ghdl/ghdl:6.0.0-mcode-ubuntu-24.04"
WHICH="${1:-both}"

run_one() {
  local tb="$1" stop="$2"; shift 2
  local gargs=("$@")
  docker run --rm -v "$REPO":/work -w /work "$IMG" bash -c "
    set -e
    mkdir -p /tmp/ghdlwork
    ghdl -i --std=08 -fsynopsys --workdir=/tmp/ghdlwork \
         src/fpga/core/rtl/cpu/*.vhd sim/${tb}.vhd
    ghdl -m --std=08 -fsynopsys --workdir=/tmp/ghdlwork ${tb}
    ghdl -r --std=08 -fsynopsys --workdir=/tmp/ghdlwork ${tb} \
         ${gargs[*]} --stop-time=${stop} --ieee-asserts=disable
  "
}

case "$WHICH" in
  export)  run_one tb_t80_ss          10us ;;
  restore) run_one tb_t80_saverestore 60us ;;
  repro)   run_one tb_t80_coretop_repro 300us -gPAUSE_DELAY=1209 ;;
  fixed)   run_one tb_t80_coretop_fixed 300us -gPAUSE_DELAY=1209 ;;
  sweep)
    for d in 1207 1208 1209 1210 1211 1212; do
      echo "=== repro (expect FAIL) PAUSE_DELAY=$d ==="
      run_one tb_t80_coretop_repro 300us -gPAUSE_DELAY=$d 2>&1 \
        | grep -E "PASS|FAIL|DONE-OK|REPRODUCED|STILL" || true
      echo "=== fixed (expect PASS) PAUSE_DELAY=$d ==="
      run_one tb_t80_coretop_fixed 300us -gPAUSE_DELAY=$d 2>&1 \
        | grep -E "PASS|FAIL|DONE-OK|REPRODUCED|STILL" || true
    done ;;
  both)    run_one tb_t80_ss 10us; run_one tb_t80_saverestore 60us ;;
  *) echo "usage: $0 [export|restore|repro|fixed|sweep|both]" >&2; exit 2 ;;
esac
