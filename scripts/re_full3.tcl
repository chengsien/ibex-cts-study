# RE_full3 wrapper: RE_full2b (9 launch moves, [20] two levels + CLKBUF_X1),
# then a third pass that moves instr_rdata_id_o[15] one more level up, onto
# the gated-tree root trunk. Target from re_select.tcl on RE_full2b
# (RE_MODE=launch, RE_T=0.040): expected shift 77.8 ps <= allowed 80 ps.
# See experiment-log E11.
source [file join [file dirname [info script]] re_full2b.tcl]
unset -nocomplain re_pre
set re_tag RF2B_L40
set re_rpt_name re_launch_early_pass3.rpt
set re_targets_file /work/runs/RE_full2b/reports/nangate45/ibex/base/re_targets_RF2B_L40.txt
source [file join [file dirname [info script]] re_launch_early.tcl]
