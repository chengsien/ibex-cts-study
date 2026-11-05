#!/usr/bin/env bash
# e18_run.sh — E18: the "10x larger design" study measured instead of
# inferred.  nangate45/ariane133 (160k cells, 20.8k flops, 132 SRAM macros;
# about 10.7x Ibex in standard-cell area and flop count) with its own ORFS
# SDC (3.0 ns), three CTS settings, the same as the Ibex study's RA/RB_nocl/RC_full:
#   A_default  ORFS default CTS (clustering on, NDR half)  - full flow
#   B_nocl     clustering off  (-repair_clock_nets)        - from A's placement
#   C_ndrfull  default + -apply_ndr full                   - from A's placement
# B and C run one after the other (detailed route of this design needs several
# GB of memory), with LEC_CHECK=0: the formal equivalence check (kepler-formal)
# only verifies the netlist, does not change timing, and takes long on this
# design (A_default ran it). Then the clock reports and per-endpoint dumps.
set -uo pipefail
cd "$(dirname "$0")/.."
D=nangate45/ariane133
DEF="-sink_clustering_enable -repair_clock_nets"
R=runs_big; SUB=nangate45/ariane133/base
# a run counts as finished only if ITS OWN run_config says so: a branch whose
# copy of the base run failed half-way (disk full) still contains the base
# run's 6_final.odb and run_config.txt
ok() { local c=$R/$1/run_config.txt; [[ -f $R/$1/results/$SUB/6_final.odb && -f $c ]] && \
       grep -qx "run_name=$1" $c && grep -qx "exit_code=0" $c; }
[[ -f $R/A_default/results/$SUB/6_final.odb ]] || { echo "A_default not finished"; exit 1; }
[[ -n ${E18_SKIP_FLOWS:-} ]] || ok B_nocl || scripts/run_big.sh -n B_nocl -D $D -b A_default -c "-repair_clock_nets" -e LEC_CHECK=0
[[ -n ${E18_SKIP_FLOWS:-} ]] || ok C_ndrfull || scripts/run_big.sh -n C_ndrfull -D $D -b A_default -c "$DEF -apply_ndr full" -e LEC_CHECK=0
for r in ${E18_ANALYSE:-A_default B_nocl C_ndrfull}; do
  ok $r || { echo "[$r] not a finished run of its own: skipped"; continue; }
  RUNS_DIR=$R scripts/post_reports.sh $r || echo "[$r] post_reports failed"
  for s in endpoint_slack dump_ck_arrivals; do
    RUNS_DIR=$R scripts/sta_run.sh $r scripts/$s.tcl $s >/dev/null 2>&1 || echo "[$r] $s failed"
  done
done
echo E18_DONE
