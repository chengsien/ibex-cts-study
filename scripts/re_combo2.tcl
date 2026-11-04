# RE_combo2 wrapper: rebuild RD_phys2, then launch-early for every launch flop
# with any path < 60 ps in RD_phys2 (re_select.tcl RE_T=0.060 RE_EPC=50).
set re_pre [file join [file dirname [info script]] rd_phys2_T30.tcl]
set re_tag RDP2_T60_multi
set re_targets_file /work/runs/RD_phys2/reports/nangate45/ibex/base/re_targets_RDP2_T60_multi.txt
source [file join [file dirname [info script]] re_launch_early.tcl]
