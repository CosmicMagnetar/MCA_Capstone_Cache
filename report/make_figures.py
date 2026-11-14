#!/usr/bin/env python3
"""Rebuild the four report figures from files in the repository.

    wave_hit.pdf  <- sim/waveforms/cache_hit.vcd
    wave_wt.pdf   <- sim/waveforms/write_through.vcd
    amat.pdf      <- AMAT_read = 2 + 9(1 - H), the measured hit/miss latencies
    bench.pdf     <- docs/results/rtl_trace_results.csv

Needs matplotlib. Run from anywhere: python3 report/make_figures.py
"""
import csv
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "report"

WAVE_SIGNALS = ["clk", "cpu_req", "cpu_write", "cpu_addr", "controller_state",
                "mem_req", "mem_ready", "cache_refill_en", "cpu_ready", "cpu_rdata",
                "hit_event", "miss_event"]
STATE_NAMES = {0: "IDLE", 1: "LOOKUP", 2: "RF_WAIT", 3: "RF_INST", 4: "RD_RET",
               5: "WH_WAIT", 6: "WM_UPD", 7: "WM_WAIT"}


def read_vcd(path):
    """Return {signal: [(time, value)]} for the top-level scope of a VCD file."""
    ids, depth, top, changes = {}, 0, None, {}
    time = 0
    lines = iter(path.read_text().splitlines())
    for line in lines:
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "$scope":
            depth += 1
            top = top or parts[2]
        elif parts[0] == "$upscope":
            depth -= 1
        elif parts[0] == "$var" and depth == 1:
            ids.setdefault(parts[3], parts[4])
        elif parts[0] == "$enddefinitions":
            break
    for line in lines:
        line = line.strip()
        if not line or line.startswith("$"):
            continue
        if line[0] == "#":
            time = int(line[1:]) / 1000  # VCD time unit is 1 ps
        elif line[0] in "01xz" and line[1:] in ids:
            changes.setdefault(ids[line[1:]], []).append((time, line[0]))
        elif line[0] == "b":
            bits, code = line[1:].split()
            if code in ids:
                value = int(bits, 2) if set(bits) <= {"0", "1"} else None
                changes.setdefault(ids[code], []).append((time, value))
    return changes


def plot_waves(vcd, out, title, t_end=None):
    waves = read_vcd(vcd)
    names = [s for s in WAVE_SIGNALS if s in waves]
    end = t_end or max(t for s in names for t, _ in waves[s])
    fig, ax = plt.subplots(figsize=(12, 0.45 * len(names) + 0.8))
    for row, name in enumerate(reversed(names)):
        y = row * 1.4
        points = [(t, v) for t, v in waves[name] if t <= end] + [(end, None)]
        is_bus = any(isinstance(v, int) and v > 1 for _, v in points[:-1]) or name in ("cpu_addr", "cpu_rdata", "controller_state")
        for (t0, v), (t1, _) in zip(points, points[1:]):
            if is_bus:
                ax.plot([t0, t1], [y, y], color="#1f4e79", lw=0.8)
                ax.plot([t0, t1], [y + 1, y + 1], color="#1f4e79", lw=0.8)
                ax.plot([t0, t0], [y, y + 1], color="#1f4e79", lw=0.8)
                if v is not None and t1 - t0 > end / 60:
                    label = STATE_NAMES.get(v, v) if name == "controller_state" else f"{v:X}"
                    ax.text((t0 + t1) / 2, y + 0.5, label, ha="center", va="center", fontsize=6)
            else:
                level = 1 if v in ("1", 1) else 0
                ax.plot([t0, t1], [y + level, y + level], color="#1f4e79", lw=1)
                nxt = next((w for t, w in points if t == t1), None)
                if nxt is not None:
                    ax.plot([t1, t1], [y, y + 1], color="#1f4e79", lw=0.6)
        ax.text(-end * 0.01, y + 0.5, name, ha="right", va="center", fontsize=8, family="monospace")
    ax.set_xlim(0, end)
    ax.set_ylim(-0.4, len(names) * 1.4)
    ax.set_yticks([])
    ax.set_xlabel("time (ns)")
    ax.set_title(title, fontsize=9)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    fig.tight_layout()
    fig.savefig(out)
    plt.close(fig)


def plot_amat(out, results):
    h = [i / 100 for i in range(101)]
    fig, ax = plt.subplots(figsize=(4.2, 2.8))
    ax.plot([x * 100 for x in h], [2 + 9 * (1 - x) for x in h], color="#1f4e79", label="2 + 9(1 - H)")
    for r in results:
        ax.scatter(float(r["hit_rate"]) * 100, float(r["measured_amat"]), zorder=3, s=18)
        ax.annotate(r["workload"], (float(r["hit_rate"]) * 100, float(r["measured_amat"])),
                    textcoords="offset points", xytext=(4, 4), fontsize=7)
    ax.set_xlabel("read hit rate H (%)")
    ax.set_ylabel("AMAT (cycles)")
    ax.grid(alpha=0.3)
    ax.legend(fontsize=7)
    fig.tight_layout()
    fig.savefig(out)
    plt.close(fig)


def plot_bench(out, results):
    names = [r["workload"] for r in results]
    measured = [float(r["measured_amat"]) for r in results]
    analytical = [1 + 5 * float(r["miss_rate"]) for r in results]
    x = range(len(names))
    fig, ax = plt.subplots(figsize=(4.2, 2.8))
    ax.bar([i - 0.2 for i in x], analytical, width=0.4, label="analytical (1 + 5M)", color="#9dc3e6")
    ax.bar([i + 0.2 for i in x], measured, width=0.4, label="measured on RTL", color="#1f4e79")
    for i, v in enumerate(measured):
        ax.text(i + 0.2, v + 0.15, f"{v:.2f}", ha="center", fontsize=7)
    ax.set_xticks(list(x), names, fontsize=8)
    ax.set_ylabel("AMAT (cycles)")
    ax.legend(fontsize=7)
    ax.grid(axis="y", alpha=0.3)
    fig.tight_layout()
    fig.savefig(out)
    plt.close(fig)


def main():
    with (ROOT / "docs/results/rtl_trace_results.csv").open() as f:
        results = list(csv.DictReader(f))
    plot_waves(ROOT / "sim/waveforms/cache_hit.vcd", OUT / "wave_hit.pdf",
               "cache_hit.vcd: cold read miss with four-word refill, then a read hit")
    plot_waves(ROOT / "sim/waveforms/write_through.vcd", OUT / "wave_wt.pdf",
               "write_through.vcd: write hit, write miss with allocation, read hit")
    plot_amat(OUT / "amat.pdf", results)
    plot_bench(OUT / "bench.pdf", results)
    print("wrote", ", ".join(p.name for p in sorted(OUT.glob("*.pdf")) if p.stem in
                             ("wave_hit", "wave_wt", "amat", "bench")))


if __name__ == "__main__":
    main()
