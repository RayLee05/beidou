# =============================================================================
# b1i_rx.sdc —— 综合/STA 约束（工艺未冻结，时钟为占位）
# 需求: REQ-IMPL-003/004
# 采样率 16.368 MSps，1 样本/时钟只需 16.4 MHz；默认 100 MHz 留足余量。
# 周期可由 dc_synth.tcl 的 CLK_NS 环境变量覆盖。端口按名字模糊匹配，
# 同一份约束可用于 channel_slice / b1i_rx_top。
# =============================================================================

if {[info exists ::env(CLK_NS)]} { set CLK_PERIOD $::env(CLK_NS) } else { set CLK_PERIOD 10.0 }

create_clock -name clk -period $CLK_PERIOD [get_ports clk]
set_clock_uncertainty [expr {0.03 * $CLK_PERIOD}] [get_clocks clk]
set_clock_transition 0.10 [get_clocks clk]

set_false_path -from [get_ports rst_n]

set IO_DLY [expr {0.3 * $CLK_PERIOD}]
set in_ports  [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_input_delay  -clock clk $IO_DLY $in_ports
set_output_delay -clock clk $IO_DLY [all_outputs]

set cfg_ports [get_ports -quiet {cfg_addr* cfg_wdata* cfg_valid}]
if {[sizeof_collection $cfg_ports] > 0} { set_false_path -from $cfg_ports }

set_max_fanout 32 [current_design]
set_max_transition 0.5 [current_design]
