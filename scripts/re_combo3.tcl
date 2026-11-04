# RE_combo3 wrapper: rebuild RD_phys2, then launch-early for every register
# whose own launch slack is < 60 ps in RD_phys2 (RE_MODE=launch RE_T=0.060).
set re_pre [file join [file dirname [info script]] rd_phys2_T30.tcl]
set re_tag RDP2_L60
set re_targets_file /work/runs/RD_phys2/reports/nangate45/ibex/base/re_targets_RDP2_L60.txt
source [file join [file dirname [info script]] re_launch_early.tcl]
