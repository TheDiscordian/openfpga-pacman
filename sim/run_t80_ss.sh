#!/usr/bin/env bash
# Build + run the T80 save-state testbenches under GHDL (docker, mcode, --std=08).
#
#   ./sim/run_t80_ss.sh            # run both testbenches
#   ./sim/run_t80_ss.sh export     # just the export read-out TB
#   ./sim/run_t80_ss.sh restore    # just the save+restore (export+import) TB
#
# Run from the repo root. The save+restore TB requires the import ports
# (ss_din/ss_wr/ss_load) on T80/T80sed/T80_Reg; until those land it analyses but
# elaboration of tb_t80_saverestore will fail on the missing ports.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMG="ghdl/ghdl:6.0.0-mcode-ubuntu-24.04"
WHICH="${1:-both}"

run_one() {
  local tb="$1" stop="$2"
  docker run --rm -v "$REPO":/work -w /work "$IMG" bash -c "
    set -e
    mkdir -p /tmp/ghdlwork
    ghdl -i --std=08 -fsynopsys --workdir=/tmp/ghdlwork \
         src/fpga/core/rtl/cpu/*.vhd sim/${tb}.vhd
    ghdl -m --std=08 -fsynopsys --workdir=/tmp/ghdlwork ${tb}
    ghdl -r --std=08 -fsynopsys --workdir=/tmp/ghdlwork ${tb} \
         --stop-time=${stop} --ieee-asserts=disable
  "
}

case "$WHICH" in
  export)  run_one tb_t80_ss          10us ;;
  restore) run_one tb_t80_saverestore 60us ;;
  both)    run_one tb_t80_ss 10us; run_one tb_t80_saverestore 60us ;;
  *) echo "usage: $0 [export|restore|both]" >&2; exit 2 ;;
esac
