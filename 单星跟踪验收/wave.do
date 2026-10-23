dataset open {@WAVEFILE@} demo
dataset current demo
catch {view wave}
catch {delete wave *}

add wave -group {1 Input} -radix binary demo:/tb_single_sat_track/if_valid
add wave -group {1 Input} -radix decimal demo:/tb_single_sat_track/if_sample
add wave -group {1 Input} -radix binary demo:/tb_single_sat_track/dump_valid

add wave -group {2 Code loop} -radix decimal demo:/tb_single_sat_track/mag_e
add wave -group {2 Code loop} -radix decimal demo:/tb_single_sat_track/mag_p
add wave -group {2 Code loop} -radix decimal demo:/tb_single_sat_track/mag_l
add wave -group {2 Code loop} -radix decimal demo:/tb_single_sat_track/el_permille
add wave -group {2 Code loop} -radix decimal demo:/tb_single_sat_track/d_dll

add wave -group {3 Carrier loop} -radix decimal demo:/tb_single_sat_track/i_p
add wave -group {3 Carrier loop} -radix decimal demo:/tb_single_sat_track/q_p
add wave -group {3 Carrier loop} -radix decimal demo:/tb_single_sat_track/iq_permille
add wave -group {3 Carrier loop} -radix decimal demo:/tb_single_sat_track/d_pll
add wave -group {3 Carrier loop} -radix decimal demo:/tb_single_sat_track/dop_word
add wave -group {3 Carrier loop} -radix decimal demo:/tb_single_sat_track/dop_hz
add wave -group {3 Carrier loop} -radix hexadecimal demo:/tb_single_sat_track/freq_word

add wave -group {4 State} -radix binary demo:/tb_single_sat_track/locked
add wave -group {4 State} -radix unsigned demo:/tb_single_sat_track/full_dumps

configure wave -namecolwidth 280
configure wave -valuecolwidth 120
configure wave -timelineunits ms
wave zoom range 0ns 640000000ns
puts {DEMO_WAVE_READY}
