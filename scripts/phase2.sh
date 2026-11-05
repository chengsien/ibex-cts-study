#!/usr/bin/env bash
# Phase 2 CTS matrix at the stress period.  usage: scripts/phase2.sh <period_ns>
# (RC_root, the N_gr* routing-noise probes and RD_phys* were added after the
#  first pass; see docs/experiment-log.md E4/E5/E7/E8/E9/E10.)
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
RD_phys    -b R0a -t scripts/rd_phys_useful_skew.tcl
RD_phys_b1 -b R0a -t scripts/rd_phys_useful_skew_bufx1.tcl
JOBS
xargs -P 2 -L 1 bash -c 'one "$@"' _ < /tmp/phase2_jobs.txt

# stage 3: useful skew round 2, selected from RD_phys's POST-ROUTE timing
#   T30: every endpoint < 30 ps not yet treated, plus a second stage for
#        round-1 flops still < 30 ps (RD2_STACK=1)  -> RD_phys2
#   444: only rf_reg[444], the RD_phys worst endpoint  -> RD_phys2_444
IMG="${ORFS_IMAGE:-openroad/orfs:26Q4-260-gc9ac73efc}"
mapfile -t MV < <(grep '^makevar=' runs/RD_phys/run_config.txt | sed 's/^makevar=//')
docker run --rm -e RD2_T=0.030 -e RD2_STACK=1 -v "$PWD:/work" -w /OpenROAD-flow-scripts/flow "$IMG" \
  bash -c 'source ../env.sh >/dev/null 2>&1; make "$@"' _ "${MV[@]}" \
  run RUN_SCRIPT=/work/scripts/rd2_select.tcl RUN_LOG_NAME_STEM=rd2_select_T30 >/dev/null 2>&1
docker run --rm -e RD2_T=0.030 -e 'RD2_ONLY=gen_regfile_ff.register_file_i.rf_reg[444]$_DFFE_PN0P_' \
  -e RD2_TAG=444 -v "$PWD:/work" -w /OpenROAD-flow-scripts/flow "$IMG" \
  bash -c 'source ../env.sh >/dev/null 2>&1; make "$@"' _ "${MV[@]}" \
  run RUN_SCRIPT=/work/scripts/rd2_select.tcl RUN_LOG_NAME_STEM=rd2_select_444 >/dev/null 2>&1
( one RD_phys2 -b R0a -t scripts/rd_phys2_T30.tcl ) & ( one RD_phys2_444 -b R0a -t scripts/rd_phys2_444.tcl ) & wait

# stage 4: launch-side useful skew (RE): targets from RA / RD_phys2 post-route
#   RA_T30 (worst path per endpoint), RA_T50_multi (50 paths/endpoint),
#   RA_L50 (own launch slack, the robust rule); same three for RD_phys2.
sel() {  # sel <base_run> <RE_T> <tag> [extra -e args...]
  local b=$1 t=$2 tag=$3; shift 3
  mapfile -t MVB < <(grep '^makevar=' "runs/$b/run_config.txt" | sed 's/^makevar=//')
  docker run --rm -e RE_T="$t" -e RE_TAG="$tag" "$@" -v "$PWD:/work" -w /OpenROAD-flow-scripts/flow "$IMG" \
    bash -c 'source ../env.sh >/dev/null 2>&1; make "$@"' _ "${MVB[@]}" \
    run RUN_SCRIPT=/work/scripts/re_select.tcl RUN_LOG_NAME_STEM=re_select_$tag >/dev/null 2>&1
}
sel RA 0.030 RA_T30
sel RA 0.050 RA_T50_multi -e RE_EPC=50
sel RA 0.050 RA_L50 -e RE_MODE=launch
sel RD_phys2 0.040 RDP2_T40
sel RD_phys2 0.060 RDP2_T60_multi -e RE_EPC=50
sel RD_phys2 0.060 RDP2_L60 -e RE_MODE=launch
# E10: second level for [20] (target file written by hand: allowed relaxed to 95 ps on request)
mkdir -p runs/RE_full/reports/nangate45/ibex/base
printf 'if_stage_i.instr_rdata_id_o[20]$_DFFE_PP_ 0.095 0.0793\n' > runs/RE_full/reports/nangate45/ibex/base/re_targets_RF_20_lvl2.txt
cat > /tmp/phase2_re_jobs.txt <<JOBS
RE        -b R0a -t scripts/re_RA.tcl
RE_multi  -b R0a -t scripts/re_multi.tcl
RE_full   -b R0a -t scripts/re_full.tcl
RE_combo  -b R0a -t scripts/re_combo.tcl
RE_combo2 -b R0a -t scripts/re_combo2.tcl
RE_combo3 -b R0a -t scripts/re_combo3.tcl
RE_full2  -b R0a -t scripts/re_full2.tcl
RE_full2b -b R0a -t scripts/re_full2b.tcl
JOBS
xargs -P 2 -L 1 bash -c 'one "$@"' _ < /tmp/phase2_re_jobs.txt

# stage 5: post-route analyses for every run (worst paths, per-endpoint
# slack, CK arrivals) -> used by summarize.py for the clock/data split
for n in R0a R0b RA RB_nocl RB_s4 RB_s20 RC_none RC_root RC_full RD RD_phys RD_phys_b1 RD_phys2_444 RD_phys2 RE RE_multi RE_full RE_full2 RE_full2b RE_combo RE_combo2 RE_combo3 N_gr48 N_gr52; do
  mapfile -t MV < <(grep '^makevar=' "runs/$n/run_config.txt" | sed 's/^makevar=//')
  for s in worst_paths endpoint_slack dump_ck_arrivals; do
    docker run --rm -v "$PWD:/work" -w /OpenROAD-flow-scripts/flow \
      "${ORFS_IMAGE:-openroad/orfs:26Q4-260-gc9ac73efc}" bash -c \
      'source ../env.sh >/dev/null 2>&1; make "$@"' _ "${MV[@]}" \
      run RUN_SCRIPT=/work/scripts/$s.tcl RUN_LOG_NAME_STEM=$s >/dev/null 2>&1
  done
  docker run --rm -v "$PWD:/work" -w /OpenROAD-flow-scripts/flow \
    "${ORFS_IMAGE:-openroad/orfs:26Q4-260-gc9ac73efc}" bash -c \
    'source ../env.sh >/dev/null 2>&1; make "$@"' _ "${MV[@]}" \
    run RUN_SCRIPT=/work/scripts/ir_launch_scan.tcl RUN_LOG_NAME_STEM=ir_launch_scan 2>/dev/null \
    | grep '^IR' > "runs/$n/reports/nangate45/ibex/base/ir_launch_scan.txt"
done
echo PHASE2_DONE
