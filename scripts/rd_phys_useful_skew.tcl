# rd_phys_useful_skew.tcl — POST_CTS_TCL hook for experiment RD_phys.
#
# Physical version of RD (scripts/rd_useful_skew.tcl). Instead of overriding
# the clock arrival in STA, it really builds the extra capture latency:
#
#  1. Selection: identical to RD (same hook point, same formula, code copied
#     verbatim from rd_useful_skew.tcl) -> registers + target delta.
#  2. The selected CK pins are grouped by the leaf clock net that drives them.
#     Each group is moved behind ONE new delay buffer (insert_buffer
#     -load_pins ... -location <group centroid>), named usefulskew_*.
#  3. The new buffers are legalized (detailed_placement_helper) and the
#     latency each group really received is measured from timing paths
#     (target_clk_delay before vs. after; the pin arrival property is not
#     used, see experiment-log E0).
#  4. Guard: if a group's realised delay exceeds what its members' launch and
#     hold constraints allow  min((s_launch - s_cap)/2, h_cap - HOLD_GUARD, DMAX)
#     the buffer is removed again (remove_buffers).
#  Nothing is overridden in the SDC: downstream GRT repair, detailed route
#  and OpenRCX STA see an ordinary (slightly unbalanced) clock tree.
set T          [expr {[info exists ::env(RD_T)]    ? $::env(RD_T)    : 0.060}]
set DMAX       [expr {[info exists ::env(RD_DMAX)] ? $::env(RD_DMAX) : 0.080}]
set DMIN       0.005
set HOLD_GUARD 0.020
set NMAX       200
set BUF_CELL   [expr {[info exists ::env(RD_BUF)] ? $::env(RD_BUF) : "CLKBUF_X1"}]

utl::info FLW 921 "RD_phys: T=$T DMAX=$DMAX DMIN=$DMIN HOLD_GUARD=$HOLD_GUARD buffer=$BUF_CELL"
set rpt [open $::env(REPORTS_DIR)/rd_phys_useful_skew.rpt w]

# ---------------------------------------------------------------- 1. select
# (verbatim from rd_useful_skew.tcl, except that the delta is recorded
#  instead of applied)
set ck_arr [dict create]
foreach p [get_pins -hierarchical *] {
  if { [get_property $p is_register_clock] } {
    dict set ck_arr [get_full_name $p] [get_property $p arrival_max_rise]
  }
}
set cands {}
foreach path [find_timing_paths -path_delay max -group_path_count $NMAX \
                -endpoint_path_count 1 -slack_max $T -sort_by_slack] {
  set ep [get_property $path endpoint]
  if { [catch { set inst [get_cells -of_objects $ep] }] || $inst == "" } { continue }
  lappend cands [get_full_name $inst]
}
set cands [lsort -unique $cands]

set sel {}   ;# list of {iname ckpin_name delta allowed_max dpin_name}
foreach iname $cands {
  set inst [get_cells $iname]
  set ck ""; set q {}; set dpins {}
  foreach p [get_pins -of_objects $inst] {
    if { [get_property $p is_register_clock] } { set ck $p
    } elseif { [get_property $p direction] == "output" } { lappend q $p }
  }
  if { $ck == "" } { continue }
  set s_cap 1e9; set h_cap 1e9; set s_launch 1e9; set dworst ""
  foreach p [get_pins -of_objects $inst -filter "direction==input"] {
    if { $p == $ck } { continue }
    set s [get_property $p slack_max]; set h [get_property $p slack_min]
    if { $s != "" && $s ne "INF" && $s < $s_cap } { set s_cap $s; set dworst [get_full_name $p] }
    if { $h != "" && $h ne "INF" && $h < $h_cap } { set h_cap $h }
  }
  foreach p $q {
    set s [get_property $p slack_max]
    if { $s != "" && $s ne "INF" && $s < $s_launch } { set s_launch $s }
  }
  if { $s_cap > 1e8 || $h_cap > 1e8 } { continue }
  if { $s_launch > 1e8 } { set s_launch 10.0 }
  set arr [dict get $ck_arr [get_full_name $ck]]
  if { $arr < 0.0 || $arr > 1.0 } { continue }
  set delta [expr {min($T - $s_cap, ($s_launch - $s_cap) / 2.0, $h_cap - $HOLD_GUARD, $DMAX)}]
  if { $delta < $DMIN } { continue }
  set allowed [expr {min(($s_launch - $s_cap) / 2.0, $h_cap - $HOLD_GUARD, $DMAX)}]
  lappend sel [list $iname [get_full_name $ck] $delta $allowed $dworst]
}
utl::info FLW 922 "RD_phys: [llength $sel] registers selected (same rule as RD)"

# capture latency of a register, from a timing path ending at its worst D pin
proc capture_latency { dpin } {
  set p [lindex [find_timing_paths -path_delay max -to [get_pins $dpin] \
                   -group_path_count 1 -endpoint_path_count 1] 0]
  if { $p == "" } { return "" }
  return [sta::format_time [$p target_clk_delay] 6]
}
set lat_before [dict create]
foreach s $sel { dict set lat_before [lindex $s 0] [capture_latency [lindex $s 4]] }

# ---------------------------------------------------------------- 2. group + insert
set groups [dict create]   ;# leaf net -> list of selection entries
foreach s $sel {
  set net [get_full_name [get_nets -of_objects [get_pins [lindex $s 1]]]]
  dict lappend groups $net $s
}
set block [ord::get_db_block]
set dbu [$block getDbUnitsPerMicron]
set gi 0
set inserted [dict create]  ;# buffer name -> group entries
dict for {net members} $groups {
  set pins {}; set sx 0.0; set sy 0.0
  foreach m $members {
    lappend pins [lindex $m 1]
    # STA and OpenDB escape bus brackets differently: convert via sta_to_db_inst
    set oi [sta::sta_to_db_inst [get_cells [lindex $m 0]]]
    set loc [$oi getLocation]
    set sx [expr {$sx + [lindex $loc 0]}]; set sy [expr {$sy + [lindex $loc 1]}]
  }
  set n [llength $members]
  set cx [expr {$sx / $n / $dbu}]; set cy [expr {$sy / $n / $dbu}]
  set bname "usefulskew_$gi"
  insert_buffer -buffer_cell $BUF_CELL -load_pins [get_pins $pins] \
    -location [list $cx $cy] -buffer_name $bname -net_name "usefulskew_net_$gi"
  dict set inserted $bname $members
  incr gi
}
# insert_buffer may suffix the requested names; find the real instances and
# mark their output nets as clock nets so later stages treat them as clock
set real_bufs {}
foreach oi [$block getInsts] {
  if { [string match "usefulskew_*" [$oi getName]] } { lappend real_bufs [$oi getName] }
}
foreach b $real_bufs {
  set oi [$block findInst $b]
  foreach it [$oi getITerms] {
    if { [$it isOutputSignal] && [$it getNet] != "NULL" } { [$it getNet] setSigType CLOCK }
  }
}
utl::info FLW 923 "RD_phys: inserted [llength $real_bufs] $BUF_CELL buffers for [llength $sel] registers on [dict size $groups] leaf nets"

detailed_placement_helper -quiet
estimate_parasitics -placement

# ---------------------------------------------------------------- 3+4. measure, guard
puts $rpt [format "%-58s %-14s %8s %8s %8s %8s %s" register buffer target allowed before after realised]
set removed {}
foreach b [lsort $real_bufs] {
  set oi [$block findInst $b]
  # members = registers whose CK is now driven by this buffer
  set members {}
  foreach it [$oi getITerms] {
    if { ![$it isOutputSignal] || [$it getNet] == "NULL" } { continue }
    foreach sink [[$it getNet] getITerms] {
      if { [$sink getInst] != $oi } { lappend members [[$sink getInst] getName] }
    }
  }
  set worst_excess -1e9; set lines {}
  foreach s $sel {
    set dbname [[sta::sta_to_db_inst [get_cells [lindex $s 0]]] getName]
    if { [lsearch -exact $members $dbname] < 0 } { continue }
    set before [dict get $lat_before [lindex $s 0]]
    set after [capture_latency [lindex $s 4]]
    set real [expr {$after - $before}]
    set excess [expr {$real - [lindex $s 3]}]
    if { $excess > $worst_excess } { set worst_excess $excess }
    lappend lines [format "%-58s %-14s %8.4f %8.4f %8.4f %8.4f %8.4f" [lindex $s 0] $b \
                     [lindex $s 2] [lindex $s 3] $before $after $real]
  }
  foreach l $lines { puts $rpt $l }
  if { $worst_excess > 0 } {
    puts $rpt "  -> $b removed: realised delay exceeds allowed by [format %.4f $worst_excess] ns"
    lappend removed $b
  }
}
if { [llength $removed] > 0 } {
  remove_buffers [get_cells $removed]
  detailed_placement_helper -quiet
  estimate_parasitics -placement
}
set kept [expr {[llength $real_bufs] - [llength $removed]}]
puts $rpt "selected=[llength $sel] groups=[dict size $groups] inserted=[llength $real_bufs] removed=[llength $removed] kept=$kept"
close $rpt
utl::info FLW 924 "RD_phys: kept $kept of [llength $real_bufs] buffers ([llength $removed] removed by guard)"
check_placement -placeable
report_worst_slack -max
report_worst_slack -min
