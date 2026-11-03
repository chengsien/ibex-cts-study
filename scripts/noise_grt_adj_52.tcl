# Noise probe (PRE_GLOBAL_ROUTE_TCL): re-set the metal2-metal3 global-routing
# capacity adjustment from the platform's 0.5 to 0.52 right before global route.
# (The platform value is applied in floorplan.tcl and stored in the ODB, so a
# FASTROUTE_TCL override has no effect on runs that branch at CTS.)
# Clock tree and placement are untouched; only routing is perturbed.
utl::info FLW 911 "noise probe: metal2-metal3 layer adjustment -> 0.52"
set_global_routing_layer_adjustment metal2-metal3 0.52
