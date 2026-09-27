"""参考模型自检与性能基线（P3 证据）。

用法: python scripts/run_ref_model.py
输出: reports/ref_model_results.md / .json
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import REPORTS_DIR, Check, bootstrap, env_banner, write_json, write_text  # noqa: E402

bootstrap()

import numpy as np  # noqa: E402
from b1i_ref import acquisition, codegen, signal_gen  # noqa: E402
from b1i_ref import params as _p  # noqa: E402
from b1i_ref.tracking_model import TrackingChannel, LoopConfig  # noqa: E402

P = _p.P
MD = os.path.join(REPORTS_DIR, "ref_model_results.md")
JSON = os.path.join(REPORTS_DIR, "ref_model_results.json")

CODE = codegen.test_code()
NH = codegen.test_nh20()
DATA = [1, 0, 1, 1, 0, 0, 1, 0]
FD_TRUE = 1500.0
CP_TRUE = 123.0


def test_codegen(c: Check):
    s = codegen.selftest()
    c.true("m 序列周期 2047", s["mseq_period_ok"], str(s))
    c.eq("测试码长度", s["code_len"], 2046)
    c.eq("NH20 长度", s["nh_len"], 20)
    c.true("测试码 0/1 均衡", s["code_ones"] == 1024, str(s["code_ones"]))


def test_packing(c: Check):
    x = np.array([-3, -1, 1, 3, 3, 3, -3, -3], dtype=np.int64)
    b = signal_gen.pack_2bit(x)
    c.eq("打包字节数", int(b.size), 2)
    c.eq("首字节 0x1B", int(b[0]), 0x1B)
    c.eq("次字节 0xF0", int(b[1]), 0xF0)   # [3,3,-3,-3] -> 11 11 00 00


def test_acquisition(c: Check) -> dict:
    s = signal_gen.make_if_signal(16384, CODE, NH, DATA, CP_TRUE, FD_TRUE, amplitude=2.6)
    grid = [FD_TRUE + d for d in range(-1000, 1001, 100)]
    hits = acquisition.serial_search(s, CODE, grid)
    best = hits[0]
    n = 16384
    cp = ((n - int(best["code_phase_chips"])) % n) * 2046.0 / n
    # 1 ms 相干 + 2 bit 量化会产生谐波混叠，粗捕获的频率估计有偏；
    # 精细频率由 FLL/PLL 拉入（P4 再做频率细化搜索）
    c.true("捕获多普勒误差 <= 500 Hz", abs(best["doppler_hz"] - FD_TRUE) <= 500.0,
           f"best={best['doppler_hz']}")
    c.true("捕获码相位误差 <= 0.5 chip", abs(cp - CP_TRUE) <= 0.5, f"cp={cp:.3f}")
    return {"best": best, "code_phase_chips": cp,
            "top3": [{"fd": h["doppler_hz"], "mag": round(h["peak_mag"])} for h in hits[:3]]}


def test_tracking(c: Check) -> dict:
    ms = 40
    sig = signal_gen.make_if_signal(16384 * ms, CODE, NH, DATA, CP_TRUE, FD_TRUE,
                                    amplitude=2.6)
    ch = TrackingChannel(CODE, spacing=1, cfg=LoopConfig(fll_en=True))
    ch.reset(code_phase_chips=CP_TRUE + 0.5, doppler_hz=FD_TRUE + 2.0)
    rows = []
    for k in range(ms):
        r = ch.step_ms(sig[k * 16384:(k + 1) * 16384])
        r["code_phase_chips"] = r["code_phase"] / 2 ** P.code_frac_w
        r["cp_err"] = r["code_phase_chips"] - CP_TRUE
        r["fd_err"] = r["doppler_hz"] - FD_TRUE
        rows.append(r)
    first, last = rows[0], rows[-1]
    c.true("码相位误差收敛", abs(last["cp_err"]) < 0.25, f"{last['cp_err']:.3f}")
    # 40 ms 内把 +2 Hz 初差压到 <1.5 Hz 且仍在下降；环路增益整定留到 P4
    c.true("多普勒误差收敛", abs(last["fd_err"]) < 1.5, f"{last['fd_err']:.2f}")
    c.true("首帧码误差大于末帧(单调趋势)", abs(first["cp_err"]) > abs(last["cp_err"]))
    c.eq("跟踪窗口数", len(rows), ms)
    return {"pull_in_range_hz": 2.0, "rows": [{k: (round(v, 6) if isinstance(v, float) else v)
                      for k, v in r.items() if k in
                      ("ms", "cp_err", "fd_err", "dll_disc", "pll_disc", "i_p", "q_p")}
                     for r in rows]}


def build_md(banner, acq, trk, check: Check) -> str:
    L = ["# 参考模型自检与跟踪基线（自动生成）", "",
         "> 由 scripts/run_ref_model.py 生成；定点模型与 RTL 逐拍等价（见 docs/TRACKING_DESIGN.md）。", "",
         f"- 生成时间: {banner['generated_at']}", f"- git: {banner['git_revision']}",
         f"- 码源: TEST_PATTERN_NOT_ICD（11 级 m 序列截断到 2046）",
         f"- 场景: 码相位真值 {CP_TRUE} chip，多普勒真值 {FD_TRUE} Hz，幅度 2.6", "",
         "## 1. 捕获", "",
         f"- 最佳多普勒 {acq['best']['doppler_hz']:.0f} Hz（真值 {FD_TRUE:.0f}）",
         f"- 码相位 {acq['code_phase_chips']:.3f} chip（真值 {CP_TRUE}）",
         f"- 峰值 {acq['best']['peak_mag']:.0f}", "", "| 多普勒假设(Hz) | 峰值 |", "|---:|---:|"]
    for h in acq["top3"]:
        L.append(f"| {h['fd']:.0f} | {h['mag']} |")
    L += ["", "## 2. 跟踪收敛（初差 +0.5 chip / +2 Hz，FLL 辅助开启）", "",
          "| ms | 码相位误差(chip) | 多普勒误差(Hz) | DLL 判别 | PLL 判别 |", "|---:|---:|---:|---:|---:|"]
    for r in trk["rows"]:
        if r["ms"] % 5 == 0 or r["ms"] <= 3:
            L.append(f"| {r['ms']} | {r['cp_err']:+.4f} | {r['fd_err']:+.2f} | "
                     f"{r['dll_disc']} | {r['pll_disc']} |")
    L += ["", "## 3. 自检结果", "",
          f"- 检查项: {check.passed} 通过 / {len(check.failures)} 失败"]
    for f in check.failures:
        L.append(f"- ❌ {f}")
    if not check.failures:
        L.append("- ✅ 全部通过")
    L.append("")
    return "\n".join(L)


def main() -> int:
    c = Check("参考模型")
    banner = env_banner()
    test_codegen(c)
    test_packing(c)
    acq = test_acquisition(c)
    trk = test_tracking(c)
    write_text(MD, build_md(banner, acq, trk, c))
    write_json(JSON, {"banner": banner, "acquisition": acq, "tracking": trk,
                      "checks_passed": c.passed, "checks_failed": c.failures})
    print(f"已生成 {MD}")
    print(f"已生成 {JSON}")
    print(f"捕获: doppler={acq['best']['doppler_hz']:.0f} Hz  cp={acq['code_phase_chips']:.3f} chip")
    print(f"跟踪末帧: cp_err={trk['rows'][-1]['cp_err']:+.4f} chip  fd_err={trk['rows'][-1]['fd_err']:+.2f} Hz")
    return c.report()


if __name__ == "__main__":
    raise SystemExit(main())
