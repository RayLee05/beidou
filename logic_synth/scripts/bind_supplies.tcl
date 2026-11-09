# Bind real library PG pins after logical elaboration. This also connects the
# mapped child cells imported from the original supply-free core DDC.
# Fetch names in a single collection operation. Per-cell attribute queries and
# hundreds of partial supply updates are prohibitively slow on the full top.
# GTECH wrapper logic has no library PG pins until compile maps it; UPF handles
# those new cells during mapping. Only imported real cells need explicit binds.
set PG_NAMES [get_object_name [get_cells -hier -filter {is_hierarchical == false && is_unmapped == false}]]
set PG_COUNT [llength $PG_NAMES]
puts "PG_BIND_START leaves=$PG_COUNT time=[clock seconds]"
foreach rail {VDD VSS} {
    set PG_PORTS {}
    foreach name $PG_NAMES {lappend PG_PORTS $name/$rail}
    puts "PG_BIND_CONNECT rail=$rail count=[llength $PG_PORTS] time=[clock seconds]"
    if {![connect_supply_net $rail -ports $PG_PORTS]} {error "Supply binding failed: $rail"}
    unset PG_PORTS
    puts "PG_BIND_DONE rail=$rail time=[clock seconds]"
}
unset PG_NAMES
set PAD_NAMES [get_object_name [get_cells -hier -filter {ref_name == PDDW04SDGZ_H_G}]]
foreach rail {POC VDDPST VSSPST} {
    set PG_PORTS {}
    foreach name $PAD_NAMES {lappend PG_PORTS $name/$rail}
    if {[llength $PG_PORTS] && ![connect_supply_net $rail -ports $PG_PORTS]} {error "PAD supply binding failed: $rail"}
}
unset PG_PORTS PAD_NAMES
puts "PG_LEAF_CELLS_BOUND=$PG_COUNT time=[clock seconds]"
