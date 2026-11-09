# External protocol at 16.368 MHz. Data/config launch 0.5..5 ns after clk;
# the executable TB uses +2 ns. Receiver setup/hold are 5 ns / 0.5 ns.
# Nominal IO 1.8 V (SS 1.62 V, FF 1.98 V), 1 pF external output load.
# PAD library capacitance/time units verified as pF/ns. PG ports are UPF supplies.
create_clock -name clk -period 61.0948191593 -waveform {0 30.5474095797} [get_ports clk]
set_clock_uncertainty 0.5 [get_clocks clk]
set_clock_transition 0.2 [get_clocks clk]
set_propagated_clock [get_clocks clk]
set DATA_IN [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_input_delay -clock clk -max 5.0 $DATA_IN
set_input_delay -clock clk -min 0.5 $DATA_IN
set_input_delay -clock clk -max 30.7474095797 [get_ports rst_n]
set_input_delay -clock clk -min 30.3474095797 [get_ports rst_n]
set_input_transition 0.2 [all_inputs]
set_output_delay -clock clk -max 5.0 [all_outputs]
set_output_delay -clock clk -min -0.5 [all_outputs]
set_load 1.0 [all_outputs]
set_max_transition 1.0 [current_design]
set_max_transition 5.0 [all_outputs]
set_max_capacitance 0.1 [current_design]
set_max_capacitance 3.0 [all_inputs]
set_max_capacitance 3.0 [all_outputs]
set_max_fanout 16 [current_design]
set_fix_hold [get_clocks clk]
# No false/multicycle paths. Reset release must satisfy recovery/removal.
