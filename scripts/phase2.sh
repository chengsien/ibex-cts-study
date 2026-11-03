#!/usr/bin/env bash
# Phase 2 CTS matrix at the stress period.  usage: scripts/phase2.sh <period_ns>
# (RC_root and the N_gr* routing-noise probes were added after the first pass;
#  see docs/experiment-log.md E4/E5.)
# R0a/R0b: two independent full flows (reproducibility of the whole flow).
# All other runs branch from R0a's 3_place.odb (identical RTL/SDC/floorplan/
# placement/tools) and differ only in CTS settings; every run goes through
# detailed route + OpenRCX STA (ORFS 'finish') and then clock_report.tcl.
set -uo pipefail
cd "$(dirname "$0")/.."
P="$1"
D="-sink_clustering_enable -repair_clock_nets"          # ORFS default CTS_ARGS
one() { local n=$1; shift; scripts/run.sh -n "$n" -p "$P" "$@" && scripts/post_reports.sh "$n"; }
export -f one; export P D

# stage 1: the two from-scratch baselines
( one R0a ) & ( one R0b ) & wait

# stage 2: CTS variants on R0a's placement, 2 at a time
cat > /tmp/phase2_jobs.txt <<JOBS
RA      -b R0a
RB_nocl -b R0a -c "-repair_clock_nets"
RB_s4   -b R0a -s 4
RB_s20  -b R0a -s 20
RC_none -b R0a -c "$D -apply_ndr none"
RC_full -b R0a -c "$D -apply_ndr full"
RD      -b R0a -t scripts/rd_useful_skew.tcl
RC_root -b R0a -c "$D -apply_ndr root_only"
N_gr48  -b R0a -e PRE_GLOBAL_ROUTE_TCL=/work/scripts/noise_grt_adj_48.tcl
N_gr52  -b R0a -e PRE_GLOBAL_ROUTE_TCL=/work/scripts/noise_grt_adj_52.tcl
JOBS
xargs -P 2 -L 1 bash -c 'one "$@"' _ < /tmp/phase2_jobs.txt

# stage 3: worst-path slack decomposition for every run
for n in R0a R0b RA RB_nocl RB_s4 RB_s20 RC_none RC_root RC_full RD N_gr48 N_gr52; do
  mapfile -t MV < <(grep '^makevar=' "runs/$n/run_config.txt" | sed 's/^makevar=//')
  docker run --rm -v "$PWD:/work" -w /OpenROAD-flow-scripts/flow \
    "${ORFS_IMAGE:-openroad/orfs:26Q4-260-gc9ac73efc}" bash -c \
    'source ../env.sh >/dev/null 2>&1; make "$@"' _ "${MV[@]}" \
    run RUN_SCRIPT=/work/scripts/worst_paths.tcl RUN_LOG_NAME_STEM=worst_paths >/dev/null 2>&1
done
echo PHASE2_DONE
