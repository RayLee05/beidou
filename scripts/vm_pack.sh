#!/usr/bin/env bash
# 打包仓库给虚拟机 IC（虚拟机无 git）。用 Git Bash 运行：bash scripts/vm_pack.sh <out.tgz>
# 只收 git 跟踪 + 未忽略的文件；排除教师信号包、课程材料与 PDF。
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-/tmp/beidou_sync.tgz}"
list="$(mktemp)"
git ls-files -co --exclude-standard \
  | grep -v -E '^(student_rease/|references/|VM-IC-SSH)' \
  | grep -v -E '\.pdf$' \
  | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done > "$list"
tar -czf "$out" -T "$list"
echo "files=$(wc -l < "$list") entries=$(tar -tzf "$out" | wc -l) bytes=$(stat -c %s "$out")"
rm -f "$list"
