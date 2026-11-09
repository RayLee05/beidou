# Fixed assignment filenames. Run only after final netlist/SDF GLS acceptance.
proc main {} {
    global target_library link_library search_path CORE_TT CORE_SS CORE_FF PDK_ROOT
    set ::env(SYNTH_CORNER) SS
    set ::env(SYNTH_PAD) 1
    source scripts/library.tcl
    foreach f {output/final.ddc output/final.sdc activity/run.saif reports/gls_accepted.txt} {
        if {![file readable $f]} { error "Required accepted input missing: $f" }
    }
    read_ddc output/final.ddc
    if {[sizeof_collection [get_designs -quiet bds_bb_6ch_pad_top]] != 1} {error "DDC lacks final top"}
    current_design bds_bb_6ch_pad_top
    if {![link]} { error "Final design link failed" }
    if {[sizeof_collection [get_cells -hierarchical -filter is_unmapped]] != 0} {
        error "Final design contains unmapped cells"
    }
    redirect reports/power_check_design.rpt {check_design}
    read_sdc output/final.sdc
    set_min_library $CORE_SS -min_version $CORE_FF
    set_min_library $PAD_SS -min_version $PAD_FF
    redirect reports/power_check_timing.rpt {check_timing}
    read_saif -input activity/run.saif -instance_name tb/dut
    # Preserve read_saif's actual mapping diagnostics in logs/power.log.
    # Do not overwrite activity with a blanket switching/toggle assignment.
    redirect reports/power.rpt {report_power}
    redirect reports/power_hierarchy.rpt {report_power -hierarchy}
    puts "POWER_REPORTS_WRITTEN_REVIEW_ACTIVITY_COVERAGE"
}
if {[catch {main} message]} { puts "FATAL: $message"; exit 1 }
exit 0
