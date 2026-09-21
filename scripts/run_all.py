"""统一运行入口：一条命令跑完全部自动化检查并留存日志。

用法:
  python scripts/run_all.py            # 全部检查
  python scripts/run_all.py --quick    # 跳过绘图（无 matplotlib 时）

每个阶段结束都应运行本脚本，并把 reports/logs/ 下的日志纳入交付证据。
"""

from __future__ import annotations

import glob
import os
import subprocess
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import LOGS_DIR, ROOT, bootstrap, env_banner, git_revision, git_dirty  # noqa: E402

bootstrap()

#: `reports/logs/` 中保留的历史运行日志份数（超出自动清理，避免仓库堆积）
KEEP_LOGS = 5


def prune_logs(keep: int = KEEP_LOGS) -> list:
    """删除最旧的运行日志，只保留最近 keep 份。返回被删除的文件名列表。"""
    logs = sorted(glob.glob(os.path.join(LOGS_DIR, "run_all-*.log")), reverse=True)
    removed = []
    for path in logs[keep:]:
        try:
            os.remove(path)
            removed.append(os.path.basename(path))
        except OSError:
            pass
    return removed


STEPS = [
    ("环境与工具链", "scripts/check_env.py", []),
    ("参数一致性", "scripts/check_params_consistency.py", []),
    ("定点与周期预算", "scripts/fixed_point_budget.py", []),
    ("架构图", "scripts/make_architecture_figure.py", ["--quick"]),
]


def main(argv) -> int:
    quick = "--quick" in argv
    banner = env_banner()
    results = []
    log_lines = []

    for name, script, skip_flags in STEPS:
        if quick and skip_flags:
            results.append((name, "SKIP", 0.0))
            log_lines.append(f"--- SKIP {name} ---")
            continue
        t0 = datetime.now()
        proc = subprocess.run(
            [sys.executable, os.path.join(ROOT, script)] + [a for a in argv[1:] if a.startswith("--") and a != "--quick"],
            cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
        dt = (datetime.now() - t0).total_seconds()
        status = "PASS" if proc.returncode == 0 else f"FAIL({proc.returncode})"
        results.append((name, status, dt))
        log_lines.append(f"--- {name} [{status}] {dt:.2f}s ---")
        log_lines.append(proc.stdout or "")
        if proc.stderr:
            log_lines.append("[stderr]\n" + proc.stderr)

    ok = all(s == "PASS" or s == "SKIP" for _, s, _ in results)

    print("=" * 68)
    print("北斗 B1I 基带处理器 · 统一运行入口")
    print("=" * 68)
    print(f"workspace      : {ROOT}")
    print(f"generated_at   : {banner['generated_at']}")
    print(f"python         : {banner['python']}")
    print(f"git revision   : {git_revision()} (dirty={git_dirty()})")
    print("-" * 68)
    for name, status, dt in results:
        print(f"  {status:<9} {name:<16} {dt:6.2f}s")
    print("-" * 68)
    print(f"结论: {'全部通过' if ok else '存在失败项'}")

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    os.makedirs(LOGS_DIR, exist_ok=True)
    log_path = os.path.join(LOGS_DIR, f"run_all-{stamp}.log")
    header = "\n".join(f"{k}: {v}" for k, v in banner.items())
    with open(log_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(header + "\n\n" + "\n".join(log_lines))
    print(f"日志: {log_path}")
    for name in prune_logs():
        print(f"已清理旧日志: {name}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
