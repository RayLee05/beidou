"""校验参数单一来源：sw/b1i_ref/params.py <-> rtl/include/b1i_params.svh <-> configs/b1i_default.json。

用法: python scripts/check_params_consistency.py
退出码: 0 = 一致，1 = 不一致（CI 阻断）
"""

from __future__ import annotations

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import ROOT, Check, bootstrap, sha256_file  # noqa: E402

bootstrap()
from b1i_ref.params import P  # noqa: E402

SVH = os.path.join(ROOT, "rtl", "include", "b1i_params.svh")
CFG = os.path.join(ROOT, "configs", "b1i_default.json")

#: SVH 常量名 -> params.py 期望值
EXPECTED = {
    "F_RF_HZ": int(P.f_rf_hz),
    "F_IF_HZ": int(P.f_if_hz),
    "F_S_HZ": int(P.f_s_hz),
    "SAMPLE_BITS": P.sample_bits,
    "SAMPLES_PER_BYTE": P.samples_per_byte,
    "SAMPLE_W": P.sample_w,
    "CODE_RATE_HZ": int(P.code_rate_hz),
    "CODE_CHIPS_PER_PERIOD": P.code_chips_per_period,
    "NH_LENGTH": P.nh_length,
    "D1_BIT_RATE_BPS": int(P.d1_bit_rate_bps),
    "D1_BIT_PERIOD_MS": int(1000 / P.d1_bit_rate_bps),
    "D1_SUBFRAME_PERIOD_S": P.d1_subframe_period_s,
    "D1_SUBFRAMES_PER_FRAME": P.d1_subframes_per_frame,
    "D1_FRAME_PERIOD_S": P.d1_frame_period_s,
    "N_CHANNELS": P.n_channels,
    "CHANNEL_ID_W": P.channel_id_w,
    "PRN_W": P.prn_w,
    "NCO_PHASE_W": P.nco_phase_w,
    "CARR_LUT_ADDR_W": P.carr_lut_addr_w,
    "CARR_LUT_DATA_W": P.carr_lut_data_w,
    "CORR_ACC_W": P.corr_acc_w,
    "BIT_ACC_W": P.bit_acc_w,
    "LOOP_COEF_W": P.loop_coef_w,
    "LOOP_COEF_FRAC_W": P.loop_coef_frac_w,
    "FREQ_WORD_W": P.freq_word_w,
    "CODE_PHASE_W": P.code_phase_w,
    "SAMPLE_INDEX_W": P.sample_index_w,
    "EPOCH_ID_W": P.epoch_id_w,
    "SAMPLES_PER_MS": P.samples_per_ms,
    "SAMPLES_PER_BIT": P.samples_per_bit,
    "SAMPLES_PER_SUBFRAME": P.samples_per_subframe,
    "SAMPLES_PER_FRAME": P.samples_per_frame,
    "MS_PER_BIT": int(1000 / P.d1_bit_rate_bps),
    "MS_PER_SUBFRAME": P.d1_subframe_period_s * 1000,
    "MS_PER_FRAME": P.d1_frame_period_s * 1000,
    # 码相位定点与环路默认值
    "CODE_FRAC_W": P.code_frac_w,
    "CODE_PERIOD_WORD": P.code_period_word,
    "CODE_INC_NOMINAL": P.code_inc_nominal,
    "CODE_INC_MIN": P.code_inc_min,
    "CODE_INC_MAX": P.code_inc_max,
    "FREQ_WORD_IF": 2 ** 30,
    "FREQ_WORD_DOP_MAX": 2621440,
    "DISC_SHIFT_DEFAULT": P.disc_shift_default,
    "DLL_KP_DEFAULT": P.dll_kp_default,
    "DLL_KI_DEFAULT": P.dll_ki_default,
    "PLL_KP_DEFAULT": P.pll_kp_default,
    "PLL_KI_DEFAULT": P.pll_ki_default,
    "FLL_KP_DEFAULT": P.fll_kp_default,
    "LOCK_THRESH_DEFAULT": P.lock_thresh_default,
    "LOCK_COUNT_MAX": P.lock_count_max,
}

LITERAL_RE = re.compile(r"(\d+)'([dD])")
DECL_RE = re.compile(
    r"localparam\s+(?:int\s+unsigned|longint\s+unsigned|int|longint"
    r"|logic\s*\[\s*\d+\s*:\s*\d+\s*\])\s+"
    r"([A-Za-z_]\w*)\s*=\s*([^;]+);"
)


def parse_svh(text: str) -> dict:
    values: dict = {}
    for name, raw in DECL_RE.findall(text):
        expr = raw.split("//")[0].strip()
        for ident in sorted(values, key=len, reverse=True):
            expr = re.sub(rf"\b{ident}\b", str(values[ident]), expr)
        expr = LITERAL_RE.sub("", expr)
        try:
            values[name] = int(eval(expr, {"__builtins__": {}}, {}))  # noqa: S307
        except Exception:
            values[name] = None
    return values


def main() -> int:
    c = Check("params 一致性")
    svh_text = open(SVH, encoding="utf-8").read()
    svh = parse_svh(svh_text)
    cfg = json.loads(open(CFG, encoding="utf-8").read())

    print(f"params.py 版本 : {P.__class__.__module__}")
    print(f"svh 常量数     : {len(svh)}")
    print(f"sha256(svh)    : {sha256_file(SVH)}")
    print(f"sha256(config) : {sha256_file(CFG)}")

    missing = [k for k in EXPECTED if k not in svh]
    c.true("SVH 覆盖全部受管常量", not missing, f"缺少 {missing}")

    for k, want in EXPECTED.items():
        if k in svh:
            c.eq(f"svh.{k}", svh[k], want)

    # 运行期配置中的冗余字段必须与参数一致
    c.eq("config.input.sample_rate_hz", int(cfg["input"]["sample_rate_hz"]), int(P.f_s_hz))
    c.eq("config.input.if_hz", int(cfg["input"]["if_hz"]), int(P.f_if_hz))
    c.eq("config.channels.count", int(cfg["channels"]["count"]), P.n_channels)
    c.eq("config.output.epoch_period_s", float(cfg["output"]["epoch_period_s"]), P.epoch_period_s)
    c.eq("config.input.sample_encoding", cfg["input"]["sample_encoding"], "2bit-pair")

    # 内部不变量
    c.eq("1 ms 样本数", P.samples_per_ms, 16368)
    c.eq("每码片样本数", P.samples_per_code_period, 8.0)
    c.eq("fIF = Fs/4", P.f_if_hz * 4, P.f_s_hz)
    c.eq("每 1 ms 码片数", int(P.code_rate_hz * 1e-3), P.code_chips_per_period)
    c.eq("1 数据位 = 20 ms", int(P.samples_per_bit), 20 * P.samples_per_ms)
    c.eq("1 子帧 = 6 s", P.samples_per_subframe, 6000 * P.samples_per_ms)
    c.eq("1 帧 = 5 子帧", P.samples_per_frame, 5 * P.samples_per_subframe)
    c.eq("1 帧 = 30 s", P.d1_frame_period_s,
         P.d1_subframes_per_frame * P.d1_subframe_period_s)
    c.eq("NH 每片 1 ms", P.nh_length, 20)
    c.true("SAMPLE_INDEX 覆盖整帧", P.sample_index_wrap_s >= P.d1_frame_period_s,
           f"{P.sample_index_wrap_s:.1f}s < {P.d1_frame_period_s}s")
    c.true("目标时钟高于采样率", P.target_clk_hz > P.f_s_hz)
    return c.report()


if __name__ == "__main__":
    raise SystemExit(main())
