"""载波 sin/cos 查表的唯一定义处。

RTL 侧的表 '`rtl/common/carrier_lut_table.svh`' 由 scripts/gen_carrier_lut.py
调用本模块生成；Python 参考模型直接调用本模块取值。两边共用同一算法，
保证"表值"永远一致。

定点约定（见 docs/FIXED_POINT.md）：
  - 地址位宽 CARR_LUT_ADDR_W = 10  -> 1024 项，覆盖一个完整周期
  - 数据位宽 CARR_LUT_DATA_W = 10  -> 有符号，幅度上限 511
  - 相位累加器高 10 位（phase[31:22]）作为地址
"""

from __future__ import annotations

import math

LUT_ADDR_W = 10
LUT_DATA_W = 10
LUT_DEPTH = 1 << LUT_ADDR_W          # 1024
LUT_AMPL = (1 << (LUT_DATA_W - 1)) - 1  # 511，保证落在 10 bit 有符号范围内


def _round_half_away(x: float) -> int:
    """四舍五入（远离零），避免 Python round() 的银行家舍入带来的歧义。"""
    return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))


def _quantize(ampl: float) -> int:
    v = _round_half_away(ampl)
    lo, hi = -(1 << (LUT_DATA_W - 1)), (1 << (LUT_DATA_W - 1)) - 1
    return max(lo, min(hi, v))


COS: tuple = tuple(_quantize(LUT_AMPL * math.cos(2.0 * math.pi * k / LUT_DEPTH))
                   for k in range(LUT_DEPTH))
SIN: tuple = tuple(_quantize(LUT_AMPL * math.sin(2.0 * math.pi * k / LUT_DEPTH))
                   for k in range(LUT_DEPTH))


def lut_index(phase_word: int, phase_w: int = 32) -> int:
    """与 RTL 一致：取相位累加器高 CARR_LUT_ADDR_W 位。"""
    return (phase_word >> (phase_w - LUT_ADDR_W)) & (LUT_DEPTH - 1)


def cos_of(phase_word: int, phase_w: int = 32) -> int:
    return COS[lut_index(phase_word, phase_w)]


def sin_of(phase_word: int, phase_w: int = 32) -> int:
    return SIN[lut_index(phase_word, phase_w)]


def stats() -> dict:
    return {
        "depth": LUT_DEPTH,
        "data_w": LUT_DATA_W,
        "ampl": LUT_AMPL,
        "cos_min": min(COS), "cos_max": max(COS),
        "sin_min": min(SIN), "sin_max": max(SIN),
    }
