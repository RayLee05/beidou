#!/usr/bin/env bash
set -eo pipefail
test "$(id -un)" = 7902_13; test "$(hostname)" = IC
date -u; hostname; whoami; free -m
for root in /home/share/libs/tsmc28 /home/user002/Public/TSMC28 /home/user002/Public/lib2; do
  echo "ROOT=$root"
  if test ! -r "$root" || test ! -x "$root"; then echo UNAVAILABLE; continue; fi
  find "$root" -type f \( -iname '*.v' -o -iname '*.sv' -o -iname '*.vp' -o -iname '*.v.gz' \)
  find "$root" -type f \( -iname '*.db' -o -iname '*.lib' -o -iname '*.tar.gz' -o -iname '*.zip' \) \
    | grep -Ei 'gpio|(^|/|_)io|pad|verilog|frontend|front_end' || true
done
echo AUDIT_COMPLETE
