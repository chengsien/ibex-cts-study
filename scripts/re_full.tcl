# RE_full wrapper: launch-early only, on the default tree, for every register
# whose own launch slack is < 50 ps in RA (re_select.tcl RE_MODE=launch RE_T=0.050).
set re_tag RA_L50
set re_targets_file /work/runs/RA/reports/nangate45/ibex/base/re_targets_RA_L50.txt
source [file join [file dirname [info script]] re_launch_early.tcl]
