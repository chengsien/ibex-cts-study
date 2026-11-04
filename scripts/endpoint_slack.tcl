# endpoint_slack.tcl — post-route (6_final.odb + SPEF) setup slack of every
# endpoint with slack < 0.1 ns, one path per endpoint, with its capture clock
# latency and startpoint. Output: reports/.../endpoint_slack_final.csv
source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
read_spef $::env(RESULTS_DIR)/6_final.spef
set f [open $::env(REPORTS_DIR)/endpoint_slack_final.csv w]
puts $f "endpoint,slack_ns,capture_clk_ns,startpoint"
foreach p [find_timing_paths -path_delay max -group_path_count 5000 \
             -endpoint_path_count 1 -slack_max 0.1 -sort_by_slack] {
  puts $f "[get_full_name [get_property $p endpoint]],[sta::format_time [$p slack] 5],[sta::format_time [$p target_clk_delay] 5],[get_full_name [get_property $p startpoint]]"
}
close $f
