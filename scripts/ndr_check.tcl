read_db /work/runs/step0_default/results/nangate45/ibex/base/4_1_cts.odb
set db [ord::get_db]
set tech [$db getTech]
set block [ord::get_db_block]
puts "tech NDRs: [llength [$tech getNonDefaultRules]] ; block NDRs: [llength [$block getNonDefaultRules]]"
foreach r [$block getNonDefaultRules] { puts "  rule [$r getName]" }
set n 0; set tot 0
foreach net [$block getNets] {
  if {[$net getSigType] != "CLOCK"} continue
  incr tot
  set r [$net getNonDefaultRule]
  if {$r != "NULL"} { incr n; if {$n<4} {puts "  [$net getName] -> [$r getName]"} }
}
puts "clock nets with NDR: $n / $tot"
