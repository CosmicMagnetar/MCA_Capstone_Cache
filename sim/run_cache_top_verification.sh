#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

command -v iverilog >/dev/null 2>&1 || {
  echo "ERROR: install Icarus Verilog (iverilog and vvp)" >&2
  exit 127
}
command -v vvp >/dev/null 2>&1 || {
  echo "ERROR: vvp not found" >&2
  exit 127
}

OUT_DIR="${TMPDIR:-/tmp}/mca-cache-issue8"
mkdir -p "$OUT_DIR" sim/waveforms

iverilog -g2012 -Wall -s tb_cache_top -o "$OUT_DIR/tb_cache_top.vvp" \
  rtl/address_decoder.v \
  rtl/cache_storage.v \
  rtl/cache_controller.v \
  rtl/performance_monitor.v \
  memory/main_memory_model.v \
  rtl/cache_top.v \
  sim/testbenches/tb_cache_top.v

echo "=== Full Issue #7 + Issue #8 integrated verification ==="
vvp "$OUT_DIR/tb_cache_top.vvp"

run_wave_scenario() {
  local scenario="$1"
  local waveform="$2"
  echo "=== Waveform scenario: $scenario -> $waveform ==="
  vvp "$OUT_DIR/tb_cache_top.vvp" \
    "+SCENARIO=$scenario" "+WAVE=sim/waveforms/$waveform"
  test -s "sim/waveforms/$waveform" || {
    echo "ERROR: waveform is missing or empty: sim/waveforms/$waveform" >&2
    exit 1
  }
  grep -Fq '$enddefinitions' "sim/waveforms/$waveform" || {
    echo "ERROR: waveform has no VCD definitions: sim/waveforms/$waveform" >&2
    exit 1
  }
  grep -Fq 'controller_state' "sim/waveforms/$waveform" || {
    echo "ERROR: waveform lacks controller state: sim/waveforms/$waveform" >&2
    exit 1
  }
  awk '
    BEGIN { target_count = split("clk cpu_req cpu_ready controller_state mem_req mem_ready cache_refill_data monitored_valid monitored_tag monitored_cache_block monitored_memory_word", targets, " ") }
    $1 == "$var" { id_by_name[$5] = $4 }
    $1 == "$enddefinitions" { body = 1; next }
    body && /^[01xXzZ]/ { samples[substr($0, 2)]++ }
    body && /^b[01xXzZ]+[[:space:]]/ { samples[$2]++ }
    END {
      for (i = 1; i <= target_count; i++) {
        name = targets[i]
        if (id_by_name[name] == "" || samples[id_by_name[name]] < 2) {
          printf "ERROR: waveform signal %s is missing or has no transitions\n", name > "/dev/stderr"
          exit 1
        }
      }
    }
  ' "sim/waveforms/$waveform" || exit 1
  echo "PASS: sim/waveforms/$waveform ($(wc -c < "sim/waveforms/$waveform") bytes)"
}

run_wave_scenario reset_invalid_lines reset_invalid_lines.vcd
run_wave_scenario cache_hit cache_hit.vcd
run_wave_scenario cache_miss cache_miss.vcd
run_wave_scenario consecutive_requests consecutive_requests.vcd
run_wave_scenario controller_busy controller_busy.vcd
run_wave_scenario block_refill_order block_refill_order.vcd
run_wave_scenario conflict_replacement conflict_replacement.vcd
run_wave_scenario write_through write_through.vcd

echo "ALL INTEGRATED CACHE VERIFICATION AND WAVEFORM RUNS PASSED"
