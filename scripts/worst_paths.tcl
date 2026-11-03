# worst_paths.tcl — top-10 post-route setup paths (6_final.odb + 6_final.spef)
# with the slack decomposed into launch clock latency, capture clock latency
# and pure data-path delay. Output: reports/.../worst_paths_final.txt
# CK arrivals are sampled BEFORE find_timing_paths (see experiment-log E0:
# the arrival_max_rise pin property is unreliable after path enumeration).
source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
read_spef $::env(RESULTS_DIR)/6_final.spef
set ck_arr [dict create]
foreach p [get_pins -hierarchical *] {
  if { [get_property $p is_register_clock] } {
    dict set ck_arr [get_full_name [get_cells -of_objects $p]] [get_property $p arrival_max_rise]
  }
}
set f [open $::env(REPORTS_DIR)/worst_paths_final.txt w]
puts $f [format "%-8s %-8s %-8s %-8s %-8s  %s -> %s" slack launch capture skew data startpoint endpoint]
foreach p [find_timing_paths -path_delay max -group_path_count 10 -endpoint_path_count 1 -sort_by_slack] {
  set sl  [sta::format_time [$p slack] 4]
  set cap [sta::format_time [$p target_clk_delay] 4]
  set arr [sta::format_time [$p data_arrival_time] 4]
  set sp  [get_full_name [get_property $p startpoint]]
  set ep  [get_full_name [get_property $p endpoint]]
  set si  [file dirname [string map {/ " "} $sp]]
  set sinst [string range $sp 0 [expr {[string last / $sp] - 1}]]
  set lau [expr {[dict exists $ck_arr $sinst] ? [dict get $ck_arr $sinst] : 0.0}]
  puts $f [format "%-8s %-8.4f %-8.4f %-8.4f %-8.4f  %s -> %s" $sl $lau $cap \
             [expr {$cap - $lau}] [expr {$arr - $lau}] $sp $ep]
}
close $f
