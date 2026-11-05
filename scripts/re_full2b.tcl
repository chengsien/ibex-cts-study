# RE_full2b wrapper: like RE_full2, then one CLKBUF_X1 is put in front of
# instr_rdata_id_o[20]/CK (fed from the root trunk), so the extra shift over
# RE_full is about one level minus one buffer delay (~45 ps expected) instead
# of a full level (79 ps). The buffer is placed at the flop.
source [file join [file dirname [info script]] re_full2.tcl]
set f20 [get_cells {if_stage_i.instr_rdata_id_o[20]$_DFFE_PP_}]
set ck20 [lindex [get_pins -of_objects $f20 -filter "is_register_clock==1"] 0]
set dp20 [re_worst_dpin [get_full_name $f20]]
set lat_a [re_cap_lat $dp20]
set loc [[sta::sta_to_db_inst $f20] getLocation]
set dbu [[ord::get_db_block] getDbUnitsPerMicron]
insert_buffer -buffer_cell CLKBUF_X1 -load_pins $ck20 \
  -location [list [expr {[lindex $loc 0] / double($dbu)}] [expr {[lindex $loc 1] / double($dbu)}]] \
  -buffer_name launchdelay_20 -net_name launchdelay_net_20
foreach oi [[ord::get_db_block] getInsts] {
  if { [string match "launchdelay_20*" [$oi getName]] } {
    foreach it [$oi getITerms] {
      if { [$it isOutputSignal] && [$it getNet] != "NULL" } { [$it getNet] setSigType CLOCK }
    }
  }
}
detailed_placement_helper -quiet
estimate_parasitics -placement
set lat_b [re_cap_lat $dp20]
set fh [open $::env(REPORTS_DIR)/re_launch_early_pass2b.rpt w]
puts $fh "instr_rdata_id_o\[20\] CK latency (placement RC): after level-2 move $lat_a, after CLKBUF_X1 $lat_b, buffer adds [expr {$lat_b - $lat_a}]"
close $fh
utl::info FLW 951 "RE_full2b: CLKBUF_X1 in front of instr_rdata_id_o\[20\]: latency $lat_a -> $lat_b"
