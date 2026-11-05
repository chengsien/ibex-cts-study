# e12_ocv.tcl — post-route STA (6_final.odb + SPEF) of one run under OCV-style
# timing derates, with CRPR (common clock path pessimism removal) enabled.
# Prints one "OCV <scenario> ..." line per scenario.
#   none     : no derate (must reproduce the normal post-route numbers)
#   ocv5     : late x1.05 / early x0.95 on cell+net delays, clock+data paths
#   ocv10    : late x1.10 / early x0.90
#   fast5    : "fast-corner proxy": all cell delays x0.80 (both early and
#              late, also cell timing checks), then ocv5 on top; for hold only
#              (crude proxy: the platform has no fast library; see E17)
source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
read_spef $::env(RESULTS_DIR)/6_final.spef
sta::set_crpr_enabled 1
puts "OCV crpr_enabled=[sta::crpr_enabled] crpr_mode=[sta::crpr_mode]"
proc res { tag } {
  set sw [sta::format_time [sta::worst_slack_cmd max] 4]
  set st [sta::format_time [sta::total_negative_slack_cmd max] 4]
  set hw [sta::format_time [sta::worst_slack_cmd min] 4]
  set ht [sta::format_time [sta::total_negative_slack_cmd min] 4]
  puts "OCV $tag setup_wns=$sw setup_tns=$st setup_viol=[sta::endpoint_violation_count max] hold_wns=$hw hold_tns=$ht hold_viol=[sta::endpoint_violation_count min]"
}
unset_timing_derate
res none
set_timing_derate -late 1.05 -cell_delay -net_delay
set_timing_derate -early 0.95 -cell_delay -net_delay
res ocv5
unset_timing_derate
set_timing_derate -late 1.10 -cell_delay -net_delay
set_timing_derate -early 0.90 -cell_delay -net_delay
res ocv10
unset_timing_derate
set_timing_derate -late [expr 0.80*1.05] -cell_delay
set_timing_derate -early [expr 0.80*0.95] -cell_delay
set_timing_derate -late 1.05 -net_delay
set_timing_derate -early 0.95 -net_delay
set_timing_derate -early 0.80 -cell_check
set_timing_derate -late 0.80 -cell_check
res fast5
