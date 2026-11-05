# e17_corners.tcl — post-route STA of an ASAP7 run (6_final.odb + SPEF) with
# the libraries of the corner selected by the make variable CORNER
# (BC = FF 0.77 V 25 C, TC = TT 0.70 V 0 C, WC = SS 0.63 V 100 C; the
# platform's load.tcl reads $LIB_FILES of that corner). One RC corner (the
# SPEF) for all.  Prints one "E17 corner=..." line. CRPR on.
source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
read_spef $::env(RESULTS_DIR)/6_final.spef
sta::set_crpr_enabled 1
# clock latency at register CK pins, before any full search (E15)
set l {}
foreach p [get_pins -hierarchical *] {
  if {![get_property $p is_register_clock]} continue
  set a [get_property $p arrival_max_rise]
  if {$a ne "" && $a ne "INF"} { lappend l $a }
}
set l [lsort -real $l]; set s 0.0; foreach x $l { set s [expr {$s + $x}] }
set lat [format "%.2f/%.2f/%.2f" [lindex $l 0] [expr {$s / [llength $l]}] [lindex $l end]]
set sw [sta::format_time [sta::worst_slack_cmd max] 2]
set st [sta::format_time [sta::total_negative_slack_cmd max] 2]
set hw [sta::format_time [sta::worst_slack_cmd min] 2]
set ht [sta::format_time [sta::total_negative_slack_cmd min] 2]
puts "E17 corner=$::env(CORNER) setup_wns=$sw setup_tns=$st setup_viol=[sta::endpoint_violation_count max] hold_wns=$hw hold_tns=$ht hold_viol=[sta::endpoint_violation_count min] ck_lat_min/mean/max=$lat n_ck=[llength $l] (times in library units: ps for ASAP7)"
