# re_add_launch_buffer.tcl — defines re_add_launch_buffer: put one CLKBUF_X1
# in front of a launch flop's CK pin (placed at the flop, fed from whatever
# net drives the CK now), legalize, and report the latency before/after.
# Used after a launch-early move overshoots the balance point (E10/E11);
# needs re_worst_dpin / re_cap_lat from re_launch_early.tcl.
proc re_add_launch_buffer { iname tag rptname } {
  set f [get_cells $iname]
  set ck [lindex [get_pins -of_objects $f -filter "is_register_clock==1"] 0]
  set dp [re_worst_dpin $iname]
  set lat_a [re_cap_lat $dp]
  set loc [[sta::sta_to_db_inst $f] getLocation]
  set dbu [[ord::get_db_block] getDbUnitsPerMicron]
  insert_buffer -buffer_cell CLKBUF_X1 -load_pins $ck \
    -location [list [expr {[lindex $loc 0] / double($dbu)}] [expr {[lindex $loc 1] / double($dbu)}]] \
    -buffer_name launchdelay_$tag -net_name launchdelay_net_$tag
  foreach oi [[ord::get_db_block] getInsts] {
    if { [string match "launchdelay_${tag}*" [$oi getName]] } {
      foreach it [$oi getITerms] {
        if { [$it isOutputSignal] && [$it getNet] != "NULL" } { [$it getNet] setSigType CLOCK }
      }
    }
  }
  detailed_placement_helper -quiet
  estimate_parasitics -placement
  set lat_b [re_cap_lat $dp]
  set fh [open $::env(REPORTS_DIR)/$rptname w]
  puts $fh "$iname CK latency (placement RC): before buffer $lat_a, after CLKBUF_X1 $lat_b, buffer adds [expr {$lat_b - $lat_a}]"
  close $fh
  utl::info FLW 952 "launch buffer for $iname: latency $lat_a -> $lat_b"
}
