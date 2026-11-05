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
| `scripts/rd_phys_useful_skew.tcl` (`_bufx1`) | RD_phys: the same selection, built with `insert_buffer` delay buffers on the leaf clock nets |
| `scripts/rd2_select.tcl`, `scripts/rd_phys2_*.tcl` | useful skew round 2: targets from post-route slack, then round 1 + round 2 buffers |
| `scripts/re_select.tcl`, `scripts/re_launch_early.tcl`, `scripts/re_*.tcl` | launch-side useful skew: pick launch flops from post-route slack, move their CK pin one clock stage up |
| `scripts/ir_launch_scan.tcl` | launch slack of every instruction-register bit (direct `-from` scan) |
| `scripts/endpoint_slack.tcl`, `scripts/dump_ck_arrivals.tcl` | per-endpoint post-route slack / capture latency / startpoint, and every register's CK arrival |
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
python3 scripts/summarize.py cts R0a R0b RA RB_nocl RB_s4 RB_s20 RC_none RC_root RC_full RD RD_phys RD_phys_b1 RD_phys2_444 RD_phys2 RE RE_multi RE_full RE_full2 RE_full2b RE_combo RE_combo2 RE_combo3 N_gr48 N_gr52
```

`phase2.sh` runs all 24 Phase 2 runs (including RC_root, the N_gr* noise
probes, RD_phys*, the round-2 runs and the RE launch-early runs, whose
targets `rd2_select.tcl` / `re_select.tcl` pick from post-route timing). It then runs `worst_paths.tcl`, `endpoint_slack.tcl`
and `dump_ck_arrivals.tcl` on each run for the per-endpoint clock/data split.

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
RA fails on 31 endpoints. All of them are register-file flops reached from
one startpoint (`if_stage_i.instr_rdata_id_o[20]`). "Δslack" is the mean
change of post-route slack on those 31 endpoints vs RA (+ = better), split
per endpoint into the **clock part** (Δcapture − Δlaunch latency) and the
**data part**.
Full table: [`results/cts_comparison.csv`](results/cts_comparison.csv).
Plots: [`results/cts_comparison.png`](results/cts_comparison.png),
[`results/cts_slack_decomposition.png`](results/cts_slack_decomposition.png).

| run | CTS setting | Δslack (ps) | **clock part** | data part | WNS (ns) | TNS (ns) | max ins. delay (ns) | clk bufs | hold WNS (ns) / hold-fix cells | clock / total power (mW) |
|---|---|---|---|---|---|---|---|---|---|---|
| R0a = R0b = RA | ORFS default (clustering auto ≈ 9, NDR half) | 0 | 0 | 0 | −0.014 | −0.36 | 0.312 | 316 | +0.086 / 0 | 4.16 / 12.71 |
| RB_nocl | clustering off | +19.4 | **+18.9** | +0.6 | +0.004 | 0 | **0.289** | 295 | +0.085 / 0 | 4.25 / 12.80 |
| RB_s4 | cluster size 4 | +27.3 | +14.6 | +12.7† | +0.010 | 0 | 0.312 | 590 | +0.085 / 0 | **5.24 / 13.78** |
| RB_s20 | cluster size 20 | = RA (identical tree) | | | | | | | | |
| RC_none | NDR none | +4.7 | +4.6 | +0.1 | −0.009 | −0.21 | 0.311 | 316 | +0.086 / 0 | 4.16 / 12.71 |
| RC_root | NDR root_only | = RA (same 7 nets as half) | | | | | | | | |
| RC_full | NDR full (9 nets) | +30.6 | +13.9 | +16.7† | +0.016 | 0 | 0.298 | 316 | +0.086 / 0 | 4.14 / 12.69 |
| RD | useful skew **emulated** (`set_clock_latency`, STA only) | +26.7 | +26.7 | 0.0 | +0.014 | 0 | 0.312 | 316 | +0.086 / 0 | 4.16 / 12.71 |
| **RD_phys** | useful skew **built**: 15 × `CLKBUF_X1` before 62 regfile flops | **+41.8** | **+36.3** | +5.6 | **+0.018** | 0 | 0.324 | 331 | +0.086 / 0 | 4.19 / 12.74 |
| RD_phys_b1 | same with 15 × `BUF_X1` | +34.2 | +28.7 | +5.5 | +0.015 | 0 | 0.316 | 331 | +0.086 / 0 | 4.20 / 12.75 |
| RD_phys2_444 | round 2: + 1 buffer for `rf_reg[444]` only | +36.9 | +34.8 | +2.1 | +0.017 | 0 | 0.324 | 332 | +0.085 / 0 | 4.19 / 12.74 |
| **RD_phys2** | round 2 from post-route timing: + 21 buffers for 57 flops < 30 ps | **+55.4** | **+45.7** | +9.7 | **+0.023** | 0 | 0.352 | 352 | +0.085 / 0 | 4.24 / 12.79 |
| RE | launch-early: `instr_rdata_id_o[20]` CK one stage up (0 cells) | +22.3 | +8.3‡ | +14.0 | +0.008 | 0 | 0.312 | 316 | +0.086 / 0 | 4.16 / 12.71 |
| **RE_full** | launch-early: 9 instruction-register bits one stage up (0 cells) | +45.8 | **+41.9** | +3.9 | **+0.032** | 0 | 0.312 | 316 | +0.086 / 0 | **4.16 / 12.71** |
| RE_full2 | RE_full + `[20]` a second level up | – | – | – | +0.025 | 0 | 0.313 | 316 | +0.085 / 0 | 4.16 / 12.71 |
| **RE_full2b** | RE_full2 + 1 `CLKBUF_X1` in front of `[20]` | – | – | – | **+0.036** | 0 | 0.314 | 317 | +0.086 / 0 | 4.16 / 12.71 |
| **RE_combo3** | RD_phys2 + 10 launch moves | **+98.4** | **+84.7** | +11.6 | **+0.048** | 0 | 0.352 | 352 | +0.085 / 0 | 4.24 / 12.79 |
| N_gr48 | *noise probe*: routing-only change | +0.4 | +0.7 | −0.3 | −0.014 | −0.35 | 0.311 | 316 | +0.086 / 0 | 4.16 / 12.71 |
| N_gr52 | *noise probe*: routing-only change | +26.8 | −0.9 | +27.7 | +0.006 | 0 | 0.315 | 316 | +0.086 / 0 | 4.16 / 12.70 |

‡ the binding path switches from `[20]` to `[15]`, so this is not the size of the move (−42 ps). RE_multi / RE_combo / RE_combo2 are in experiment-log E9.

† within the data-part noise band (up to +27.7 ps, N_gr52), so not
credited to CTS. The clock part moves by ≤ 0.9 ps in the noise probes, so it
is the trustworthy column.

**Takeaways** (details in [`docs/findings.md`](docs/findings.md) and
[`docs/experiment-log.md`](docs/experiment-log.md)):
* Repeating a run gives zero noise (the flow is deterministic). A
  routing-only perturbation still moves WNS by up to 21 ps, so pass/fail at
  the stress period does not rank strategies. Compare the clock part on a
  fixed endpoint set instead.
* **Useful skew built with real buffers (RD_phys) gives the largest gain:
  +36 ps clock part.** It costs 15 `CLKBUF_X1`, +0.9 % clock power and no hold
  fixing. OpenROAD has no useful-skew engine; it was scripted with
  `insert_buffer` on the leaf clock nets (`scripts/rd_phys_useful_skew.tcl`).
  It beat the STA emulation (+27 ps) only because one buffer stage
  (about 36 ps) overshoots the requested 13 ps. The launch side of those
  flops had ≥ 0.14 ns to spare.
* **Round 2** used post-route slack to pick targets.
  * Delaying only `rf_reg[444]`, the new worst endpoint, lifts that
    endpoint by +28.6 ps but lowers WNS by 1.7 ps: routing noise moved its
    neighbours by more than the 0.3 ps that was available.
  * Treating the whole < 30 ps tier (RD_phys2) gets WNS to +23.5 ps, but
    only +5 ps more for 21 buffers and +1.1 % clock power. New path
    families from other instruction-register bits now limit it.
* **Launch-side useful skew is the cheapest lever** (E9). Moving the CK pins
  of the 9 most critical instruction-register flops one clock stage up
  (`connect_pin`, **no new cell**, +0.1 % clock power) gives WNS +31.6 ps.
  That beats RD_phys2's 36 capture-side buffers. Combined with those
  buffers (RE_combo3) it reaches **+48.2 ps**, the best result. Selecting
  by each register's own launch slack mattered: two earlier attempts that
  enumerated paths per endpoint missed launch flops.
* Moving `[20]` a **second** clock level up overshoots (79 ps). The paths
  *into* `[20]` become critical and WNS drops to +24.6 ps, as predicted
  before the run. Adding one `CLKBUF_X1` back balances its launch and
  capture sides (+62.8 / +61.3 ps) and gives **+36.2 ps**, the best
  launch-only result (E10).
* TritonCTS knobs:
  * clustering **off**: +19 ps for +2 % clock power.
  * cluster size 4: +15 ps for +26 % clock power.
  * NDR **full**: +14 ps, ≈ free here.
  * cluster size 20 and NDR root_only: no-ops in this design.
* No strategy needed or saved any hold fixing: hold slack was +85 ps
  everywhere at the single typical corner.
