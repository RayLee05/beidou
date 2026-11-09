set ::env(SYNTH_CORNER) SS
set ::env(SYNTH_PAD) 1
source scripts/library.tcl
proc main {} {
    global CORE_SS CORE_FF PAD_SS PAD_FF
    read_ddc $::env(PROBE_DIR)/probe.ddc
    file mkdir build/hier_power output/hier_power reports/hier_power
    define_design_lib HIER -path build/hier_power
    if {![analyze -library HIER -format sverilog rtl/hier_power_probe.sv]} {error "Analyze failed"}
    if {![elaborate hier_power_probe -library HIER]} {error "Elaborate failed"}
    current_design hier_power_probe
    if {![link]} {error "Link failed"}
    if {![load_upf scripts/power_intent.upf]} {error "Top UPF failed"}
    foreach rail {VDD VSS VDDPST VSSPST POC} {
        if {![connect_supply_net $rail -ports [list u0/$rail u1/$rail]]} {error "Child supply binding failed: $rail"}
    }
    set_voltage 0.81 -min 0.99 -object_list VDD
    set_voltage 1.62 -min 1.98 -object_list {VDDPST POC}
    set_voltage 0.0 -object_list {VSS VSSPST}
    set_related_supply_net -object_list [get_ports *] -power VDDPST -ground VSSPST
    set_min_library $CORE_SS -min_version $CORE_FF
    set_min_library $PAD_SS -min_version $PAD_FF
    set_operating_conditions -analysis_type bc_wc -max ssg0p81v125c -max_library [file rootname [file tail $CORE_SS]] -min ffg0p99vm40c -min_library [file rootname [file tail $CORE_FF]]
    redirect reports/hier_power/check_design.rpt {check_design}
    write -format verilog -hier -pg -output output/hier_power/probe.v
    write -format ddc -hier -output output/hier_power/probe.ddc
    save_upf output/hier_power/probe.upf
    puts "HIER_POWER_PROBE_DONE"
}
if {[catch {main} message]} {puts "FATAL: $message";exit 1}
exit 0
