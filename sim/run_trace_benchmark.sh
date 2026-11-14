#!/usr/bin/env bash
# Replays every workload in the trace CSV through the RTL and writes the
# measured hit/miss counts and AMAT to docs/results/rtl_trace_results.csv.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TRACE_CSV="${1:-sim/traces/phase1_read_traces.csv}"
BUILD="sim/traces/build"
OUT="docs/results/rtl_trace_results.csv"
SIM="${TMPDIR:-/tmp}/tb_trace_replay.vvp"
mkdir -p "$BUILD" docs/results

iverilog -g2012 -Wall -s tb_trace_replay -o "$SIM" \
  rtl/address_decoder.v rtl/cache_storage.v rtl/cache_controller.v \
  rtl/performance_monitor.v memory/main_memory_model.v rtl/cache_top.v \
  sim/testbenches/tb_trace_replay.v

workloads=$(tail -n +2 "$TRACE_CSV" | cut -d, -f1 | awk '!seen[$0]++')

echo "workload,accesses,hits,misses,hit_rate,miss_rate,total_cycles,avg_hit_cycles,avg_miss_cycles,measured_amat" > "$OUT"
status=0
for w in $workloads; do
  hex="$BUILD/$w.hex"
  awk -F, -v w="$w" 'NR > 1 && $1 == w { sub(/^0[xX]/, "", $2); print $2 }' "$TRACE_CSV" > "$hex"
  n=$(wc -l < "$hex" | tr -d ' ')
  line=$(vvp -n "$SIM" +TRACE="$hex" +N="$n" +NAME="$w" | grep '^RESULT,')
  IFS=, read -r _ name acc hits misses cyc hcyc mcyc errs <<< "$line"
  if [[ "$errs" != 0 ]]; then
    echo "FAIL: $name had $errs errors"
    status=1
  fi
  awk -v n="$name" -v a="$acc" -v h="$hits" -v m="$misses" -v c="$cyc" -v hc="$hcyc" -v mc="$mcyc" 'BEGIN {
    printf "%s,%d,%d,%d,%.4f,%.4f,%d,%.2f,%.2f,%.4f\n", n, a, h, m, h/a, m/a, c,
      (h ? hc/h : 0), (m ? mc/m : 0), c/a
  }' >> "$OUT"
done

column -s, -t "$OUT"
[[ $status == 0 ]] && echo "ALL TRACES PASS" || echo "SOME TRACES FAILED"
exit $status
