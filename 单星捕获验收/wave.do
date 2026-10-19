dataset open {@WAVEFILE@} demo
dataset current demo
catch {view wave}
catch {delete wave *}
add wave -group {1 Code comparison} -radix binary demo:/tb_single_sat_capture/signal_code
add wave -group {1 Code comparison} -radix binary demo:/tb_single_sat_capture/local_code
add wave -group {2 Capture result} -radix unsigned demo:/tb_single_sat_capture/result_phase
add wave -group {2 Capture result} -radix unsigned demo:/tb_single_sat_capture/energy
add wave -group {2 Capture result} -radix binary demo:/tb_single_sat_capture/dump
add wave -group {2 Capture result} -radix binary demo:/tb_single_sat_capture/capture
configure wave -namecolwidth 230
configure wave -valuecolwidth 150
configure wave -timelineunits ms
wave zoom range 0ns 14000000ns
puts {DEMO_WAVE_READY}
