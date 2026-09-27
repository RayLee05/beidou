"""PRN 码 / NH20 序列的来源管理。

**重要（REQ-SIG-006 / REQ-SYN-005）**：本模块不内嵌 B1I ICD 码表。
凭记忆补写码表是被明令禁止的。本模块提供两条路径：

1. `load_bits(path)`  -- 正式路径：从 ICD 导出文件读取真实码表（0/1 文本或每行一个 bit）
2. `test_code()` / `test_nh20()` -- 仅供数据通路验证的**确定性测试图案**

测试图案用 11 级 m 序列（生成多项式 x^11 + x^2 + 1，周期 2047）截断到 2046 个码片。
它具备良好的自相关特性（峰 2047 / 旁瓣 -1），足以验证捕获与跟踪数据通路，
但它**不是** B1I 的 PRN 码，绝不能用于真实信号处理。
"""

from __future__ import annotations

import os

CODE_LEN = 2046
NH_LEN = 20
MSEQ_STAGES = 11
MSEQ_PERIOD = (1 << MSEQ_STAGES) - 1     # 2047


def m_sequence(taps=(0, 2), stages: int = MSEQ_STAGES, seed: int = 1) -> list:
    """11 级 m 序列（Fibonacci 型）。taps=(0,2) 对应 x^11 + x^2 + 1。"""
    st = seed & ((1 << stages) - 1)
    if st == 0:
        st = 1
    out = []
    for _ in range((1 << stages) - 1):
        out.append(st & 1)
        fb = 0
        for t in taps:
            fb ^= (st >> t) & 1
        st = (st >> 1) | (fb << (stages - 1))
    return out


def test_code(len_: int = CODE_LEN) -> list:
    """测试用伪码（非 ICD 真值），长度 len_。"""
    seq = m_sequence()
    return seq[:len_]


def test_nh20() -> list:
    """测试用 NH20 占位序列（非 ICD 真值）。"""
    seq = m_sequence()
    return seq[100:100 + NH_LEN]


def load_bits(path: str, expected_len: int | None = None) -> list:
    """从文本文件加载 0/1 码表（每行一个 bit，或一行连续字符串）。"""
    bits = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line[0] in "01" and len(line) > 1:
                bits.extend(int(c) for c in line if c in "01")
            elif line in ("0", "1"):
                bits.append(int(line))
    if expected_len is not None and len(bits) != expected_len:
        raise ValueError(f"{path}: 期望 {expected_len} 个 bit，实际 {len(bits)}")
    return bits


def selftest() -> dict:
    seq = m_sequence()
    return {
        "mseq_len": len(seq),
        "mseq_period_ok": len(seq) == MSEQ_PERIOD and len(set(seq)) == 2,
        "code_len": len(test_code()),
        "nh_len": len(test_nh20()),
        "code_ones": sum(test_code()),
    }


if __name__ == "__main__":
    import json
    print(json.dumps(selftest(), ensure_ascii=False, indent=2))
