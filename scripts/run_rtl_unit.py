"""编译并运行 RTL 单元/系统测试。

用法:
  python scripts/run_rtl_unit.py                    # 全部（自动选仿真器）
  python scripts/run_rtl_unit.py unpacker           # 只跑名字包含 unpacker 的用例
  python scripts/run_rtl_unit.py --sim modelsim     # 指定：vcs / modelsim / vivado / iverilog
  python scripts/run_rtl_unit.py --list             # 列出用例

仿真器自动选择顺序：VCS > ModelSim/Questa > Vivado xsim > Icarus。
源文件清单唯一来源是 rtl/filelist.f 与 tb/filelist.f。
约定：testbench 顶层模块名 = 文件名；通过时打印 "TEST PASSED"。
带 "slow" 标记的用例（tb/filelist.f 行尾 `// slow`）在 --quick 时跳过。
"""

from __future__ import annotations

import os
import argparse
import re
import subprocess
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import ROOT, REPORTS_DIR, bootstrap, env_banner, write_json  # noqa: E402
import rtl_tools  # noqa: E402

bootstrap()

BUILD = os.path.join(REPORTS_DIR, "build")
SIMDIR = os.path.join(REPORTS_DIR, "sim")
RTL_FILELIST = os.path.join(ROOT, "rtl", "filelist.f")
TB_FILELIST = os.path.join(ROOT, "tb", "filelist.f")
INC_DIRS = ["rtl/include", "rtl/common"]

#: 单个用例的仿真墙钟上限（秒）。挂死的 testbench 会被判失败而不是卡住整个套件。
SIM_TIMEOUT_S = int(os.environ.get("RTL_SIM_TIMEOUT_S", "600"))
if SIM_TIMEOUT_S < 1:
    raise ValueError("RTL_SIM_TIMEOUT_S must be positive")


def parse_filelist(path: str) -> list:
    """返回 [(相对路径, 标记集合)]，忽略 +incdir 与注释行。"""
    out = []
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("//") or line.startswith("+"):
                continue
            body, _, comment = line.partition("//")
            tags = set(comment.split())
            out.append((body.strip(), tags))
    return out


def rtl_sources() -> list:
    return [p for p, _ in parse_filelist(RTL_FILELIST)]


def tb_entries() -> list:
    return parse_filelist(TB_FILELIST)


def _run(cmd, timeout, cwd=ROOT):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=timeout)


def _judge(res: dict, log: str, rc: int) -> None:
    res["run_log"] = log
    res["run_ok"] = rc == 0
    res["passed"] = ("TEST PASSED" in log) and ("TEST FAILED" not in log) and rc == 0


# ---------------------------------------------------------------- VCS
def run_one_vcs(tb: str, vcs: str) -> dict:
    name = os.path.splitext(os.path.basename(tb))[0]
    out = os.path.join(BUILD, "simv_" + name)
    csrc = os.path.join(BUILD, "csrc_" + name)
    os.makedirs(csrc, exist_ok=True)
    cmd = [vcs, "-full64", "-sverilog", "+v2k", "-timescale=1ns/1ps",
           "-Mdir", csrc, "-o", out, "-f", RTL_FILELIST, "-top", name, tb]
    cmd += ["+incdir+" + d for d in INC_DIRS]
    comp = _run(cmd, 900)
    res = {"name": name, "tb": tb, "tool": "vcs", "compile_ok": comp.returncode == 0,
           "compile_log": (comp.stdout or "") + (comp.stderr or ""),
           "run_ok": False, "passed": False, "run_log": "", "seconds": 0.0}
    if not res["compile_ok"]:
        return res
    t0 = datetime.now()
    try:
        sim = _run([out], SIM_TIMEOUT_S)
        _judge(res, (sim.stdout or "") + (sim.stderr or ""), sim.returncode)
    except subprocess.TimeoutExpired:
        res["run_log"] = f"<<仿真超时 {SIM_TIMEOUT_S}s，按失败处理>>"
    res["seconds"] = (datetime.now() - t0).total_seconds()
    return res


# ---------------------------------------------------------------- ModelSim
class ModelSim:
    """一次性把全部 RTL + TB 编进同一个 work 库，再逐个 vsim -c 运行。"""

    def __init__(self, tools):
        self.vlib, self.vlog, self.vsim = tools
        self.lib = "reports/sim/msim/work"     # 相对 ROOT；vsim 不接受带反斜杠的绝对库路径
        self.compile_log = ""
        self.compile_ok = False

    def compile(self, tbs: list) -> bool:
        os.makedirs(os.path.join(ROOT, os.path.dirname(self.lib)), exist_ok=True)
        if not os.path.isdir(os.path.join(ROOT, self.lib)):
            _run([self.vlib, self.lib], 120)
        cmd = [self.vlog, "-sv", "-work", self.lib, "-timescale", "1ns/1ps",
               "-suppress", "2583"]
        cmd += ["+incdir+" + d for d in INC_DIRS]
        cmd += rtl_sources() + tbs
        comp = _run(cmd, 900)
        self.compile_log = (comp.stdout or "") + (comp.stderr or "")
        self.compile_ok = comp.returncode == 0 and "** Error" not in self.compile_log
        return self.compile_ok

    def run(self, tb: str) -> dict:
        name = os.path.splitext(os.path.basename(tb))[0]
        res = {"name": name, "tb": tb, "tool": "modelsim", "compile_ok": self.compile_ok,
               "compile_log": "" if self.compile_ok else self.compile_log,
               "run_ok": False, "passed": False, "run_log": "", "seconds": 0.0}
        if not self.compile_ok:
            return res
        t0 = datetime.now()
        cmd = [self.vsim, "-c", "-lib", self.lib, name, "-do",
               "onfinish exit; run -all; quit -f"]
        try:
            sim = _run(cmd, SIM_TIMEOUT_S)
            log = (sim.stdout or "") + (sim.stderr or "")
            rc = sim.returncode
            if re.search(r"\*\* (Fatal|Error)", log):
                rc = rc or 1
            _judge(res, log, rc)
        except subprocess.TimeoutExpired:
            res["run_log"] = f"<<仿真超时 {SIM_TIMEOUT_S}s，按失败处理>>"
        res["seconds"] = (datetime.now() - t0).total_seconds()
        return res


# ---------------------------------------------------------------- Vivado xsim
def run_one_xsim(tb: str, tools) -> dict:
    xvlog, xelab, xsim = tools
    name = os.path.splitext(os.path.basename(tb))[0]
    work = os.path.join(SIMDIR, "xsim", name)
    os.makedirs(work, exist_ok=True)
    cmd = [xvlog, "-sv", "--include", "rtl/include", "--include", "rtl/common"]
    cmd += rtl_sources() + [tb]
    comp = _run(cmd, 900, cwd=ROOT)
    # xvlog 把工作库写在 cwd；改到 work 下再编一次
    res = {"name": name, "tb": tb, "tool": "vivado", "compile_ok": comp.returncode == 0,
           "compile_log": (comp.stdout or "") + (comp.stderr or ""),
           "run_ok": False, "passed": False, "run_log": "", "seconds": 0.0}
    if not res["compile_ok"]:
        return res
    elab = _run([xelab, name, "-s", name + "_sim", "-timescale", "1ns/1ps"], 900)
    res["compile_log"] += (elab.stdout or "") + (elab.stderr or "")
    res["compile_ok"] = elab.returncode == 0
    if not res["compile_ok"]:
        return res
    t0 = datetime.now()
    try:
        sim = _run([xsim, name + "_sim", "-runall"], SIM_TIMEOUT_S)
        _judge(res, (sim.stdout or "") + (sim.stderr or ""), sim.returncode)
    except subprocess.TimeoutExpired:
        res["run_log"] = f"<<仿真超时 {SIM_TIMEOUT_S}s，按失败处理>>"
    res["seconds"] = (datetime.now() - t0).total_seconds()
    return res


# ---------------------------------------------------------------- Icarus
def run_one_iverilog(tb: str, iv: str, vp: str) -> dict:
    name = os.path.splitext(os.path.basename(tb))[0]
    out = os.path.join(BUILD, name + ".vvp")
    cmd = [iv, "-g2012", "-s", name, "-o", out] + sum((["-I", d] for d in INC_DIRS), [])
    cmd += rtl_sources() + [tb]
    comp = _run(cmd, 600)
    res = {"name": name, "tb": tb, "tool": "iverilog", "compile_ok": comp.returncode == 0,
           "compile_log": (comp.stdout or "") + (comp.stderr or ""),
           "run_ok": False, "passed": False, "run_log": "", "seconds": 0.0}
    if not res["compile_ok"]:
        return res
    t0 = datetime.now()
    try:
        sim = _run([vp, out], SIM_TIMEOUT_S)
        _judge(res, (sim.stdout or "") + (sim.stderr or ""), sim.returncode)
    except subprocess.TimeoutExpired:
        res["run_log"] = f"<<仿真超时 {SIM_TIMEOUT_S}s，按失败处理>>"
    res["seconds"] = (datetime.now() - t0).total_seconds()
    return res


def pick_sim(want: str | None) -> str:
    if want:
        return want
    if rtl_tools.vcs():
        return "vcs"
    if rtl_tools.modelsim():
        return "modelsim"
    if rtl_tools.vivado():
        return "vivado"
    return "iverilog"


def parse_args(args):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("filter", nargs="?", default="")
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--sim", choices=("vcs", "modelsim", "vivado", "iverilog"))
    return parser.parse_args(args)


def result_path(sim: str, filt: str = "", quick: bool = False) -> str:
    # 定向/快速检查不覆盖完整回归结果，避免把 1/1 误当成全套通过。
    suffix = re.sub(r"[^A-Za-z0-9_-]", "_", filt) if filt else ("quick" if quick else "")
    name = f"rtl_unit_results_{sim}_{suffix}.json" if suffix else "rtl_unit_results.json"
    return os.path.join(REPORTS_DIR, name)


def main(argv) -> int:
    args = parse_args(argv[1:])
    quick, want = args.quick, args.sim
    entries = tb_entries()
    if args.list:
        for tb, tags in entries:
            print(f"  {os.path.splitext(os.path.basename(tb))[0]:<28} {' '.join(sorted(tags))}")
        return 0
    filt = args.filter
    os.makedirs(BUILD, exist_ok=True)

    selected = []
    for tb, tags in entries:
        base = os.path.basename(tb)
        if filt and filt not in base:
            continue
        if quick and "slow" in tags and not filt:
            continue
        selected.append(tb)

    if not selected:
        print(f"未找到匹配的 RTL 用例: {filt!r}")
        return 1
    sim = pick_sim(want)
    results = []
    if sim == "vcs":
        vcs = rtl_tools.vcs()
        print(f"仿真器  : VCS ({vcs})")
        runner = lambda tb: run_one_vcs(tb, vcs)  # noqa: E731
    elif sim == "modelsim":
        tools = rtl_tools.modelsim()
        if not tools:
            raise SystemExit("未找到 ModelSim（vlib/vlog/vsim），可设置 MODELSIM_HOME")
        print(f"仿真器  : ModelSim ({tools[2]})")
        ms = ModelSim(tools)
        if not ms.compile([tb for tb, _ in entries]):
            print("编译失败：")
            errs = [ln.strip() for ln in ms.compile_log.splitlines() if "Error" in ln]
            for line in errs[:20]:
                print("    " + line)
        runner = ms.run
    elif sim == "vivado":
        tools = rtl_tools.vivado()
        if not tools:
            raise SystemExit("未找到 Vivado xsim（xvlog/xelab/xsim），可设置 XILINX_VIVADO")
        print(f"仿真器  : Vivado xsim ({tools[2]})")
        runner = lambda tb: run_one_xsim(tb, tools)  # noqa: E731
    else:
        iv, vp = rtl_tools.require()
        print(f"仿真器  : Icarus ({rtl_tools.version(iv)})")
        runner = lambda tb: run_one_iverilog(tb, iv, vp)  # noqa: E731

    for tb in selected:
        r = runner(tb)
        results.append(r)
        mark = "PASS" if r["passed"] else ("COMPILE-FAIL" if not r["compile_ok"] else "FAIL")
        print(f"  [{mark:<12}] {r['name']:<28} {r['seconds']:8.2f}s", flush=True)

    n_pass = sum(1 for r in results if r["passed"])
    print("-" * 60)
    print(f"RTL 用例: {n_pass}/{len(results)} 通过")
    report = {"banner": env_banner(), "simulator": sim,
              "total": len(results), "passed": n_pass, "results": results}
    path = result_path(sim, filt, quick)
    write_json(path, report)
    print(f"测试结果: {path}")
    for r in results:
        if not r["passed"]:
            print(f"\n--- {r['name']} 输出尾部 ---")
            print("\n".join((r["compile_log"] + r["run_log"]).splitlines()[-30:]))
    return 0 if results and n_pass == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
