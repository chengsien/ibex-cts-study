# Findings: CTS strategies for Ibex on Nangate45 (stress period 2.2 ns)

All numbers come from `results/cts_comparison_full.csv`, which
`scripts/summarize.py` builds from the run reports. The details and
per-experiment tables are in [`experiment-log.md`](experiment-log.md) (E2–E6).
Every run uses R0a's byte-identical placement and goes through detailed
route + OpenRCX + OpenSTA. The design and PDK are open source (Ibex,
FreePDK45/Nangate45), with a single typical corner and no OCV/derates and
no SI analysis.

## Summary table (post-route, 2.2 ns)

| run | what changed | max insertion delay (ns) | setup skew (ns) | clock buffers | setup WNS (ns) | setup TNS (ns) | worst-path Δskew vs RA (ps) | worst-path Δdata vs RA (ps) | hold WNS (ns) | hold-fix cells | clock / total power (mW) | GRT usage |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| RA (=R0a=R0b) | ORFS default: clustering auto (size 9), NDR half | 0.3122 | 0.0397 | 316 | −0.0143 | −0.360 | 0 | 0 | +0.0855 | 0 | 4.158 / 12.71 | 28.60 % |
| RB_nocl | clustering **off** | **0.2886** | **0.0217** | 295 | +0.0043 | 0 | **+17.5** | −0.7 | +0.0853 | 0 | 4.245 / 12.80 | 28.91 % |
| RB_s4 | cluster size 4 | 0.3124 | −0.0298 | **590** | +0.0102 | 0 | 0.0 | +25.7 | +0.0848 | 0 | **5.239 / 13.78** | 29.06 % |
| RB_s20 | cluster size 20 | = RA (byte-identical CTS DB) | | | | | | | | | | |
| RC_none | NDR none (0 nets) | 0.3107 | 0.0316 | 316 | −0.0090 | −0.213 | +5.0 | +0.3 | +0.0855 | 0 | 4.162 / 12.71 | 28.41 % |
| RC_root | NDR root_only (7 nets) | = RA (byte-identical CTS DB, same 7 nets as half) | | | | | | | | | | |
| RC_full | NDR full (9 nets) | 0.2979 | 0.0267 | 316 | **+0.0164** | 0 | +14.1 | +16.7 | +0.0855 | 0 | 4.140 / 12.69 | 28.72 % |
| RD | `set_clock_latency` on 62 regfile CK pins (STA what-if) | 0.3122 | 0.0397* | 316 | +0.0139 | 0 | **+27.8** | +0.2 | +0.0855 | 0 | 4.158 / 12.71 | 28.60 % |
| N_gr48 | **noise probe**: GRT M2–M3 capacity 0.48, CTS = RA | 0.3114 | 0.0390 | 316 | −0.0139 | −0.347 | +0.6 | −0.1 | +0.0855 | 0 | 4.158 / 12.71 | 28.60 % |
| N_gr52 | **noise probe**: GRT M2–M3 capacity 0.52, CTS = RA | 0.3146 | 0.0423 | 316 | +0.0063 | 0 | 0.0 | **+20.6** | +0.0855 | 0 | 4.158 / 12.70 | 29.10 % |

\*`report_clock_skew` does not reflect RD's pin-latency overrides. The
worst-path decomposition does.

Plots: `results/cts_comparison.png` (six metrics per run) and
`results/cts_slack_decomposition.png` (Δslack split into clock part and
data part, with the routing-noise band shaded).

---

## 1. Which metric differs the most, and why?

**In relative terms: clock-tree size and clock power. In timing terms:
setup skew. Setup WNS changes are small and half of them are noise.**

* **Clock buffers and clock power** have the largest spread. RB_s4 (cluster
  size 4) doubles the clock buffers (316 → 590, +87 %), adds 14 % clock
  wire, and raises clock power by **+26 %** (4.16 → 5.24 mW), which is
  **+8.5 % of total power**. The cause is direct: each cluster gets its own
  leaf `CLKBUF_X3`, so capping clusters at 4 sinks instead of about 9
  nearly doubles the number of leaf drivers. Clock power is already 33 % of
  total power in the default run, so any change to the tree shows up in
  total power.
* **Setup skew** is the timing metric that changes the most, and it is a
  *real* clock-tree effect. It goes from 0.040 ns (RA) to 0.022 ns with
  clustering off (−45 %) and to 0.027 ns with NDR full. The routing-only
  noise probes move the critical-path skew term by 0.6 ps at most. On the
  critical path (IF-stage instruction register → register-file write),
  turning clustering off removes 17.5 ps of harmful skew. With clustering,
  the launch flop sits in a cluster whose leaf buffer arrives 21 ps after
  the capture flops' clusters. The 7-level H-tree built straight to the
  sinks has uniform depth and is better balanced.
* **Setup WNS** spans 30.7 ps (−0.0143 … +0.0164 ns), about 1.4 % of the
  period. **TNS and pass/fail** look like the biggest change (−0.36 ns → 0,
  fail → pass). But the stress period misses by only 14 ps, and a
  routing-only perturbation (N_gr52) already makes it pass. So the
  pass/fail column cannot rank strategies.
* **Hold** does not differ at all: hold WNS is +0.0848 to +0.0855 ns in every
  run and **0 hold-fix cells** are inserted anywhere. Routing resources
  barely move: GRT usage 28.4–29.1 %, overflow 0 and 0 DRC in every run.

## 2. What do the improvements cost?

| improvement (credited part only) | cost |
|---|---|
| **Clustering off** (RB_nocl): +17.5 ps skew on the critical path, −23 ps max latency | **+2.1 % clock power** (+0.09 mW) despite 21 fewer buffers. Total power +0.7 %. GRT usage +0.3 pp, metal4 +0.4 pp. The tree is deeper (7 levels vs 4 + leaf), so it has more stages exposed to OCV in a real sign-off (not modelled here). CTS runtime is unchanged (seconds). |
| **NDR full** (RC_full): +14 ps skew, −14 ps max latency | Practically free *in this design*. Only 9 nets carry the rule, the clock wire is 4.9 % of all wire, GRT usage changes by +0.1 pp, clock power −0.4 %. The cost of NDR is routing tracks. It stays small only because the NDR nets are few and short. The SI benefit that NDR exists for is not measured (OpenSTA has no crosstalk analysis). |
| **Smaller clusters** (RB_s4) | **Not an improvement.** The skew term is unchanged. The +25.7 ps comes from the data path, which is the same size as the routing noise. Paid for with +26 % clock power, +8.5 % total power, +0.9 % area. |
| **Useful skew, emulated** (RD): +27.8 ps | Free in STA because nothing is built. A real version would need roughly 13–20 ps of extra latency on 62 register-file flops (≈ one extra `CLKBUF_X1` stage per group): some clock power and area, plus hold risk on regfile → regfile paths. Hold slack is +85 ps at the only (typical) corner, so there is room, but a fast corner would have to confirm it. The emulation also freezes CTS-stage latencies (≈ 8 ps off post-route), so the +27.8 ps is optimistic. |

General trade-off: **every lever that changes the tree's balance also
changes clock power**, and none of them came for free except NDR at this
scale. The only lever that gave more than 20 ps was useful skew, which
TritonCTS does not provide.

## 3. Why are the differences small?

1. **The clock tree is shallow and short.** There are 1 938 sinks on a
   237 × 237 µm core. The default tree has 2–3 buffer stages from the root to a
   flop, and the insertion delay is about 0.29–0.31 ns, only **14 % of the
   period**. The whole design-wide skew (0.02–0.04 ns) is 1–2 % of the
   period. A strategy can only redistribute a few tens of ps.
2. **There is almost nothing to tune in the cell library.** Nangate45's
   strongest clock buffer is `CLKBUF_X3`, and TritonCTS uses it for all
   316 buffers. There is no buffer sizing, no clock inverters and no
   multi-bit flops. Cluster size is capped by the buffer's max capacitance:
   size 20 produced a byte-identical tree to size 9.
3. **Most NDR settings change the same few nets.** With clustering, about 300 of 318 clock nets are
   leaf nets, and NDRs are never put on leaf nets. `half` = `root_only`
   (7 nets) and `full` adds 2.
4. **The critical path is dominated by the data path.** The
   instruction-register → decode → register-file write path is 2.16 ns of
   2.2 ns. The clock contributes only the ±20 ps launch/capture offset.
   The 10 worst setup paths all start at the same instruction-register
   bit (`if_stage_i.instr_rdata_id_o[20]`), so one cluster's offset decides
   the result.
5. **Hold is not a constraint.** Hold slack is about +85 ps everywhere
   (single typical corner, DFF clock-to-Q), so no strategy pays or saves
   hold fixing. In a real flow, fast-corner hold is where a skewed tree
   gets expensive.
6. **The analysis model ignores the effects CTS strategies usually target.**
   There is one corner, no OCV/AOCV derates (so no CRPR benefit from shared
   tree paths), no SI and no jitter. A shorter or better-shared tree, or NDR,
   would count more under derates and crosstalk.
7. **The noise floor is comparable to the effects.** A routing-only
   perturbation moves WNS by up to 20.6 ps. The repeat noise is 0 because the
   flow is deterministic, but that hides the real sensitivity. The clock
   effects (5–17.5 ps) are only identifiable because the slack was split
   into a clock term and a data term.

## 4. What would change if the design were 10× larger?

The following is a reasoned **expectation**, not a measurement.
Assumptions: about 20 000 sinks at the same utilization, so the core edge
grows by about √10 ≈ 3.2× (≈ 750 µm), possibly with SRAM macros.

* **Insertion delay and skew grow with wire length.** The tree needs about
  3–4 more levels, and latency would roughly double to ~0.5–0.7 ns. That is
  a much larger share of a 2–3 ns period. Skew would be several tens of ps
  even when "balanced". The options affect a bigger number, so the
  differences between strategies should grow from ~1 % to several % of the
  period.
* **Sink clustering becomes necessary.** Building the H-tree directly to
  20 k sinks (the RB_nocl approach) would need many more levels and buffers
  near the root. The cluster-offset problem seen in RB_nocl vs RA probably
  stays, but it is averaged over many more critical paths. Cluster size
  would matter more if the library offered stronger leaf buffers. With
  Nangate45's `CLKBUF_X3` the size cap of about 9 stays the same.
* **NDR matters more, and costs more.** Trunk wires would be hundreds of µm
  long and the upper-level net count grows, so `half` and `full` would
  cover a meaningful fraction of the tree. The latency and skew reduction
  should scale with trunk length. The track cost would then compete with
  signal routing in congested areas, which it did not do here (GRT usage
  ≈ 29 %).
* **Clock power share stays high or rises.** More buffers and longer trunk
  wires mean RB_s4-type choices (+26 % clock power) become very expensive
  in absolute terms.
* **Useful skew becomes more valuable and riskier.** There are more
  critical path families with different slack profiles, and so more room to
  borrow time. Hold impact and fast-corner checks become the limit. A
  built-in useful-skew or latency-adjust engine would matter more than any
  TritonCTS option tested here.
* **Under OCV derates**, which a real 10× design would be signed off with,
  a shorter tree with more shared top-level paths (CRPR) would dominate. That
  favours lower latency (RB_nocl-like, NDR on the trunk) more than this
  single-corner study shows.
* **Noise.** The ±20 ps routing noise would probably not scale with the
  design, while the clock effects should. The ranking would become clearer,
  and the WNS pass/fail would be less dominated by the GRT-vs-RCX gap seen
  in E1.

## Bottom line

At 2.2 ns the three ORFS/TritonCTS knobs tested (clustering, cluster size,
NDR) move post-route WNS by at most about 30 ps, and part of that is
routing noise. The **robust** effects are:

* Turning sink clustering **off** cuts critical-path skew by 17.5 ps, for
  +2 % clock power.
* NDR **full** cuts it by 14 ps at negligible cost.
* Smaller clusters cost 26 % more clock power and give **no** clock benefit.

The largest gain (+28 ps) came from **useful skew**, which this OpenROAD
version does not have and which was only emulated in STA. For this small,
shallow-tree design the clock tree is not the bottleneck. The data path and
the GRT-vs-RCX correlation gap (E1) are.
