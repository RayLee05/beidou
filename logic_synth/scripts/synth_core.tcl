# Run from logic_synth/: dc_shell -f scripts/synth_core.tcl
# This stage estimates core scale only. It never creates final.* deliverables.
proc main {} {
    global target_library link_library search_path CORE_TT CORE_SS CORE_FF PDK_ROOT
    source scripts/library.tcl
    set requested 4
    if {[info exists ::env(MAX_CORES)]} {set requested $::env(MAX_CORES)}
    set available [string trim [exec /usr/bin/getconf _NPROCESSORS_ONLN]]
    set used [expr {min($requested,$available)}]
    set_host_options -max_cores $used
    puts "HOST_CORES requested=$requested available=$available configured=$used"
    set TOP bds_channel
    if {[info exists ::env(CORE_TOP)]} { set TOP $::env(CORE_TOP) }
    if {$TOP ni {bds_channel bds_bb_6ch_core}} { error "Unsupported exploratory top: $TOP" }
    set OUT output/core_$TOP
    set RPT reports/core_$TOP
    file mkdir $OUT $RPT build/dc_$TOP
    define_design_lib WORK -path build/dc_$TOP
    set RTL {}
    set f [open rtl/core.f r]
    while {[gets $f line] >= 0} {
        set line [string trim $line]
        if {$line ne "" && ![string match +* $line] && ![string match //* $line]} {
            lappend RTL $line
        }
    }
    close $f
    if {![analyze -format sverilog $RTL]} { error "RTL analysis failed" }
    if {![elaborate $TOP]} { error "Elaboration failed" }
    current_design $TOP
    if {![link]} { error "Link failed" }
    uniquify
    redirect $RPT/check_design_pre.rpt {check_design}
    source constraints/core_exploration.sdc
    # Use the library's default operating condition and wire-load model, report
    # both rather than inventing a physical RC model. No layout parasitics here.
    redirect $RPT/design_environment.rpt {report_design}
    redirect $RPT/library.rpt {report_lib [get_object_name [get_libs *tt0p9v25c]]}
    if {[info exists ::env(SYNTH_MODE)] && $::env(SYNTH_MODE) eq "ultra"} {
        if {![compile_ultra -no_autoungroup]} {error "Ultra mapping failed"}
    } else {
        if {![compile]} {error "Technology mapping failed"}
    }
    set unmapped [sizeof_collection [get_cells -hierarchical -filter is_unmapped]]
    set cells [sizeof_collection [get_cells -hierarchical *]]
    puts "UNMAPPED_COUNT=$unmapped"
    puts "HIERARCHICAL_CELL_COUNT=$cells"
    if {$cells == 0} { error "Empty design after mapping" }
    if {$unmapped != 0} { error "Unmapped cells remain" }
    redirect $RPT/check_design.rpt {check_design}
    redirect $RPT/check_timing.rpt {check_timing}
    redirect $RPT/qor.rpt {report_qor}
    redirect $RPT/area.rpt {report_area -hierarchy}
    redirect $RPT/cells.rpt {report_reference -hierarchy}
    redirect $RPT/setup.rpt {report_timing -delay_type max -max_paths 20}
    redirect $RPT/hold.rpt {report_timing -delay_type min -max_paths 20}
    redirect $RPT/constraints.rpt {report_constraint -all_violators}
    change_names -rules verilog -hierarchy
    write -format verilog -hierarchy -output $OUT/baseline.v
    write -format ddc -hierarchy -output $OUT/baseline.ddc
    write_sdc $OUT/exploratory.sdc
    puts "CORE_MAPPING_DONE top=$TOP unmapped=$unmapped scope=EXPLORATORY_ONLY"
}
if {[catch {main} message]} { puts "FATAL: $message"; exit 1 }
exit 0
