# e16_select.tcl — candidate list for one E16 iteration, from a ROUTED run
# (6_final.odb + SPEF): every register whose own launch slack (worst setup
# slack at its Q/QN pins) is below E16_T and whose CK net is driven by a
# buffer (so the CK pin can move one stage up), worst first, at most E16_N.
# Output: REPORTS_DIR/e16_cands.txt  ("register launch_slack capture_slack")
source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
read_spef $::env(RESULTS_DIR)/6_final.spef
set T [expr {[info exists ::env(E16_T)] ? $::env(E16_T) : 0.030}]
set N [expr {[info exists ::env(E16_N)] ? $::env(E16_N) : 40}]
set c {}
foreach ck [get_pins -hierarchical *] {
  if { ![get_property $ck is_register_clock] } continue
  set inst [get_cells -of_objects $ck]
  set sl 1e9; set sc 1e9
  foreach p [get_pins -of_objects $inst] {
    if { $p == $ck } continue
    set s [get_property $p slack_max]
    if { $s eq "" || $s eq "INF" } continue
    if { [get_property $p direction] eq "output" } {
      if { $s < $sl } { set sl $s }
    } elseif { $s < $sc } { set sc $s }
  }
  if { $sl >= $T } continue
  set drv [lindex [get_pins -of_objects [get_nets -of_objects $ck] -filter "direction==output"] 0]
  if { $drv eq "" } continue
  set lc [sta::find_liberty_cell [get_property [get_cells -of_objects $drv] ref_name]]
  if { $lc eq "NULL" || ![$lc is_buffer] } continue
  lappend c [list [get_full_name $inst] $sl $sc]
}
set c [lrange [lsort -real -index 1 $c] 0 [expr {$N - 1}]]
set f [open $::env(REPORTS_DIR)/e16_cands.txt w]
puts $f "# E16 candidates: launch slack < $T ns, worst first (max $N)  register launch_slack capture_slack"
foreach x $c { puts $f $x }
close $f
puts "E16SEL candidates=[llength $c] setup_wns=[sta::format_time [sta::worst_slack_cmd max] 4]"
