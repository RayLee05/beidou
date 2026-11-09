set PDK /home/share/libs/tsmc28
set CORE_SS $PDK/logic/selected_db/tcbn28hpcplusbwp40p140ssg0p81v125c.db
set CORE_FF $PDK/logic/selected_db/tcbn28hpcplusbwp40p140ffg0p99vm40c.db
set PAD_DIR $PDK/pad/timing_nldm/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tphn28hpcpgv18_170a
set PAD_SS $PAD_DIR/tphn28hpcpgv18ssg0p81v1p62v125c.db
set PAD_FF $PAD_DIR/tphn28hpcpgv18ffg0p99v1p98vm40c.db
set CORNER SS
if {[info exists ::env(PT_CORNER)]} {set CORNER $::env(PT_CORNER)}
set CORE $CORE_SS
set PAD $PAD_SS
set COC ssg0p81v125c
set POC ssg0p81v1p62v125c
if {$CORNER eq "FF"} {set CORE $CORE_FF;set PAD $PAD_FF;set COC ffg0p99vm40c;set POC ffg0p99v1p98vm40c}
set link_path [list * $CORE $PAD]
file mkdir output/pad_probe reports/pad_probe
read_verilog $::env(PROBE_DIR)/probe.v
link_design bds_pad_probe
# Preserve all timing constraints; set_voltage is DC's UPF-specific annotation.
# PT obtains SS/FF voltages from the corresponding core and IO library corners.
set fh [open $::env(PROBE_DIR)/probe.sdc r]
set sdc [read $fh];close $fh
regsub -all {\\\r?\n} $sdc { } sdc
set fh [open output/probe_pt.sdc w]
foreach line [split $sdc \n] {
    if {![string match {set_voltage *} $line] && ![string match {set_operating_conditions *} $line]} {puts $fh $line}
}
close $fh
read_sdc output/probe_pt.sdc
set_operating_conditions -analysis_type single -library [file rootname [file tail $CORE]] $COC
set_operating_conditions -library [file rootname [file tail $PAD]] $POC -object_list [get_cells {pclk prst pdat pout}]
update_timing
report_timing -delay_type max > reports/pad_probe/setup.rpt
report_timing -delay_type min > reports/pad_probe/hold.rpt
write_sdf -version 3.0 -context verilog -significant_digits 6 -include {SETUPHOLD RECREM} output/pad_probe/probe_$CORNER.sdf
file copy -force $::env(PROBE_DIR)/probe.v output/pad_probe/probe.v
puts "PT_PROBE_SDF3_WRITTEN"
exit
