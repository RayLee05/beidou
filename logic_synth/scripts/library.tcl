# Library settings only. No design operations; reusable by power.tcl.
set PDK_ROOT /home/share/libs/tsmc28
# Reuse Synopsys' own versioned library analysis cache across immutable jobs.
set ALIB_CACHE /home/7902_13/beidou_runs/alib_cache_K2015
file mkdir $ALIB_CACHE
set_app_var alib_library_analysis_path $ALIB_CACHE
set CORE_TT $PDK_ROOT/logic/selected_db/tcbn28hpcplusbwp40p140tt0p9v25c.db
set CORE_SS $PDK_ROOT/logic/selected_db/tcbn28hpcplusbwp40p140ssg0p81v125c.db
set CORE_FF $PDK_ROOT/logic/selected_db/tcbn28hpcplusbwp40p140ffg0p99vm40c.db
set PAD_DIR $PDK_ROOT/pad/timing_nldm/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tphn28hpcpgv18_170a
set PAD_TT $PAD_DIR/tphn28hpcpgv18tt0p9v1p8v25c.db
set PAD_SS $PAD_DIR/tphn28hpcpgv18ssg0p81v1p62v125c.db
set PAD_FF $PAD_DIR/tphn28hpcpgv18ffg0p99v1p98vm40c.db
set CORE_MODEL $PDK_ROOT/logic/verilog/extracted/TSMCHOME/digital/Front_End/verilog/tcbn28hpcplusbwp40p140_110a/tcbn28hpcplusbwp40p140.v
set PAD_MODEL $PDK_ROOT/pad/simulation_vlg/TSMCHOME/digital/Front_End/verilog/tphn28hpcpgv18_110a/tphn28hpcpgv18_pwr.v
foreach lib [list $CORE_TT $CORE_SS $CORE_FF] {
    if {![file readable $lib]} { error "Missing TSMC28 standard-cell library: $lib" }
}
set target_library [list $CORE_TT]
set link_library [concat [list *] $target_library [list $CORE_SS $CORE_FF]]
if {[info exists ::env(SYNTH_CORNER)] && $::env(SYNTH_CORNER) eq "SS"} {
    set target_library [list $CORE_SS]
    set link_library [list * $CORE_SS $CORE_FF]
}
if {[info exists ::env(SYNTH_PAD)] && $::env(SYNTH_PAD) eq "1"} {
    foreach lib [list $PAD_SS $PAD_FF] {
        if {![file readable $lib]} { error "Missing verified PAD library: $lib" }
    }
    # PADs are explicit instances, never candidates for core logic mapping.
    set link_library [concat $link_library [list $PAD_SS $PAD_FF]]
}
set search_path [concat $search_path [list $PDK_ROOT/logic/selected_db ../rtl/include ../rtl/common]]
