# =============================================================================
# b1i_rx.sdc —— 综合/STA 约束模板（目标工艺未冻结，先用占位值）
# 需求: REQ-IMPL-003/004（目标时钟、面积预算与处理周期共同满足吞吐）
# 状态: 占位。工艺/PDK/时钟确认后必须重新生成并回写 reports/
# =============================================================================

# ---- 时钟 ----
# 占位 100 MHz；采样率 16.384 MHz，1 样本/时钟只需 16.4% 占用。
# 冻结前请与 docs/FIXED_POINT.md 第 7 节核对。
create_clock -name clk -period 10.0 [get_ports clk]
set_clock_uncertainty 0.30 [get_clocks clk]      ;# 预留 30%，见 params clk_uncertainty
set_clock_transition 0.10 [get_clocks clk]

# ---- 复位 ----
set_false_path -from [get_ports rst_n]

# ---- 输入延迟 ----
# 输入样本由外部适配器给出，按 0.3 个周期估计
set_input_delay -clock clk 3.0 [get_ports {sample_valid sample_i* data_byte* byte_valid}]
set_output_delay -clock clk 3.0 [get_ports {byte_ready sample_valid sample* rec_*}]

# ---- 异步/静态配置 ----
set_false_path -from [get_ports {cfg_addr* cfg_wdata* cfg_valid}]

# ---- 面积/扇出 ----
set_max_fanout 32 [current_design]
set_max_transition 0.5 [current_design]

# ---- 设计规则（占位，需按库更新）----
# set_max_capacitance 0.5 [current_design]
