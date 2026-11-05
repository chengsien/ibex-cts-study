#!/usr/bin/env bash
# post_reports.sh <run_name> [stage...]   (stages: cts final; default both)
# Runs scripts/clock_report.tcl on a finished run inside the ORFS image,
# writing runs/<run>/reports/nangate45/ibex/base/clock_<stage>.{rpt,kv}
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORFS_IMAGE="${ORFS_IMAGE:-openroad/orfs:26Q4-260-gc9ac73efc}"
NAME="$1"; shift
STAGES=("${@:-cts final}"); STAGES=(${STAGES[@]})
RUN="$REPO/${RUNS_DIR:-runs}/$NAME"   # RUNS_DIR=runs_big for the E18 designs
mapfile -t MV < <(grep '^makevar=' "$RUN/run_config.txt" | sed 's/^makevar=//')
for st in "${STAGES[@]}"; do
  docker run --rm -e CLK_RPT_STAGE="$st" -v "$REPO:/work" \
    -w /OpenROAD-flow-scripts/flow "$ORFS_IMAGE" bash -c \
    'source ../env.sh >/dev/null 2>&1; make "$@"' _ "${MV[@]}" \
    run RUN_SCRIPT=/work/scripts/clock_report.tcl RUN_LOG_NAME_STEM=clock_report_$st \
    > "$RUN/clock_report_$st.log" 2>&1 || { echo "[$NAME] clock_report $st FAILED"; tail -20 "$RUN/clock_report_$st.log"; exit 1; }
done
echo "[$NAME] clock reports done"
