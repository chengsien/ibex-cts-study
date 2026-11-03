# Ibex on Nangate45: CTS strategy study with OpenROAD-flow-scripts

**Goal.** Implement the Ibex RISC-V core with the open-source
OpenROAD-flow-scripts (ORFS) flow on the Nangate45 platform. Find the clock
period at which timing just fails (the "stress period"). At that period,
compare clock-tree-synthesis (CTS) strategies after **detailed route and
RC-extracted STA**, with RTL, SDC, floorplan, placement and tools held
fixed.

> * **Design:** [lowRISC Ibex](https://github.com/lowRISC/ibex), an
>   open-source RV32IMC core (Apache-2.0). ORFS's pruned copy at lowRISC commit
>   `77d80100` is used.
> * **Process:** FreePDK45 + Nangate Open Cell Library, an **open-source
>   academic PDK**. It is **not a foundry process** and is "purposely
>   non-manufacturable". It has a single typical corner (1.1 V, 25 °C).
>   Absolute numbers say nothing about any commercial 45 nm node. Only the
>   *relative* comparisons are meaningful.

## Flow

```
Ibex SV RTL ──yosys+slang──► netlist ──floorplan (50 % util)──► place
        ──► CTS (TritonCTS)  ◄── the only variable in Phase 2
        ──► global route + repair_timing ──► detailed route (TritonRoute)
        ──► OpenRCX extraction ──► OpenSTA (setup/hold/power) ──► GDS
```

* Tools are pinned through the ORFS Docker image `openroad/orfs:26Q4-260-gc9ac73efc`
  (ORFS `c9ac73efc`, OpenROAD `98c6045c`, Yosys 0.68, KLayout 0.30.12).
  Details are in [`docs/setup-notes.md`](docs/setup-notes.md) and
  [`fetch_inputs.md`](fetch_inputs.md).
* Phase 2 runs branch from **one** placement database (`runs/R0a/3_place.odb`),
  so the CTS setting is the only thing that differs. CTS is deterministic:
  the same placement gives a byte-identical CTS database.

## Repository layout

| Path | Content |
|---|---|
| `scripts/run.sh` | one ORFS run → `runs/<name>/` (period, utilization, CTS args, cluster size/diameter, POST_CTS hook, branch-from-placement) |
| `scripts/post_reports.sh`, `scripts/clock_report.tcl` | clock metrics on the CTS and final databases: insertion delay, skew, clock buffers, clock wirelength, WNS/TNS, power breakdown |
| `scripts/summarize.py` | builds `results/*.csv` + plots from the run reports |
| `scripts/sweep_period.sh`, `scripts/phase2.sh` | Phase 1 / Phase 2 drivers |
| `scripts/rd_useful_skew.tcl` | RD: useful-skew emulation with `set_clock_latency` |
| `scripts/ndr_check.tcl` | counts clock nets carrying a non-default rule |
| `scripts/worst_paths.tcl` | top post-route setup paths split into launch / capture clock latency and data delay |
| `scripts/noise_grt_adj_*.tcl` | routing-only perturbation probes (PRE_GLOBAL_ROUTE_TCL) |
| `scripts/fetch_orfs_image.sh` | rebuilds the ORFS image from verified layer blobs when Docker Hub returns 429 |
| `constraints/ibex_constraint.sdc` | byte-identical copy of the ORFS ibex SDC (only `clk_period` is substituted per run) |
| `runs/<name>/` | per-run logs, reports, `run_config.txt`. Large DB/layout files are git-ignored. |
| `results/` | `period_sweep.csv`, `cts_comparison.csv`, plots |
| `docs/` | `setup-notes.md`, `experiment-log.md`, `findings.md` |

## Reproduce

```bash
docker pull openroad/orfs:26Q4-260-gc9ac73efc    # or: scripts/fetch_orfs_image.sh
```

```bash
scripts/run.sh -n step0_default -p 2.2 -u 50 && scripts/post_reports.sh step0_default
```

```bash
scripts/sweep_period.sh 1.8 2.0 2.2 2.3 2.4 2.6
```

```bash
python3 scripts/summarize.py sweep P1p8 P2p0 P2p2 P2p25 P2p3 P2p4 P2p6
```

```bash
scripts/phase2.sh 2.2
```

```bash
python3 scripts/summarize.py cts R0a R0b RA RB_nocl RB_s4 RB_s20 RC_none RC_root RC_full RD N_gr48 N_gr52
```

`phase2.sh` runs all 12 Phase 2 runs (including RC_root and the N_gr*
noise probes) and then `scripts/worst_paths.tcl` for the slack
decomposition.

A full flow takes about 8.6 min on 4 vCPUs. A Phase 2 branch (CTS → finish)
takes about 5–7 min.

## Results summary

### Phase 1: period sweep (post-route, OpenRCX)

| period (ns) | 1.8 | 2.0 | **2.2** | **2.25** | 2.3 | 2.4 | 2.6 |
|---|---|---|---|---|---|---|---|
| setup WNS (ns) | −0.216 | −0.020 | **−0.014** | **+0.013** | +0.023 | +0.018 | +0.118 |
| setup TNS (ns) | −216.6 | −2.74 | −0.36 | 0 | 0 | 0 | 0 |

The shortest closing period is **2.25 ns**. The stress period is **2.2 ns**.
See [`results/period_sweep_wns.png`](results/period_sweep_wns.png).

### Phase 2: CTS strategies at 2.2 ns

All runs share R0a's placement. The numbers are post-route (OpenRCX SPEF).
"Δskew / Δdata" splits the change in worst-path slack vs RA into the clock
part (capture − launch latency) and the data-path part (+ = better).
Full table: [`results/cts_comparison.csv`](results/cts_comparison.csv).
Plots: [`results/cts_comparison.png`](results/cts_comparison.png),
[`results/cts_slack_decomposition.png`](results/cts_slack_decomposition.png).

| run | CTS setting | max ins. delay (ns) | skew (ns) | clk bufs | WNS (ns) | TNS (ns) | Δskew (ps) | Δdata (ps) | hold WNS (ns) | hold-fix cells | clock / total power (mW) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| R0a = R0b = RA | ORFS default (clustering auto ≈ 9, NDR half) | 0.312 | 0.040 | 316 | −0.014 | −0.36 | 0 | 0 | +0.086 | 0 | 4.16 / 12.71 |
| RB_nocl | clustering off | **0.289** | **0.022** | 295 | +0.004 | 0 | **+17.5** | −0.7 | +0.085 | 0 | 4.25 / 12.80 |
| RB_s4 | cluster size 4 | 0.312 | −0.030 | 590 | +0.010 | 0 | 0.0 | +25.7† | +0.085 | 0 | **5.24 / 13.78** |
| RB_s20 | cluster size 20 | = RA (identical tree) | | | | | | | | | |
| RC_none | NDR none | 0.311 | 0.032 | 316 | −0.009 | −0.21 | +5.0 | +0.3 | +0.086 | 0 | 4.16 / 12.71 |
| RC_root | NDR root_only | = RA (same 7 nets as half) | | | | | | | | | |
| RC_full | NDR full (9 nets) | 0.298 | 0.027 | 316 | **+0.016** | 0 | +14.1 | +16.7† | +0.086 | 0 | 4.14 / 12.69 |
| RD | manual skew via `set_clock_latency` (STA only) | 0.312 | – | 316 | +0.014 | 0 | +27.8 | +0.2 | +0.086 | 0 | 4.16 / 12.71 |
| N_gr48 | *noise probe*: routing-only change | 0.311 | 0.039 | 316 | −0.014 | −0.35 | +0.6 | −0.1 | +0.086 | 0 | 4.16 / 12.71 |
| N_gr52 | *noise probe*: routing-only change | 0.315 | 0.042 | 316 | +0.006 | 0 | 0.0 | +20.6 | +0.086 | 0 | 4.16 / 12.70 |

† within the ±20 ps data-path noise that a routing-only change produces
(N_gr52), so not credited to CTS.

**Takeaways** (details in [`docs/findings.md`](docs/findings.md)):
* Repeating a run gives zero noise (the flow is deterministic). A
  routing-only perturbation still moves WNS by up to 21 ps, so pass/fail at
  the stress period does not rank strategies.
* Robust clock effects:
  * Sink clustering **off** removes 17.5 ps of harmful skew on the
    critical path, for +2 % clock power.
  * NDR **full** removes 14 ps at no measurable cost.
* Smaller clusters cost +26 % clock power and give no clock benefit.
  Cluster size 20 and NDR root_only are no-ops in this design.
* Emulated useful skew gives the largest gain (+28 ps). It is not a
  TritonCTS feature, and the emulation is an STA what-if.
* No strategy needed or saved any hold fixing: hold slack was +85 ps
  everywhere at the single typical corner.
