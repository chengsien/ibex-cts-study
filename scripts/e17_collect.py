#!/usr/bin/env python3
"""e17_collect.py — E17: Ibex on ASAP7 implemented at TT, signed off at
FF (BC) / TT (TC) / SS (WC).  Reads runs_big/asap7_*/reports/.../e17_corners.txt
(scripts/e17_corners.tcl) and clock_final.kv (TT), writes results/e17_corners.csv
and results/e17_corners.png.  ASAP7 times are in ps."""
import csv
import re
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = Path(__file__).resolve().parent.parent
SUB = Path("asap7/ibex/base")
RUNS = [("asap7_A", "default"), ("asap7_B", "clustering off"), ("asap7_C", "NDR full")]
CORN = [("BC", "FF 0.77 V 25 C"), ("TC", "TT 0.70 V 0 C"), ("WC", "SS 0.63 V 100 C")]

rows = []
for run, label in RUNS:
    rep = REPO / "runs_big" / run / "reports" / SUB
    kv = {}
    for line in (rep / "clock_final.kv").read_text().splitlines():
        if "=" in line:
            k, v = line.split("=", 1); kv[k] = v
    for line in (rep / "e17_corners.txt").read_text().splitlines():
        m = re.match(r"E17 corner=(\w+) (.*?) \(times", line)
        if not m:
            continue
        d = dict(x.split("=", 1) for x in m.group(2).split())
        lmin, lmean, lmax = d["ck_lat_min/mean/max"].split("/")
        rows.append({"run": run, "setting": label, "corner": m.group(1),
                     "setup_wns_ps": float(d["setup_wns"]), "setup_tns_ps": float(d["setup_tns"]),
                     "setup_viol": int(d["setup_viol"]), "hold_wns_ps": float(d["hold_wns"]),
                     "hold_viol": int(d["hold_viol"]), "ck_lat_min_ps": float(lmin),
                     "ck_lat_mean_ps": float(lmean), "ck_lat_max_ps": float(lmax),
                     "clock_buffers": kv.get("clock_buffers"),
                     "clock_power_tt_mw": round(1e3 * float(kv["power_clock_w"]), 4),
                     "total_power_tt_mw": round(1e3 * float(kv["power_total_w"]), 4)})
with open(REPO / "results" / "e17_corners.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)

fig, axs = plt.subplots(1, 3, figsize=(12.5, 4))
cols = {"asap7_A": "#4C72B0", "asap7_B": "#DD8452", "asap7_C": "#55A868"}
wd = 0.26
for ax, key, title in [(axs[0], "hold_wns_ps", "hold WNS (ps)"),
                       (axs[1], "setup_wns_ps", "setup WNS (ps), FF and TT"),
                       (axs[2], "ck_lat_mean_ps", "mean clock latency (ps)")]:
    corners = [c for c in CORN if not (key == "setup_wns_ps" and c[0] == "WC")]
    for i, (run, label) in enumerate(RUNS):
        ys = [next(r[key] for r in rows if r["run"] == run and r["corner"] == c) for c, _ in corners]
        xs = [k + (i - 1) * wd for k in range(len(corners))]
        ax.bar(xs, ys, wd, color=cols[run], label=label)
        for x, y in zip(xs, ys):
            ax.text(x, y, f"{y:.1f}", ha="center", va="bottom", fontsize=7)
    ax.set_xticks(range(len(corners))); ax.set_xticklabels([n for _, n in corners], fontsize=8)
    ax.set_title(title, fontsize=10); ax.grid(axis="y", alpha=0.3)
axs[0].legend(fontsize=8)
ss = {r["run"]: r["setup_wns_ps"] for r in rows if r["corner"] == "WC"}
axs[1].text(0.02, 0.95, "SS setup WNS: " + ", ".join(f"{k[-1]} {v:.0f}" for k, v in ss.items()),
            transform=axs[1].transAxes, fontsize=7, va="top")
fig.suptitle("E17: Ibex on ASAP7, implemented at TT (1468 ps), post-route sign-off at three corners")
fig.tight_layout(); fig.savefig(REPO / "results" / "e17_corners.png", dpi=150)
for r in rows:
    print(r)
