set ::env(SYNTH_CORNER) SS
set ::env(SYNTH_PAD) 1
source scripts/library.tcl
if {![info exists ::env(PROBE_DIR)]} {exit 2}
file mkdir output/pad_probe reports/pad_probe
read_ddc $::env(PROBE_DIR)/probe.ddc
if {[sizeof_collection [get_designs -quiet bds_pad_probe]] != 1} {exit 1}
current_design bds_pad_probe
if {![link]} {exit 1}
read_sdc $::env(PROBE_DIR)/probe.sdc
set_min_library $CORE_SS -min_version $CORE_FF
set_min_library $PAD_SS -min_version $PAD_FF
set_operating_conditions -analysis_type bc_wc -max ssg0p81v125c -max_library [file rootname [file tail $CORE_SS]] -min ffg0p99vm40c -min_library [file rootname [file tail $CORE_FF]]
source scripts/repair_hold.tcl
if {[catch {repair_hold [file rootname [file tail $CORE_SS]] 64} message]} {puts "FATAL: $message";exit 1}
redirect reports/pad_probe/setup.rpt {report_timing -delay_type max -max_paths 10}
redirect reports/pad_probe/hold.rpt {report_timing -delay_type min -max_paths 10}
redirect reports/pad_probe/constraints.rpt {report_constraint -all_violators}
redirect reports/pad_probe/timing_check.rpt {check_timing}
redirect reports/pad_probe/design.rpt {check_design}
redirect reports/pad_probe/area.rpt {report_area -hierarchy}
write -format verilog -hier -pg -output output/pad_probe/probe.v
write -format ddc -hier -output output/pad_probe/probe.ddc
write_sdc output/pad_probe/probe.sdc
save_upf output/pad_probe/probe.upf
write_sdf -version 2.1 -significant_digits 6 output/pad_probe/probe_ss.sdf
puts "PAD_PROBE_REPAIRED"
exit 0
