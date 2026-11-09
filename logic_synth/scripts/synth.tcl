# Bottom-up integration. Produces candidate.*, never declares final acceptance.
set ::env(SYNTH_CORNER) SS
set ::env(SYNTH_PAD) 1
source scripts/library.tcl
set REQUESTED_CORES 4
if {[info exists ::env(MAX_CORES)]} {set REQUESTED_CORES $::env(MAX_CORES)}
set AVAILABLE_CORES [string trim [exec /usr/bin/getconf _NPROCESSORS_ONLN]]
set_host_options -max_cores [expr {min($REQUESTED_CORES,$AVAILABLE_CORES)}]
proc main {} {
    global CORE_SS CORE_FF PAD_SS PAD_FF target_library
    if {![info exists ::env(BASE_DDC)] || ![file readable $::env(BASE_DDC)]} {
        error "BASE_DDC must identify a completed, mapped single-channel snapshot"
    }
    file mkdir build/full output reports/full
    read_ddc $::env(BASE_DDC)
    if {[sizeof_collection [get_designs -quiet bds_channel]] != 1} {error "Base DDC lacks bds_channel"}
    current_design bds_channel
    if {![link]} {error "Base channel link failed"}
    if {[sizeof_collection [get_cells -hier -filter is_unmapped]]} {error "Base DDC is not mapped"}
    # Identical cell functions across corners; preserve the mapped structure.
    set SS_NAME [file rootname [file tail $CORE_SS]]
    set LEAVES [get_cells -hier -filter {is_hierarchical == false}]
    if {![info exists ::env(BASE_IS_SS)] || $::env(BASE_IS_SS) ne "1"} {
      foreach ref [lsort -unique [get_attribute $LEAVES ref_name]] {
        if {[sizeof_collection [get_lib_cells -quiet $SS_NAME/$ref]] != 1} {
            error "No identical SS counterpart for mapped cell $ref"
        }
        if {![change_link [get_cells -hier -filter "ref_name == $ref && is_hierarchical == false"] $SS_NAME/$ref]} {
            error "SS rebind failed for $ref"
        }
      }
    }
    set_min_library $CORE_SS -min_version $CORE_FF
    set_operating_conditions -analysis_type bc_wc -max ssg0p81v125c -max_library $SS_NAME -min ffg0p99vm40c -min_library [file rootname [file tail $CORE_FF]]
    source constraints/core_exploration.sdc
    set_fix_hold [get_clocks clk]
    if {[info exists ::env(REPAIR_CHANNEL)] && $::env(REPAIR_CHANNEL) eq "1"} {
        if {![compile -incremental_mapping]} {error "Channel SS incremental repair failed"}
    } else {
        puts "UNREPAIRED_BASELINE: preserve violations for first full-top review"
    }
    redirect reports/full/channel_ss_setup.rpt {report_timing -delay_type max -max_paths 20}
    redirect reports/full/channel_ss_hold.rpt {report_timing -delay_type min -max_paths 20}
    write -format ddc -hier -output output/channel_ss.ddc
    define_design_lib WRAP -path build/full
    if {![analyze -library WRAP -format sverilog -define {MAPPED_CHANNEL_CORE SYNTH_PG_BIND} [list rtl/bds_bb_6ch_core_mapped.sv rtl/bds_bb_6ch_pad_top.sv]]} {error "PAD wrapper analysis failed"}
    if {![elaborate bds_bb_6ch_pad_top -library WRAP]} {error "PAD wrapper elaboration failed"}
    current_design bds_bb_6ch_pad_top
    if {![link]} {error "Full top link failed"}
    # These are unconnected logical placeholders in SYNTH_PG_BIND view.
    # Replace them by supply objects before UPF creates ports with these names.
    remove_port [get_ports -quiet {POC VDD VSS VDDPST VSSPST}]
    foreach_in_collection pn [get_nets -quiet {POC VDD VSS VDDPST VSSPST}] {remove_net $pn}
    if {![load_upf scripts/power_intent.upf]} {error "Power-intent read failed"}
    source scripts/bind_supplies.tcl
    set_dont_touch [get_designs bds_channel] true
    set_voltage 0.81 -min 0.99 -object_list VDD
    set_voltage 1.62 -min 1.98 -object_list {VDDPST POC}
    set_voltage 0.0 -object_list {VSS VSSPST}
    set_related_supply_net -object_list [get_ports *] -power VDDPST -ground VSSPST
    set_min_library $CORE_SS -min_version $CORE_FF
    set_min_library $PAD_SS -min_version $PAD_FF
    set_operating_conditions -analysis_type bc_wc -max ssg0p81v125c -max_library $SS_NAME -min ffg0p99vm40c -min_library [file rootname [file tail $CORE_FF]]
    set_dont_touch [get_cells -hier -filter {ref_name == PDDW04SDGZ_H_G}] true
    source constraints/pad_interface.sdc
    if {![info exists ::env(REPAIR_CHANNEL)] || $::env(REPAIR_CHANNEL) ne "1"} {
        remove_attribute [get_clocks clk] fix_hold
    }
    if {![compile_ultra -no_autoungroup]} {error "Full-top mapping failed"}
    if {[sizeof_collection [get_cells -hier -filter is_unmapped]]} {error "Unmapped cells remain"}
    redirect reports/full/check_design.rpt {check_design}
    redirect reports/full/check_timing.rpt {check_timing}
    redirect reports/full/qor.rpt {report_qor}
    redirect reports/full/area.rpt {report_area -hierarchy}
    redirect reports/full/setup.rpt {report_timing -delay_type max -max_paths 30}
    redirect reports/full/hold.rpt {report_timing -delay_type min -max_paths 30}
    redirect reports/full/constraints.rpt {report_constraint -all_violators}
    redirect reports/full/environment.rpt {report_design}
    change_names -rules verilog -hier
    write -format verilog -hier -pg -output output/candidate.v
    write -format ddc -hier -output output/candidate.ddc
    write_sdc output/candidate.sdc
    save_upf output/candidate.upf
    write_sdf -version 2.1 -significant_digits 6 output/candidate_bc_wc.sdf
    puts "CANDIDATE_MAPPED unmapped=0; REVIEW_TIMING_AND_PG_BEFORE_FINAL_EXPORT"
}
if {[catch {main} message]} {puts "FATAL: $message";exit 1}
exit 0
