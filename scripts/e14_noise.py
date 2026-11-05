#!/usr/bin/env python3
"""e14_noise.py — routing-noise distribution (E14).

Every N_grXX run has the clock tree of RA (default CTS on R0a's placement)
and differs only in the metal2-metal3 global-routing capacity adjustment
(0.XX instead of 0.50) set right before global route.  For each probe:
  * post-route setup WNS / TNS (clock_final.kv) and the change vs RA,
  * the per-endpoint split over the endpoints that fail in RA, the same
    method as summarize.py (E7):
        dclock = d(capture latency) - d(launch latency)
        ddata  = dslack - dclock
Writes results/e14_noise.csv and results/e14_noise.png and prints the
distribution (mean, sample std, min, max) over the probes.
"""
import csv
import statistics as st
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = Path(__file__).resolve().parent.parent
SUB = Path("nangate45/ibex/base")


def kv(run):
    d = {}
    for line in (REPO / "runs" / run / "reports" / SUB / "clock_final.kv").read_text().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            d[k] = v
    return d


def ep(run):
    with open(REPO / "runs" / run / "reports" / SUB / "endpoint_slack_final.csv") as f:
        return {x["endpoint"]: x for x in csv.DictReader(f)}


def arr(run):
    with open(REPO / "runs" / run / "reports" / SUB / "ck_arrivals_final.csv") as f:
        return {x["instance"]: float(x["arrival_ns"]) for x in csv.DictReader(f)}


def split(run, e_ra, a_ra, fail):
    e_r, a_r = ep(run), arr(run)
    ds, dc, dd = [], [], []
    for e in fail:
        s_r = float(e_r[e]["slack_ns"]) if e in e_r else 0.1   # absent: >= 0.1 ns
        ds.append(1e3 * (s_r - float(e_ra[e]["slack_ns"])))
        if e not in e_r:
            continue
        sp_ra = e_ra[e]["startpoint"].rsplit("/", 1)[0]
        sp_r = e_r[e]["startpoint"].rsplit("/", 1)[0]
        if sp_ra not in a_ra or sp_r not in a_r:
            continue
        c = 1e3 * ((float(e_r[e]["capture_clk_ns"]) - float(e_ra[e]["capture_clk_ns"]))
                   - (a_r[sp_r] - a_ra[sp_ra]))
        dc.append(c)
        dd.append(1e3 * (float(e_r[e]["slack_ns"]) - float(e_ra[e]["slack_ns"])) - c)
    m = lambda x: sum(x) / len(x) if x else float("nan")
    return m(ds), m(dc), m(dd), len(dc)


def main():
    probes = sorted(p.name for p in (REPO / "runs").glob("N_gr*")
                    if (p / "reports" / SUB / "clock_final.kv").exists()
                    and (p / "reports" / SUB / "endpoint_slack_final.csv").exists())
    e_ra, a_ra = ep("RA"), arr("RA")
    fail = [e for e, x in e_ra.items() if float(x["slack_ns"]) < 0]
    k_ra = kv("RA")
    w_ra = float(k_ra["setup_wns_ns"])
    rows = []
    for r in probes:
        k = kv(r)
        w = float(k["setup_wns_ns"])
        dslack, dclk, ddata, n = split(r, e_ra, a_ra, fail)
        rows.append({
            "run": r, "m2m3_adjust": "0." + r[len("N_gr"):],
            "setup_wns_ps": round(1e3 * w, 1), "dwns_ps": round(1e3 * (w - w_ra), 1),
            "setup_tns_ns": k["setup_tns_ns"], "setup_viol": k["setup_viol_endpoints"],
            "skew_setup_ps": round(1e3 * float(k["skew_setup_ns"]), 1),
            "ra_fail_dslack_mean_ps": round(dslack, 2), "ra_fail_dclock_mean_ps": round(dclk, 2),
            "ra_fail_ddata_mean_ps": round(ddata, 2), "split_n": n,
        })
    out = REPO / "results" / "e14_noise.csv"
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader(); w.writerows(rows)
    print(f"RA: WNS {1e3*w_ra:.1f} ps, {len(fail)} failing endpoints")
    for r in rows:
        print(f"{r['run']:8s} adj={r['m2m3_adjust']}  WNS {r['setup_wns_ps']:6.1f} (d {r['dwns_ps']:+6.1f})"
              f"  31-ep dslack {r['ra_fail_dslack_mean_ps']:+6.2f} = clock {r['ra_fail_dclock_mean_ps']:+5.2f}"
              f" + data {r['ra_fail_ddata_mean_ps']:+6.2f}  (n={r['split_n']})")
    for key in ("dwns_ps", "ra_fail_dclock_mean_ps", "ra_fail_ddata_mean_ps"):
        v = [r[key] for r in rows]
        print(f"{key:24s} n={len(v)} mean={st.mean(v):+.2f} sd={st.stdev(v):.2f} "
              f"min={min(v):+.2f} max={max(v):+.2f}")

    fig, axs = plt.subplots(1, 2, figsize=(11, 4.2))
    xs = [float(r["m2m3_adjust"]) for r in rows]
    ax = axs[0]
    ax.axhline(0, color="black", lw=0.8)
    ax.plot(xs, [r["dwns_ps"] for r in rows], "o-", color="#4C72B0", label="setup WNS change")
    ax.plot([0.50], [0], "s", color="black", label="RA (0.50)")
    ax.set_xlabel("metal2-metal3 GRT capacity adjustment (RA = 0.50)")
    ax.set_ylabel("change vs RA (ps)")
    ax.set_title("post-route WNS, same clock tree")
    ax.grid(alpha=0.3); ax.legend(fontsize=8)
    ax = axs[1]
    ax.axhline(0, color="black", lw=0.8)
    ax.plot(xs, [r["ra_fail_ddata_mean_ps"] for r in rows], "o-", color="#DD8452", label="data part")
    ax.plot(xs, [r["ra_fail_dclock_mean_ps"] for r in rows], "o-", color="#55A868", label="clock part")
    ax.set_xlabel("metal2-metal3 GRT capacity adjustment")
    ax.set_ylabel("mean change over RA's failing endpoints (ps)")
    ax.set_title("per-endpoint split (31 endpoints)")
    ax.grid(alpha=0.3); ax.legend(fontsize=8)
    fig.suptitle(f"E14: routing-only noise, {len(rows)} probes")
    fig.tight_layout()
    fig.savefig(REPO / "results" / "e14_noise.png", dpi=150)
    print("wrote", out, "and results/e14_noise.png")


if __name__ == "__main__":
    main()
