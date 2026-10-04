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


def vcs() -> str | None:
    """Synopsys VCS（虚拟机里是主用仿真器）。"""
    return find_tool("vcs")


def vcs_home() -> str | None:
    return os.environ.get("VCS_HOME")


MODELSIM_DIRS = [
    "C:\\modeltech64_2020.4\\win64",
    "C:\\modeltech64_10.6c\\win64",
    "C:\\modeltech64_10.7\\win64",
    "C:\\questasim64_2021.1\\win64",
    "C:\\intelFPGA\\20.1\\modelsim_ase\\win32aloem",
    "C:\\altera\\13.0sp1\\modelsim_ase\\win32aloem",
    "D:\\modeltech64_2020.4\\win64",
    "E:\\modeltech64_2020.4\\win64",
    "E:\\intelFPGA\\20.1\\modelsim_ase\\win32aloem",
]


def modelsim() -> tuple | None:
    """返回 (vlib, vlog, vsim)；找不到返回 None。环境变量 MODELSIM_HOME 优先。"""
    dirs = []
    home = os.environ.get("MODELSIM_HOME")
    if home:
        dirs += [home, os.path.join(home, "win64"), os.path.join(home, "bin")]
    found = shutil.which("vsim")
    if found:
        dirs.insert(0, os.path.dirname(found))
    dirs += MODELSIM_DIRS
    for d in dirs:
        tools = tuple(os.path.join(d, n + EXE) for n in ("vlib", "vlog", "vsim"))
        if all(os.path.isfile(t) for t in tools):
            return tools
    return None


def _vivado_bin_dirs() -> list:
    dirs = []
    home = os.environ.get("XILINX_VIVADO") or os.environ.get("VIVADO_HOME")
    if home:
        dirs += [os.path.join(home, "bin"), home]
    found = shutil.which("xvlog") or shutil.which("xvlog.bat")
    if found:
        dirs.insert(0, os.path.dirname(found))
    roots = [
        "C:\\Xilinx\\Vivado",
        "D:\\Xilinx\\Vivado",
        "E:\\Xilinx\\Vivado",
        "E:\\fpga\\vivado\\Vivado",
        "C:\\fpga\\vivado\\Vivado",
        "C:\\Program Files\\Xilinx\\Vivado",
    ]
    for root in roots:
        if not os.path.isdir(root):
            continue
        try:
            vers = sorted(os.listdir(root), reverse=True)
        except OSError:
            continue
        for v in vers:
            dirs.append(os.path.join(root, v, "bin"))
    return dirs


def vivado() -> tuple | None:
    """返回 (xvlog, xelab, xsim)；找不到返回 None。"""
    for d in _vivado_bin_dirs():
        names = ("xvlog", "xelab", "xsim")
        tools = []
        ok = True
        for n in names:
            cand = os.path.join(d, n + EXE)
            if not os.path.isfile(cand):
                cand = os.path.join(d, n + ".bat")
            if not os.path.isfile(cand):
                ok = False
                break
            tools.append(cand)
        if ok:
            return tuple(tools)
    return None


def require() -> tuple:
    iv, vp = iverilog(), vvp()
    if not iv or not vp:
        raise SystemExit(
            "未找到 Icarus Verilog，也没找到 VCS。\n"
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
