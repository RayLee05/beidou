"""生成捕获 + 移交 + 跟踪的 RTL 测试向量（tb_acquisition）。

用法: python scripts/gen_acq_vectors.py [--ms 500] [--cn0 45]
输出（tb/vectors/）:
  acq_input.hex   输入字节流（每行 16 字节）
  acq_cfg.hex     目标 PRN、缺席 PRN、dop_min、dop_step、n_bins、nc、thr、字节数（每行一项）
  acq_truth.hex   第 m 行 = 第 m*16368-1 个样本（0 起）处目标星的真值：
                  64 bit = 码相位 Q(11.21)（高 32 位）| 多普勒字（低 32 位）
  acq_meta.json   场景说明
"""

from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import ROOT, bootstrap, write_json, write_text  # noqa: E402

bootstrap()

from b1i_ref import params as _p, scenario  # noqa: E402
from b1i_ref.signal_gen import pack_2bit  # noqa: E402
from b1i_ref.tracking_model import doppler_to_word  # noqa: E402

P = _p.P
OUT = os.path.join(ROOT, "tb", "vectors")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ms", type=int, default=650)
    ap.add_argument("--cn0", type=float, default=45.0)
    ap.add_argument("--seed", type=int, default=11)
    a = ap.parse_args()

    rx = scenario.geodetic_to_ecef(39.9, 116.4, 50.0)
    sow0 = 345611.7
    ephs = scenario.make_constellation(rx, sow0, 1000, n_sats=3, seed=a.seed)
    target, other = ephs[0], ephs[1]
    present = {e.prn for e in ephs[:2]}
    absent = next(p for p in range(6, 38) if p not in present)
    sc = scenario.Scenario(rx_ecef=rx, sow0=sow0, wn=1000, rx_clock_bias=2e-4, seed=a.seed,
                           sats=[scenario.SatConfig(target, cn0_dbhz=a.cn0, phase0_cycles=0.1),
                                 scenario.SatConfig(other, cn0_dbhz=a.cn0 + 2, phase0_cycles=0.6)])
    n = a.ms * P.samples_per_ms
    samples = sc.samples(0, n)
    packed = pack_2bit(samples.astype("int64"))
    lines = [" ".join(f"{b:02x}" for b in packed[i:i + 16]) for i in range(0, packed.size, 16)]
    write_text(os.path.join(OUT, "acq_input.hex"), "\n".join(lines) + "\n")

    fd0 = sc.truth(0)[target.prn]["doppler_hz"]
    step = 500.0
    dop_min = round(fd0 / step) * step - 2 * step
    n_bins, nc, thr = 5, 2, 56          # thr Q4.4 = 3.5（2 次非相干时纯噪声峰均比约 2.6~3.2）
    cfg = [target.prn, absent, doppler_to_word(dop_min) & 0xFFFFFFFF,
           doppler_to_word(step), n_bins, nc, thr, packed.size]
    write_text(os.path.join(OUT, "acq_cfg.hex"), "".join(f"{v:08x}\n" for v in cfg))

    rows = []
    for m in range(1, a.ms + 1):
        t = sc.truth(m * P.samples_per_ms - 1)[target.prn]
        cp = int(round(t["code_phase_chips"] * (1 << P.code_frac_w))) % (2046 << P.code_frac_w)
        rows.append(f"{cp:08x}{doppler_to_word(t['doppler_hz']) & 0xFFFFFFFF:08x}")
    write_text(os.path.join(OUT, "acq_truth.hex"), "\n".join(rows) + "\n")

    write_json(os.path.join(OUT, "acq_meta.json"), {
        "target_prn": target.prn, "interferer_prn": other.prn, "absent_prn": absent,
        "cn0_dbhz": a.cn0, "doppler_hz_at_0": fd0, "dop_min_hz": dop_min, "dop_step_hz": step,
        "n_bins": n_bins, "nc": nc, "thr_q4_4": thr, "ms": a.ms, "bytes": int(packed.size),
        "truth_code_phase_at_0": sc.truth(0)[target.prn]["code_phase_chips"],
    })
    print(f"target PRN {target.prn} (fd={fd0:.1f} Hz)  interferer {other.prn}  absent {absent}")
    print(f"bins: {dop_min:.0f} Hz + k*{step:.0f}, k<{n_bins}; bytes={packed.size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
