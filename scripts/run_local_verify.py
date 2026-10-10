"""本机一键验证（不依赖 IC 虚拟机）。

默认：参数检查 + 快 RTL（ModelSim）+ 跟踪 L2 + 顶层冒烟 + 软件链路。
加 --acq 才跑 64 路捕获（约 2–3 分钟）。
加 --vivado 再跑 xsim 快用例。
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import REPORTS_DIR, ROOT, bootstrap  # noqa: E402
from run_rtl_unit import parse_args, result_path  # noqa: E402

bootstrap()
LOCAL = os.path.join(REPORTS_DIR, "local")


def run(args: list) -> int:
    print("+", " ".join(args), flush=True)
    return subprocess.call([sys.executable] + args, cwd=ROOT)


def main() -> int:
    acq = "--acq" in sys.argv
    xv = "--vivado" in sys.argv
    os.makedirs(LOCAL, exist_ok=True)
    rc = 0
    steps = [
        ["scripts/check_params_consistency.py"],
        ["scripts/run_rtl_unit.py", "--sim", "modelsim", "--quick"],
        ["scripts/run_rtl_unit.py", "--sim", "modelsim", "tracking_channel"],
        ["scripts/run_rtl_unit.py", "--sim", "modelsim", "b1i_rx_top"],
        ["scripts/run_local_chain.py", "--sec", "7", "--sats", "4"],
    ]
    if xv:
        steps.append(["scripts/run_rtl_unit.py", "--sim", "vivado", "--quick"])
    if acq:
        steps.append(["scripts/run_rtl_unit.py", "--sim", "modelsim", "acquisition"])
    for s in steps:
        r = run(s)
        if "run_rtl_unit" in s[0]:
            args = parse_args(s[1:])
            src = result_path(args.sim, args.filter, args.quick)
            if os.path.isfile(src):
                scope = args.filter or ("quick" if args.quick else "full")
                shutil.copy2(src, os.path.join(LOCAL, f"{args.sim}_{scope}.json"))
        rc |= r
    note = os.path.join(LOCAL, "last_run.txt")
    with open(note, "w", encoding="utf-8") as f:
        f.write(f"{datetime.now().isoformat()} rc={rc} acq={acq} vivado={xv}\n")
    print("归档目录:", LOCAL, "结论:", "PASS" if rc == 0 else "FAIL")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
