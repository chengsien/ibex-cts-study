#!/usr/bin/env python3
"""e16_plot.py — E16: post-route WNS of the automated useful-skew loop next to
the manual launch-side runs (results/e16_compare.png, results/e16_compare.csv).
Values come from each run's clock_final.kv; E16r_* runs (relaxed guard) are
included when they exist."""
import csv
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = Path(__file__).resolve().parent.parent
SUB = Path("nangate45/ibex/base")
RUNS = [("RA", "RA\n(default)"), ("RE_full", "RE_full\n(manual, 9 moves)"),
        ("RE_full3b", "RE_full3b\n(manual, +2 buf)"),
        ("E16_1", "E16_1\n(auto, strict)"), ("E16_2", "E16_2\n(same tree)")]
RUNS += [(p.name, f"{p.name}\n(auto, 2 ps tol.)") for p in sorted((REPO / "runs").glob("E16r_*"))]


def kv(run):
    d = {}
    p = REPO / "runs" / run / "reports" / SUB / "clock_final.kv"
    if p.exists():
        for line in p.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1); d[k] = v
    return d


rows = []
for run, label in RUNS:
    k = kv(run)
    if "setup_wns_ns" not in k:
        continue
    mv = REPO / "runs" / run / "reports" / SUB / "e16_moves_out.txt"
    rows.append({"run": run, "setup_wns_ps": round(1e3 * float(k["setup_wns_ns"]), 1),
                 "hold_wns_ps": round(1e3 * float(k["hold_wns_ns"]), 1),
                 "clock_buffers": k.get("clock_buffers"),
                 "clock_power_mw": round(1e3 * float(k["power_clock_w"]), 3),
                 "moved_registers": sum(1 for _ in open(mv)) if mv.exists() else "",
                 "label": label})
with open(REPO / "results" / "e16_compare.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=[c for c in rows[0] if c != "label"], extrasaction="ignore")
    w.writeheader(); w.writerows(rows)
fig, ax = plt.subplots(figsize=(8.5, 4))
col = ["#999999" if r["run"] == "RA" else "#4C72B0" if r["run"].startswith("RE") else "#C44E52" for r in rows]
ax.bar(range(len(rows)), [r["setup_wns_ps"] for r in rows], color=col)
for i, r in enumerate(rows):
    v = r["setup_wns_ps"]
    ax.text(i, v + (1 if v >= 0 else -1), f"{v:+.1f}", ha="center", va="bottom" if v >= 0 else "top", fontsize=9)
ax.axhline(0, color="black", lw=0.8)
ax.set_xticks(range(len(rows))); ax.set_xticklabels([r["label"] for r in rows], fontsize=8)
ax.set_ylabel("post-route setup WNS (ps)")
ax.set_title("E16: automated launch-side useful skew (red) vs manual runs (blue), Ibex 2.2 ns")
ax.grid(axis="y", alpha=0.3)
fig.tight_layout(); fig.savefig(REPO / "results" / "e16_compare.png", dpi=150)
for r in rows:
    print(r)
