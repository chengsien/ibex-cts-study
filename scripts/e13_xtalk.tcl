# e13_xtalk.tcl — crosstalk proxy for one post-route run (no SI engine).
#
# OpenSTA has no crosstalk delta-delay analysis, but its SPEF reader turns
# every coupling cap into a grounded cap multiplied by
# -coupling_reduction_factor (k).  k = 1 is the normal flow; k = 0 is an
# aggressor switching the same way (coupling cap invisible), k = 2 one
# switching the opposite way (Miller factor 2).  Reading a k=2 SPEF as the
# MAX (late) parasitics and a k=0 SPEF as the MIN (early) parasitics makes
# every late path see worst-case crosstalk and every early path best-case,
# which is the usual pessimistic bound for both setup (late launch + data,
# early capture) and hold (early launch + data, late capture); CRPR removes
# the part on the common clock path.
#
# env:
#   E13_MODE  dump  : write REPORTS_DIR/e13_clock_nets.txt (clock network
#                     nets, found by walking from the clock source through
#                     combinational cells up to liberty clock pins) and stop
#             sta   : timing with E13_MAX / E13_MIN SPEF files and factors
#   E13_TAG       scenario name printed on the result line
#   E13_MAX_SPEF  SPEF for late paths (default RESULTS_DIR/6_final.spef)
#   E13_MIN_SPEF  SPEF for early paths (default: same file)
#   E13_MAX_K / E13_MIN_K  coupling factors (default 1 / 1)
#   E13_SINGLE=1  read one SPEF for both (E13_MAX_SPEF, E13_MAX_K)
source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
proc envd { n d } { if {[info exists ::env($n)]} { return $::env($n) } { return $d } }
set mode [envd E13_MODE sta]

if {$mode eq "dump"} {
  set seen [dict create]
  set queue {}
  # clock source port(s) from the SDC (ibex: clk_i)
  foreach src [envd E13_CLK_PORTS clk_i] { lappend queue $src }
  while {[llength $queue]} {
    set nm [lindex $queue 0]; set queue [lrange $queue 1 end]
    if {[dict exists $seen $nm]} continue
    dict set seen $nm 1
    set net [get_nets -quiet $nm]
    if {$net eq ""} { puts "E13 warn: net $nm not found"; continue }
    foreach p [get_pins -quiet -of_objects $net] {
      if {[get_property $p direction] ne "input"} continue
      if {[get_property $p is_clock]} continue  ;# register/latch/ICG clock pin: sink
      set inst [get_cells -of_objects $p]
      foreach o [get_pins -quiet -of_objects $inst] {
        if {[get_property $o direction] ne "output"} continue
        set on [get_nets -quiet -of_objects $o]
        if {$on ne "" && $on ne "NULL"} { lappend queue [get_full_name $on] }  ;# unconnected outputs give NULL
      }
    }
  }
  set f [open $::env(REPORTS_DIR)/e13_clock_nets.txt w]
  foreach nm [lsort [dict keys $seen]] { puts $f $nm }
  close $f
  puts "E13 clock_nets=[dict size $seen]"
  # clock nets carrying a CTS non-default rule, and what the rule is
  set blk [ord::get_db_block]
  set f [open $::env(REPORTS_DIR)/e13_ndr_nets.txt w]
  set nn 0
  foreach nm [lsort [dict keys $seen]] {
    set net [$blk findNet $nm]
    if {$net eq "NULL"} continue
    set r [$net getNonDefaultRule]
    if {$r ne "NULL"} { puts $f "$nm [$r getName]"; incr nn }
  }
  close $f
  foreach r [$blk getNonDefaultRules] {
    foreach l [[ord::get_db_tech] getLayers] {
      if {[$l getType] ne "ROUTING"} continue
      set lr [$r getLayerRule $l]
      if {$lr eq "NULL"} continue
      puts "E13 ndr [$r getName] [$l getName] width=[$lr getWidth] spacing=[$lr getSpacing] (default width=[$l getWidth] spacing=[$l getSpacing])"
    }
  }
  puts "E13 ndr_nets=$nn"
  exit
}

set tag [envd E13_TAG nom]
set maxf [envd E13_MAX_SPEF $::env(RESULTS_DIR)/6_final.spef]
set minf [envd E13_MIN_SPEF $maxf]
set maxk [envd E13_MAX_K 1]
set mink [envd E13_MIN_K 1]
if {[envd E13_SINGLE 0]} {
  read_spef -coupling_reduction_factor $maxk $maxf
} else {
  read_spef -max -coupling_reduction_factor $maxk $maxf
  read_spef -min -coupling_reduction_factor $mink $minf
}
sta::set_crpr_enabled 1

# clock latency over all register clock pins, sampled before any path query
# (E15: arrival properties read after find_timing_paths are not reliable)
set lmax {}; set lmin {}
foreach p [get_pins -hierarchical *] {
  if {![get_property $p is_clock]} continue
  set a [get_property $p arrival_max_rise]
  set b [get_property $p arrival_min_rise]
  if {$a ne "" && $a ne "INF"} { lappend lmax $a }
  if {$b ne "" && $b ne "INF"} { lappend lmin $b }
}
proc stats { l } {
  set l [lsort -real $l]; set s 0.0; foreach x $l { set s [expr {$s+$x}] }
  return [format "%.4f/%.4f/%.4f" [lindex $l 0] [expr {$s/[llength $l]}] [lindex $l end]]
}
set sw [sta::format_time [sta::worst_slack_cmd max] 4]
set st [sta::format_time [sta::total_negative_slack_cmd max] 4]
set hw [sta::format_time [sta::worst_slack_cmd min] 4]
set ht [sta::format_time [sta::total_negative_slack_cmd min] 4]
puts "E13 $tag maxk=$maxk mink=$mink setup_wns=$sw setup_tns=$st setup_viol=[sta::endpoint_violation_count max] hold_wns=$hw hold_tns=$ht hold_viol=[sta::endpoint_violation_count min] ck_late_min/mean/max=[stats $lmax] ck_early_min/mean/max=[stats $lmin] n_ck=[llength $lmax]"
# worst setup path, for the clock / data split under this scenario
set p [lindex [find_timing_paths -path_delay max -group_path_count 1 -sort_by_slack] 0]
set ps [sta::format_time [$p slack] 4]; set pc [sta::format_time [$p target_clk_delay] 4]
set pe [get_full_name [get_property $p endpoint]]; set pst [get_full_name [get_property $p startpoint]]
puts "E13 $tag worst_setup slack=$ps capture_clk_delay=$pc endpoint=$pe startpoint=$pst"
