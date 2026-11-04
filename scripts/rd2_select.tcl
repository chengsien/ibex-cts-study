# rd2_select.tcl — round-2 useful-skew target selection from POST-ROUTE timing.
#
# Run with `make run` on a finished RD_phys run (6_final.odb + 6_final.spef).
# Round 1 (rd_phys_useful_skew.tcl) selected from CTS-stage (placement-RC)
# slack, so it missed endpoints that only became critical after routing, such
# as rf_reg[444]. Round 2 selects from the extracted post-route slack instead.
#
# Candidates: register endpoints with post-route setup slack < RD2_T whose
# CK is NOT already driven by a round-1 usefulskew_* buffer. For each:
#   s_cap    worst setup slack at its data inputs
#   s_launch worst setup slack through its outputs (paths it launches)
#   h_cap    worst hold slack at its data inputs
#   allowed  = min((s_launch - s_cap)/2, h_cap - HOLD_GUARD, DMAX)
# Kept only if allowed >= STEP: one CLKBUF_X1 stage realised +27..41 ps in
# RD_phys, so a register must tolerate at least STEP = 45 ps of extra latency.
#
# Output: $REPORTS_DIR/rd2_targets_<tag>.txt  (per line: STA instance name, allowed ns)
#         $REPORTS_DIR/rd2_select_<tag>.rpt   (table with the numbers above)
# Variables: RD2_T (ns, default 0.030), RD2_ONLY (optional instance name:
#            select just that register), RD2_TAG (file-name tag),
#            RD2_STACK (1 = also select registers already behind a round-1
#            buffer if they still allow >= STEP; round 2 then puts a second
#            stage behind the first one).
set T          [expr {[info exists ::env(RD2_T)] ? $::env(RD2_T) : 0.030}]
set ONLY       [expr {[info exists ::env(RD2_ONLY)] ? $::env(RD2_ONLY) : ""}]
set TAG        [expr {[info exists ::env(RD2_TAG)] ? $::env(RD2_TAG) : "T[expr {int($T*1000)}]"}]
set STACK      [expr {[info exists ::env(RD2_STACK)] ? $::env(RD2_STACK) : 0}]
set HOLD_GUARD 0.020
set DMAX       0.080
set STEP       0.045

source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
read_spef $::env(RESULTS_DIR)/6_final.spef

set cands {}
foreach p [find_timing_paths -path_delay max -group_path_count 5000 \
             -endpoint_path_count 1 -slack_max $T -sort_by_slack] {
  set ep [get_property $p endpoint]
  if { [catch { set inst [get_cells -of_objects $ep] }] || $inst == "" } { continue }
  lappend cands [get_full_name $inst]
}
set cands [lsort -unique $cands]
if { $ONLY != "" } { set cands [lsearch -all -inline -exact $cands $ONLY] }

set rpt [open $::env(REPORTS_DIR)/rd2_select_${TAG}.rpt w]
set out [open $::env(REPORTS_DIR)/rd2_targets_${TAG}.txt w]
puts $rpt "# round-2 selection: T=$T ONLY='$ONLY' STACK=$STACK STEP=$STEP HOLD_GUARD=$HOLD_GUARD DMAX=$DMAX"
puts $rpt [format "%-58s %8s %8s %8s %8s %-14s %s" register s_cap s_launch h_cap allowed ck_driver decision]
set nsel 0
foreach iname $cands {
  set inst [get_cells $iname]
  set ck ""; set q {}
  foreach p [get_pins -of_objects $inst] {
    if { [get_property $p is_register_clock] } { set ck $p
    } elseif { [get_property $p direction] == "output" } { lappend q $p }
  }
  if { $ck == "" } { continue }
  set drv ""
  foreach d [get_pins -of_objects [get_nets -of_objects $ck] -filter "direction==output"] {
    set drv [get_full_name [get_cells -of_objects $d]]
  }
  set s_cap 1e9; set h_cap 1e9; set s_launch 1e9
  foreach p [get_pins -of_objects $inst -filter "direction==input"] {
    if { $p == $ck } { continue }
    set s [get_property $p slack_max]; set h [get_property $p slack_min]
    if { $s != "" && $s ne "INF" && $s < $s_cap } { set s_cap $s }
    if { $h != "" && $h ne "INF" && $h < $h_cap } { set h_cap $h }
  }
  foreach p $q {
    set s [get_property $p slack_max]
    if { $s != "" && $s ne "INF" && $s < $s_launch } { set s_launch $s }
  }
  if { $s_cap > 1e8 || $h_cap > 1e8 } { continue }
  if { $s_launch > 1e8 } { set s_launch 10.0 }
  set allowed [expr {min(($s_launch - $s_cap) / 2.0, $h_cap - $HOLD_GUARD, $DMAX)}]
  if { [string match "usefulskew_*" $drv] && !$STACK } {
    set dec "skip:already-delayed"
  } elseif { $allowed < $STEP } {
    set dec "skip:allowed<step"
  } else {
    set dec [expr {[string match "usefulskew_*" $drv] ? "select:stack" : "select"}]
    puts $out "$iname $allowed"
    incr nsel
  }
  puts $rpt [format "%-58s %8.4f %8.4f %8.4f %8.4f %-14s %s" $iname $s_cap $s_launch $h_cap $allowed \
               [string range $drv 0 13] $dec]
}
puts $rpt "candidates=[llength $cands] selected=$nsel"
close $rpt
close $out
puts "RD2_SELECT tag=$TAG candidates=[llength $cands] selected=$nsel"
