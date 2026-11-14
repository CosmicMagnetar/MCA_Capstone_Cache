#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p sim/waveforms
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
command -v iverilog >/dev/null 2>&1 || { echo "ERROR: install Icarus Verilog (iverilog/vvp)"; exit 127; }
command -v vvp >/dev/null 2>&1 || { echo "ERROR: vvp not found"; exit 127; }

OUT_DIR="${TMPDIR:-/tmp}/mca-cache-phase1-tests"
mkdir -p "$OUT_DIR"

run_test() {
  local top="$1" output="$2"; shift 2
  echo "=== Compile: $top ==="
  iverilog -g2012 -Wall -s "$top" -o "$OUT_DIR/$output" "$@"
  echo "=== Run: $top ==="
  vvp "$OUT_DIR/$output"
}

run_test tb_address_decoder address_decoder.vvp rtl/address_decoder.v sim/testbenches/tb_address_decoder.v
run_test tb_cache_storage storage.vvp rtl/cache_storage.v sim/testbenches/tb_cache_storage.v
run_test tb_cache_controller controller.vvp rtl/cache_controller.v rtl/performance_monitor.v sim/testbenches/tb_cache_controller.v
run_test tb_main_memory main_memory.vvp memory/main_memory_model.v sim/testbenches/tb_main_memory.v
run_test tb_memory_init memory_init.vvp memory/main_memory_model.v sim/testbenches/tb_memory_init.v
run_test tb_performance_monitor performance_monitor.vvp rtl/performance_monitor.v sim/testbenches/tb_performance_monitor.v

echo "=== Full integrated cache_top and waveform verification ==="
bash sim/run_cache_top_verification.sh

echo "=== RTL trace replay ==="
bash sim/run_trace_benchmark.sh

echo "ALL PHASE I UNIT, INTEGRATION, AND WAVEFORM TESTS COMPLETED"
