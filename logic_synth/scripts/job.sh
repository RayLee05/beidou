#!/usr/bin/env bash
set -eo pipefail
cd "$(dirname "$0")/../.."
TASK_ROOT=$(pwd -P)
TASK_STATE="$TASK_ROOT/job_state"
mkdir -p "$TASK_STATE"
case ${1:-status} in
status)
  if test -f "$TASK_STATE/exit_code"; then
    echo "EXIT_CODE=$(cat "$TASK_STATE/exit_code")"
  elif test -f "$TASK_STATE/pid" && kill -0 "$(cat "$TASK_STATE/pid")" 2>/dev/null; then
    echo STATE=RUNNING
  else echo STATE=NOT_RUNNING; fi
  test ! -f "$TASK_STATE/run.log" || tail -n 25 "$TASK_STATE/run.log"
  test ! -f "$TASK_STATE/stage" || cat "$TASK_STATE/stage"
  exit 0;;
start)
  exec 9>"$TASK_STATE/start.lock"; flock -x 9
  if test -f "$TASK_STATE/pid"; then bash logic_synth/scripts/job.sh status; exit; fi
  nohup setsid bash logic_synth/scripts/job.sh worker </dev/null >"$TASK_STATE/run.log" 2>&1 8>&- 9>&- &
  echo $! >"$TASK_STATE/pid"
  echo "STARTED PID=$(cat "$TASK_STATE/pid")"; exit 0;;
worker) ;;
*) exit 2;;
esac
finish() { result=$?; trap - EXIT; echo "$result" >"$TASK_STATE/exit_code.tmp"; mv "$TASK_STATE/exit_code.tmp" "$TASK_STATE/exit_code"; }
trap finish EXIT
test "$(id -un)" = 7902_13; test "$(hostname)" = IC
sha256sum -c SOURCE_SHA256SUMS >"$TASK_STATE/source_verify.log"
test ! -r /etc/profile.d/eda.sh || . /etc/profile.d/eda.sh
. "$TASK_ROOT/job_config.sh"
if test -n "$AFTER_DIR"; then
  echo "WAITING_FOR=$AFTER_DIR" | tee "$TASK_STATE/stage"
  while test ! -f "$AFTER_DIR/job_state/exit_code"; do
    test -f "$AFTER_DIR/job_state/pid" && kill -0 "$(cat "$AFTER_DIR/job_state/pid")" 2>/dev/null || { echo 'DEPENDENCY_INTERRUPTED'; exit 3; }
    sleep 15
  done
  test "$(cat "$AFTER_DIR/job_state/exit_code")" = 0 || { echo 'DEPENDENCY_FAILED'; exit 3; }
fi
export CORE_TOP BASE_DDC PROBE_DIR MAX_CORES SYNTH_MODE REPAIR_CHANNEL BASE_IS_SS
cd logic_synth
mkdir -p output reports logs build
sha256sum /home/share/libs/tsmc28/logic/selected_db/*.db >"$TASK_STATE/library.sha256"
echo "EDA_TOP=$CORE_TOP" | tee "$TASK_STATE/stage"
if test "$CORE_TOP" = pad_probe_pt; then
  for PT_CORNER in SS FF; do
    export PT_CORNER
    timeout -s KILL 600 pt_shell -f scripts/probe_pt.tcl >"logs/probe_pt_$PT_CORNER.log" 2>&1
    if grep -E '(^Error:|^FATAL:)' "logs/probe_pt_$PT_CORNER.log"; then exit 1;fi
    grep -q PT_PROBE_SDF3_WRITTEN "logs/probe_pt_$PT_CORNER.log"
  done
  cp output/pad_probe/probe_SS.sdf output/pad_probe/probe_ss.sdf
  exit 0
fi
if test "$CORE_TOP" = hier_power_probe; then
  timeout -s KILL 600 dc_shell -f scripts/hier_power_probe.tcl >logs/hier_power.log 2>&1
  if grep -E '(^Error:|^FATAL:)' logs/hier_power.log; then exit 1;fi
  grep -q HIER_POWER_PROBE_DONE logs/hier_power.log
  exit 0
fi
if test "$CORE_TOP" = pad_delay_probe; then
  timeout -s KILL 600 dc_shell -f scripts/delay_probe.tcl >logs/delay_probe.log 2>&1
  if grep -E '(^Error:|^FATAL:)' logs/delay_probe.log; then exit 1;fi
  grep -q DELAY_PROBE_DONE logs/delay_probe.log
  exit 0
fi
if test "$CORE_TOP" = pad_probe_repair; then
  timeout -s KILL 600 dc_shell -f scripts/pad_repair.tcl >logs/pad_probe.log 2>&1
  if grep -E '(^Error:|^FATAL:)' logs/pad_probe.log; then exit 1;fi
  grep -q 'PAD_PROBE_REPAIRED' logs/pad_probe.log
  exit 0
fi
if test "$CORE_TOP" = pad_probe_gls; then
  test -r "$PROBE_DIR/probe.v";test -r "$PROBE_DIR/probe_ss.sdf"
  cp "$PROBE_DIR/probe.v" output/probe.v
  cp "$PROBE_DIR/probe_ss.sdf" output/probe.sdf
  CORE_MODEL=/home/share/libs/tsmc28/logic/verilog/extracted/TSMCHOME/digital/Front_End/verilog/tcbn28hpcplusbwp40p140_110a/tcbn28hpcplusbwp40p140_pwr.v
  PAD_MODEL=/home/share/libs/tsmc28/pad/simulation_vlg/TSMCHOME/digital/Front_End/verilog/tphn28hpcpgv18_110a/tphn28hpcpgv18_pwr.v
  timeout -s KILL 600 vcs -full64 -sverilog -debug_pp -negdelay +neg_tchk +define+NTC+RECREM -timescale=1ns/1ps "$CORE_MODEL" "$PAD_MODEL" output/probe.v sim/pad_probe_gls.sv -top tb_probe -o build/simv_probe >logs/probe_gls_compile.log 2>&1
  for mode in MAX MIN; do
    if test "$mode" = MIN && test -f "$PROBE_DIR/probe_FF.sdf"; then cp "$PROBE_DIR/probe_FF.sdf" output/probe.sdf;fi
    timeout -s KILL 60 ./build/simv_probe "+$mode" >"logs/probe_gls_$mode.log" 2>&1
    grep -q 'TEST PASSED' "logs/probe_gls_$mode.log"
    if grep -Ei '(BUS CONFLICT|Abnormal Pattern|Fatal:|Error:|Timing violation|Warning.*SDF)' "logs/probe_gls_$mode.log"; then exit 1;fi
  done
  if grep -E 'Total (errors|warnings):[[:space:]]*[1-9]' logs/probe_sdf_*.log; then exit 1;fi
  exit 0
fi
if test "$CORE_TOP" = bds_bb_6ch_pad_top; then
  test -r "$BASE_DDC"
  sha256sum "$BASE_DDC" >"$TASK_STATE/base_ddc.sha256"
  /usr/bin/time -v timeout -s KILL 7200 dc_shell -f scripts/synth.tcl >logs/full_dc.log 2>&1
  if grep -E '(^Error:|^FATAL:)' logs/full_dc.log; then exit 1; fi
  grep -q 'CANDIDATE_MAPPED unmapped=0' logs/full_dc.log
  exit 0
fi
if test "$CORE_TOP" = pad_connectivity; then
  PAD_MODEL=/home/share/libs/tsmc28/pad/simulation_vlg/TSMCHOME/digital/Front_End/verilog/tphn28hpcpgv18_110a/tphn28hpcpgv18_pwr.v
  /usr/bin/time -v timeout -s KILL 600 vcs -full64 -sverilog -debug_pp -timescale=1ns/1ps -f rtl/core.f rtl/bds_bb_6ch_pad_top.sv "$PAD_MODEL" sim/pad_connectivity.sv -top tb_pad_connectivity -o build/simv_pad >logs/pad_compile.log 2>&1
  timeout -s KILL 60 ./build/simv_pad >logs/pad_run.log 2>&1
  grep -q 'TEST PASSED' logs/pad_run.log
  if grep -E '(BUS CONFLICT|Abnormal Pattern|Fatal:|Error:)' logs/pad_run.log; then exit 1; fi
  exit 0
fi
if test "$CORE_TOP" = pad_probe; then
  /usr/bin/time -v timeout -s KILL 600 dc_shell -f scripts/pad_probe.tcl >logs/pad_probe.log 2>&1
  if grep -E '(^Error:|^FATAL:)' logs/pad_probe.log; then exit 1; fi
  grep -q 'PAD_PROBE_MAPPED' logs/pad_probe.log
  exit 0
fi
if test "$CORE_TOP" = pad_six_signal; then
  PAD_MODEL=/home/share/libs/tsmc28/pad/simulation_vlg/TSMCHOME/digital/Front_End/verilog/tphn28hpcpgv18_110a/tphn28hpcpgv18_pwr.v
  /usr/bin/time -v timeout -s KILL 600 vcs -full64 -sverilog -debug_pp -timescale=1ns/1ps -f rtl/core.f rtl/bds_bb_6ch_pad_top.sv "$PAD_MODEL" sim/tb.sv -top tb -o build/simv_pad >logs/pad_six_compile.log 2>&1
  /usr/bin/time -v timeout -s KILL 1200 ./build/simv_pad >logs/pad_six_run.log 2>&1
  grep -q 'TEST PASSED' logs/pad_six_run.log
  if grep -E '(BUS CONFLICT|Abnormal Pattern|Fatal:|Error:)' logs/pad_six_run.log; then exit 1; fi
  exit 0
fi
if test "${MEMORY_LIMIT_MB:-0}" -gt 0; then ulimit -v $((MEMORY_LIMIT_MB * 1024));fi
TASK_DC_SCRIPT=scripts/synth_core.tcl
if test "$CORE_TOP" = channel_hold_repair; then
  test -r "$BASE_DDC"
  sha256sum "$BASE_DDC" >"$TASK_STATE/base_ddc.sha256"
  TASK_DC_SCRIPT=scripts/fix_channel_hold.tcl
fi
/usr/bin/time -v timeout -s KILL 7200 dc_shell -f "$TASK_DC_SCRIPT" >logs/core_dc.log 2>&1 &
TASK_EDA_PID=$!
# Stop only this newly submitted EDA task if system headroom becomes small.
(
  while kill -0 "$TASK_EDA_PID" 2>/dev/null; do
    TASK_FREE_MB=$(awk '/MemFree:|Buffers:|^Cached:/ {s+=$2} END {print int(s/1024)}' /proc/meminfo)
    if test "$TASK_FREE_MB" -lt 768; then
      echo "MEMORY_GUARD free_mb=$TASK_FREE_MB" >"$TASK_STATE/memory_guard.txt"
      # time -> timeout -> DC. Signal timeout so it forwards TERM to its DC group.
      pkill -TERM -P "$TASK_EDA_PID" 2>/dev/null || true
      exit
    fi
    sleep 5
  done
) &
TASK_GUARD_PID=$!
set +e
wait "$TASK_EDA_PID"
TASK_EDA_EXIT=$?
set -e
kill "$TASK_GUARD_PID" 2>/dev/null || true
test "$TASK_EDA_EXIT" = 0 || exit "$TASK_EDA_EXIT"
if grep -E '(^Error:|^FATAL:)' logs/core_dc.log; then exit 1; fi
if test "$CORE_TOP" = channel_hold_repair; then
  grep -q CHANNEL_HOLD_REPAIR_DONE logs/core_dc.log
else
  grep -q 'CORE_MAPPING_DONE.*unmapped=0' logs/core_dc.log
fi
