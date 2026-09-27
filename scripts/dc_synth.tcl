# =============================================================================
# dc_synth.tcl —— Design Compiler 综合脚本模板
# 用法（在虚拟机里，仓库根目录）：
#   dc_shell -f scripts/dc_synth.tcl -output_log_file reports/synth/dc.log
#
# 目标工艺/库未冻结：先填好下面的变量再跑。产出必须与 RTL 版本标识绑定
# （REQ-IMPL-007：RTL/约束/网表/版图/报告同一版本）。
# =============================================================================

set REPO_ROOT   [pwd]
set RTL_INCDIRS "$REPO_ROOT/rtl/include $REPO_ROOT/rtl/common"
set RTL_FILES [list \
  $REPO_ROOT/rtl/common/carrier_lut.sv \
  $REPO_ROOT/rtl/common/sample_unpacker.sv \
  $REPO_ROOT/rtl/common/sample_timebase.sv \
  $REPO_ROOT/rtl/track/carrier_mixer_nco.sv \
  $REPO_ROOT/rtl/track/code_nco.sv \
  $REPO_ROOT/rtl/track/code_ram.sv \
  $REPO_ROOT/rtl/track/correlator_epl.sv \
  $REPO_ROOT/rtl/track/dll_loop.sv \
  $REPO_ROOT/rtl/track/fll_pll_loop.sv \
  $REPO_ROOT/rtl/track/tracking_channel.sv \
]
set TOP         "tracking_channel"
set SDC_FILE    "$REPO_ROOT/constraints/b1i_rx.sdc"
set OUT_DIR     "$REPO_ROOT/reports/synth"

# ---- 待填写（工艺冻结后）----
# set target_library "xxx.db"
# set link_library   "* $target_library"
# set symbol_library "xxx.sdb"

file mkdir $OUT_DIR

set search_path [concat $search_path $RTL_INCDIRS]
foreach f $RTL_FILES { analyze -format sverilog -vcs "+incdir+$RTL_INCDIRS" $f }
elaborate $TOP
current_design $TOP
link
check_design > $OUT_DIR/check_design.rpt

source $SDC_FILE
compile_ultra

report_area      > $OUT_DIR/area.rpt
report_timing -max_paths 20 > $OUT_DIR/timing.rpt
report_power     > $OUT_DIR/power.rpt
report_constraint -all_violators > $OUT_DIR/constraints.rpt
write -format verilog -hierarchy -output $OUT_DIR/tracking_channel_netlist.v
write_sdc $OUT_DIR/tracking_channel.sdc

puts "综合完成：把 reports/synth 下的报告与 git revision 一并归档"
