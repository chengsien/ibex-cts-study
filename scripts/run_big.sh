#!/usr/bin/env bash
# run_big.sh — one ORFS run of any ORFS design (used for the "10x larger
# design" study, E18) into runs_big/<run_name>/. Same idea as run.sh, but the
# design and its own SDC are used unchanged (no period substitution).
#
# Usage:
#   scripts/run_big.sh -n <run_name> -D <platform/design> [options]
#
# Options:
#   -n NAME     run name (required) -> runs_big/NAME/
#   -D DESIGN   ORFS design, e.g. nangate45/ariane133 (required)
#   -c "ARGS"   full override of clock_tree_synthesis args (ORFS CTS_ARGS)
#   -b BASE     reuse synth/floorplan/place of runs_big/BASE, restart at CTS
#   -e VAR=VAL  extra ORFS make variable (repeatable)
#   -T TARGET   make target (default: finish; e.g. synth to stop after synthesis)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORFS_IMAGE="${ORFS_IMAGE:-openroad/orfs:26Q4-260-gc9ac73efc}"

NAME="" DESIGN="" CTS_ARGS_OVR="" BASE="" TARGET="finish"; EXTRA=()
while getopts "n:D:c:b:e:T:h" o; do
  case "$o" in
    n) NAME="$OPTARG" ;; D) DESIGN="$OPTARG" ;; c) CTS_ARGS_OVR="$OPTARG" ;;
    b) BASE="$OPTARG" ;; e) EXTRA+=("$OPTARG") ;; T) TARGET="$OPTARG" ;;
    h|*) sed -n '2,18p' "$0"; exit 1 ;;
  esac
done
[[ -n "$NAME" && -n "$DESIGN" ]] || { echo "need -n run_name and -D platform/design" >&2; exit 1; }

RUN="$REPO/runs_big/$NAME"
if [[ -e "$RUN/logs" ]]; then echo "runs_big/$NAME already exists" >&2; exit 1; fi

if [[ -n "$BASE" ]]; then
  B="$REPO/runs_big/$BASE"
  bdir=$(dirname "$(find "$B/results" -name 3_place.odb | head -1)")
  [[ -f "$bdir/3_place.odb" ]] || { echo "base run $BASE has no 3_place.odb" >&2; exit 1; }
  # copy the whole base run (timestamps preserved), drop stage 4 onward
  mkdir -p "$REPO/runs_big"
  cp -a "$B" "$RUN"
  rm -f "$RUN/flow.log" "$RUN/run_config.txt" "$RUN"/clock_report_*.log
  for d in results logs reports objects; do
    find "$RUN/$d" -path '*/base/*' \( -name '4_*' -o -name '5_*' -o -name '6_*' \
      -o -name 'clock_*' -o -name 'route.guide' -o -name 'final_*' -o -name 'drt*' \
      -o -name '*.png' -o -name '*.webp' -o -name 'metadata*' -o -name 'VDD.rpt' -o -name 'VSS.rpt' \
      -o -name 'congestion*' -o -name 'antenna*' -o -name 'synth_check*' \) -prune -exec rm -rf {} +
  done
  echo "$BASE" > "$RUN/BASE_RUN"
else
  mkdir -p "$RUN"
fi

MAKEVARS=(
  "DESIGN_CONFIG=./designs/$DESIGN/config.mk"
  "WORK_HOME=/work/runs_big/$NAME"
)
[[ -n "$CTS_ARGS_OVR" ]] && MAKEVARS+=("CTS_ARGS=$CTS_ARGS_OVR")
MAKEVARS+=("${EXTRA[@]}")

{
  echo "run_name=$NAME"; echo "date_utc=$(date -u +%FT%TZ)"
  echo "design=$DESIGN"; echo "cts_args_override=$CTS_ARGS_OVR"
  echo "base_run=$BASE"; echo "target=$TARGET"; echo "image=$ORFS_IMAGE"
  printf 'makevar=%s\n' "${MAKEVARS[@]}"
} > "$RUN/run_config.txt"

start=$(date +%s)
set +e
docker run --rm -u "$(id -u):$(id -g)" \
  -v "$REPO:/work" -w /OpenROAD-flow-scripts/flow \
  "$ORFS_IMAGE" bash -c \
  'source ../env.sh >/dev/null 2>&1 || true; make "$@"' _ \
  "${MAKEVARS[@]}" "$TARGET" > "$RUN/flow.log" 2>&1
rc=$?
set -e
end=$(date +%s)
echo "exit_code=$rc" >> "$RUN/run_config.txt"
echo "wall_seconds=$((end-start))" >> "$RUN/run_config.txt"
echo "[$NAME] rc=$rc wall=$((end-start))s"
exit $rc
