#!/usr/bin/env bash
# e13_run.sh — crosstalk-proxy STA (E13) on existing post-route runs.
#   usage: scripts/e13_run.sh RUN [RUN ...]
# Per run: dump the clock nets, write three coupling-scaled SPEF copies
# (all nets x2, clock nets x2, clock nets x0; see e13_spef_coupling.py for why
# read_spef -coupling_reduction_factor cannot be used for x2), run four STA
# scenarios, delete the copies.  Result lines -> reports/.../e13_xtalk.txt.
#   nom        original SPEF (must equal the normal post-route numbers)
#   clk_x2     clock-net coupling x2 for both early and late (uniform)
#   clk_bound  late = clock coupling x2, early = clock coupling x0
#   all_bound  late = all coupling x2,  early = all coupling x0
set -uo pipefail
cd "$(dirname "$0")/.."
SUB=nangate45/ibex/base
for r in "$@"; do
  R=runs/$r/results/$SUB; W=/work/runs/$r/results/$SUB
  out=runs/$r/reports/$SUB/e13_xtalk.txt
  scripts/sta_run.sh "$r" scripts/e13_xtalk.tcl e13_dump -e E13_MODE=dump 2>&1 | grep '^E13 ' > "$out"
  python3 scripts/e13_spef_coupling.py --scale "$r" 2 "$R/e13_all_x2.spef" all   >> "$out"
  python3 scripts/e13_spef_coupling.py --scale "$r" 2 "$R/e13_clk_x2.spef" clock >> "$out"
  python3 scripts/e13_spef_coupling.py --scale "$r" 0 "$R/e13_clk_x0.spef" clock >> "$out"
  sc() { scripts/sta_run.sh "$r" scripts/e13_xtalk.tcl "e13_$1" -e E13_TAG="$1" "${@:2}" 2>&1 | grep -E '^E13 |ERROR'; }
  sc nom       -e E13_SINGLE=1 >> "$out"
  sc clk_x2    -e E13_SINGLE=1 -e E13_MAX_SPEF="$W/e13_clk_x2.spef" >> "$out"
  sc clk_bound -e E13_MAX_SPEF="$W/e13_clk_x2.spef" -e E13_MIN_SPEF="$W/e13_clk_x0.spef" >> "$out"
  sc all_bound -e E13_MAX_SPEF="$W/e13_all_x2.spef" -e E13_MIN_SPEF="$W/6_final.spef" -e E13_MIN_K=0 >> "$out"
  rm -f "$R/e13_all_x2.spef" "$R/e13_clk_x2.spef" "$R/e13_clk_x0.spef"
  echo "[$r] done"; grep -E 'setup_wns' "$out" | cut -c1-120
done
