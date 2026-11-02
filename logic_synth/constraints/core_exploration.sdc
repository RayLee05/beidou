# Exploratory CORE PIN environment, not a frozen external PAD interface.
# Clock is fixed by Fs. Other numbers define an explicit provisional test budget:
# source launches 0.5..5 ns after clk, receiver needs 5 ns setup and 0.5 ns hold;
# 10 fF output load, 0.2 ns input/clock slew, 0.5 ns clock uncertainty.
# Reconcile with real PAD specs before formal synthesis; never export as final.sdc.
create_clock -name clk -period 61.0948191593 -waveform {0 30.5474095797} [get_ports clk]
set_clock_uncertainty 0.5 [get_clocks clk]
set_clock_transition 0.2 [get_clocks clk]
set DATA_IN [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay -clock clk -max 5.0 $DATA_IN
set_input_delay -clock clk -min 0.5 $DATA_IN
set_input_transition 0.2 $DATA_IN
set_output_delay -clock clk -max 5.0 [all_outputs]
set_output_delay -clock clk -min -0.5 [all_outputs]
set_load 0.01 [all_outputs]
set_max_transition 1.0 [current_design]
set_max_capacitance 0.1 [current_design]
set_max_fanout 16 [current_design]
# No false paths: rst_n release is required to meet recovery/removal. The test
# source releases reset at a falling edge; configuration is synchronous to clk.
