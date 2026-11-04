# RE wrapper: launch-early only, on the default tree. Targets from RA's
# post-route timing (re_select.tcl, RE_T=0.030).
set re_tag RA_T30
set re_targets_file /work/runs/RA/reports/nangate45/ibex/base/re_targets_RA_T30.txt
source [file join [file dirname [info script]] re_launch_early.tcl]
