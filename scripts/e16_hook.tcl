# e16_hook.tcl — POST_CTS_TCL hook of the automated launch-side useful-skew
# loop (E16).  Driven by scripts/e16_auto.sh, which writes a small wrapper that
# sets the variables below and sources this file.
#
# Move = reconnect a register's CK pin from its clock net to the input net of
# the buffer driving that net (one clock stage earlier; no cell added, as in
# RE).  Only through buffers: never across the clock gate or an inverter.
#
#   1. Re-apply the moves accepted in earlier iterations ($e16_moves_in,
#      lines "register levels"); the CTS result is deterministic, so this
#      rebuilds the previous iteration's tree exactly.
#   2. Greedy pass over the candidates ($e16_cands_file, from e16_select.tcl
#      on the previous iteration's ROUTED result, worst launch slack first):
#      try one more level up, re-estimate parasitics, re-time the WHOLE design
#      and keep the move only if
#        - J = sum over endpoints of min(0, slack - T)   improves by > EPS,
#        - setup WNS does not get worse (tolerance WNS_TOL),
#        - hold WNS stays >= HOLD_GUARD,
#      otherwise revert it.  Because the check re-times every endpoint, the
#      side effect of the extra pin load on the shared upstream net (all its
#      other sinks get later; E11 measured 3.4-5.4 ps) is part of the guard.
#      An accepted register is re-queued for another level (up to MAXLEV).
#   3. Write the cumulative move list ($REPORTS_DIR/e16_moves_out.txt) and a
#      per-try report ($REPORTS_DIR/e16_hook.rpt).
#
# Variables: e16_cands_file e16_moves_in e16_tag  (paths may be "")
# Optional:  e16_T (0.030) e16_hold_guard (0.020) e16_maxlev (3)
#            e16_eps (0.0005 ns) e16_wns_tol (0.0001 ns) e16_pre (hook first)
#            e16_prev_wns: post-route setup WNS (ns) of the tree that step 1
#              rebuilds.  Post-CTS timing (placement RC) is optimistic by tens
#              of ps, so the threshold of J is shifted by the measured offset:
#              T_eff = e16_T + (post-CTS WNS after step 1 - e16_prev_wns).
if { [info exists e16_pre] && $e16_pre != "" } { source $e16_pre }
foreach {v d} {e16_T 0.030 e16_hold_guard 0.020 e16_maxlev 3 e16_eps 0.0005 e16_wns_tol 0.0001} {
  if { ![info exists $v] } { set $v $d }
}
utl::info FLW 961 "E16 ($e16_tag): T=$e16_T hold_guard=$e16_hold_guard maxlev=$e16_maxlev"

proc e16_ck { iname } {
  return [lindex [get_pins -of_objects [get_cells $iname] -filter "is_register_clock==1"] 0]
}
# upstream net of the CK pin's net if its driver is a buffer, else ""
proc e16_up { ck } {
  set n [get_full_name [get_nets -of_objects $ck]]
  set drv [lindex [get_pins -of_objects [get_nets $n] -filter "direction==output"] 0]
  if { $drv eq "" } { return "" }
  set inst [get_cells -of_objects $drv]
  set lc [sta::find_liberty_cell [get_property $inst ref_name]]
  if { $lc eq "NULL" || ![$lc is_buffer] } { return "" }
  set bin [lindex [get_pins -of_objects $inst -filter "direction==input"] 0]
  set un [get_nets -quiet -of_objects $bin]
  if { $un eq "" || $un eq "NULL" } { return "" }
  return [list $n [get_full_name $un]]
}
proc e16_move { ck from to } { disconnect_pin $from $ck; connect_pin $to $ck }
# whole-design metrics; path values are extracted at once (E15: path objects
# die at the next query)
proc e16_metrics { T } {
  set wns [sta::worst_slack_cmd max]
  set hold [sta::worst_slack_cmd min]
  set J 0.0; set n 0
  foreach p [find_timing_paths -path_delay max -group_path_count 100000 \
               -endpoint_path_count 1 -slack_max $T] {
    set J [expr {$J + [$p slack] * 1e9 - $T}]; incr n
  }
  return [list [expr {$wns * 1e9}] [expr {$hold * 1e9}] $J $n]
}

# 1. re-apply earlier moves
set lev [dict create]
set napplied 0
if { $e16_moves_in != "" && [file exists $e16_moves_in] } {
  foreach line [split [string trim [read [set fh [open $e16_moves_in]]]] "\n"] {
    if { [llength $line] != 2 } continue
    lassign $line iname l
    for {set i 0} {$i < $l} {incr i} {
      set ck [e16_ck $iname]; set u [e16_up $ck]
      if { $u eq "" } { utl::warn FLW 963 "E16: cannot re-apply level [expr $i+1] of $iname"; break }
      e16_move $ck {*}$u; incr napplied
    }
    dict set lev $iname $l
  }
  close $fh
}
estimate_parasitics -placement
set Teff $e16_T
if { [info exists e16_prev_wns] && $e16_prev_wns != "" } {
  set w0 [expr {[sta::worst_slack_cmd max] * 1e9}]
  set Teff [expr {$e16_T + ($w0 - $e16_prev_wns)}]
}
lassign [e16_metrics $Teff] wns hold J nJ
utl::info FLW 962 "E16: re-applied $napplied level moves; start WNS=[format %.4f $wns] hold=[format %.4f $hold] T_eff=[format %.4f $Teff] J=[format %.4f $J] (n=$nJ)"

# 2. greedy pass
set rpt [open $::env(REPORTS_DIR)/e16_hook.rpt w]
puts $rpt "# E16 $e16_tag start: wns=$wns hold=$hold T=$e16_T T_eff=$Teff J=$J n=$nJ re-applied=$napplied"
puts $rpt [format "%-46s %3s %-26s %-26s %9s %9s %9s %9s %9s %9s %s" register lev from to wns0 wns1 hold1 J0 J1 dJ decision]
set queue {}
if { $e16_cands_file != "" && [file exists $e16_cands_file] } {
  foreach line [split [string trim [read [set fh [open $e16_cands_file]]]] "\n"] {
    if { [string index $line 0] eq "#" || [llength $line] < 1 } continue
    lappend queue [lindex $line 0]
  }
  close $fh
}
set tries 0; set acc 0
while { [llength $queue] } {
  set iname [lindex $queue 0]; set queue [lrange $queue 1 end]
  set l [expr {[dict exists $lev $iname] ? [dict get $lev $iname] : 0}]
  if { $l >= $e16_maxlev } continue
  set ck [e16_ck $iname]
  if { $ck eq "" } continue
  set u [e16_up $ck]
  if { $u eq "" } {
    puts $rpt [format "%-46s %3d %s" $iname $l "no buffer above: skipped"]; continue
  }
  lassign $u from to
  e16_move $ck $from $to
  estimate_parasitics -placement
  lassign [e16_metrics $Teff] wns1 hold1 J1 n1
  incr tries
  set ok [expr {$J1 > $J + $e16_eps && $wns1 >= $wns - $e16_wns_tol && $hold1 >= $e16_hold_guard}]
  if { $ok } {
    set dec "kept"; incr acc
    dict set lev $iname [expr {$l + 1}]
    lappend queue $iname          ;# try one more level later
    set wns0 $wns; set J0 $J
    set wns $wns1; set hold $hold1; set J $J1
  } else {
    set dec [expr {$hold1 < $e16_hold_guard ? "reverted(hold)" : ($wns1 < $wns - $e16_wns_tol ? "reverted(wns)" : "reverted(J)")}]
    e16_move $ck $to $from
    estimate_parasitics -placement
    set wns0 $wns; set J0 $J
  }
  puts $rpt [format "%-46s %3d %-26s %-26s %9.4f %9.4f %9.4f %9.4f %9.4f %9.4f %s" \
               $iname [expr {$l + 1}] $from $to $wns0 $wns1 $hold1 $J0 $J1 [expr {$J1 - $J0}] $dec]
  flush $rpt
}
lassign [e16_metrics $Teff] wns hold J nJ
puts $rpt "# E16 $e16_tag end: tries=$tries kept=$acc wns=$wns hold=$hold J=$J n=$nJ"
close $rpt
set mo [open $::env(REPORTS_DIR)/e16_moves_out.txt w]
dict for {k v} $lev { if { $v > 0 } { puts $mo [list $k $v] } }
close $mo
utl::info FLW 964 "E16: $tries tries, $acc kept; post-CTS WNS=[format %.4f $wns] hold=[format %.4f $hold]"
