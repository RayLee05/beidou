"""编译并运行 RTL 单元/系统测试（Icarus Verilog）。

用法:
  python scripts/run_rtl_unit.py             # 全部
  python scripts/run_rtl_unit.py unpacker    # 只跑名字包含 unpacker 的用例

约定：每个 testbench 顶层模块名 = 文件名（去掉 tb_ 前缀）；通过时打印 "TEST PASSED"。
"""

from __future__ import annotations

import glob
import os
import re
import subprocess
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import ROOT, REPORTS_DIR, bootstrap, env_banner, write_json, write_text  # noqa: E402
import rtl_tools  # noqa: E402

bootstrap()

BUILD = os.path.join(REPORTS_DIR, "build")
RTL_DIRS = [os.path.join(ROOT, "rtl", "include"), os.path.join(ROOT, "rtl", "common"),
            os.path.join(ROOT, "rtl", "track"), os.path.join(ROOT, "rtl", "acq")]
TB_DIRS = [os.path.join(ROOT, "tb", "unit"), os.path.join(ROOT, "tb", "system")]

#: 单个用例的仿真墙钟上限（秒）。挂死的 testbench 会被判失败而不是卡住整个套件。
SIM_TIMEOUT_S = 120


def rtl_sources() -> list:
    files = []
    for d in RTL_DIRS:
        files += sorted(glob.glob(os.path.join(d, "*.sv")))
    return files


def tb_sources() -> list:
    files = []
    for d in TB_DIRS:
        files += sorted(glob.glob(os.path.join(d, "*.sv")))
    return files


def run_one_vcs(tb: str, vcs: str, inc_dirs: list) -> dict:
    """用 Synopsys VCS 编译并运行（虚拟机 IC 上的主用流程）。"""
    name = os.path.splitext(os.path.basename(tb))[0]
    out = os.path.join(BUILD, "simv_" + name)
    csrc = os.path.join(BUILD, "csrc_" + name)
    os.makedirs(csrc, exist_ok=True)
    cmd = [vcs, "-full64", "-sverilog", "+v2k", "-timescale=1ns/1ps",
           "-Mdir", csrc, "-o", out,
           "-f", os.path.join(ROOT, "rtl", "filelist.f"),
           "-top", name, tb]
    for d in inc_dirs:
        cmd.append("+incdir+" + d)
    comp = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=900)
    res = {"name": name, "tb": os.path.relpath(tb, ROOT), "tool": "vcs",
           "compile_ok": comp.returncode == 0,
           "compile_log": (comp.stdout or "") + (comp.stderr or ""),
           "run_ok": False, "passed": False, "run_log": "", "seconds": 0.0}
    if comp.returncode != 0:
        return res
    t0 = datetime.now()
    try:
        sim = subprocess.run([out], cwd=ROOT, capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=SIM_TIMEOUT_S)
        res["run_log"] = (sim.stdout or "") + (sim.stderr or "")
        res["run_ok"] = sim.returncode == 0
        res["passed"] = ("TEST PASSED" in res["run_log"]) and sim.returncode == 0 \
                        and ("TEST FAILED" not in res["run_log"])
    except subprocess.TimeoutExpired:
        res["run_log"] = f"<<仿真超时 {SIM_TIMEOUT_S}s，按失败处理>>"
        res["passed"] = False
    res["seconds"] = (datetime.now() - t0).total_seconds()
    return res


def run_one(tb: str, iv: str, vp: str, inc_dirs: list) -> dict:
    name = os.path.splitext(os.path.basename(tb))[0]
    out = os.path.join(BUILD, name + ".vvp")
    cmd = [iv, "-g2012", "-Wall", "-o", out]
    for d in inc_dirs:
        cmd += ["-I", d]
    cmd += rtl_sources()
    cmd += [tb]
    comp = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=600)
    res = {"name": name, "tb": os.path.relpath(tb, ROOT),
           "compile_ok": comp.returncode == 0,
           "compile_log": (comp.stdout or "") + (comp.stderr or ""),
           "run_ok": False, "passed": False, "run_log": "", "seconds": 0.0}
    if comp.returncode != 0:
        return res
    t0 = datetime.now()
    sim = subprocess.run([vp, out], cwd=ROOT, capture_output=True, text=True,
                         encoding="utf-8", errors="replace", timeout=1800)
    res["seconds"] = (datetime.now() - t0).total_seconds()
    res["run_log"] = (sim.stdout or "") + (sim.stderr or "")
    res["run_ok"] = sim.returncode == 0
    res["passed"] = ("TEST PASSED" in res["run_log"]) and sim.returncode == 0                     and ("TEST FAILED" not in res["run_log"])
    return res


def main(argv) -> int:
    filt = argv[1] if len(argv) > 1 else ""
    os.makedirs(BUILD, exist_ok=True)
    use_vcs = rtl_tools.vcs()
    iv = vp = None
    if use_vcs:
        print(f"仿真器  : VCS ({use_vcs})")
    else:
        iv, vp = rtl_tools.require()
        print(f"iverilog: {iv}")
        print(f"版本    : {rtl_tools.version(iv)}")

    inc_dirs = [os.path.join(ROOT, "rtl", "include"), os.path.join(ROOT, "rtl", "common")]
    results = []
    for tb in tb_sources():
        if filt and filt not in os.path.basename(tb):
            continue
        r = (run_one_vcs(tb, use_vcs, inc_dirs) if use_vcs
             else run_one(tb, iv, vp, inc_dirs))
        results.append(r)
        mark = "PASS" if r["passed"] else ("COMPILE-FAIL" if not r["compile_ok"] else "FAIL")
        print(f"  [{mark:<12}] {r['name']:<24} {r['seconds']:.2f}s")
        if not r["compile_ok"]:
            for line in r["compile_log"].splitlines():
                if re.search(r"error|Error", line):
                    print("      " + line.strip())

    n_pass = sum(1 for r in results if r["passed"])
    print("-" * 60)
    print(f"RTL 用例: {n_pass}/{len(results)} 通过")
    report = {"banner": env_banner(),
              "simulator": "vcs" if use_vcs else rtl_tools.version(iv),
              "total": len(results), "passed": n_pass, "results": results}
    write_json(os.path.join(REPORTS_DIR, "rtl_unit_results.json"), report)
    print(f"报告: {os.path.join(REPORTS_DIR, 'rtl_unit_results.json')}")
    for r in results:
        if not r["passed"]:
            print(f"\n--- {r['name']} 输出尾部 ---")
            print("\n".join((r["compile_log"] + r["run_log"]).splitlines()[-25:]))
    return 0 if n_pass == len(results) and results else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
