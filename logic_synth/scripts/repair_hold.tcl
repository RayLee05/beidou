# Bounded ECO: non-inverting delay from a pair of real library inverters.
# Input interface, clock period, uncertainty and checks stay unchanged.
proc repair_hold {libname limit} {
    for {set round 0} {$round < $limit} {incr round} {
        set bad [get_timing_paths -delay_type min -slack_lesser_than 0.0 -max_paths 1]
        if {[sizeof_collection $bad] == 0} {puts "HOLD_ECO_DONE pairs=$round";return}
        set path [index_collection $bad 0]
        set ep [get_attribute $path endpoint]
        set name [get_object_name $ep]
        if {![regexp {/(D|DI|D0|D1)$} $name]} {error "Hold ECO requires review of non-data endpoint $name"}
        puts "HOLD_ECO endpoint=$name slack=[get_attribute $path slack]"
        insert_buffer $ep $libname/INVD1BWP40P140 -inverter_pair -new_cell_names HOLD_ECO_$round -new_net_names HOLD_NET_$round
    }
    error "Hold ECO exceeded limit $limit"
}
