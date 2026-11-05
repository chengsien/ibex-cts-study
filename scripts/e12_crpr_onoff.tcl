# e12_crpr_onoff.tcl — ocv5 (late x1.05 / early x0.95) setup/hold with CRPR on and off
# (experiment-log E12). Output: "NOCRPR crpr=<0|1> ..." lines in the run log.
source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
read_spef $::env(RESULTS_DIR)/6_final.spef
set_timing_derate -late 1.05 -cell_delay -net_delay
set_timing_derate -early 0.95 -cell_delay -net_delay
foreach m {1 0} {
  sta::set_crpr_enabled $m
  puts "NOCRPR crpr=$m setup_wns=[sta::format_time [sta::worst_slack_cmd max] 4] setup_tns=[sta::format_time [sta::total_negative_slack_cmd max] 4] hold_wns=[sta::format_time [sta::worst_slack_cmd min] 4]"
}
