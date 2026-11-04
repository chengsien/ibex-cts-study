# RE_combo wrapper: rebuild RD_phys2 (capture-side useful skew, rounds 1+2),
# then launch-early on the startpoints that limit RD_phys2 after route
# (re_select.tcl on RD_phys2, RE_T=0.040).
set re_pre [file join [file dirname [info script]] rd_phys2_T30.tcl]
set re_tag RDP2_T40
set re_targets_file /work/runs/RD_phys2/reports/nangate45/ibex/base/re_targets_RDP2_T40.txt
source [file join [file dirname [info script]] re_launch_early.tcl]
