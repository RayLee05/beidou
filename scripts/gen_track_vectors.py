"""生成跟踪通道的 RTL 回归向量（输入样本 + 参考模型期望输出）。

用法: python scripts/gen_track_vectors.py
输出（tb/vectors/）:
  track_code.hex     2046 行，每行 1 个 bit —— 喂给 RTL code_ram
  track_input.hex    输入字节流（每行 16 字节），2 bit/样本、早样本在高位
  track_expected.txt 每个 1 ms 一行的参考模型观测量
  track_meta.json    场景参数与版本信息
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import ROOT, bootstrap, sha256_file, write_json, write_text  # noqa: E402

bootstrap()

from b1i_ref import codegen, signal_gen  # noqa: E402
from b1i_ref.tracking_model import TrackingChannel, LoopConfig  # noqa: E402
from b1i_ref import params as _p  # noqa: E402

P = _p.P
OUT = os.path.join(ROOT, "tb", "vectors")
MS = 7                  # 生成 7 ms 输入
CMP = 6                 # 前 6 个窗口参与比对
CODE_PHASE_TRUE = 123.0
CODE_PHASE_INIT = 123.3     # 故意留 0.3 chip 初差，考验码环
DOPPLER_TRUE = 1500.0
DOPPLER_INIT = 1500.0
AMPLITUDE = 2.6


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    code = codegen.test_code()
    nh = codegen.test_nh20()
    data = [1, 0, 1, 1, 0, 0, 1, 0]

    sig = signal_gen.make_if_signal(16384 * MS, code, nh, data,
                                    code_phase_chips=CODE_PHASE_TRUE,
                                    doppler_hz=DOPPLER_TRUE,
                                    amplitude=AMPLITUDE)
    packed = signal_gen.pack_2bit(sig)

    ch = TrackingChannel(code, spacing=1, cfg=LoopConfig(fll_en=False))
    ch.reset(code_phase_chips=CODE_PHASE_INIT, doppler_hz=DOPPLER_INIT)

    expected = []
    for k in range(CMP):
        r = ch.step_ms(sig[k * 16384:(k + 1) * 16384])
        expected.append(r)

    write_text(os.path.join(OUT, "track_code.hex"),
               "".join(f"{b:x}\n" for b in code))
    lines = []
    for i in range(0, packed.size, 16):
        lines.append(" ".join(f"{b:02x}" for b in packed[i:i + 16]))
    write_text(os.path.join(OUT, "track_input.hex"), "\n".join(lines) + "\n")
    exp_lines = ["i_e q_e i_p q_p i_l q_l code_phase freq_word dll_disc pll_disc"]
    for r in expected:
        exp_lines.append(" ".join(str(int(r[k])) for k in
                                  ("i_e", "q_e", "i_p", "q_p", "i_l", "q_l",
                                   "code_phase", "freq_word", "dll_disc", "pll_disc")))
    write_text(os.path.join(OUT, "track_expected.txt"), "\n".join(exp_lines) + "\n")

    write_json(os.path.join(OUT, "track_meta.json"), {
        "carrier_lut_generated_by": "scripts/gen_carrier_lut.py",
        "params_version": _p.PARAMS_VERSION,
        "code_source": {
            "kind": "TEST_PATTERN_NOT_ICD",
            "description": "11 级 m 序列 x^11+x^2+1 截断到 2046 chip",
            "warning": "仅用于数据通路验证；真实 PRN 必须取自正式 B1I ICD",
        },
        "nh_source": "TEST_PATTERN_NOT_ICD",
        "ms_generated": MS,
        "ms_compared": CMP,
        "code_phase_true_chips": CODE_PHASE_TRUE,
        "code_phase_init_chips": CODE_PHASE_INIT,
        "doppler_true_hz": DOPPLER_TRUE,
        "doppler_init_hz": DOPPLER_INIT,
        "amplitude": AMPLITUDE,
        "spacing_chips": 1,
        "samples_sha256": sha256_file(os.path.join(OUT, "track_input.hex")),
        "expected_sha256": sha256_file(os.path.join(OUT, "track_expected.txt")),
    })

    print(f"code_bits      : {len(code)}")
    print(f"samples        : {sig.size}  bytes: {packed.size}")
    print(f"expected row   : {len(expected)}")
    print("末行期望:", exp_lines[-1])
    print(f"输出目录       : {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
