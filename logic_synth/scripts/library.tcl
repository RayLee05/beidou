# Library settings only. No design operations; reusable by power.tcl.
set PDK_ROOT /home/share/libs/tsmc28
set CORE_TT $PDK_ROOT/logic/selected_db/tcbn28hpcplusbwp40p140tt0p9v25c.db
set CORE_SS $PDK_ROOT/logic/selected_db/tcbn28hpcplusbwp40p140ssg0p81v125c.db
set CORE_FF $PDK_ROOT/logic/selected_db/tcbn28hpcplusbwp40p140ffg0p99vm40c.db
foreach lib [list $CORE_TT $CORE_SS $CORE_FF] {
    if {![file readable $lib]} { error "Missing TSMC28 standard-cell library: $lib" }
}
set target_library [list $CORE_TT]
set link_library [concat [list *] $target_library [list $CORE_SS $CORE_FF]]
set search_path [concat $search_path [list $PDK_ROOT/logic/selected_db ../rtl/include ../rtl/common]]
# PAD .db and paired timing-model paths must be established before formal use.
# Do not add a behavioral stand-in or another technology's IO library here.
