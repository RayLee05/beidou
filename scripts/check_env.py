"""输出环境与工具链版本，供证据记录使用。

用法: python scripts/check_env.py
"""

from __future__ import annotations

import importlib.util
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import ROOT, env_banner  # noqa: E402

PY_MODULES = ["numpy", "matplotlib", "pypdf", "fitz", "scipy", "pytest"]
BINARIES = ["git", "python", "node", "iverilog", "verilator", "yosys",
            "vcs", "xrun", "vlog", "dc_shell", "genus", "innovus"]


def main() -> int:
    banner = env_banner()
    print("== 环境 ==")
    for k, v in banner.items():
        print(f"  {k:<16}: {v}")
    print(f"  {'workspace':<16}: {ROOT}")

    print("== Python 模块 ==")
    for m in PY_MODULES:
        print(f"  {m:<16}: {'OK' if importlib.util.find_spec(m) else 'MISSING'}")

    print("== 外部工具 ==")
    for b in BINARIES:
        p = shutil.which(b)
        print(f"  {b:<16}: {p or 'MISSING'}")

    print("== 结论 ==")
    print("  RTL 仿真器/综合器缺失不阻塞 P0/P1（架构与定点设计）阶段；")
    print("  进入 P2（单通道 RTL）前必须在 docs/status.md 记录所选工具与版本。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
