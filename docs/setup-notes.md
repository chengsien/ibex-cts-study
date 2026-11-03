# Setup notes

## Step 0 — environment feasibility

### Machine

Cloud container: Ubuntu 24.04.5, 4 vCPU, 15 GB RAM, no GPU. Docker 29.9.2 is
installed, but the daemon was not running; starting `dockerd` by hand worked.

### What was tried, in order

| # | Approach | Result |
|---|---|---|
| 1 | `docker pull openroad/orfs:<tag>` (official ORFS prebuilt image) | **Blocked**: Docker Hub `429 Too Many Requests`. The container shares its egress IP, and `ratelimit-remaining: 0;w=3600` showed the anonymous 100-pulls/hour budget for that IP was already spent. `mirror.gcr.io` also returned 429. |
| 2 | Precision Innovations prebuilt `.deb` (GitHub releases) | **Blocked**: the session's network policy only allows the GitHub API for attached repos, so the release list could not be read (HTTP 403). |
| 3 | conda `litex-hub` channel | Reachable, but the newest `openroad` / `yosys` / `klayout` builds are from **2024-02-23** (OpenROAD `2.0_12381`, Yosys 0.38). That is about 2.5 years older than ORFS master, and there is no `yosys-slang`, which this ORFS version's ibex config needs (`SYNTH_HDL_FRONTEND = slang`). Rejected because of the version skew. |
| 4 | **Rebuild the official image from its layer blobs** | **Worked.** Docker Hub only rate-limits *manifest* requests; layer blob downloads are not limited. The Hub web API (`hub.docker.com/v2/repositories/openroad/orfs/tags/<tag>/images`) lists every layer digest. All 26 blobs (1.56 GB) were downloaded in about 40 s and each was **SHA256-verified against its digest**. They were unpacked in order with OCI whiteout handling, then loaded with `docker import`. Script: `scripts/fetch_orfs_image.sh`. |
| – | Build from source | Not needed, so not attempted. |

The image tag `26Q4-260-gc9ac73efc` is the CI build of **the same ORFS commit**
that was cloned (`c9ac73efc603…`). Running `diff -rq` between the clone's `flow/` and
the image's `/OpenROAD-flow-scripts/flow` showed **no differences**. So the
flow scripts, platform files and design files are the cloned commit exactly.

### Tool versions

| Tool | Version | Source |
|---|---|---|
| ORFS | commit `c9ac73efc603ec3b830caecd7874b1419c1b7d41` (2026-11-03) | git clone + identical copy in image |
| OpenROAD | ORFS submodule commit `98c6045c72b79e40023a129f11370587eec47e5a` (2026-10-27) | image binary. `openroad -version` prints `unknown` because the CI build has no git metadata. The submodule pin is the version. The `help clock_tree_synthesis` output matches `src/cts/README.md` at that commit. |
| OpenSTA | OpenROAD submodule `384b539085c5` | (inside OpenROAD) |
| Yosys | 0.68+post, with the slang frontend built in (`3. Executing SLANG frontend.` in the synth log) | image |
| KLayout | 0.30.12 (Ubuntu package inside the image) | image |
| Image OS | Ubuntu 26.04.1 LTS | image |

### Default full flow (Step 0 check)

```
scripts/run.sh -n step0_default -p 2.2 -u 50      # = make DESIGN_CONFIG=./designs/nangate45/ibex/config.mk
```

* Result: completed all stages, synth → floorplan → place → CTS → GRT → detailed route →
  fill → final report, plus GDS merge (`6_final.gds`). Detailed route finished
  with **0 DRC violations**.
* **Wall time: about 515 s (8.6 min)** on 4 vCPUs, from `constraint.sdc` written
  (08:06:19) to `6_report.log` written (08:14:51). The wrapper's own timer was
  lost for this one run: I edited `run.sh` while bash was still executing it,
  and the final bookkeeping line broke. Every later run records `wall_seconds`
  in `runs/<run>/run_config.txt`.
* Per-stage elapsed times from ORFS logs: synthesis 67 s, global place 23 s,
  global route (with timing repair) 71 s, **detailed route 258 s**, final
  report and LEC about 37 s. CTS itself takes seconds.
* Post-route timing at the ORFS default 2.2 ns: setup WNS **−0.014 ns**
  (31 endpoints fail, TNS −0.36 ns), hold WNS +0.085 ns. So the ORFS default
  period is *just* not met after RCX extraction, though it is met at GRT
  (+0.016 ns).

## Phase 1.1 — what the ibex design config says

Source files: `flow/designs/nangate45/ibex/config.mk` and `constraint.sdc` (ORFS `c9ac73efc`).

| Item | Value | Where |
|---|---|---|
| Top module | `ibex_core` | `DESIGN_NAME` |
| Clock port | **`clk_i`** | SDC `clk_port_name` |
| Clock name | `core_clock` (plus a virtual `vclk_core_clock` for I/O constraints) | SDC |
| Default period | **2.2 ns** (≈ 454.5 MHz) | SDC `clk_period` |
| Time unit | **ns**. Liberty `time_unit : "1ns"`, so SDC numbers are in ns | `NangateOpenCellLibrary_typical.lib` |
| I/O delay | 20 % of period on all non-clock inputs/outputs, w.r.t. `vclk_core_clock` | SDC `clk_io_pct 0.2` |
| Pre-CTS clock latency | `set_clock_latency 0.285` on both clocks. This is an *ideal* network latency. After CTS the clock is `set_propagated_clock` and the real tree delay replaces it. | SDC |
| RTL | lowRISC **Ibex**, pruned copy of https://github.com/lowRISC/ibex at commit `77d801001554cce8fe69e742e96539eecbe74425`. SystemVerilog, read through the **yosys-slang** frontend. | `designs/src/ibex_sv/README.md`, `SYNTH_HDL_FRONTEND = slang` |
| Ibex parameters | `ibex_core` defaults: RV32IMC, `RV32M = RV32MFast`, `RV32B = None`, `RV32E = 0`, PMP off, no I-cache, no writeback stage, `BranchTargetALU = 0`, `MHPMCounterNum = 0` | `ibex_core.sv` |
| **Register file** | **`RegFile = RegFileFF`**: flip-flop register file (`ibex_register_file_ff.sv`), 31 × 32 b in DFFs. These flops are about half of all clock sinks, which matters for CTS. | `ibex_core.sv` line 24 |
| Clock gating | one core clock gate, `prim_clock_gating` from `syn/rtl/prim_clock_gating.v` (latch + AND). Synthesised to `DLL_X1` + AND. | `config.mk` `VERILOG_FILES` |
| **Core utilization** | **50 %** (`CORE_UTILIZATION ?= 50`) | `config.mk` |
| Other non-default knobs | `PLACE_DENSITY_LB_ADDON = 0.20`, `TNS_END_PERCENT = 100`, `SETUP_REPAIR_PHASES = PARALLEL_EVAL`, `GPL_PLACE_IOS = 1` | `config.mk` |

Size of the implemented baseline (2.2 ns): 1 937 flip-flops (1 655 DFFR, 273 DFF,
9 DFFS) plus 1 clock-gate latch, so **1 938 clock sinks**. 15 091 standard cells
before fill. Synthesis cell area 28 151 µm². Core 56 103 µm² (about 237 × 237 µm).

## Phase 1.2 — Nangate45 library corners

`flow/platforms/nangate45/lib/` holds exactly **one** standard-cell Liberty file:

* `NangateOpenCellLibrary_typical.lib`, operating condition `typical`:
  process 1.00, **1.10 V, 25 °C**.

Everything else in that directory is `fakeram45_*.lib`, SRAM black-box models
generated by FakeRAM2.0. Ibex does not use them. There are **no slow/fast
(SS/FF) corners** in the platform, and `config.mk` defines no `CORNERS`. So:

* All setup **and** hold analysis in this study is single-corner (TT, 1.1 V, 25 °C).
  A real sign-off would check hold at the fast corner and setup at the slow
  corner. Hold margins here are therefore optimistic in an absolute sense,
  though they are still comparable between runs.
* The Nangate library is "purposely non-manufacturable" (platform README). It
  sits on FreePDK45, an open academic PDK, **not a foundry process**.

Clock-relevant cells in the library: `CLKBUF_X1/X2/X3` (the strongest clock
buffer is only X3), `BUF_X1…X32`, `CLKGATE(TST)_X1…X8`. TritonCTS picked
`CLKBUF_X3` for every tree buffer in the baseline. That leaves CTS very little
choice in buffer sizes.

## Phase 1.3 — run wrapper

`scripts/run.sh` (see header for all options). Each run writes to its own
`runs/<run_name>/` (ORFS `WORK_HOME`): `logs/ reports/ results/ objects/`,
`flow.log`, the per-run `constraint.sdc`, and `run_config.txt`, which records
every knob, the image, the exit code and the wall time.

* `-p` period: substitutes only the `set clk_period` line of the ORFS SDC.
* `-u` utilization: `CORE_UTILIZATION`.
* `-c` CTS args: full override of ORFS `CTS_ARGS`. `-s` and `-d` set the cluster size and diameter.
* `-t` POST_CTS_TCL hook, used for the manual-skew experiment.
* `-b BASE`: copy a finished run and delete every stage-4+ artifact, so `make`
  restarts **at CTS from the identical 3_place.odb**. This is how Phase 2 holds
  RTL, SDC, floorplan and placement fixed.

`scripts/post_reports.sh <run>` then runs `scripts/clock_report.tcl` on
`4_1_cts.odb` (placement-estimated RC) and `6_final.odb` + `6_final.spef`
(OpenRCX). It reports insertion delay, skew, clock buffers, clock wirelength,
WNS/TNS and the power breakdown.
