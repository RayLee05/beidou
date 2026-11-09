set ::env(SYNTH_CORNER) SS
set ::env(SYNTH_PAD) 1
source scripts/library.tcl
file mkdir build/pad_probe output/pad_probe reports/pad_probe
define_design_lib WORK -path build/pad_probe
if {![analyze -format sverilog rtl/bds_pad_probe.sv]} {exit 1}
if {![elaborate bds_pad_probe]} {exit 1}
current_design bds_pad_probe
if {![link]} {exit 1}
if {![load_upf scripts/power_intent.upf]} {exit 1}
set_voltage 0.81 -min 0.99 -object_list VDD
set_voltage 1.62 -min 1.98 -object_list {VDDPST POC}
set_voltage 0.0 -object_list {VSS VSSPST}
set SIGNAL_PORTS [get_ports *]
set_related_supply_net -object_list $SIGNAL_PORTS -power VDDPST -ground VSSPST
set_min_library $CORE_SS -min_version $CORE_FF
set_min_library $PAD_SS -min_version $PAD_FF
set_operating_conditions -analysis_type bc_wc -max ssg0p81v125c -max_library [file rootname [file tail $CORE_SS]] -min ffg0p99vm40c -min_library [file rootname [file tail $CORE_FF]]
set_dont_touch [get_cells {pclk prst pdat pout}]
create_clock -name clk -period 61.0948191593 [get_ports clk]
set_clock_uncertainty 0.5 [get_clocks clk]
set_input_delay -clock clk -max 5 [get_ports {rst_n data}]
set_input_delay -clock clk -min 0.5 [get_ports {rst_n data}]
set_input_transition 0.2 [all_inputs]
set_output_delay -clock clk -max 5 [get_ports result]
set_output_delay -clock clk -min -0.5 [get_ports result]
set_load 1.0 [get_ports result]
set_propagated_clock [get_clocks clk]
set_fix_hold [get_clocks clk]
if {![compile_ultra]} {exit 1}
redirect reports/pad_probe/design.rpt {check_design}
redirect reports/pad_probe/timing_check.rpt {check_timing}
redirect reports/pad_probe/area.rpt {report_area -hierarchy}
redirect reports/pad_probe/setup.rpt {report_timing -delay_type max}
redirect reports/pad_probe/hold.rpt {report_timing -delay_type min}
redirect reports/pad_probe/constraints.rpt {report_constraint -all_violators}
if {[sizeof_collection [get_cells -hierarchical -filter is_unmapped]] != 0} {exit 1}
write -format verilog -hierarchy -pg -output output/pad_probe/probe.v
write -format ddc -hierarchy -output output/pad_probe/probe.ddc
write_sdc output/pad_probe/probe.sdc
save_upf output/pad_probe/probe.upf
write_sdf -version 2.1 -significant_digits 6 output/pad_probe/probe_ss.sdf
redirect reports/pad_probe/write_help.rpt {help write}
redirect reports/pad_probe/supply_help.rpt {help connect_supply_net}
puts "PAD_PROBE_MAPPED"
exit 0
