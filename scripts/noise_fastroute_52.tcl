# Noise probe: identical to platforms/nangate45/fastroute.tcl except the
# metal2-metal3 global-routing capacity adjustment (0.5 -> 0.52). Clock tree
# and placement are untouched; this only perturbs global/detailed routing.
set_global_routing_layer_adjustment metal2-metal3 0.52
set_global_routing_layer_adjustment metal4-$::env(MAX_ROUTING_LAYER) 0.25

set_routing_layers -clock $::env(MIN_CLK_ROUTING_LAYER)-$::env(MAX_ROUTING_LAYER)
set_routing_layers -signal $::env(MIN_ROUTING_LAYER)-$::env(MAX_ROUTING_LAYER)
