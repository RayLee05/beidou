# =============================================================================
# dc_synth.tcl —— Design Compiler 综合脚本
# 用法（虚拟机 IC，仓库根目录）：
#   TARGET_LIB=/path/xxx.db dc_shell -f scripts/dc_synth.tcl -output_log_file reports/synth/dc.log
#   TOP=b1i_rx_top PARAMS="N_LANES=4,BUF_DEPTH=256" TARGET_LIB=... dc_shell -f scripts/dc_synth.tcl
#
# 环境变量：
#   TOP         顶层模块，默认 channel_slice（单通道，先拿面积/时序基线）
#   PARAMS      elaborate -parameters 字符串，可空
#   TARGET_LIB  工艺 .db 绝对路径（必填）
#   CLK_NS      时钟周期 ns，默认 10.0
# 源文件唯一来源：rtl/filelist.f。产出与 git revision 一起归档（REQ-IMPL-007）。
# =============================================================================

set REPO_ROOT [pwd]
proc env_or {name dflt} {
  if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
  return $dflt
}

set TOP     [env_or TOP channel_slice]
set PARAMS  [env_or PARAMS ""]
set CLK_NS  [env_or CLK_NS 10.0]
set TLIB    [env_or TARGET_LIB ""]
set OUT_DIR "$REPO_ROOT/reports/synth/$TOP"
file mkdir $OUT_DIR

if {$TLIB eq "" || ![file exists $TLIB]} {
  puts "ERROR: TARGET_LIB 需为工艺 .db 绝对路径（当前: '$TLIB'）"
  exit 1
}
set target_library $TLIB
set link_library   [list * $TLIB]

set INCDIRS [list $REPO_ROOT/rtl/include $REPO_ROOT/rtl/common]
set search_path [concat $search_path $INCDIRS]

set RTL_FILES {}
set fh [open $REPO_ROOT/rtl/filelist.f r]
while {[gets $fh line] >= 0} {
  set line [string trim [regsub {//.*$} $line ""]]
  if {$line eq "" || [string index $line 0] eq "+"} { continue }
  lappend RTL_FILES $REPO_ROOT/$line
}
close $fh

define_design_lib WORK -path $OUT_DIR/work
if {![analyze -format sverilog $RTL_FILES]} {
  puts "ERROR: analyze 失败"
  exit 1
}
if {$PARAMS eq ""} {
  set ok [elaborate $TOP]
} else {
  set ok [elaborate $TOP -parameters $PARAMS]
}
if {!$ok} { puts "ERROR: elaborate $TOP 失败"; exit 1 }
current_design $TOP
link
uniquify
check_design > $OUT_DIR/check_design.rpt

set ::env(CLK_NS) $CLK_NS
source $REPO_ROOT/constraints/b1i_rx.sdc
compile_ultra -no_autoungroup

report_qor                         > $OUT_DIR/qor.rpt
report_area -hierarchy             > $OUT_DIR/area.rpt
report_timing -max_paths 20        > $OUT_DIR/timing.rpt
report_power                       > $OUT_DIR/power.rpt
report_constraint -all_violators   > $OUT_DIR/constraints.rpt
write -format verilog -hierarchy -output $OUT_DIR/${TOP}_netlist.v
write_sdc $OUT_DIR/${TOP}.sdc

puts "DC_DONE top=$TOP clk_ns=$CLK_NS lib=$TLIB"
exit 0
