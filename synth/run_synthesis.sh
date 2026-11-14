#!/usr/bin/env bash
# Synthesis for the cache subsystem.
#   generic : technology-independent gate/flip-flop count (yosys)
#   ecp5    : Lattice ECP5-85F utilisation, then place-and-route timing (nextpnr-ecp5)
#
# Needs yosys. nextpnr-ecp5 is optional; the pip package yowasp-nextpnr-ecp5
# works if there's no native build (set NEXTPNR=yowasp-nextpnr-ecp5).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
mkdir -p build reports

NEXTPNR="${NEXTPNR:-nextpnr-ecp5}"

yosys -q -l reports/generic.log cache_generic.ys
yosys -q -l reports/ecp5.log cache_ecp5.ys

if command -v "$NEXTPNR" >/dev/null 2>&1; then
  "$NEXTPNR" --85k --package CABGA756 --json build/cache_top_ecp5.json \
    --lpf-allow-unconstrained --freq 100 --seed 1 \
    --report reports/ecp5_pnr_report.json --log reports/ecp5_pnr.log >/dev/null
  grep -E 'Max frequency for clock' reports/ecp5_pnr.log | tail -1
else
  echo "nextpnr-ecp5 not found: utilisation only, no timing"
fi

grep -E 'cells|DFF|LUT4|TRELLIS_FF|DP16KD|CCU2C' reports/generic_stat.txt reports/ecp5_stat.txt
