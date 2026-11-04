# RD_phys_b1: same as rd_phys_useful_skew.tcl but with BUF_X1 as the delay
# cell (smaller delay step than CLKBUF_X1). Set here rather than through the
# environment because ORFS erases non-stage env vars at each stage.
set ::env(RD_BUF) BUF_X1
source [file join [file dirname [info script]] rd_phys_useful_skew.tcl]
