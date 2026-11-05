# e15_repro.tcl — minimal reproductions of the two OpenSTA behaviours that
# were only worked around earlier (experiment-log E0 / E4).
#
# E15_PART=A  (default) arrival_max_rise on register CK pins changes after a
#             full search.  Mechanism (OpenSTA search/Sta.cc, Search.cc):
#             Sta::arrival() runs only Search::findArrivals(level), ONE pass,
#             in which latch D->Q outputs are postponed; find_timing_paths /
#             worst_slack run Search::findAllArrivals(thru_latches=true),
#             which iterates until the latch outputs settle.  Ibex's core
#             clock gate is a latch + AND2, so after the full search the
#             latch Q *data* arrival propagates through the AND2 onto the
#             gated clock tree, and the pin property (max over ALL tags at
#             the vertex, clock and data) returns that data arrival.
#             Control: disable the AND2 enable->output arc and repeat.
# E15_PART=B  a path object from find_timing_paths is freed by the next
#             query: every query starts with Sta::searchPreamble(), which
#             calls search_->deletePathGroups(); the PathEnds belong to the
#             path groups, so held Tcl handles dangle (use-after-free).
source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
read_spef $::env(RESULTS_DIR)/6_final.spef
set part [expr {[info exists ::env(E15_PART)] ? $::env(E15_PART) : "A"}]

# the clock gate: the cell driving net 'clk' (gated core clock)
set drv [lindex [get_pins -of_objects [get_nets clk] -filter "direction==output"] 0]
set cg  [get_cells -of_objects $drv]
set cg_name [get_full_name $cg]
set en_pin ""; set ck_in ""
foreach p [get_pins -of_objects $cg -filter "direction==input"] {
  set n [get_full_name [get_nets -of_objects $p]]
  # the clock input sits on a clock-tree net (clk_i / clknet_* / delaynet_*)
  if {[regexp {^(clk|delaynet)} $n]} { set ck_in $p } else { set en_pin $p; set en_net $n }
}
set en_drv [lindex [get_pins -of_objects [get_nets $en_net] -filter "direction==output"] 0]
set latch [get_cells -of_objects $en_drv]
puts "E15 clock_gate=$cg_name ([get_property [get_lib_cells -of_objects $cg] name]) clk_in=[get_full_name $ck_in] enable_in=[get_full_name $en_pin] enable_driver=[get_full_name $en_drv] ([get_property [get_lib_cells -of_objects $latch] name])"

# register CK pins, split by clock root (gated 'clk' tree vs 'clk_i_regs')
proc root_of { ckpin } {
  # walk the clock buffers back to clk / clk_i_regs / clk_i
  set net [get_full_name [get_nets -of_objects $ckpin]]
  for {set i 0} {$i < 40} {incr i} {
    if {$net in {clk clk_i_regs clk_i}} { return $net }
    set d [lindex [get_pins -of_objects [get_nets $net] -filter "direction==output"] 0]
    if {$d eq ""} { return "?" }
    set inp [lindex [get_pins -of_objects [get_cells -of_objects $d] -filter "direction==input"] 0]
    set net [get_full_name [get_nets -of_objects $inp]]
  }
  return "?"
}
proc sample { } {
  set d [dict create]
  foreach p [get_pins -hierarchical *] {
    if {[get_property $p is_register_clock]} {
      dict set d [get_full_name $p] [get_property $p arrival_max_rise]
    }
  }
  return $d
}
proc compare { tag a b roots } {
  set cnt [dict create]
  set ex ""
  dict for {k v} $a {
    set r [dict get $roots $k]
    dict incr cnt "$r:total"
    set w [dict get $b $k]
    if {abs($w - $v) > 0.001} {   ;# > 1 ps
      dict incr cnt "$r:changed"
      if {$ex eq ""} { set ex "$k $v->$w ns" }
    }
  }
  puts "E15 $tag [lsort [dict keys $cnt]] -> [join [lmap k [lsort [dict keys $cnt]] {dict get $cnt $k}] /] example: $ex"
}

if {$part eq "A"} {
  set a0 [sample]
  set roots [dict create]
  dict for {k v} $a0 { dict set roots $k [root_of [get_pins $k]] }
  # one CK pin on each tree for the tag report
  set ex_clk ""; set ex_regs ""
  dict for {k v} $roots {
    if {$v eq "clk" && $ex_clk eq ""} { set ex_clk $k }
    if {$v eq "clk_i_regs" && $ex_regs eq ""} { set ex_regs $k }
  }
  puts "E15 before: $ex_clk arrival_max_rise=[dict get $a0 $ex_clk] ns"
  puts "E15 --- tag arrivals at $ex_clk BEFORE full search ---"
  sta::report_tag_arrivals [get_pins $ex_clk]
  # full search (findAllArrivals with latch passes)
  set wns [sta::worst_slack_cmd max]
  set a1 [sample]
  compare "after_worst_slack" $a0 $a1 $roots
  puts "E15 after: $ex_clk arrival_max_rise=[get_property [get_pins $ex_clk] arrival_max_rise] arrival_min_rise=[get_property [get_pins $ex_clk] arrival_min_rise] ns"
  puts "E15 --- tag arrivals at $ex_clk AFTER full search ---"
  sta::report_tag_arrivals [get_pins $ex_clk]
  puts "E15 --- tag arrivals at $ex_regs (clk_i_regs tree) AFTER full search ---"
  sta::report_tag_arrivals [get_pins $ex_regs]
  # control: cut the enable -> gated-clock arc of the clock gate
  set_disable_timing -from [file tail [get_full_name $en_pin]] \
                     -to [file tail [get_full_name $drv]] $cg
  set a2 [sample]
  set wns2 [sta::worst_slack_cmd max]
  set a3 [sample]
  compare "control_disabled_enable_arc_after_worst_slack" $a0 $a3 $roots
  puts "E15 setup_wns normal=[sta::format_time $wns 4] with_enable_arc_disabled=[sta::format_time $wns2 4]"
}

if {$part eq "B"} {
  set ps [find_timing_paths -path_delay max -group_path_count 3 -sort_by_slack]
  set p1 [lindex $ps 1]
  puts "E15B handle=$p1 slack_read_immediately=[sta::format_time [$p1 slack] 4]"
  # any query runs Sta::searchPreamble -> deletePathGroups
  set s [get_property [get_pins -of_objects [get_cells $cg_name] -filter "direction==output"] slack_max]
  puts "E15B intervening query done (slack_max on clock gate output = $s)"
  flush stdout
  # use-after-free: the PathEnd behind $p1 was deleted
  puts "E15B same handle read again -> [sta::format_time [$p1 slack] 4]"
  flush stdout
  catch { puts "E15B endpoint via freed handle -> [get_full_name [get_property $p1 endpoint]]" } err
  puts "E15B (no crash this time; err=$err)"
}
