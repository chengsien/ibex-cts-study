#!/usr/bin/env bash
# run.sh — one ORFS run of Ibex on Nangate45 into runs/<run_name>/
#
# Every run gets its own WORK_HOME (runs/<run_name>/) so logs/, reports/,
# results/ and objects/ never collide. Only the knobs below are changed;
# everything else is the ORFS default for designs/nangate45/ibex.
#
# Usage:
#   scripts/run.sh -n <run_name> [options]
#
# Options:
#   -n NAME        run name (required) -> runs/NAME/
#   -p PERIOD      clock period in ns (default: 2.2, the ORFS ibex default)
#   -u UTIL        CORE_UTILIZATION in % (default: 50, the ORFS ibex default)
#   -c "ARGS"      full override of clock_tree_synthesis args (ORFS CTS_ARGS)
#                  ORFS default when unset: "-sink_clustering_enable -repair_clock_nets"
#   -s SIZE        CTS_CLUSTER_SIZE      (-sink_clustering_size)
#   -d DIAM        CTS_CLUSTER_DIAMETER  (-sink_clustering_max_diameter, um)
#   -t TCL         POST_CTS_TCL hook (path inside repo), e.g. for manual skew
#   -b BASE_RUN    reuse synth/floorplan/place results of runs/BASE_RUN and
#                  start the flow at CTS (keeps placement bit-identical)
#   -e VAR=VAL     extra ORFS make variable (repeatable)
#   -T TARGET      make target (default: "finish"; e.g. "route" to stop early)
#
# Environment:
#   ORFS_IMAGE     docker image (default openroad/orfs:26Q4-260-gc9ac73efc)
#   ORFS_NATIVE=1  use a local ORFS checkout ($ORFS_HOME) instead of docker
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORFS_IMAGE="${ORFS_IMAGE:-openroad/orfs:26Q4-260-gc9ac73efc}"

NAME="" PERIOD="2.2" UTIL="50" CTS_ARGS_OVR="" CL_SIZE="" CL_DIAM=""
POST_CTS="" BASE="" TARGET="finish"; EXTRA=()
while getopts "n:p:u:c:s:d:t:b:e:T:h" o; do
  case "$o" in
    n) NAME="$OPTARG" ;; p) PERIOD="$OPTARG" ;; u) UTIL="$OPTARG" ;;
    c) CTS_ARGS_OVR="$OPTARG" ;; s) CL_SIZE="$OPTARG" ;; d) CL_DIAM="$OPTARG" ;;
    t) POST_CTS="$OPTARG" ;; b) BASE="$OPTARG" ;; e) EXTRA+=("$OPTARG") ;;
    T) TARGET="$OPTARG" ;;
    h|*) sed -n '2,30p' "$0"; exit 1 ;;
  esac
done
[[ -n "$NAME" ]] || { echo "need -n run_name" >&2; exit 1; }

RUN="$REPO/runs/$NAME"
if [[ -e "$RUN/logs" ]]; then echo "runs/$NAME already exists" >&2; exit 1; fi
mkdir -p "$RUN"

# ---- per-run SDC: the ORFS ibex SDC with only clk_period substituted -------
sed -E "s/^set clk_period .*/set clk_period ${PERIOD}/" \
  "$REPO/constraints/ibex_constraint.sdc" > "$RUN/constraint.sdc"

# ---- branch from an existing placement ------------------------------------
if [[ -n "$BASE" ]]; then
  B="$REPO/runs/$BASE"
  [[ -f "$B/results/nangate45/ibex/base/3_place.odb" ]] || {
    echo "base run $BASE has no 3_place.odb" >&2; exit 1; }
  # copy the whole base run (timestamps preserved) and delete every
  # artifact of stage 4 (CTS) onward, so make resumes exactly at CTS
  rm -rf "$RUN" && cp -a "$B" "$RUN"
  rm -f "$RUN"/flow.log "$RUN"/run_config.txt "$RUN"/clock_report_*.log "$RUN"/BASE_RUN
  for d in results logs reports objects; do
    find "$RUN/$d" -path '*/base/*' \( -name '4_*' -o -name '5_*' -o -name '6_*' \
      -o -name 'clock_*' -o -name 'route.guide' -o -name 'final_*' -o -name 'drt*' \
      -o -name '*.png' -o -name '*.webp' -o -name 'metadata*' -o -name 'VDD.rpt' -o -name 'VSS.rpt' \
      -o -name 'congestion*' -o -name 'antenna*' -o -name 'synth_check*' \
      -o -name 'ck_arrivals_*' -o -name 'endpoint_slack_*' -o -name 'worst_paths*' \
      -o -name 'ir_launch_scan*' -o -name 'e1[2-9]_*' -o -name 'grt_antennas*' \) -prune -exec rm -rf {} +
  done
  # the SDC used by CTS onward is 3_place.sdc copied from base; refuse if the
  # requested period differs from the base period (would silently mismatch)
  bp=$(grep -E '^set clk_period' "$B/constraint.sdc" | awk '{print $3}')
  [[ "$bp" == "$PERIOD" ]] || { echo "period $PERIOD != base period $bp" >&2; exit 1; }
  cp -p "$B/constraint.sdc" "$RUN/constraint.sdc"
  echo "$BASE" > "$RUN/BASE_RUN"
fi

MAKEVARS=(
  "DESIGN_CONFIG=./designs/nangate45/ibex/config.mk"
  "WORK_HOME=/work/runs/$NAME"
  "SDC_FILE=/work/runs/$NAME/constraint.sdc"
  "CORE_UTILIZATION=$UTIL"
)
[[ -n "$CTS_ARGS_OVR" ]] && MAKEVARS+=("CTS_ARGS=$CTS_ARGS_OVR")
[[ -n "$CL_SIZE" ]] && MAKEVARS+=("CTS_CLUSTER_SIZE=$CL_SIZE")
[[ -n "$CL_DIAM" ]] && MAKEVARS+=("CTS_CLUSTER_DIAMETER=$CL_DIAM")
[[ -n "$POST_CTS" ]] && MAKEVARS+=("POST_CTS_TCL=/work/$POST_CTS")
MAKEVARS+=("${EXTRA[@]}")

# ---- record exactly what was run ------------------------------------------
{
  echo "run_name=$NAME"; echo "date_utc=$(date -u +%FT%TZ)"
  echo "period_ns=$PERIOD"; echo "core_utilization=$UTIL"
  echo "cts_args_override=$CTS_ARGS_OVR"; echo "cluster_size=$CL_SIZE"
  echo "cluster_diameter=$CL_DIAM"; echo "post_cts_tcl=$POST_CTS"
  echo "base_run=$BASE"; echo "target=$TARGET"; echo "image=$ORFS_IMAGE"
  printf 'makevar=%s\n' "${MAKEVARS[@]}"
} > "$RUN/run_config.txt"

start=$(date +%s)
set +e
if [[ "${ORFS_NATIVE:-0}" == "1" ]]; then
  # native: map /work to the repo through a symlink-free WORK_HOME
  NV=("${MAKEVARS[@]//\/work/$REPO}")
  (cd "$ORFS_HOME/flow" && make "${NV[@]}" "$TARGET") > "$RUN/flow.log" 2>&1
else
  docker run --rm -u "$(id -u):$(id -g)" \
    -v "$REPO:/work" -w /OpenROAD-flow-scripts/flow \
    "$ORFS_IMAGE" bash -c \
    'source ../env.sh >/dev/null 2>&1 || true; make "$@"' _ \
    "${MAKEVARS[@]}" "$TARGET" > "$RUN/flow.log" 2>&1
fi
rc=$?
set -e
end=$(date +%s)
echo "exit_code=$rc" >> "$RUN/run_config.txt"
echo "wall_seconds=$((end-start))" >> "$RUN/run_config.txt"
echo "[$NAME] rc=$rc wall=$((end-start))s"
exit $rc
