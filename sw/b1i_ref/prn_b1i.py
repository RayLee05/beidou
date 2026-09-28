"""B1I 测距码与 D1 电文编码 —— **参数全部取自 ICD 2.1（BDS-SIS-ICD-2.1，2016-11）**。

来源与页码（本地文件 北斗_B1I_B2I_ICD_2.1版_中文版.pdf）：
  4.3 节（第 6-9 页）  测距码特性、G1/G2 生成多项式与初相、表 4-2 G2 相位分配
  5.1.3 节（第 12 页）  BCH(15,11,1)，g(X) = X^4 + X + 1，两两交织成 30 bit
  5.2.1 节（第 19 页） NH 码 20 bit：(0,0,0,0,0,1,0,0,1,1,0,1,0,1,0,0,1,1,1,0)
  5.2.2 节（第 19 页） 超帧 36000 bit/12 min，主帧 1500 bit/30 s，子帧 300 bit/6 s

**转录状态**：G2 抽头表已转录 **37** 组（PRN 1..{N}），其余行需继续从 ICD 表 4-2 转录。
未转录的 PRN 调用会抛错，绝不"猜"一对抽头。
"""
from __future__ import annotations
import numpy as np

CODE_LEN = 2046
NH20 = (0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 0, 1, 0, 0, 1, 1, 1, 0)

#: ICD 表 4-2 G2 序列相位分配（测距码编号 -> 抽头对）
G2_TAPS = {
    1: (1, 3),
    2: (1, 4),
    3: (1, 5),
    4: (1, 6),
    5: (1, 8),
    6: (1, 9),
    7: (1, 10),
    8: (1, 11),
    9: (2, 7),
    10: (3, 4),
    11: (3, 5),
    12: (3, 6),
    13: (3, 8),
    14: (3, 9),
    15: (3, 10),
    16: (3, 11),
    17: (4, 5),
    18: (4, 6),
    19: (4, 8),
    20: (4, 9),
    21: (4, 10),
    22: (4, 11),
    23: (5, 6),
    24: (5, 8),
    25: (5, 9),
    26: (5, 10),
    27: (5, 11),
    28: (6, 8),
    29: (6, 9),
    30: (6, 10),
    31: (6, 11),
    32: (8, 9),
    33: (8, 10),
    34: (8, 11),
    35: (9, 10),
    36: (9, 11),
    37: (10, 11),
}


def _lfsr(poly_taps, init_bits, length):
    """11 级线性移位寄存器，Fibonacci 型；返回长度 length 的 0/1 序列。

    poly_taps: 生成多项式中除最高次外的抽头阶数（1 起算），例如 G1: (1,7,8,9,10)。
    init_bits: 11 位初相，ICD 给的是 01010101010，按"第 1 位最先输出"解释。
    """
    reg = list(init_bits)          # reg[0] 为最先输出的那一位
    out = []
    for _ in range(length):
        out.append(reg[0])
        fb = 0
        for t in poly_taps:
            fb ^= reg[t - 1]       # 阶数 1 对应 reg[0]
        reg = reg[1:] + [fb]
    return out


def g1_sequence(length=CODE_LEN):
    """G1(X) = 1 + X + X^7 + X^8 + X^9 + X^10 + X^11"""
    return _lfsr((1, 7, 8, 9, 10), [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0], length)


def g2_sequence(length=CODE_LEN):
    """G2(X) = 1 + X + X^2 + X^3 + X^4 + X^5 + X^8 + X^9 + X^11"""
    return _lfsr((1, 2, 3, 4, 5, 8, 9, 10), [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0], length)


def prn_code(prn: int, length: int = CODE_LEN):
    """CB1I 码：G1 与"按抽头对偏移后的 G2"模二加，截短 1 码片后为 2046 chip。"""
    if prn not in G2_TAPS:
        raise KeyError(f"PRN {prn} 的 G2 抽头未从 ICD 表 4-2 转录，禁止猜测")
    a, b = G2_TAPS[prn]
    extra = 32
    g1 = g1_sequence(length + extra)
    g2 = g2_sequence(length + extra)
    # 抽头 a/b 的模二加作为 G2 的移位输出（相位偏移）
    g2s = [g2[i + a - 1] ^ g2[i + b - 1] for i in range(length)]
    return [g1[i] ^ g2s[i] for i in range(length)]        # 截短 1 码片 -> 2046


def bch15_11_encode(info11):
    """BCH(15,11,1)，g(X)=X^4+X+1，系统码：15 bit = 11 bit 信息 + 4 bit 校验。"""
    if len(info11) != 11:
        raise ValueError("需要 11 位信息")
    reg = [0, 0, 0, 0]
    for bit in info11:
        fb = bit ^ reg[3]
        reg = [fb, reg[0] ^ fb, reg[1], reg[2] ^ fb]     # 除以 g(X)=x^4+x+1
    return list(info11) + [reg[3], reg[2], reg[1], reg[0]]


def interleave_30(cw_a, cw_b):
    """两组 15 bit BCH 码按 1 比特顺序并/串，组成 30 bit 交织码（ICD 5.1.3）。"""
    return [cw_a[0], cw_b[0]] + [x for pair in zip(cw_a[1:], cw_b[1:]) for x in pair]


def selftest(prn: int = 1) -> dict:
    c = prn_code(prn)
    arr = np.array(c)
    # 自相关（循环）
    pm = 2 * arr - 1
    ac = np.array([int(np.dot(pm, np.roll(pm, k))) for k in range(CODE_LEN)])
    return {
        "prn": prn,
        "len": len(c),
        "ones": int(arr.sum()),
        "balanced_within_2": abs(int(arr.sum()) - CODE_LEN // 2) <= 2,
        "autocorr_peak": int(ac.max()),
        "autocorr_second_peak": int(np.sort(ac)[-2]),
        "nh_len": len(NH20),
        "bch_ok": len(bch15_11_encode([1] * 11)) == 15,
        "taps_transcribed": len(G2_TAPS),
    }


if __name__ == "__main__":
    import json
    print(json.dumps(selftest(), ensure_ascii=False, indent=2))
