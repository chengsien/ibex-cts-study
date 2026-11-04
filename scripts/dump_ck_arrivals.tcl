# dump_ck_arrivals.tcl — post-route (6_final.odb + SPEF) clock arrival at every
# register CK pin, sampled in a fresh process before any path enumeration.
# Output: reports/.../ck_arrivals_final.csv  (instance,arrival_ns,driver_cell)
source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
read_spef $::env(RESULTS_DIR)/6_final.spef
set f [open $::env(REPORTS_DIR)/ck_arrivals_final.csv w]
puts $f "instance,arrival_ns,ck_driver_cell"
foreach p [get_pins -hierarchical *] {
  if { ![get_property $p is_register_clock] } { continue }
  set drv ""
  foreach d [get_pins -of_objects [get_nets -of_objects $p] -filter "direction==output"] {
    set drv [get_property [get_cells -of_objects $d] ref_name]
  }
  puts $f "[get_full_name [get_cells -of_objects $p]],[get_property $p arrival_max_rise],$drv"
}
close $f
