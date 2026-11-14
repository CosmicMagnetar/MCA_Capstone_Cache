#!/usr/bin/env python3
"""Append a seeded random read workload to the trace CSV.

Addresses are word aligned and drawn from a window the size of the cache
(1 KiB), so the hit rate shows how quickly random reuse warms the cache.
Running it again with the same seed gives the same rows.
"""
import argparse
import csv
import random
from pathlib import Path


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("trace", nargs="?", default="sim/traces/phase1_read_traces.csv")
    ap.add_argument("--count", type=int, default=64)
    ap.add_argument("--seed", type=int, default=2026)
    ap.add_argument("--window", type=lambda s: int(s, 0), default=0x400)
    args = ap.parse_args()

    path = Path(args.trace)
    with path.open(newline="") as f:
        rows = [r for r in csv.DictReader(f) if r["workload"] != "random"]

    rng = random.Random(args.seed)
    words = args.window // 4
    for _ in range(args.count):
        rows.append({"workload": "random", "address": f"0x{rng.randrange(words) * 4:08X}"})

    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["workload", "address"])
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {args.count} random rows (seed={args.seed}) to {path}")


if __name__ == "__main__":
    main()
