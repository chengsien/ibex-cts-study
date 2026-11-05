# e18_hold_paths.tcl — worst hold paths (one per endpoint) of a routed run: slack, startpoint, endpoint, capture clock latency (ns)
source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
read_spef $::env(RESULTS_DIR)/6_final.spef
set out {}
foreach p [find_timing_paths -path_delay min -group_path_count 8 -endpoint_path_count 1 -sort_by_slack] {
  lappend out [list [sta::format_time [$p slack] 4] [get_full_name [get_property $p startpoint]] [get_full_name [get_property $p endpoint]] [sta::format_time [$p target_clk_delay] 4]]
}
foreach o $out { puts "HOLD $o" }
