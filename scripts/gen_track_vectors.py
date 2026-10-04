"""生成跟踪通道的 RTL 回归向量（输入样本 + 参考模型逐窗口期望值）。

用法: python scripts/gen_track_vectors.py [--ms 300] [--cn0 45]
输出（tb/vectors/）:
  track_code.hex      2046 行，每行 1 bit —— 装入 code_ram
  track_input.hex     输入字节流（每行 16 字节），2 bit/样本、早样本在 [7:6]
  track_init.hex      装载参数：init_code_phase(48b) / init_doppler(32b) / 字节数 / 窗口数
  track_expected.txt  每个码周期窗口一行的参考模型可观测量（含表头）
  track_meta.json     场景参数、真值与文件哈希
"""

from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import ROOT, bootstrap, sha256_file, write_json, write_text  # noqa: E402

bootstrap()

from b1i_ref import params as _p, prn_b1i, scenario  # noqa: E402
from b1i_ref.signal_gen import pack_2bit  # noqa: E402
from b1i_ref.tracking_model import (LoopConfig, TrackingChannel, chips_to_code_phase,  # noqa: E402
                                    doppler_to_word)

P = _p.P
OUT = os.path.join(ROOT, "tb", "vectors")
COLS = ("ms", "partial", "i_e", "q_e", "i_p", "q_p", "i_l", "q_l", "code_phase", "freq_word",
        "dop_word", "locked", "lock_cnt", "d_pll", "d_fll", "d_dll")


def build(ms: int, cn0: float, cp_err: float, fd_err: float, seed: int):
    rx = scenario.geodetic_to_ecef(39.9, 116.4, 50.0)
    sow0 = 345623.4
    eph = scenario.make_constellation(rx, sow0, 1000, n_sats=1, seed=seed)[0]
    sc = scenario.Scenario(rx_ecef=rx, sow0=sow0, wn=1000,
                           sats=[scenario.SatConfig(eph, cn0_dbhz=cn0, phase0_cycles=0.3)],
                           rx_clock_bias=1e-4, seed=seed)
    n = ms * P.samples_per_ms
    samples = sc.samples(0, n)
    truth = sc.truth(0)[eph.prn]
    init_cp = chips_to_code_phase(truth["code_phase_chips"] + cp_err)
    init_dop = doppler_to_word(truth["doppler_hz"] + fd_err)
    ch = TrackingChannel(prn_b1i.prn_code(eph.prn), LoopConfig(fll_en=True))
    ch.reset(code_phase_word=init_cp, dop_word=init_dop)
    rows = ch.process(samples)
    return eph, sc, samples, truth, init_cp, init_dop, rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ms", type=int, default=300)
    ap.add_argument("--cn0", type=float, default=45.0)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)

    eph, sc, samples, truth, init_cp, init_dop, rows = build(a.ms, a.cn0, 0.3, 100.0, a.seed)
    packed = pack_2bit(samples.astype("int64"))

    write_text(os.path.join(OUT, "track_code.hex"),
               "".join(f"{b:x}\n" for b in prn_b1i.prn_code(eph.prn)))
    lines = [" ".join(f"{b:02x}" for b in packed[i:i + 16]) for i in range(0, packed.size, 16)]
    write_text(os.path.join(OUT, "track_input.hex"), "\n".join(lines) + "\n")
    write_text(os.path.join(OUT, "track_init.hex"),
               f"{init_cp:012x}\n{init_dop & 0xFFFFFFFF:08x}\n{packed.size:08x}\n{len(rows):08x}\n")

    exp = [" ".join(COLS)]
    for r in rows:
        v = []
        for k in COLS:
            x = int(r[k])
            v.append(f"{x:08x}" if k in ("code_phase", "freq_word") else str(x))
        exp.append(" ".join(v))
    write_text(os.path.join(OUT, "track_expected.txt"), "\n".join(exp) + "\n")

    write_json(os.path.join(OUT, "track_meta.json"), {
        "carrier_lut_generated_by": "scripts/gen_carrier_lut.py",
        "params_version": _p.PARAMS_VERSION,
        "code_source": {"kind": "ICD_2.1", "prn": eph.prn,
                        "generator": "sw/b1i_ref/prn_b1i.py (ICD 图 4-1 / 表 4-2)"},
        "scenario": {"cn0_dbhz": a.cn0, "noise_sigma": sc.noise_sigma, "seed": a.seed,
                     "sow0": sc.sow0, "ms": a.ms},
        "truth_at_sample0": truth,
        "init_errors": {"code_phase_chips": 0.3, "doppler_hz": 100.0},
        "init_code_phase_word48": init_cp, "init_doppler_word": init_dop,
        "windows": len(rows), "bytes": int(packed.size),
        "final_locked": bool(rows[-1]["locked"]),
        "samples_sha256": sha256_file(os.path.join(OUT, "track_input.hex")),
        "expected_sha256": sha256_file(os.path.join(OUT, "track_expected.txt")),
    })
    print(f"PRN {eph.prn}  windows={len(rows)}  bytes={packed.size}  "
          f"final locked={rows[-1]['locked']}")
    print(f"输出目录: {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
