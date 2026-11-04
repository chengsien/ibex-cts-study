# RD_phys2 wrapper (T30): round 1 = RD_phys, round 2 = targets selected by
# scripts/rd2_select.tcl on RD_phys's post-route timing (tag T30).
set rd2_tag T30
set rd2_targets_file /work/runs/RD_phys/reports/nangate45/ibex/base/rd2_targets_T30.txt
source [file join [file dirname [info script]] rd_phys2_useful_skew.tcl]
