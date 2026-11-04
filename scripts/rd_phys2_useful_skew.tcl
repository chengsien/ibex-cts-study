# rd_phys2_useful_skew.tcl — POST_CTS_TCL hook: two rounds of physical useful skew.
#
#   round 1: scripts/rd_phys_useful_skew.tcl, unchanged (deterministic, so
#            it rebuilds exactly the 15 RD_phys buffers)
#   round 2: delay the registers listed in $rd2_targets_file, which
#            scripts/rd2_select.tcl picked from RD_phys's POST-ROUTE slack
#            (round 1 could only see CTS-stage estimates).
#
# Round 2 groups the targets by the net that currently drives their CK pin
# and puts one new buffer (usefulskew2_*) in front of each group. A target
# that is already behind a round-1 buffer therefore gets a second stage
# behind the first one. The guard is the same as round 1: a group's buffer
# is removed again if its realised extra latency (path target_clk_delay
# before vs. after, placement RC) exceeds the smallest "allowed" value of its
# members. "allowed" comes from the post-route selection.
#
# Set by the wrapper before sourcing: rd2_targets_file, rd2_tag.
# Optional: rd2_buf (default CLKBUF_X1).
if { ![info exists rd2_buf] } { set rd2_buf CLKBUF_X1 }

# ------------------------------------------------------------- round 1
source [file join [file dirname [info script]] rd_phys_useful_skew.tcl]

# ------------------------------------------------------------- round 2
utl::info FLW 931 "RD_phys2 round 2 ($rd2_tag): targets from $rd2_targets_file, buffer=$rd2_buf"
set fh [open $rd2_targets_file]
set tgts {}
foreach line [split [string trim [read $fh]] "\n"] {
  if { [llength $line] == 2 } { lappend tgts $line }
}
close $fh

set rpt2 [open $::env(REPORTS_DIR)/rd_phys2_round2.rpt w]
puts $rpt2 "# round 2 ($rd2_tag) targets=[llength $tgts] buffer=$rd2_buf file=$rd2_targets_file"

# worst data pin of each target (for the path-based latency measurement)
proc worst_dpin { iname } {
  set best ""; set bs 1e9
  foreach p [get_pins -of_objects [get_cells $iname] -filter "direction==input"] {
    if { [get_property $p is_register_clock] } { continue }
    set s [get_property $p slack_max]
    if { $s != "" && $s ne "INF" && $s < $bs } { set bs $s; set best [get_full_name $p] }
  }
  return $best
}
set info2 [dict create]   ;# iname -> {allowed dpin before}
foreach t $tgts {
  lassign $t iname allowed
  set dp [worst_dpin $iname]
  if { $dp == "" } { continue }
  dict set info2 $iname [list $allowed $dp [capture_latency $dp]]
}

# group by the net currently driving each CK pin
set groups2 [dict create]
dict for {iname v} $info2 {
  set ck [lindex [get_pins -of_objects [get_cells $iname] -filter "is_register_clock==1"] 0]
  dict lappend groups2 [get_full_name [get_nets -of_objects $ck]] $iname
}
set block [ord::get_db_block]
set dbu [$block getDbUnitsPerMicron]
set gi 0
dict for {net members} $groups2 {
  set pins {}; set sx 0.0; set sy 0.0
  foreach m $members {
    lappend pins [get_full_name [lindex [get_pins -of_objects [get_cells $m] -filter "is_register_clock==1"] 0]]
    set loc [[sta::sta_to_db_inst [get_cells $m]] getLocation]
    set sx [expr {$sx + [lindex $loc 0]}]; set sy [expr {$sy + [lindex $loc 1]}]
  }
  set n [llength $members]
  insert_buffer -buffer_cell $rd2_buf -load_pins [get_pins $pins] \
    -location [list [expr {$sx / $n / $dbu}] [expr {$sy / $n / $dbu}]] \
    -buffer_name "usefulskew2_$gi" -net_name "usefulskew2_net_$gi"
  incr gi
}
set bufs2 {}
foreach oi [$block getInsts] {
  if { [string match "usefulskew2_*" [$oi getName]] } { lappend bufs2 [$oi getName] }
}
foreach b $bufs2 {
  foreach it [[$block findInst $b] getITerms] {
    if { [$it isOutputSignal] && [$it getNet] != "NULL" } { [$it getNet] setSigType CLOCK }
  }
}
utl::info FLW 932 "RD_phys2: inserted [llength $bufs2] round-2 buffers for [dict size $info2] registers on [dict size $groups2] nets"
detailed_placement_helper -quiet
estimate_parasitics -placement

# measure + guard
puts $rpt2 [format "%-58s %-16s %8s %8s %8s %8s %s" register buffer allowed before after realised stacked]
set removed2 {}
foreach b [lsort $bufs2] {
  set oi [$block findInst $b]
  set members {}
  foreach it [$oi getITerms] {
    if { ![$it isOutputSignal] || [$it getNet] == "NULL" } { continue }
    foreach sink [[$it getNet] getITerms] {
      if { [$sink getInst] != $oi } { lappend members [[$sink getInst] getName] }
    }
  }
  # which master drives this round-2 buffer's input (round-1 buffer = stacked)
  set upstream ""
  foreach it [$oi getITerms] {
    if { [$it isInputSignal] && [$it getNet] != "NULL" } {
      foreach d [[$it getNet] getITerms] {
        if { [$d isOutputSignal] } { set upstream [[$d getInst] getName] }
      }
    }
  }
  set stacked [expr {[string match "usefulskew_*" $upstream] ? "yes" : "no"}]
  set worst_excess -1e9
  dict for {iname v} $info2 {
    if { [lsearch -exact $members [[sta::sta_to_db_inst [get_cells $iname]] getName]] < 0 } { continue }
    lassign $v allowed dp before
    set after [capture_latency $dp]
    set real [expr {$after - $before}]
    set ex [expr {$real - $allowed}]
    if { $ex > $worst_excess } { set worst_excess $ex }
    puts $rpt2 [format "%-58s %-16s %8.4f %8.4f %8.4f %8.4f %s" $iname $b $allowed $before $after $real $stacked]
  }
  if { $worst_excess > 0 } {
    puts $rpt2 "  -> $b removed: realised delay exceeds allowed by [format %.4f $worst_excess] ns"
    lappend removed2 $b
  }
}
if { [llength $removed2] > 0 } {
  remove_buffers [get_cells $removed2]
  detailed_placement_helper -quiet
  estimate_parasitics -placement
}
set kept2 [expr {[llength $bufs2] - [llength $removed2]}]
puts $rpt2 "round2: targets=[dict size $info2] groups=[dict size $groups2] inserted=[llength $bufs2] removed=[llength $removed2] kept=$kept2"
close $rpt2
utl::info FLW 933 "RD_phys2: kept $kept2 of [llength $bufs2] round-2 buffers ([llength $removed2] removed by guard)"
check_placement -placeable
report_worst_slack -max
report_worst_slack -min
