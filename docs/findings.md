# Findings: CTS strategies for Ibex on Nangate45 (stress period 2.2 ns)

All numbers come from `results/cts_comparison_full.csv`, which
`scripts/summarize.py` builds from the run reports. The details and
per-experiment tables are in [`experiment-log.md`](experiment-log.md) (E2–E7).
Every run uses R0a's byte-identical placement and goes through detailed
route + OpenRCX + OpenSTA. The design and PDK are open source (Ibex,
FreePDK45/Nangate45), with a single typical corner and no OCV/derates and
no SI analysis.

## How the runs are compared

At 2.2 ns, RA (the ORFS default) fails on **31 endpoints**. All of them are
register-file flops `rf_reg[*]/D`, and all are reached from one startpoint,
the IF-stage instruction-register bit `if_stage_i.instr_rdata_id_o[20]`.
The main metric is the **mean change of post-route slack on those 31
endpoints**, split per endpoint into:

* **clock part** = Δ(capture clock latency) − Δ(launch clock latency)
* **data part** = the rest (data-path delay and setup time)

This view stays valid when a strategy moves the single worst endpoint
to another flop, which happens in RD_phys. The two routing-only
**noise probes** (N_gr48/N_gr52: placement and clock tree identical to RA,
global-routing capacity changed by ±0.02) set the noise floor. They move the
**data part by up to +27.7 ps** but the **clock part by only ≤ 0.9 ps**.
So a clock-part change is a real CTS effect, and a data-part change of up
to about 28 ps is not.

## Summary table (post-route, 2.2 ns)

| run | what changed | Δslack on RA's 31 failing endpoints (ps) | **clock part** | data part | WNS (ns) | TNS (ns) | max ins. delay (ns) | clock buffers | hold WNS (ns) / hold-fix cells | clock / total power (mW) | cell area (µm²) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| RA (= R0a = R0b) | ORFS default: clustering auto (size 9), NDR half | 0 | 0 | 0 | −0.0143 | −0.360 | 0.312 | 316 | +0.0855 / 0 | 4.158 / 12.706 | 29 018 |
| RB_nocl | clustering **off** | +19.4 | **+18.9** | +0.6 | +0.0043 | 0 | **0.289** | 295 | +0.0853 / 0 | 4.245 / 12.795 | 29 008 |
| RB_s4 | cluster size 4 | +27.3 | +14.6 | +12.7 | +0.0102 | 0 | 0.312 | **590** | +0.0848 / 0 | **5.239 / 13.782** | 29 281 |
| RB_s20 | cluster size 20 | = RA (byte-identical CTS DB) | | | | | | | | | |
| RC_none | NDR none (0 nets) | +4.7 | +4.6 | +0.1 | −0.0090 | −0.213 | 0.311 | 316 | +0.0855 / 0 | 4.162 / 12.710 | 29 019 |
| RC_root | NDR root_only (7 nets) | = RA (byte-identical CTS DB, same 7 nets as half) | | | | | | | | | |
| RC_full | NDR full (9 nets) | +30.6 | +13.9 | +16.7 | +0.0164 | 0 | 0.298 | 316 | +0.0855 / 0 | 4.140 / 12.688 | 29 018 |
| RD | useful skew **emulated** (`set_clock_latency`, 62 flops, STA only) | +26.7 | +26.7 | 0.0 | +0.0139 | 0 | 0.312 | 316 | +0.0855 / 0 | 4.158 / 12.706 | 29 018 |
| **RD_phys** | useful skew **built**: 15 × `CLKBUF_X1` in front of the same 62 flops | **+41.8** | **+36.3** | +5.6 | **+0.0185** | 0 | 0.324 | 331 | +0.0856 / 0 | 4.193 / 12.742 | 29 030 |
| **RD_phys_b1** | same, with 15 × `BUF_X1` | +34.2 | +28.7 | +5.5 | +0.0146 | 0 | 0.316 | 331 | +0.0856 / 0 | 4.201 / 12.748 | 29 030 |
| RD_phys2_444 | round 2: + 1 `CLKBUF_X1` in front of `rf_reg[444]` only | +36.9 | +34.8 | +2.1 | +0.0167 | 0 | 0.324 | 332 | +0.0854 / 0 | 4.194 / 12.743 | 29 031 |
| **RD_phys2** | round 2: + 21 `CLKBUF_X1` for 57 flops < 30 ps post-route (9 of them stacked, two stages) | **+55.4** | **+45.7** | +9.7 | **+0.0235** | 0 | **0.352** | 352 | +0.0854 / 0 | 4.240 / 12.788 | 29 047 |
| RE | launch-early: CK pin of `instr_rdata_id_o[20]` moved one stage up (0 cells) | +22.3 | +8.3† | +14.0 | +0.0078 | 0 | 0.312 | 316 | +0.0855 / 0 | 4.160 / 12.708 | 29 018 |
| **RE_full** | launch-early: 9 instruction-register bits moved one stage up (0 cells) | +45.8 | **+41.9** | +3.9 | **+0.0316** | 0 | 0.312 | 316 | +0.0855 / 0 | 4.162 / 12.710 | 29 018 |
| RE_full2 | RE_full + `[20]` a second level up (onto the root trunk) | – | – | – | +0.0246 | 0 | 0.313 | 316 | +0.0854 / 0 | 4.156 / 12.705 | 29 019 |
| **RE_full2b** | RE_full2 + 1 `CLKBUF_X1` in front of `[20]` (net extra shift 33 ps) | – | – | – | **+0.0362** | 0 | 0.314 | 317 | +0.0855 / 0 | 4.159 / 12.708 | 29 020 |
| RE_full3 | RE_full2b + `[15]` a second level up | – | – | – | +0.0372 | 0 | 0.320 | 317 | +0.0855 / 0 | 4.163 / 12.713 | 29 020 |
| **RE_full3b** | RE_full3 + 1 `CLKBUF_X1` in front of `[15]` | – | – | – | **+0.0405** | 0 | 0.320 | 318 | +0.0854 / 0 | 4.167 / 12.716 | 29 020 |
| **RE_combo3** | RD_phys2 + 10 launch moves | **+98.4** | **+84.7** | +11.6 | **+0.0482** | 0 | 0.352 | 352 | +0.0854 / 0 | 4.243 / 12.794 | 29 047 |
| N_gr48 | **noise probe** (routing only) | +0.4 | +0.7 | −0.3 | −0.0139 | −0.347 | 0.311 | 316 | +0.0855 / 0 | 4.158 / 12.706 | 29 018 |
| N_gr52 | **noise probe** (routing only) | +26.8 | −0.9 | **+27.7** | +0.0063 | 0 | 0.315 | 316 | +0.0855 / 0 | 4.158 / 12.702 | 29 019 |

†In RE the binding path into the 31 endpoints switches from `[20]` to `[15]`. The clock part then compares `[15]`'s launch now with `[20]`'s launch before, so the +8.3 ps is not the size of the move (−42 ps on `[20]`). Intermediate RE variants (RE_multi, RE_combo, RE_combo2) are in experiment-log E9.

GRT usage is 28.4–29.1 % with overflow 0, and DRC is 0 in every run.
Plots: `results/cts_comparison.png` (six metrics per run) and
`results/cts_slack_decomposition.png` (the clock/data split above, with the
routing-noise band shaded).

---

## 1. Which metric differs the most, and why?

**In relative terms: clock-tree size and clock power. In timing terms: the
clock part of the slack on the critical endpoints, i.e. latency/skew.**

* **Clock buffers and clock power** have the largest spread. RB_s4 (cluster
  size 4) doubles the clock buffers (316 → 590, +87 %), adds 14 % clock
  wire, and raises clock power by **+26 %**, which is **+8.5 % of total
  power**. The cause is direct: each cluster gets its own leaf `CLKBUF_X3`,
  so capping clusters at 4 sinks instead of about 9 nearly doubles the leaf
  drivers. Clock power is already 33 % of total power in the default run.
* **The clock part of the critical-endpoint slack** is the timing quantity
  that differs most among strategies (0 to +85 ps), and it is the one that
  can be trusted (noise ≤ 0.9 ps).
  * The largest come from **physically built useful skew**. On the capture
    side: +36.3 ps after one round (RD_phys), +45.7 ps after two (RD_phys2).
    On the **launch side** (9 instruction-register flops moved one clock
    stage earlier, RE_full): +41.9 ps with no new cell. Both together
    (RE_combo3): +84.7 ps.
  * Among the TritonCTS knobs, **clustering off (+18.9 ps)** is the
    largest. With clustering, the launch flop `instr_rdata_id_o[20]` sits in
    a cluster whose leaf buffer arrives about 21 ps *after* the capture
    flops' clusters, which is harmful skew. A 7-level H-tree built straight
    to the sinks (uniform depth 3) removes most of that offset. It also
    lowers max insertion delay by 23 ps, the largest latency change among
    the CTS knobs.
* **Setup WNS** spans 62.5 ps (−0.0143 … +0.0482 ns), about 2.8 % of the
  period. **TNS and pass/fail** look like the biggest change (−0.36 ns → 0,
  fail → pass). But the stress period misses by only 14 ps, and a
  routing-only perturbation (N_gr52) already makes it pass. So the
  pass/fail column cannot rank strategies.
* **Hold** does not differ: hold WNS is +0.0848 to +0.0856 ns in every run,
  and **0 hold-fix cells** are inserted anywhere, RD_phys included.

## 2. What do the improvements cost?

| improvement (clock part, credited) | cost |
|---|---|
| **Useful skew, built** (RD_phys): +36.3 ps | 15 `CLKBUF_X1` (+12 µm², +0.04 % area). Clock power **+0.9 %** (+0.036 mW), total +0.3 %. Clock wire +0.5 %, max insertion delay +11 ps. The delayed flops give up slack where they *launch*: register-file → register-file paths lose about 34 ps, but they started with ≥ 0.14 ns, so it does not show in WNS. Hold *into* the delayed flops drops by 39 ps (0.401 → 0.362 ns), still a large margin at the typical corner. The step is coarse: one `CLKBUF_X1` gives +27…41 ps (median 36) where 7–20 ps was asked for. That overshoot happens to help here, but it means the delay cannot be tuned finely. `BUF_X1` gives a smaller step (+20…34 ps) for +28.7 ps. |
| **Useful skew on the launch side** (RE_full): +41.9 ps; WNS +0.0316 ns | **No cell added**: 9 CK pins reconnected one clock stage up. Clock power +0.1 %, total +0.04 %, area unchanged. Paths captured *by* the moved flops (fetch → instruction register) lose about 15 ps (worst 0.117 → 0.103 ns). Hold is unchanged, because the worst hold paths are the flops' own enable loops. Side effect: up to 5 extra loads on shared upstream nets make some other flops up to 10 ps later. It beats RD_phys2's 36 buffers. Combined with them (RE_combo3): WNS +0.0482 ns. |
| **Useful skew, round 2** (RD_phys2): another +9.4 ps clock part on RA's 31 endpoints; +38.5 ps on the 57 new targets | 21 more buffers (36 in total), clock power +1.1 % on top of round 1 (+2.0 % vs RA), total +0.65 % vs RA, area +0.1 %. Max insertion delay rises to 0.352 ns (+40 ps vs RA), because of the 9 two-stage flops. Margins on the 110 delayed flops: launch side 0.126 ns (−17 ps vs RA), hold into them 0.338 ns (−63 ps). It buys only **+5 ps of WNS**. The next limiters are new path families (`instr_rdata_id_o[15]`, `[1]`) and a wall of 108 endpoints at 30–40 ps. Treating `rf_reg[444]` alone (RD_phys2_444) lifts that endpoint by +28.6 ps but *lowers* WNS by 1.7 ps through routing noise. |
| **Clustering off** (RB_nocl): +18.9 ps, −23 ps max latency | **+2.1 % clock power** (+0.09 mW) despite 21 fewer buffers, total +0.7 %. GRT usage +0.3 pp. A deeper tree (7 levels vs 4 + leaf) means more stages exposed to OCV in a real sign-off (not modelled here). |
| **Smaller clusters** (RB_s4): +14.6 ps | The most expensive: +274 buffers, **+26 % clock power, +8.5 % total power**, +0.9 % area, +14 % clock wire. The other +12.7 ps of its total gain is in the data part, inside the noise band. |
| **NDR full** (RC_full): +13.9 ps, −14 ps max latency | Practically free *in this design*. Only 9 nets carry the rule, GRT usage +0.1 pp, clock power −0.4 %. NDR costs routing tracks, and that stays small only because the NDR nets are few. The SI benefit that NDR exists for is not measured (no crosstalk analysis). Its other +16.7 ps is in the data part (noise band). |
| **Useful skew, emulated** (RD): +26.7 ps | Free in STA because nothing is built. RD_phys shows the real thing costs 15 buffers and about 1 % clock power, and that the realised shift is not the one asked for. |

General trade-off: **every lever that changes the tree's balance changes
clock power.** Measured as ps of critical-endpoint clock gain per % of
clock power, targeted physical useful skew is by far the most efficient:
+36 ps for +0.9 %. Next come clustering off (+19 ps for +2.1 %) and NDR full
(+14 ps for ≈ 0 %). Smaller clusters are the worst (+15 ps for +26 %).

## 3. Why are the differences small?

1. **The clock tree is shallow and short.** There are 1 938 sinks on a
   237 × 237 µm core. The default tree has 2–3 buffer stages from the root to a
   flop, and the insertion delay is about 0.29–0.31 ns, only **14 % of the
   period**. Design-wide skew (0.02–0.04 ns) is 1–2 % of the period. A
   balance-oriented strategy can only redistribute a few tens of ps.
2. **There is almost nothing to tune in the cell library.** Nangate45's
   strongest clock buffer is `CLKBUF_X3`, and TritonCTS uses it for all
   316 buffers. Cluster size is capped by that buffer's max capacitance:
   size 20 produced a byte-identical tree to size 9. The *smallest* delay
   step is also coarse: one `CLKBUF_X1` is about 36 ps, so useful skew
   cannot be applied in 5–10 ps increments.
3. **Most NDR settings change the same few nets.** With clustering, about 300 of 318 clock nets are
   leaf nets, and NDRs are never put on leaf nets. `half` = `root_only`
   (7 nets) and `full` adds 2.
4. **The critical path is dominated by the data path.** The
   instruction-register → decode → register-file write path is 2.16 ns of
   2.2 ns, and all 31 failing endpoints come from one startpoint. A
   balance-oriented CTS can only change the ±20 ps offset between that
   launch flop and the capture flops. Only targeted skew goes beyond that,
   and the cone shape (a few instruction-register bits fanning out to
   hundreds of register-file flops) makes the launch side the cheap place to
   apply it (RE_full).
5. **Hold is not a constraint.** Hold slack is about +85 ps everywhere
   (single typical corner, DFF clock-to-Q), so no strategy pays or saves
   hold fixing. In a real flow, fast-corner hold is where a skewed tree
   gets expensive.
6. **The analysis model ignores the effects CTS strategies usually target.**
   There is one corner, no OCV/AOCV derates (so no CRPR benefit), no SI and
   no jitter.
7. **The noise floor is comparable to the effects.** A routing-only
   perturbation moves WNS by up to 20.6 ps, and the data part of the
   critical-endpoint slack by up to 27.7 ps. The repeat noise is 0 because
   the flow is deterministic, but that hides the real sensitivity. The CTS
   effects are only identifiable because the slack was split into a clock
   part and a data part.

## 4. What would change if the design were 10× larger?

The following is a reasoned **expectation**, not a measurement.
Assumptions: about 20 000 sinks at the same utilization, so the core edge
grows by about √10 ≈ 3.2× (≈ 750 µm), possibly with SRAM macros.

* **Insertion delay and skew grow with wire length.** The tree needs about
  3–4 more levels, and latency would roughly double to ~0.5–0.7 ns. That is
  a much larger share of the period. Skew would be tens of ps even when
  "balanced", so the differences between strategies should grow from
  ~1 % to several % of the period.
* **Sink clustering becomes necessary.** An H-tree built directly to 20 k
  sinks (the RB_nocl approach) would need many more levels and buffers near
  the root. The cluster-offset effect seen in RB_nocl vs RA probably
  stays, but it is averaged over many more critical paths.
* **NDR matters more, and costs more.** Trunk wires would be hundreds of µm
  long and the upper-level net count grows, so `half` and `full` would
  cover a meaningful fraction of the tree. Their track cost would compete
  with signal routing in congested areas.
* **Clock power share stays high or rises**, so RB_s4-type choices
  (+26 % clock power) become very expensive in absolute terms.
* **Useful skew becomes more valuable and harder to do by hand.** There are
  more critical path families with different slack profiles, and so more
  room to borrow time. But the RD_phys recipe (one fixed buffer per leaf
  group) would conflict across path families: a flop that captures one
  critical path usually launches another. Hold at a fast corner becomes the
  limit. A real latency-scheduling engine would matter more than any
  TritonCTS option tested here.
  Whether the launch side stays the cheap lever (as in RE_full) depends on
  the cone shape. A few launch flops feeding many captures favours it, but
  in a bigger design more flops are both launch and capture of different
  critical paths, and moving them earlier costs setup on their own inputs.
* **Under OCV derates**, which a real 10× design would be signed off with,
  a shorter tree with more shared top-level paths (CRPR) would dominate. That
  favours lower latency (RB_nocl-like, NDR on the trunk). It penalises
  useful-skew buffers slightly, because each one adds an unshared stage.
* **Noise.** The ±20–28 ps routing noise would probably not scale with the
  design, while the clock effects should. The ranking would become clearer.

## Bottom line

At 2.2 ns, ranked by post-route WNS and by cost:

1. **Useful skew, launch + capture (RE_combo3): WNS +48.2 ps**. It uses
   RD_phys2's 36 capture buffers plus 10 launch-side pin moves, for +2.0 %
   clock power.
2. **Useful skew, launch side only (RE_full): WNS +31.6 ps with no new
   cell**. With `[20]` moved a second level and one `CLKBUF_X1` added back
   to balance it (RE_full2b, E10): **+36.2 ps** for one cell. Moving `[20]` a
   full second level without the buffer overshoots: the paths into `[20]`
   become critical and WNS falls to +24.6 ps. The same check on `[15]`
   (RE_full3b, E11) gives **+40.5 ps** with 2 added cells. The gain is
   smaller than predicted: each move onto the shared root trunk makes
   every other launch bit about 4 ps later, and the remaining bits are
   now within a few ps of each other. Nine instruction-register flops are moved one clock stage
   earlier, for +0.1 % clock power. This is the most cost-effective result
   of the study.
3. **Useful skew, capture side (RD_phys / RD_phys2): WNS +18.5 / +23.5 ps**.
   That takes 15 / 36 delay buffers and +0.9 / +2.0 % clock power, with
   sharply diminishing returns in the second round.

The TritonCTS settings, by clock-part gain on the 31 critical endpoints:

* Sink clustering **off: +19 ps** (+2.1 % clock power).
* Cluster size 4: +15 ps (+26 % clock power, not worth it).
* NDR **full: +14 ps** (≈ free here).
* NDR none: +5 ps.

Cluster size 20 and NDR root_only are no-ops. The useful-skew result is the
one that cannot be had from TritonCTS settings: OpenROAD has no useful-skew
engine. Here it was built with a script, using `insert_buffer` on the leaf
clock nets (capture side) and `connect_pin` one stage up (launch side). The
STA-only emulation (RD) *under*-estimated the real capture-side result,
because a single buffer stage overshoots the requested delay. The
launch-side result depended on selecting by each register's own launch
slack. Path enumeration per endpoint missed launch flops twice (E9). For this
small, shallow-tree design the clock tree is not the main bottleneck. The
data path and the GRT-vs-RCX correlation gap (E1) are.
