#!/usr/bin/env bash
# Phase 1 clock-period sweep: full flow per period, 2 runs in parallel.
# usage: scripts/sweep_period.sh 1.8 2.0 2.2 ...
set -uo pipefail
cd "$(dirname "$0")/.."
run_one() {
  local p=$1 n="P${1/./p}"
  scripts/run.sh -n "$n" -p "$p" -u 50 && scripts/post_reports.sh "$n"
}
export -f run_one
printf '%s\n' "$@" | xargs -P 2 -I{} bash -c 'run_one {}'
