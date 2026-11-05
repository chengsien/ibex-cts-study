#!/usr/bin/env python3
"""e13_collect.py — gather the E13 crosstalk-proxy result lines
(runs/<run>/reports/.../e13_xtalk.txt, written by scripts/e13_run.sh) and the
SPEF coupling summary (results/e13_coupling.csv) into results/e13_xtalk.csv,
and plot setup WNS per scenario (results/e13_xtalk.png)."""
import csv
import re
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = Path(__file__).resolve().parent.parent
SUB = Path("nangate45/ibex/base")
RUNS = ["RC_none", "RA", "RC_full", "RB_nocl", "RB_s4", "RD_phys2", "RE_combo3"]
SCEN = ["nom", "clk_x2", "clk_bound", "all_bound"]
LABEL = {"RC_none": "RC_none\n(NDR none)", "RA": "RA\n(default)",
         "RC_full": "RC_full\n(NDR full)", "RB_nocl": "RB_nocl\n(no clustering)",
         "RB_s4": "RB_s4\n(cluster 4)", "RD_phys2": "RD_phys2\n(capture skew)",
         "RE_combo3": "RE_combo3\n(best)"}


def ms(x):
    return round(float(x) * 1000.0, 1)


def main():
    cpl = {}
    for r in csv.DictReader(open(REPO / "results" / "e13_coupling.csv")):
        if r["nets"] == "clock":
            cpl[r["run"]] = r
    rows = []
    for run in RUNS:
        txt = (REPO / "runs" / run / "reports" / SUB / "e13_xtalk.txt").read_text()
        for sc in SCEN:
            m = re.search(rf"^E13 {sc} maxk=\S+ mink=\S+ (.*)$", txt, re.M)
            w = re.search(rf"^E13 {sc} worst_setup slack=(\S+) capture_clk_delay=(\S+) "
                          rf"endpoint=(\S+) startpoint=(\S+)", txt, re.M)
            kv = dict(p.split("=", 1) for p in m.group(1).split())
            lmin, lmean, lmax = kv["ck_late_min/mean/max"].split("/")
            emin, emean, emax = kv["ck_early_min/mean/max"].split("/")
            rows.append({
                "run": run, "scenario": sc,
                "setup_wns_ps": ms(kv["setup_wns"]), "setup_tns_ns": kv["setup_tns"],
                "setup_viol": kv["setup_viol"],
                "hold_wns_ps": ms(kv["hold_wns"]), "hold_viol": kv["hold_viol"],
                "ck_late_mean_ps": ms(lmean), "ck_late_max_ps": ms(lmax),
                "ck_early_mean_ps": ms(emean), "ck_early_min_ps": ms(emin),
                "worst_startpoint": w.group(4), "worst_endpoint": w.group(3),
                "clock_coupling_frac": cpl[run]["coupling_frac"],
                "clock_coupling_pF": cpl[run]["coupling_cap_pF"],
            })
    out = REPO / "results" / "e13_xtalk.csv"
    with open(out, "w", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        wr.writeheader(); wr.writerows(rows)
    print("wrote", out)
    for r in rows:
        print(f"{r['run']:10s} {r['scenario']:10s} setup {r['setup_wns_ps']:7.1f} ps "
              f"(viol {r['setup_viol']:>4s})  hold {r['hold_wns_ps']:5.1f} ps  "
              f"ck late mean {r['ck_late_mean_ps']:5.1f} early mean {r['ck_early_mean_ps']:5.1f}")

    # plot: setup WNS per run for nom / clk_x2 / clk_bound (all_bound is off-scale)
    fig, ax = plt.subplots(figsize=(9.5, 4.6))
    colors = {"nom": "#4C72B0", "clk_x2": "#DD8452", "clk_bound": "#C44E52"}
    names = {"nom": "nominal (coupling x1)", "clk_x2": "clock-net coupling x2",
             "clk_bound": "clock bound: late x2 / early x0"}
    wd = 0.26
    for i, sc in enumerate(["nom", "clk_x2", "clk_bound"]):
        ys = [next(r["setup_wns_ps"] for r in rows if r["run"] == run and r["scenario"] == sc)
              for run in RUNS]
        xs = [k + (i - 1) * wd for k in range(len(RUNS))]
        ax.bar(xs, ys, wd, color=colors[sc], label=names[sc])
        for x, y in zip(xs, ys):
            ax.text(x, y + (1.2 if y >= 0 else -1.2), f"{y:.0f}", ha="center",
                    va="bottom" if y >= 0 else "top", fontsize=7)
    ax.axhline(0, color="black", lw=0.8)
    ax.set_xticks(range(len(RUNS)))
    ax.set_xticklabels([LABEL[r] for r in RUNS], fontsize=8)
    ax.set_ylabel("post-route setup WNS (ps)")
    ax.set_title("E13: setup WNS when clock-net coupling caps are scaled (Ibex, 2.2 ns, CRPR on)")
    ax.legend(fontsize=8, loc="upper left")
    ax.grid(axis="y", alpha=0.3)
    fig.tight_layout()
    fig.savefig(REPO / "results" / "e13_xtalk.png", dpi=150)
    print("wrote results/e13_xtalk.png")


if __name__ == "__main__":
    main()
