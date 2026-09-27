"""定位 RTL 工具链（iverilog / vvp），让脚本在队友机器上也能跑。

查找顺序：
  1. 环境变量 IVERILOG_HOME（其 bin/ 下含 iverilog.exe）
  2. PATH 中的 iverilog / vvp
  3. 常见安装位置（Windows: E:\\iverilog\\app\\bin、C:\\iverilog\\bin、
     <repo>/.tools/iverilog/bin；Linux/macOS: /usr/bin）

说明：Icarus Verilog 是**本机开发工具**，不入库。安装方式见 docs/TRACKING_DESIGN.md 附录。
"""

from __future__ import annotations

import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import ROOT  # noqa: E402

EXE = ".exe" if os.name == "nt" else ""

CANDIDATE_DIRS = [
    os.path.join(ROOT, ".tools", "iverilog", "bin"),
    os.path.join(ROOT, ".tools", "iverilog", "app", "bin"),
    "E:\\iverilog\\app\\bin",
    "E:\\iverilog\\bin",
    "C:\\iverilog\\bin",
    "C:\\Program Files\\iverilog\\bin",
    "/usr/local/bin",
    "/usr/bin",
    "/opt/homebrew/bin",
]


def find_tool(name: str) -> str | None:
    home = os.environ.get("IVERILOG_HOME")
    if home:
        cand = os.path.join(home, "bin", name + EXE)
        if os.path.isfile(cand):
            return cand
        cand = os.path.join(home, name + EXE)
        if os.path.isfile(cand):
            return cand
    found = shutil.which(name)
    if found:
        return found
    for d in CANDIDATE_DIRS:
        cand = os.path.join(d, name + EXE)
        if os.path.isfile(cand):
            return cand
    return None


def iverilog() -> str | None:
    return find_tool("iverilog")


def vvp() -> str | None:
    return find_tool("vvp")


def require() -> tuple:
    iv, vp = iverilog(), vvp()
    if not iv or not vp:
        raise SystemExit(
            "未找到 Icarus Verilog。\n"
            "  - 设置环境变量 IVERILOG_HOME 指向安装目录，或\n"
            "  - 把 iverilog/vvp 加入 PATH，或\n"
            "  - 参见 docs/TRACKING_DESIGN.md 附录的安装步骤。"
        )
    return iv, vp


def version(iv_path: str) -> str:
    import subprocess
    try:
        out = subprocess.run([iv_path, "-V"], capture_output=True, text=True, timeout=20)
        return (out.stdout or out.stderr).splitlines()[0].strip()
    except Exception as exc:  # pragma: no cover
        return f"unknown ({exc})"
