# Trace benchmark results

Traces live in `sim/traces/phase1_read_traces.csv`. Every workload starts from a cold cache.

## Measured on the RTL

`sim/run_trace_benchmark.sh` replays each workload through `cache_top` (decoder, storage, controller, memory model and performance monitor) and counts the clock cycles from the request edge until `cpu_ready`. Each read value is checked against memory, which is preloaded with a different pattern in every word. Hit and miss counts come from the hardware performance counters.

| Workload | Reads | Hits | Misses | Hit rate | Hit latency | Miss latency | Measured AMAT |
|---|---:|---:|---:|---:|---:|---:|---:|
| Sequential | 20 | 16 | 4 | 80.00% | 2 cycles | 11 cycles | 3.80 cycles |
| Repeated block | 16 | 15 | 1 | 93.75% | 2 cycles | 11 cycles | 2.56 cycles |
| Conflict thrashing | 8 | 0 | 8 | 0.00% | – | 11 cycles | 11.00 cycles |
| Random (seed 2026, 64 reads in 1 KiB) | 64 | 23 | 41 | 35.94% | 2 cycles | 11 cycles | 7.77 cycles |

Measured AMAT is total cycles divided by accesses. It works out to `2 + miss_rate × 9`: a hit takes 2 cycles, and a miss adds 9 more, made up of the 5-cycle memory latency plus the controller's request, refill and response states.

## Analytical model

`analysis/cache_trace_benchmark.py` is a pure Python model of the same mapping (64 lines, 16-byte blocks). It uses the textbook form `AMAT = hit_time + miss_rate × miss_penalty`, with hit time 1 and penalty 5.

| Workload | Hits | Misses | Analytical AMAT |
|---|---:|---:|---:|
| Sequential | 16 | 4 | 2.00 |
| Repeated block | 15 | 1 | 1.3125 |
| Conflict thrashing | 0 | 8 | 6.00 |
| Random | 23 | 41 | 4.20 |

The hit and miss counts agree exactly with the RTL on all four traces, which cross-checks the decoder and the tag/valid logic. The AMAT values differ only because the model ignores controller overhead. Use the measured numbers when quoting performance.

These are small, constructed traces that show spatial locality, temporal locality, conflict thrashing and random reuse. They don't represent any real application workload.

## Reproduce

```sh
python3 analysis/gen_random_trace.py      # rebuilds the random rows (seed 2026)
bash sim/run_trace_benchmark.sh           # RTL replay -> docs/results/rtl_trace_results.csv
python3 analysis/cache_trace_benchmark.py # analytical model
```
