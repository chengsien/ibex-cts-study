#!/usr/bin/env bash
# e17_run.sh — E17: Ibex on ASAP7, implemented at the TYPICAL corner (as the
# Nangate45 study, which has only a typical library), then signed off at all
# three corners: hold at the fast corner (BC/FF) is the check the Nangate45
# study could not do; setup at the slow corner (WC/SS).
#   asap7_A    ORFS default CTS
#   asap7_B    clustering off   (CTS_ARGS=-repair_clock_nets)
#   asap7_C    NDR full         (default + -apply_ndr full)
# Period: ORFS's own "pos_slack" SDC for asap7/ibex (1468 ps), because the
# default 900 ps SDC is tuned for implementation at the fast corner.
set -uo pipefail
cd "$(dirname "$0")/.."
D=asap7/ibex
SDC=SDC_FILE=./designs/asap7/ibex/constraint_pos_slack.sdc
DEF="-sink_clustering_enable -repair_clock_nets"
[[ -f runs_big/asap7_A/results/asap7/ibex/base/6_final.odb ]] || \
  scripts/run_big.sh -n asap7_A -D $D -e CORNER=TC -e "$SDC"
[[ -f runs_big/asap7_B/results/asap7/ibex/base/6_final.odb ]] || \
  scripts/run_big.sh -n asap7_B -D $D -e CORNER=TC -e "$SDC" -b asap7_A -c "-repair_clock_nets"
[[ -f runs_big/asap7_C/results/asap7/ibex/base/6_final.odb ]] || \
  scripts/run_big.sh -n asap7_C -D $D -e CORNER=TC -e "$SDC" -b asap7_A -c "$DEF -apply_ndr full"
for r in asap7_A asap7_B asap7_C; do
  out=runs_big/$r/reports/asap7/ibex/base/e17_corners.txt; : > "$out"
  for c in BC TC WC; do
    RUNS_DIR=runs_big STA_MAKEVARS="CORNER=$c" scripts/sta_run.sh $r scripts/e17_corners.tcl e17_$c 2>&1 | grep '^E17 ' >> "$out"
  done
  RUNS_DIR=runs_big scripts/post_reports.sh $r final >/dev/null 2>&1 || true
  echo "[$r]"; cat "$out"
done
echo E17_DONE
