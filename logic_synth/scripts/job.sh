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
export CORE_TOP
cd logic_synth
mkdir -p output reports logs
sha256sum /home/share/libs/tsmc28/logic/selected_db/*.db >"$TASK_STATE/library.sha256"
/usr/bin/time -v timeout -s KILL 7200 dc_shell -f scripts/synth_core.tcl >logs/core_dc.log 2>&1
if grep -E '(^Error:|^FATAL:)' logs/core_dc.log; then exit 1; fi
grep -q 'CORE_MAPPING_DONE.*unmapped=0' logs/core_dc.log
