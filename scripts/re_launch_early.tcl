# re_launch_early.tcl — POST_CTS_TCL hook for experiment RE ("launch early").
#
# For every register in $re_targets_file (from scripts/re_select.tcl on a
# routed run), move its CK pin from the leaf clock net up to the input net of
# the leaf buffer that drives it:
#      before:  U --[leaf buf]-- N --> F/CK
#      after:   U --> F/CK          (one buffer stage skipped)
# No cell is added, removed or moved. The realised shift is measured from
# timing paths into F (target_clk_delay before vs. after, placement RC). A
# move is reverted if the clock got later, or earlier by more than "allowed"
# (computed post-route by re_select.tcl from the setup slack of the paths F
# captures and the hold slack of the paths F launches).
#
# Set by the wrapper before sourcing: re_targets_file, re_tag.
# Optional: re_pre = script sourced first (e.g. the RD_phys2 hook);
#           re_rpt_name = report file name (default re_launch_early.rpt), so a
#           second pass (e.g. moving one flop a second level up) gets its own
#           report.
if { [info exists re_pre] && $re_pre != "" } { source $re_pre }

utl::info FLW 941 "RE launch-early ($re_tag): targets from $re_targets_file"
set fh [open $re_targets_file]
set re_t {}
foreach line [split [string trim [read $fh]] "\n"] {
  if { [llength $line] == 3 } { lappend re_t $line }
}
close $fh

proc re_worst_dpin { iname } {
  set best ""; set bs 1e9
  foreach p [get_pins -of_objects [get_cells $iname] -filter "direction==input"] {
    if { [get_property $p is_register_clock] } { continue }
    set s [get_property $p slack_max]
    if { $s != "" && $s ne "INF" && $s < $bs } { set bs $s; set best [get_full_name $p] }
  }
  return $best
}
proc re_cap_lat { dpin } {
  set p [lindex [find_timing_paths -path_delay max -to [get_pins $dpin] \
                   -group_path_count 1 -endpoint_path_count 1] 0]
  if { $p == "" } { return "" }
  return [sta::format_time [$p target_clk_delay] 6]
}

if { ![info exists re_rpt_name] } { set re_rpt_name re_launch_early.rpt }
set re_rpt [open $::env(REPORTS_DIR)/$re_rpt_name w]
puts $re_rpt [format "%-44s %-28s %-28s %8s %8s %8s %8s %8s %s" register leaf_net upstream_net est allowed before after earlier decision]
set moves {}
foreach t $re_t {
  lassign $t iname allowed est
  set ck [lindex [get_pins -of_objects [get_cells $iname] -filter "is_register_clock==1"] 0]
  set n_leaf [get_full_name [get_nets -of_objects $ck]]
  set drv [lindex [get_pins -of_objects [get_nets $n_leaf] -filter "direction==output"] 0]
  set binst [get_cells -of_objects $drv]
  set bin [lindex [get_pins -of_objects $binst -filter "direction==input"] 0]
  set n_up [get_full_name [get_nets -of_objects $bin]]
  set dp [re_worst_dpin $iname]
  set before [re_cap_lat $dp]
  disconnect_pin $n_leaf $ck
  connect_pin $n_up $ck
  lappend moves [list $iname [get_full_name $ck] $n_leaf $n_up $allowed $est $dp $before]
}
estimate_parasitics -placement

set kept 0; set reverted 0
foreach m $moves {
  lassign $m iname ckname n_leaf n_up allowed est dp before
  set after [re_cap_lat $dp]
  set earlier [expr {$before - $after}]
  if { $earlier <= 0 || $earlier > $allowed } {
    disconnect_pin $n_up [get_pins $ckname]
    connect_pin $n_leaf [get_pins $ckname]
    set dec "reverted"
    incr reverted
  } else {
    set dec "kept"
    incr kept
  }
  puts $re_rpt [format "%-44s %-28s %-28s %8.4f %8.4f %8.4f %8.4f %8.4f %s" $iname $n_leaf $n_up \
                  $est $allowed $before $after $earlier $dec]
}
if { $reverted > 0 } { estimate_parasitics -placement }
puts $re_rpt "targets=[llength $moves] kept=$kept reverted=$reverted"
close $re_rpt
utl::info FLW 942 "RE: moved $kept CK pins one stage up ($reverted reverted)"
report_worst_slack -max
report_worst_slack -min
