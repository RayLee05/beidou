# Characterize a real delay-cell ECO on the small powered probe before using
# it on the receiver. The deliberately tighter hold budget is probe-only.
set ::env(SYNTH_CORNER) SS
set ::env(SYNTH_PAD) 1
source scripts/library.tcl
proc main {} {
    global CORE_SS CORE_FF PAD_SS PAD_FF
    read_ddc $::env(PROBE_DIR)/probe.ddc
    current_design bds_pad_probe
    if {![link]} {error "Probe link failed"}
    read_sdc $::env(PROBE_DIR)/probe.sdc
    set_min_library $CORE_SS -min_version $CORE_FF
    set_min_library $PAD_SS -min_version $PAD_FF
    set lib [file rootname [file tail $CORE_SS]]
    set_operating_conditions -analysis_type bc_wc -max ssg0p81v125c -max_library $lib -min ffg0p99vm40c -min_library [file rootname [file tail $CORE_FF]]
    # A stricter synthetic test; receiver constraints are never changed here.
    set_clock_uncertainty -hold 1.5 [get_clocks clk]
    file mkdir output/pad_probe reports/pad_probe
    set delay [get_lib_cells $lib/DEL250MD1BWP40P140]
    if {[sizeof_collection $delay] != 1} {error "Delay cell missing"}
    set done 0
    for {set round 0} {$round <= 16} {incr round} {
        set paths [get_timing_paths -delay_type min -max_paths 1]
        set path [index_collection $paths 0]
        set slack [get_attribute $path slack]
        puts "DELAY_PROBE round=$round hold_slack=$slack"
        if {$slack >= 0.0} {set done 1;break}
        if {$round == 16} {break}
        set ep [get_attribute $path endpoint]
        set ep_name [get_object_name $ep]
        # The external result port is also a data endpoint; never delay clocks
        # or asynchronous reset pins to repair hold.
        if {![regexp {/(D|DI|D0|D1)$} $ep_name] && $ep_name ne "result"} {error "Non-data endpoint needs review: $ep_name"}
        if {$ep_name eq "result"} {
            # Keep the delay on the core side of the output PAD, not on the
            # package-facing IO-voltage connection.
            set ep [get_pins pout/I]
        }
        puts "DELAY_PROBE_ENDPOINT=$ep_name"
        set added [insert_buffer $ep $delay -new_cell_names DELAY_ECO_$round -new_net_names DELAY_NET_$round]
        if {[sizeof_collection $added] != 1} {error "Delay insertion failed"}
    }
    if {!$done} {error "Delay-cell probe did not close hold"}
    redirect reports/pad_probe/setup.rpt {report_timing -delay_type max}
    redirect reports/pad_probe/hold.rpt {report_timing -delay_type min}
    redirect reports/pad_probe/check_design.rpt {check_design}
    write -format verilog -hier -pg -output output/pad_probe/probe.v
    write -format ddc -hier -output output/pad_probe/probe.ddc
    write_sdc output/pad_probe/probe.sdc
    puts "DELAY_PROBE_DONE"
}
if {[catch {main} message]} {puts "FATAL: $message";exit 1}
exit 0
