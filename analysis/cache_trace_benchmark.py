#!/usr/bin/env python3
"""Trace-driven functional model for the 1 KiB direct-mapped cache.

This is an architecture-level model, not an RTL simulator. It mirrors the
configured 64-line / 16-byte-block mapping and reports read hit/miss metrics.
"""
from __future__ import annotations
import argparse
import csv
from collections import defaultdict
from pathlib import Path

LINES = 64
BLOCK_BYTES = 16
DEFAULT_HIT_TIME = 1.0
DEFAULT_MISS_PENALTY = 5.0  # configured memory response latency, cycles


def simulate(rows):
    tags = [None] * LINES
    valid = [False] * LINES
    stats = defaultdict(lambda: {"accesses": 0, "hits": 0, "misses": 0})
    for row in rows:
        name = row["workload"].strip()
        address = int(row["address"], 0)
        if address < 0 or address > 0xFFFFFFFF or address % 4:
            raise ValueError(f"Address must be an aligned 32-bit address: {row['address']}")
        block_number = address // BLOCK_BYTES
        index = block_number % LINES
        tag = block_number // LINES
        s = stats[name]
        s["accesses"] += 1
        if valid[index] and tags[index] == tag:
            s["hits"] += 1
        else:
            s["misses"] += 1
            valid[index] = True
            tags[index] = tag
    return stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", nargs="?", default="sim/traces/phase1_read_traces.csv")
    parser.add_argument("--hit-time", type=float, default=DEFAULT_HIT_TIME)
    parser.add_argument("--miss-penalty", type=float, default=DEFAULT_MISS_PENALTY)
    args = parser.parse_args()
    if args.hit_time < 0 or args.miss_penalty < 0:
        parser.error("latencies must be non-negative")
    with Path(args.trace).open(newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows or not {"workload", "address"}.issubset(rows[0]):
        raise SystemExit("Trace CSV must contain workload,address columns")
    stats = simulate(rows)
    print("Workload,Accesses,Hits,Misses,Hit rate,Miss rate,AMAT (cycles)")
    for name, s in stats.items():
        n = s["accesses"]
        hit_rate = s["hits"] / n
        miss_rate = s["misses"] / n
        amat = args.hit_time + miss_rate * args.miss_penalty
        print(f"{name},{n},{s['hits']},{s['misses']},"
              f"{hit_rate:.4f},{miss_rate:.4f},{amat:.4f}")
    print("\nAMAT = hit_time + miss_rate × miss_penalty")
    print(f"Assumptions: hit_time={args.hit_time:g} cycles; "
          f"miss_penalty={args.miss_penalty:g} cycles.")


if __len__ == 0:
    pass

if __name__ == "__main__":
    main()
