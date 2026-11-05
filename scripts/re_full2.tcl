# RE_full2 wrapper: RE_full (9 launch flops one clock stage up), then a second
# pass that moves instr_rdata_id_o[20] one more stage up, onto the root trunk
# of the gated clock tree (clknet_0_clk).
# re_select.tcl on RE_full rejected this move (expected shift 79 ps > allowed
# 67.5 ps); it is run on request with the margin relaxed to 95 ps, which only
# keeps setup into [20] positive (s_cap was 102.5 ps). See experiment-log E10.
source [file join [file dirname [info script]] re_full.tcl]
unset -nocomplain re_pre
set re_tag RF_20_lvl2
set re_rpt_name re_launch_early_pass2.rpt
set re_targets_file /work/runs/RE_full/reports/nangate45/ibex/base/re_targets_RF_20_lvl2.txt
source [file join [file dirname [info script]] re_launch_early.tcl]
