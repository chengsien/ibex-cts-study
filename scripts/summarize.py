#!/usr/bin/env python3
"""summarize.py — collect metrics from runs/<name>/ into CSV tables + plots.

Sources (all produced by the actual ORFS runs, nothing is estimated here):
  runs/<r>/run_config.txt                       knobs + wall time + exit code
  runs/<r>/logs/nangate45/ibex/base/*.json      ORFS/OpenROAD stage metrics
  runs/<r>/logs/nangate45/ibex/base/5_1_grt.log global-route congestion table
  runs/<r>/reports/.../clock_{cts,final}.kv     scripts/clock_report.tcl output

Usage:
  scripts/summarize.py sweep  RUN [RUN ...]   -> results/period_sweep.csv + png
  scripts/summarize.py cts    RUN [RUN ...]   -> results/cts_comparison.csv + png
  scripts/summarize.py show   RUN             -> print all collected fields
"""
import csv
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SUB = Path("nangate45/ibex/base")


def read_kv(p):
    d = {}
    if p.exists():
        for line in p.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                d.setdefault(k, v)  # first occurrence wins (makevar repeats)
    return d


def read_json(p):
    try:
        return json.loads(p.read_text())
    except Exception:
        return {}


def grt_congestion(logp):
    """Parse the *last* 'Final congestion report' table of the GRT log."""
    out = {}
    if not logp.exists():
        return out
    txt = logp.read_text(errors="replace")
    blocks = txt.split("Final congestion report:")
    if len(blocks) < 2:
        return out
    blk = blocks[-1]
    for m in re.finditer(
        r"^(metal\d+|Total)\s+(\d+)\s+(\d+)\s+([\d.]+)%\s+(\d+)\s*/\s*(\d+)\s*/\s*(\d+)",
        blk, re.M):
        layer = m.group(1).lower()
        out[f"grt_usage_{layer}_pct"] = float(m.group(4))
        out[f"grt_overflow_{layer}"] = int(m.group(7))
        if layer == "total":
            break
    return out


def drt_stats(logp):
    out = {}
    if not logp.exists():
        return out
    txt = logp.read_text(errors="replace")
    m = re.findall(r"Total wire length = ([\d.]+) um", txt)
    if m:
        out["drt_wirelength_um"] = float(m[-1])
    m = re.findall(r"Total number of vias = (\d+)", txt)
    if m:
        out["drt_vias"] = int(m[-1])
    m = re.findall(r"Number of violations = (\d+)", txt)
    if m:
        out["drt_violations_final"] = int(m[-1])
    return out


def collect(name):
    r = REPO / "runs" / name
    cfg = read_kv(r / "run_config.txt")
    logs = r / "logs" / SUB
    reps = r / "reports" / SUB
    row = {
        "run": name,
        "period_ns": float(cfg.get("period_ns", "nan")),
        "core_util": cfg.get("core_utilization"),
        "cts_args": cfg.get("cts_args_override") or "(ORFS default)",
        "cluster_size": cfg.get("cluster_size", ""),
        "cluster_diameter": cfg.get("cluster_diameter", ""),
        "post_cts_tcl": cfg.get("post_cts_tcl", ""),
        "base_run": cfg.get("base_run", ""),
        "exit_code": cfg.get("exit_code"),
        "wall_s": cfg.get("wall_seconds"),
    }
    m = {}
    for j in sorted(logs.glob("*.json")):
        m.update(read_json(j))

    def g(k):
        v = m.get(k)
        return v

    # ---- timing at each checkpoint (ORFS metrics, OpenSTA) ----
    for stage, pre in [("place", "detailedplace"), ("cts", "cts"),
                       ("grt", "globalroute"), ("route", "detailedroute"),
                       ("final", "finish")]:
        row[f"{stage}_setup_wns"] = g(f"{pre}__timing__setup__ws")
        row[f"{stage}_setup_tns"] = g(f"{pre}__timing__setup__tns")
        row[f"{stage}_hold_wns"] = g(f"{pre}__timing__hold__ws")
        row[f"{stage}_hold_tns"] = g(f"{pre}__timing__hold__tns")
    for stage, pre in [("cts", "cts"), ("grt", "globalroute"), ("final", "finish")]:
        row[f"{stage}_skew_setup_metric"] = g(f"{pre}__clock__skew__setup")
        row[f"{stage}_skew_hold_metric"] = g(f"{pre}__clock__skew__hold")
    row["final_fmax_core_clock_mhz"] = (
        g("finish__timing__fmax__clock:core_clock") or 0) / 1e6 or None
    row["final_power_total_w"] = g("finish__power__total")
    row["final_instance_count"] = g("finish__design__instance__count")
    row["final_instance_area_um2"] = g("finish__design__instance__area")
    row["final_utilization"] = g("finish__design__instance__utilization")
    row["core_area_um2"] = g("finish__design__core__area")
    # hold / setup buffers inserted by repair_timing at each stage
    for stage, pre in [("floorplan", "floorplan"), ("cts", "cts"),
                       ("grt", "globalroute")]:
        row[f"{stage}_hold_buffers"] = g(f"{pre}__design__instance__count__hold_buffer")
        row[f"{stage}_setup_buffers"] = g(f"{pre}__design__instance__count__setup_buffer")
    row["drt_drc_errors"] = g("detailedroute__route__drc_errors")
    row["drt_wirelength_metric"] = g("detailedroute__route__wirelength")
    row.update(grt_congestion(logs / "5_1_grt.log"))
    row.update(drt_stats(logs / "5_2_route.log"))

    # ---- per-endpoint post-route setup slack (scripts/endpoint_slack.tcl) ----
    es = reps / "endpoint_slack_final.csv"
    if es.exists():
        with open(es) as fh:
            ep = {x["endpoint"]: float(x["slack_ns"]) for x in csv.DictReader(fh)}
        row["endpoints_below_0ps"] = sum(1 for v in ep.values() if v < 0)
        row["endpoints_below_20ps"] = sum(1 for v in ep.values() if v < 0.020)
        ref = REPO / "runs" / "RA" / "reports" / SUB / "endpoint_slack_final.csv"
        if ref.exists():
            with open(ref) as fh:
                ra = {x["endpoint"]: float(x["slack_ns"]) for x in csv.DictReader(fh)}
            fail = [e for e, v in ra.items() if v < 0]
            # endpoints absent from the dump have slack >= 0.1 ns: count them as 0.1
            d = [1e3 * (ep.get(e, 0.1) - ra[e]) for e in fail]
            if d:
                row["ra_fail_endpoints_dslack_mean_ps"] = round(sum(d) / len(d), 2)
                row["ra_fail_endpoints_dslack_min_ps"] = round(min(d), 2)
            # per-endpoint split of that change into clock and data parts:
            #   dclock = d(capture latency) - d(launch latency)
            #   ddata  = dslack - dclock      (data path + setup time)
            ca = REPO / "runs" / "RA" / "reports" / SUB / "ck_arrivals_final.csv"
            cr = reps / "ck_arrivals_final.csv"
            if ca.exists() and cr.exists():
                def arrivals(path):
                    with open(path) as fh:
                        return {x["instance"]: float(x["arrival_ns"]) for x in csv.DictReader(fh)}
                def ep_rows(path):
                    with open(path) as fh:
                        return {x["endpoint"]: x for x in csv.DictReader(fh)}
                a_ra, a_r = arrivals(ca), arrivals(cr)
                e_ra, e_r = ep_rows(ref), ep_rows(es)
                dclk, ddat = [], []
                for e in fail:
                    if e not in e_r:
                        continue
                    sp_ra = e_ra[e]["startpoint"].rsplit("/", 1)[0]
                    sp_r = e_r[e]["startpoint"].rsplit("/", 1)[0]
                    if sp_ra not in a_ra or sp_r not in a_r:
                        continue
                    dcap = float(e_r[e]["capture_clk_ns"]) - float(e_ra[e]["capture_clk_ns"])
                    dlau = a_r[sp_r] - a_ra[sp_ra]
                    dc = 1e3 * (dcap - dlau)
                    dclk.append(dc)
                    ddat.append(1e3 * (float(e_r[e]["slack_ns"]) - float(e_ra[e]["slack_ns"])) - dc)
                if dclk:
                    row["ra_fail_dclock_mean_ps"] = round(sum(dclk) / len(dclk), 2)
                    row["ra_fail_ddata_mean_ps"] = round(sum(ddat) / len(ddat), 2)
                    row["ra_fail_split_n"] = len(dclk)
    # number of physical useful-skew buffers (RD_phys*), from the clock report
    # masters list is not enough (CLKBUF_X1 could come from CTS); use the hook report
    hk = reps / "rd_phys_useful_skew.rpt"
    if hk.exists():
        m = re.search(r"kept=(\d+)", hk.read_text())
        row["usefulskew_buffers"] = int(m.group(1)) if m else None

    # ---- worst post-route setup path, decomposed (scripts/worst_paths.tcl) ----
    wp = reps / "worst_paths_final.txt"
    if wp.exists():
        lines = wp.read_text().splitlines()
        if len(lines) > 1:
            f = lines[1].split()
            row.update({"wp_slack_ns": float(f[0]), "wp_launch_clk_ns": float(f[1]),
                        "wp_capture_clk_ns": float(f[2]), "wp_skew_cap_minus_launch_ns": float(f[3]),
                        "wp_data_delay_ns": float(f[4]), "wp_startpoint": f[5], "wp_endpoint": f[7]})

    # ---- clock-network metrics from scripts/clock_report.tcl ----
    for st in ("cts", "final"):
        kv = read_kv(reps / f"clock_{st}.kv")
        for k, v in kv.items():
            if k in ("parasitics", "clock_buffer_masters",
                     "insertion_delay_min_pin", "insertion_delay_max_pin"):
                row[f"{st}_{k}"] = v
                continue
            try:
                row[f"{st}_{k}"] = float(v)
            except ValueError:
                row[f"{st}_{k}"] = v
    return row


def write_csv(rows, path, cols=None):
    if cols is None:
        cols = []
        for r in rows:
            for k in r:
                if k not in cols:
                    cols.append(k)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k) for k in cols})
    print(f"wrote {path.relative_to(REPO)} ({len(rows)} rows)")


def plot_sweep(rows, png):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    rows = sorted(rows, key=lambda r: r["period_ns"])
    x = [r["period_ns"] for r in rows]
    fig, ax = plt.subplots(figsize=(6.4, 4.0), dpi=150)
    for key, lab, mk in [("cts_setup_wns", "post-CTS (placement RC est.)", "s"),
                         ("grt_setup_wns", "post-GRT (global-route RC est.)", "^"),
                         ("final_setup_wns", "post-route (OpenRCX SPEF)", "o")]:
        y = [r.get(key) for r in rows]
        if any(v is not None for v in y):
            ax.plot(x, [v if v is not None else float("nan") for v in y],
                    marker=mk, label=lab)
    ax.axhline(0, color="0.4", lw=0.8, ls="--")
    ax.set_xlabel("clock period (ns)")
    ax.set_ylabel("setup WNS (ns)")
    ax.set_title("Ibex / Nangate45 — clock-period sweep")
    ax.grid(alpha=0.3)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(png)
    print(f"wrote {png.relative_to(REPO)}")


def plot_cts(rows, png):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    names = [r["run"] for r in rows]
    panels = [
        ("final_insertion_delay_max_ns", "max insertion delay (ns)"),
        ("final_skew_setup_ns", "setup skew, post-route (ns)"),
        ("final_clock_buffers", "clock buffers"),
        ("final_setup_wns", "setup WNS, post-route (ns)"),
        ("final_setup_tns", "setup TNS, post-route (ns)"),
        ("final_power_clock_w", "clock-network power (mW)"),
    ]
    fig, axs = plt.subplots(2, 3, figsize=(12, 6.5), dpi=150)
    for ax, (k, lab) in zip(axs.flat, panels):
        vals = [r.get(k) if isinstance(r.get(k), (int, float)) else float("nan")
                for r in rows]
        if k.endswith("_w"):
            vals = [v * 1e3 for v in vals]
        ax.bar(range(len(names)), vals, color="#4C72B0")
        ax.set_xticks(range(len(names)))
        ax.set_xticklabels(names, rotation=45, ha="right", fontsize=7)
        ax.set_title(lab, fontsize=9)
        ax.grid(axis="y", alpha=0.3)
        for i, v in enumerate(vals):
            if v == v:
                ax.annotate(f"{v:.3g}", (i, v), ha="center", rotation=90,
                            va="bottom" if v >= 0 else "top", fontsize=6)
    fig.suptitle("CTS strategy comparison (same placement, post detailed route)")
    fig.tight_layout()
    fig.savefig(png)
    print(f"wrote {png.relative_to(REPO)}")


def plot_decomp(rows, png, ref="RA"):
    """Mean change of post-route setup slack over the endpoints that fail in
    the reference run, split into the clock part (capture - launch latency)
    and the data-path part. Per-endpoint, so it stays valid when the single
    worst endpoint moves to another flop."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    rr = [r for r in rows if r["run"] != ref and "ra_fail_dclock_mean_ps" in r]
    names = [r["run"] for r in rr]
    dclk = [r["ra_fail_dclock_mean_ps"] for r in rr]
    ddat = [r["ra_fail_ddata_mean_ps"] for r in rr]
    dtot = [r["ra_fail_endpoints_dslack_mean_ps"] for r in rr]
    n = rr[0].get("ra_fail_split_n", "?") if rr else "?"
    fig, ax = plt.subplots(figsize=(9, 4.3), dpi=150)
    x = range(len(names))
    ax.bar([i - 0.2 for i in x], dclk, 0.4, label="clock part (Δ capture − Δ launch latency)", color="#4C72B0")
    ax.bar([i + 0.2 for i in x], ddat, 0.4, label="data-path part", color="#DD8452")
    ax.plot(list(x), dtot, "k_", ms=18, mew=2, label="Δ slack (mean)")
    noise = [v for r, v in zip(rr, ddat) if r["run"].startswith("N_")]
    if noise:
        ax.axhspan(min(0, min(noise)), max(0, max(noise)), color="0.85", zorder=0,
                   label="data-path change from routing-only probes")
    ax.axhline(0, color="0.3", lw=0.8)
    ax.set_xticks(list(x)); ax.set_xticklabels(names, rotation=30, ha="right")
    ax.set_ylabel(f"change vs {ref} (ps, + = better)")
    ax.set_title(f"Post-route slack change on the {n} endpoints that fail in {ref} (2.2 ns), "
                 "mean per endpoint", fontsize=9)
    ax.legend(fontsize=7, loc="upper left"); ax.grid(axis="y", alpha=0.3)
    fig.tight_layout(); fig.savefig(png)
    print(f"wrote {png.relative_to(REPO)}")


SWEEP_COLS = [
    "run", "period_ns", "core_util", "exit_code", "wall_s",
    "place_setup_wns", "cts_setup_wns", "cts_setup_tns", "grt_setup_wns",
    "grt_setup_tns", "final_setup_wns", "final_setup_tns", "final_hold_wns",
    "final_hold_tns", "final_fmax_core_clock_mhz", "final_instance_count",
    "final_instance_area_um2", "cts_hold_buffers", "grt_hold_buffers",
    "final_power_total_w", "drt_drc_errors", "drt_wirelength_um",
]

CTS_COLS = [
    "run", "period_ns", "cts_args", "cluster_size", "cluster_diameter",
    "post_cts_tcl", "base_run", "exit_code",
    "cts_clock_sinks", "cts_clock_buffers", "cts_cts_dummy_loads",
    "cts_cts_delay_buffers", "cts_clock_buffer_area_um2",
    "cts_insertion_delay_min_ns", "cts_insertion_delay_max_ns",
    "cts_skew_setup_ns", "cts_skew_hold_ns",
    "final_insertion_delay_min_ns", "final_insertion_delay_max_ns",
    "final_skew_setup_ns", "final_skew_hold_ns",
    "final_clock_buffers", "final_clock_routed_wirelength_um",
    "cts_setup_wns", "cts_setup_tns", "cts_hold_wns", "cts_hold_tns",
    "grt_setup_wns", "grt_setup_tns",
    "final_setup_wns", "final_setup_tns", "final_hold_wns", "final_hold_tns",
    "cts_hold_buffers", "grt_hold_buffers", "final_hold_buffers_by_name",
    "cts_setup_buffers", "grt_setup_buffers",
    "final_power_clock_w", "final_power_sequential_w",
    "final_power_combinational_w", "final_power_total_w",
    "grt_usage_metal4_pct", "grt_usage_metal5_pct", "grt_usage_total_pct",
    "grt_overflow_total", "drt_wirelength_um", "drt_vias", "drt_drc_errors",
    "final_instance_count", "final_instance_area_um2",
    "wp_slack_ns", "wp_launch_clk_ns", "wp_capture_clk_ns",
    "wp_skew_cap_minus_launch_ns", "wp_data_delay_ns", "wp_startpoint", "wp_endpoint",
    "endpoints_below_0ps", "endpoints_below_20ps",
    "ra_fail_endpoints_dslack_mean_ps", "ra_fail_endpoints_dslack_min_ps",
    "ra_fail_dclock_mean_ps", "ra_fail_ddata_mean_ps", "ra_fail_split_n",
    "usefulskew_buffers",
]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    mode, runs = sys.argv[1], sys.argv[2:]
    rows = [collect(r) for r in runs]
    if mode == "show":
        for r in rows:
            for k, v in r.items():
                print(f"{k:40s} {v}")
    elif mode == "sweep":
        write_csv(rows, REPO / "results/period_sweep.csv", SWEEP_COLS)
        plot_sweep(rows, REPO / "results/period_sweep_wns.png")
    elif mode == "cts":
        write_csv(rows, REPO / "results/cts_comparison.csv", CTS_COLS)
        write_csv(rows, REPO / "results/cts_comparison_full.csv")
        plot_cts(rows, REPO / "results/cts_comparison.png")
        if any(r["run"] == "RA" for r in rows):
            plot_decomp(rows, REPO / "results/cts_slack_decomposition.png")
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
