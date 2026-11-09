# Coarse real-cell ECO on an immutable mapped channel, followed by measured
# endpoint-specific repair. Receiver timing constraints remain unchanged.
set ::env(SYNTH_CORNER) SS
source scripts/library.tcl
proc main {} {
    global CORE_SS CORE_FF
    if {![file readable $::env(BASE_DDC)]} {error "Mapped base missing"}
    read_ddc $::env(BASE_DDC)
    current_design bds_channel
    if {![link]} {error "Mapped channel link failed"}
    set lib [file rootname [file tail $CORE_SS]]
    if {![info exists ::env(BASE_IS_SS)] || $::env(BASE_IS_SS) ne "1"} {error "Use the SS-rebound checkpoint"}
    set_min_library $CORE_SS -min_version $CORE_FF
    set_operating_conditions -analysis_type bc_wc -max ssg0p81v125c -max_library $lib -min ffg0p99vm40c -min_library [file rootname [file tail $CORE_FF]]
    source constraints/core_exploration.sdc
    set out output/core_bds_channel
    set rpt reports/core_bds_channel
    file mkdir $out $rpt
    redirect $rpt/hold_before.rpt {report_timing -delay_type min -max_paths 10}
    redirect $rpt/setup_before.rpt {report_timing -delay_type max -max_paths 10}
    set dpins [all_registers -data_pins]
    puts "BATCH_HOLD_START data_pins=[sizeof_collection $dpins] time=[clock seconds]"
    set delay [get_lib_cells $lib/DEL250MD1BWP40P140]
    if {[sizeof_collection $delay] != 1} {error "Verified delay cell missing"}
    set added [insert_buffer $dpins $delay -no_of_cells 2 -new_cell_names HOLD_DATA -new_net_names HOLD_DATA_NET]
    if {[sizeof_collection $added] == 0} {error "Batch data delay insertion failed"}
    puts "BATCH_HOLD_DATA inserted=[sizeof_collection $added] time=[clock seconds]"
    set added [insert_buffer [all_outputs] $delay -no_of_cells 4 -new_cell_names HOLD_OUT -new_net_names HOLD_OUT_NET]
    if {[sizeof_collection $added] == 0} {error "Output delay insertion failed"}
    puts "BATCH_HOLD_OUTPUT inserted=[sizeof_collection $added] time=[clock seconds]"
    # Review residual endpoints before any further changes. A failed candidate
    # still exports diagnostic reports but never claims timing closure.
    redirect $rpt/hold.rpt {report_timing -delay_type min -max_paths 30}
    redirect $rpt/setup.rpt {report_timing -delay_type max -max_paths 30}
    redirect $rpt/qor.rpt {report_qor}
    redirect $rpt/check_timing.rpt {check_timing}
    redirect $rpt/check_design.rpt {check_design}
    redirect $rpt/constraints.rpt {report_constraint -all_violators}
    redirect $rpt/area.rpt {report_area -hierarchy}
    if {[sizeof_collection [get_cells -hier -filter is_unmapped]]} {error "Unmapped cells after ECO"}
    change_names -rules verilog -hier
    write -format verilog -hier -output $out/baseline.v
    write -format ddc -hier -output $out/baseline.ddc
    write_sdc $out/exploratory.sdc
    set worst [get_timing_paths -delay_type min -max_paths 1]
    puts "BATCH_HOLD_WORST=[get_attribute $worst slack]"
    puts "CHANNEL_HOLD_REPAIR_DONE scope=CANDIDATE_REQUIRES_REPORT_REVIEW"
}
if {[catch {main} message]} {puts "FATAL: $message";exit 1}
exit 0
