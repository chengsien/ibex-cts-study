# RE_multi wrapper: launch-early only, on the default tree, for every launch
# flop with any path < 50 ps in RA (re_select.tcl RE_T=0.050 RE_EPC=50).
set re_tag RA_T50_multi
set re_targets_file /work/runs/RA/reports/nangate45/ibex/base/re_targets_RA_T50_multi.txt
source [file join [file dirname [info script]] re_launch_early.tcl]
