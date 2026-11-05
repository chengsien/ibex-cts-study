#!/usr/bin/env bash
# sta_run.sh — run one Tcl script inside ORFS against an existing run
# (ORFS 'make run', same make variables as the run itself, so RESULTS_DIR,
# REPORTS_DIR, platform libs etc. point at runs/<run>/).
#   usage: scripts/sta_run.sh <run> <script.tcl> <log_stem> [-e VAR=VAL ...]
#   RUNS_DIR=runs_big for runs made by run_big.sh
#   STA_MAKEVARS="VAR=VAL ..." extra make variables appended after the run's
#   own (later wins), e.g. STA_MAKEVARS="CORNER=WC" to time an ASAP7 run
#   with its slow-corner libraries
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${ORFS_IMAGE:-openroad/orfs:26Q4-260-gc9ac73efc}"
RUN=$1 TCL=$2 STEM=$3; shift 3
ENVS=()
while [[ $# -gt 0 ]]; do [[ $1 == -e ]] && { ENVS+=(-e "$2"); shift 2; } || { echo "bad arg $1" >&2; exit 1; }; done
mapfile -t MV < <(grep '^makevar=' "$REPO/${RUNS_DIR:-runs}/$RUN/run_config.txt" | sed 's/^makevar=//')
read -r -a XMV <<< "${STA_MAKEVARS:-}"
MV+=("${XMV[@]}")
docker run --rm "${ENVS[@]}" -v "$REPO:/work" -w /OpenROAD-flow-scripts/flow "$IMG" \
  bash -c 'source ../env.sh >/dev/null 2>&1; make "$@"' _ "${MV[@]}" \
  run RUN_SCRIPT="/work/$TCL" RUN_LOG_NAME_STEM="$STEM"
