# Phase I read-trace results

Generated from `sim/traces/phase1_read_traces.csv` using the repository's trace-driven direct-mapped cache model.

| Workload | Reads | Hits | Misses | Hit rate | Miss rate | Analytical AMAT |
|---|---:|---:|---:|---:|---:|---:|
| Sequential | 20 | 16 | 4 | 80.00% | 20.00% | 2.00 cycles |
| Repeated block | 16 | 15 | 1 | 93.75% | 6.25% | 1.3125 cycles |
| Conflict thrashing | 8 | 0 | 8 | 0.00% | 100.00% | 6.00 cycles |

AMAT uses the documented analytical convention: hit time = 1 cycle and miss penalty = 5 cycles (the configured memory response latency). It is not cycle-accurate RTL timing; controller/refill overhead is not included. These are small, deliberately constructed traces demonstrating spatial locality, temporal locality and direct-mapped conflict behavior—not a claim about a real application workload.

Reproduce with:

```sh
python3 analysis/cache_trace_benchmark.py
```
