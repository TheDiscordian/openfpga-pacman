#!/usr/bin/env bash
# Build + run the TRUE end-to-end save-state round-trip TB under GHDL (docker,
# mcode, --std=08), against the REAL Pac-Man datapath subset:
#   real T80sed/T80 + real dpram (work RAM + ss_buf, altera_mf) + verbatim
#   pacman watchdog + transcribed savestate FSM + APF host model.
#
#   ./sim/run_savestate_e2e.sh
#
# altera_mf is compiled from the quartus 21.1 sim_lib sources vendored under
# sim/altera_mf/ (altsyncram) into its own GHDL lib, then the DUT is analyzed
# against it. Run from the repo root.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMG="ghdl/ghdl:6.0.0-mcode-ubuntu-24.04"
QIMG="raetro/quartus:21.1"
STOP="${1:-9ms}"

# Extract the Intel altera_mf sim_lib (altsyncram model) from the cached quartus
# image if not already present. It's gitignored (Intel-licensed, build-time only).
if [ ! -f "$REPO/sim/altera_mf/altera_mf.vhd" ]; then
  echo "=== extracting altera_mf sim_lib from $QIMG ==="
  mkdir -p "$REPO/sim/altera_mf"
  CID="$(docker create "$QIMG")"
  docker cp "$CID:/opt/intelFPGA/quartus/eda/sim_lib/altera_mf.vhd" "$REPO/sim/altera_mf/altera_mf.vhd"
  docker cp "$CID:/opt/intelFPGA/quartus/eda/sim_lib/altera_mf_components.vhd" "$REPO/sim/altera_mf/altera_mf_components.vhd"
  docker rm "$CID" >/dev/null
fi

docker run --rm -v "$REPO":/work -w /work "$IMG" bash -c "
  set -e
  mkdir -p /tmp/amf /tmp/w
  echo '=== compile altera_mf (altsyncram sim model) ==='
  ghdl -a --std=08 -fsynopsys --work=altera_mf --workdir=/tmp/amf \
       sim/altera_mf/altera_mf_components.vhd >/dev/null 2>&1
  ghdl -a --std=08 -fsynopsys --work=altera_mf --workdir=/tmp/amf \
       sim/altera_mf/altera_mf.vhd >/dev/null 2>&1
  echo '=== analyze real RTL (dpram, T80 stack) + the e2e TB ==='
  ghdl -a --std=08 -fsynopsys -P/tmp/amf --workdir=/tmp/w \
       src/fpga/core/rtl/dpram.vhd \
       src/fpga/core/rtl/cpu/T80_Pack.vhd \
       src/fpga/core/rtl/cpu/T80_ALU.vhd \
       src/fpga/core/rtl/cpu/T80_Reg.vhd \
       src/fpga/core/rtl/cpu/T80_MCode.vhd \
       src/fpga/core/rtl/cpu/T80.vhd \
       src/fpga/core/rtl/cpu/T80sed.vhd \
       sim/tb_savestate_e2e.vhd
  echo '=== elaborate ==='
  ghdl -e --std=08 -fsynopsys -P/tmp/amf --workdir=/tmp/w tb_savestate_e2e
  echo '=== run ==='
  ghdl -r --std=08 -fsynopsys -P/tmp/amf --workdir=/tmp/w tb_savestate_e2e \
       --stop-time=${STOP} --ieee-asserts=disable
"
