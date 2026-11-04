# ir_launch_scan.tcl — worst setup slack of the paths launched by each
# instruction-register bit if_stage_i.instr_rdata_id_o[0..31], post-route
# (6_final.odb + SPEF), one find_timing_paths -from per bit. Prints "IR <bit> <slack_ns>".
# Used in experiment-log E9: path enumeration with -endpoint_path_count 50 hid
# bit [21]; querying each launch flop directly does not.
source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
read_spef $::env(RESULTS_DIR)/6_final.spef
for {set b 0} {$b < 32} {incr b} {
  set c [get_cells -quiet "if_stage_i.instr_rdata_id_o\[$b\]\$_DFFE_PP_"]
  if { $c == "" } { continue }
  set s [sta::format_time [[lindex [find_timing_paths -path_delay max -from $c -group_path_count 1] 0] slack] 5]
  puts "IR $b $s"
}
