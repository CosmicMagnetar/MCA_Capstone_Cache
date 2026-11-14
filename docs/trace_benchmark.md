# Phase I trace benchmark

## Purpose and method

This benchmark supplies repeatable word-aligned read traces to an architecture-level direct-mapped cache model. It uses the RTL configuration: 64 lines and 16-byte blocks (four 32-bit words per line). For each byte address:

- block number = address / 16
- index = block number mod 64
- tag = floor(block number / 64)

The model starts with all valid bits clear. A hit requires a valid indexed line and matching tag; a miss installs the requested tag in that line. The trace contains three deliberately distinct patterns: sequential spatial locality, repeated temporal locality, and repeated conflict between addresses 0x00000000 and 0x00000400 (same index, different tags).

## Run

From the repository root:

```sh
python3 analysis/cache_trace_benchmark.py
```

Optional AMAT assumptions can be supplied with `--hit-time` and `--miss-penalty`.

## AMAT convention and limitation

The script reports the conventional estimate:

`AMAT = hit time + miss rate × miss penalty`

Defaults are hit time = 1 cycle and miss penalty = 5 cycles, where five cycles is the configured main-memory model response latency. This is a transparent analytical estimate, not a measured end-to-end RTL latency: controller state transitions and refill installation add cycles, and write-through transactions are excluded because these traces are read-only. The results must not be described as cycle-accurate measurements from `cache_top`.

## Scope

The trace model is a functional reference for mapping and locality analysis. The committed Icarus Verilog regression remains the evidence that the actual RTL lookup, refill, replacement, write-through and counters work. A follow-up RTL trace-replay testbench should be used if cycle-accurate AMAT is required.
