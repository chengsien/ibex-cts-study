#!/usr/bin/env python3
"""e18_collect.py — E18: the same three CTS settings on Ibex and on a design
about 10x larger (nangate45/ariane133), side by side.

Reads clock_final.kv (scripts/clock_report.tcl), run_config.txt and, for the
per-endpoint split, endpoint_slack_final.csv + ck_arrivals_final.csv.
Writes results/e18_10x.csv and results/e18_10x.png.

Per-endpoint split (as in E7): over the endpoints that fail in the default
run of the same design, the mean change of slack vs the default, split into
  dclock = d(capture latency) - d(launch latency)   and   ddata = rest.
"""
import csv
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = Path(__file__).resolve().parent.parent
DESIGNS = {
    "ibex": {"root": REPO / "runs", "sub": Path("nangate45/ibex/base"),
             "runs": {"default": "RA", "no clustering": "RB_nocl", "NDR full": "RC_full"},
             "period_ns": 2.2},
    "ariane133": {"root": REPO / "runs_big", "sub": Path("nangate45/ariane133/base"),
                  "runs": {"default": "A_default", "no clustering": "B_nocl", "NDR full": "C_ndrfull"},
                  "period_ns": 3.0},
}


def kv(path):
    d = {}
    if path.exists():
        for line in path.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                d[k] = v
    return d


def rows_csv(path, key):
    if not path.exists():
        return {}
    with open(path) as f:
        return {x[key]: x for x in csv.DictReader(f)}


def split(dd, ref, run):
    rep = lambda r: dd["root"] / r / "reports" / dd["sub"]
    e_ref = rows_csv(rep(ref) / "endpoint_slack_final.csv", "endpoint")
    e_r = rows_csv(rep(run) / "endpoint_slack_final.csv", "endpoint")
    a_ref = {k: float(v["arrival_ns"]) for k, v in rows_csv(rep(ref) / "ck_arrivals_final.csv", "instance").items()}
    a_r = {k: float(v["arrival_ns"]) for k, v in rows_csv(rep(run) / "ck_arrivals_final.csv", "instance").items()}
    fail = [e for e, x in e_ref.items() if float(x["slack_ns"]) < 0]
    ds, dc = [], []
    for e in fail:
        if e not in e_r:
            continue
        s1, s0 = float(e_r[e]["slack_ns"]), float(e_ref[e]["slack_ns"])
        sp0 = e_ref[e]["startpoint"].rsplit("/", 1)[0]
        sp1 = e_r[e]["startpoint"].rsplit("/", 1)[0]
        if sp0 not in a_ref or sp1 not in a_r:
            continue
        c = (float(e_r[e]["capture_clk_ns"]) - float(e_ref[e]["capture_clk_ns"])) - (a_r[sp1] - a_ref[sp0])
        ds.append(1e3 * (s1 - s0)); dc.append(1e3 * c)
    if not ds:
        return None
    m = lambda x: sum(x) / len(x)
    return {"n_fail_ref": len(fail), "n_split": len(ds), "dslack_ps": round(m(ds), 2),
            "dclock_ps": round(m(dc), 2), "ddata_ps": round(m(ds) - m(dc), 2)}


def main():
    out = []
    for dname, dd in DESIGNS.items():
        base = None
        for label, run in dd["runs"].items():
            rd = dd["root"] / run
            k = kv(rd / "reports" / dd["sub"] / "clock_final.kv")
            if not k:
                print(f"{dname}/{run}: no clock_final.kv yet"); continue
            rc = kv(rd / "run_config.txt")
            f = lambda key: float(k[key]) if key in k and k[key] not in ("", "nan") else float("nan")
            row = {
                "design": dname, "setting": label, "run": run, "period_ns": dd["period_ns"],
                "std_cells": k.get("std_cell_instances"), "clock_sinks": k.get("clock_sinks"),
                "clock_buffers": k.get("clock_buffers"), "clock_nets": k.get("clock_nets"),
                "insertion_min_ps": round(1e3 * f("insertion_delay_min_ns"), 1),
                "insertion_mean_ps": round(1e3 * f("insertion_delay_mean_ns"), 1),
                "insertion_max_ps": round(1e3 * f("insertion_delay_max_ns"), 1),
                "insertion_spread_ps": round(1e3 * f("insertion_delay_spread_ns"), 1),
                "skew_setup_ps": round(1e3 * f("skew_setup_ns"), 1),
                "clock_wl_um": k.get("clock_routed_wirelength_um"),
                "clock_power_mw": round(1e3 * f("power_clock_w"), 3),
                "total_power_mw": round(1e3 * f("power_total_w"), 3),
                "setup_wns_ps": round(1e3 * f("setup_wns_ns"), 1),
                "setup_tns_ns": k.get("setup_tns_ns"), "setup_viol": k.get("setup_viol_endpoints"),
                "hold_wns_ps": round(1e3 * f("hold_wns_ns"), 1), "hold_viol": k.get("hold_viol_endpoints"),
                "wall_s": rc.get("wall_seconds"),
            }
            row["insertion_mean_pct_period"] = round(100 * row["insertion_mean_ps"] / (1e3 * dd["period_ns"]), 1)
            row["clock_power_share_pct"] = round(100 * row["clock_power_mw"] / row["total_power_mw"], 1)
            if base is None:
                base = row
            else:
                row["dwns_vs_default_ps"] = round(row["setup_wns_ps"] - base["setup_wns_ps"], 1)
                row["dclockpower_vs_default_pct"] = round(100 * (row["clock_power_mw"] / base["clock_power_mw"] - 1), 1)
                sp = split(dd, base["run"], run)
                if sp:
                    row.update({f"fail_{k2}": v for k2, v in sp.items()})
            out.append(row)
    if not out:
        return
    cols = []
    for r in out:
        for k2 in r:
            if k2 not in cols:
                cols.append(k2)
    p = REPO / "results" / "e18_10x.csv"
    with open(p, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols); w.writeheader(); w.writerows(out)
    print("wrote", p)
    for r in out:
        print({k2: r.get(k2) for k2 in ("design", "setting", "clock_sinks", "clock_buffers", "insertion_mean_ps",
                                        "insertion_mean_pct_period", "skew_setup_ps", "clock_power_share_pct",
                                        "setup_wns_ps", "setup_viol", "hold_wns_ps", "dwns_vs_default_ps",
                                        "fail_dclock_ps", "fail_ddata_ps", "fail_n_split", "dclockpower_vs_default_pct")})

    # plot: per design, clock-part gain and clock-power change vs default
    fig, axs = plt.subplots(1, 3, figsize=(12.5, 4))
    for ax, key, title in [(axs[0], "insertion_mean_pct_period", "mean insertion delay (% of period)"),
                           (axs[1], "fail_dclock_ps", "clock-part slack change vs default\n(mean over default's failing endpoints, ps)"),
                           (axs[2], "dclockpower_vs_default_pct", "clock power change vs default (%)")]:
        labels, vals, cols_ = [], [], []
        for r in out:
            v = r.get(key)
            if v is None:
                continue
            labels.append(f"{r['design']}\n{r['setting']}"); vals.append(v)
            cols_.append("#4C72B0" if r["design"] == "ibex" else "#C44E52")
        ax.bar(range(len(vals)), vals, color=cols_)
        for i, v in enumerate(vals):
            ax.text(i, v, f"{v:.1f}", ha="center", va="bottom" if v >= 0 else "top", fontsize=8)
        ax.set_xticks(range(len(vals))); ax.set_xticklabels(labels, fontsize=7)
        ax.axhline(0, color="black", lw=0.8); ax.set_title(title, fontsize=9); ax.grid(axis="y", alpha=0.3)
    fig.suptitle("E18: Ibex (blue) vs ariane133, about 10x larger (red), same three CTS settings")
    fig.tight_layout()
    fig.savefig(REPO / "results" / "e18_10x.png", dpi=150)
    print("wrote results/e18_10x.png")


if __name__ == "__main__":
    main()
