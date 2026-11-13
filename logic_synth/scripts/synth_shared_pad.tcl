# Six channels share one already-timed bds_channel netlist. This session maps
# only the pad ring and the IF/config glue. It does not copy the channel leaves.
set ::env(SYNTH_CORNER) SS
set ::env(SYNTH_PAD) 1
source scripts/library.tcl
set_host_options -max_cores 3
proc main {} {
    global CORE_SS CORE_FF PAD_SS PAD_FF
    file mkdir build/shared output/shared_pad reports/shared_pad logs
    define_design_lib WORK -path build/shared
    set stub [open output/shared_pad/bds_channel_stub.v w]
    puts $stub {
module bds_channel ( clk, rst_n, sample, cfg_write, cfg_enable, cfg_prn,
        cfg_dop_min, cfg_dop_step, cfg_bins, capture_ok, bit_sync_ok, nav_data,
        nav_valid );
  input [2:0] sample;
  input [5:0] cfg_prn;
  input [31:0] cfg_dop_min;
  input [31:0] cfg_dop_step;
  input [7:0] cfg_bins;
  input clk, rst_n, cfg_write, cfg_enable;
  output capture_ok, bit_sync_ok, nav_data, nav_valid;
endmodule
}
    close $stub
    if {[read_verilog output/shared_pad/bds_channel_stub.v] == 0} { error "Channel stub was not read" }
    if {![analyze -format sverilog -define {MAPPED_CHANNEL_CORE SYNTH_PG_BIND} [list rtl/bds_bb_6ch_core_mapped.sv rtl/bds_bb_6ch_pad_top.sv]]} {
        error "Pad wrapper analysis failed"
    }
    if {![elaborate bds_bb_6ch_pad_top]} { error "Pad wrapper elaboration failed" }
    current_design bds_bb_6ch_pad_top
    if {![link]} { error "Pad wrapper link failed" }
    set_dont_touch [get_designs bds_channel]
    set channels [get_cells -hierarchical -filter {ref_name == bds_channel}]
    set leaves [sizeof_collection [get_cells -hierarchical -filter {is_hierarchical == false}]]
    puts "SHARED_ELAB channels=[sizeof_collection $channels] leaves=$leaves"
    if {[sizeof_collection $channels] != 6} { error "Expected 6 shared channel instances" }
    if {$leaves > 2000} { error "Channel leaves were copied into this session" }
    remove_port [get_ports -quiet {POC VDD VSS VDDPST VSSPST}]
    foreach_in_collection pn [get_nets -quiet {POC VDD VSS VDDPST VSSPST}] { remove_net $pn }
    if {![load_upf scripts/power_intent.upf]} { error "Power-intent read failed" }
    set pads [get_cells -hierarchical -filter {ref_name == PDDW04SDGZ_H_G}]
    puts "SHARED_PADS=[sizeof_collection $pads]"
    if {[sizeof_collection $pads] != 111} { error "Expected 111 signal pads" }
    foreach rail {VDD VSS VDDPST VSSPST POC} {
        set ports {}
        foreach_in_collection pad $pads { lappend ports "[get_object_name $pad]/$rail" }
        set rc [connect_supply_net $rail -ports $ports]
        puts "SHARED_PAD_RAIL $rail count=[llength $ports] rc=$rc"
    }
    set ss_name [file rootname [file tail $CORE_SS]]
    set ff_name [file rootname [file tail $CORE_FF]]
    set_min_library $CORE_SS -min_version $CORE_FF
    set_min_library $PAD_SS -min_version $PAD_FF
    set_operating_conditions -analysis_type bc_wc -max ssg0p81v125c -max_library $ss_name -min ffg0p99vm40c -min_library $ff_name
    set_voltage 0.81 -min 0.99 -object_list VDD
    set_voltage 1.62 -min 1.98 -object_list {VDDPST POC}
    set_voltage 0.0 -object_list {VSS VSSPST}
    set_dont_touch [get_cells -hierarchical -filter {ref_name == PDDW04SDGZ_H_G}]
    source constraints/pad_interface.sdc
    # The channel is the already-timed netlist, so its pins are absent here.
    # Give the nets that drive those stubs a small load. A zero load prints as
    # a minimum-capacitance violation at the default precision.
    set ch_pins [get_pins -of_objects [get_cells -hierarchical -filter {ref_name == bds_channel}] -filter "pin_direction == in"]
    set ch_nets [get_nets -of_objects $ch_pins]
    puts "SHARED_STUB_NETS=[sizeof_collection $ch_nets]"
    set_load 0.05 [add_to_collection $ch_nets [get_nets -quiet u_core/*]]
    # compile_ultra otherwise optimizes leakage against an implicit budget of 0.
    set_leakage_optimization false
    set_fix_hold [get_clocks clk]
    if {![compile_ultra -no_autoungroup]} { error "Pad-ring mapping failed" }
    set stray [filter_collection [get_cells -hierarchical -filter is_unmapped] {ref_name != bds_channel}]
    puts "SHARED_UNMAPPED=[sizeof_collection $stray]"
    if {[sizeof_collection $stray] != 0} { error "Unmapped cells remain outside the shared channel" }
    if {[sizeof_collection [get_cells -hierarchical -filter {ref_name == bds_channel}]] != 6} {
        error "Shared channel instances were removed"
    }
    redirect reports/shared_pad/qor.rpt { report_qor }
    redirect reports/shared_pad/setup.rpt { report_timing -delay_type max -max_paths 20 }
    redirect reports/shared_pad/hold.rpt { report_timing -delay_type min -max_paths 20 }
    redirect reports/shared_pad/constraints.rpt { report_constraint -all_violators }
    redirect reports/shared_pad/area.rpt { report_area }
    change_names -rules verilog -hierarchy
    write -format verilog -hierarchy -pg -output output/shared_pad/pad_ring.v
    write -format ddc -hierarchy -output output/shared_pad/pad_ring.ddc
    write_sdc output/shared_pad/pad_ring.sdc
    puts "SHARED_PAD_DONE channels=6 pads=111"
}
if {[catch {main} message]} { puts "FATAL: $message"; exit 1 }
exit 0
