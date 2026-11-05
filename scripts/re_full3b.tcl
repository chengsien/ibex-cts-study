# RE_full3b wrapper: RE_full3, then one CLKBUF_X1 in front of
# instr_rdata_id_o[15]/CK, so its extra shift is about one level minus one
# buffer delay instead of a full level. See experiment-log E11.
source [file join [file dirname [info script]] re_full3.tcl]
source [file join [file dirname [info script]] re_add_launch_buffer.tcl]
re_add_launch_buffer {if_stage_i.instr_rdata_id_o[15]$_DFFE_PP_} 15 re_launch_early_pass3b.rpt
