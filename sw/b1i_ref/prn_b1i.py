"""B1I 测距码、NH 码与 BCH(15,11,1) —— 参数全部取自 ICD 2.1（BDS-SIS-ICD-2.1，2016-11）。

来源与页码（references/北斗_B1I_B2I_ICD_2.1版_中文版.pdf，页码为 PDF 页）：
  第 11 页 4.3 节 / 图 4-1  G1/G2 生成多项式、初相、发生器结构（级 1→11 移位，反馈进第 1 级）
  第 12-13 页 表 4-2        G2 相位分配（37 组）
  第 16-19 页 5.1.3 节      BCH(15,11,1)，g(X)=X^4+X+1；图 5-2 编码器；表 5-2 纠错 ROM；
                            两组码字逐比特交错成 30 bit
  第 19 页 5.2.1 节         NH 码 (0,0,0,0,0,1,0,0,1,1,0,1,0,1,0,0,1,1,1,0)

发生器（图 4-1）：
  G1 反馈 = 级 1⊕7⊕8⊕9⊕10⊕11，输出取级 11；
  G2 反馈 = 级 1⊕2⊕3⊕4⊕5⊕8⊕9⊕11，输出取表 4-2 两个相位选择抽头的异或；
  初相 01010101010 依次对应级 1..11（该图案是回文，不存在位序歧义）。
验证：未截短的 2047 位序列两两周期互相关只取 {-65, -1, 63}（Gold 码三值特性），
见 selftest()；截短到 2046 后的循环相关次峰约 130，是 B1I 码本身的性质。
"""
from __future__ import annotations

import numpy as np

CODE_LEN = 2046
NH20 = (0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 0, 1, 0, 0, 1, 1, 1, 0)
INIT_PHASE = (0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0)       # 级 1..11

#: ICD 表 4-2：测距码编号 -> G2 相位选择抽头（级号）
G2_TAPS = {
    1: (1, 3), 2: (1, 4), 3: (1, 5), 4: (1, 6), 5: (1, 8), 6: (1, 9), 7: (1, 10),
    8: (1, 11), 9: (2, 7), 10: (3, 4), 11: (3, 5), 12: (3, 6), 13: (3, 8), 14: (3, 9),
    15: (3, 10), 16: (3, 11), 17: (4, 5), 18: (4, 6), 19: (4, 8), 20: (4, 9), 21: (4, 10),
    22: (4, 11), 23: (5, 6), 24: (5, 8), 25: (5, 9), 26: (5, 10), 27: (5, 11), 28: (6, 8),
    29: (6, 9), 30: (6, 10), 31: (6, 11), 32: (8, 9), 33: (8, 10), 34: (8, 11), 35: (9, 10),
    36: (9, 11), 37: (10, 11),
}
G1_FB = (1, 7, 8, 9, 10, 11)
G2_FB = (1, 2, 3, 4, 5, 8, 9, 11)


def prn_code(prn: int, length: int = CODE_LEN) -> list:
    """返回 PRN 的 0/1 码片序列（默认 2046 chip，即 2047 位 Gold 码截短最后 1 位）。"""
    if prn not in G2_TAPS:
        raise KeyError(f"PRN {prn} 不在 ICD 表 4-2 中")
    a, b = G2_TAPS[prn]
    g1 = list(INIT_PHASE)
    g2 = list(INIT_PHASE)
    out = []
    for _ in range(length):
        out.append(g1[10] ^ g2[a - 1] ^ g2[b - 1])
        f1 = 0
        for t in G1_FB:
            f1 ^= g1[t - 1]
        f2 = 0
        for t in G2_FB:
            f2 ^= g2[t - 1]
        g1 = [f1] + g1[:10]
        g2 = [f2] + g2[:10]
    return out


# ---------------------------------------------------------------- BCH(15,11,1)
def _pack4(d) -> int:
    return (d[3] << 3) | (d[2] << 2) | (d[1] << 1) | d[0]


def _bch_encode_reg(bits) -> int:
    """图 5-2 编码器：输入在 D3 输出端与反馈异或后进入 D0/D1。返回 D3D2D1D0。"""
    d = [0, 0, 0, 0]
    for bit in bits:
        fb = int(bit) ^ d[3]
        d = [fb, d[0] ^ fb, d[1], d[2]]
    return _pack4(d)


def _bch_divide(bits) -> int:
    """图 5-4 译码除法电路：D0 <- 输入⊕D3，D1 <- D0⊕D3，D2 <- D1，D3 <- D2。"""
    d = [0, 0, 0, 0]
    for bit in bits:
        d = [int(bit) ^ d[3], d[0] ^ d[3], d[1], d[2]]
    return _pack4(d)


def bch15_11_encode(info11) -> list:
    """系统码：11 bit 信息在前，4 bit 校验在后（校验按 D3、D2、D1、D0 顺序移出）。"""
    if len(info11) != 11:
        raise ValueError("需要 11 位信息")
    s = _bch_encode_reg(info11)
    return [int(b) for b in info11] + [(s >> 3) & 1, (s >> 2) & 1, (s >> 1) & 1, s & 1]


#: ICD 表 5-2：D3D2D1D0 -> 15 位纠错信号（字符串最左位对应码字第 1 个比特）
BCH_ROM = {
    0b0000: "000000000000000", 0b0001: "000000000000001", 0b0010: "000000000000010",
    0b0011: "000000000010000", 0b0100: "000000000000100", 0b0101: "000000100000000",
    0b0110: "000000000100000", 0b0111: "000010000000000", 0b1000: "000000000001000",
    0b1001: "100000000000000", 0b1010: "000001000000000", 0b1011: "000000010000000",
    0b1100: "000000001000000", 0b1101: "010000000000000", 0b1110: "000100000000000",
    0b1111: "001000000000000",
}


def bch15_11_decode(cw15) -> tuple:
    """返回 (纠错后的 11 bit 信息, 是否发生纠错, 码字是否合法)。

    合法：纠错后再编码与纠错后码字一致。单比特错误可纠且合法；
    实现错误或非码字会让 ok=False（REQ-SYN-004）。
    """
    s = _bch_divide(cw15)
    pat = BCH_ROM[s]
    fixed = [int(b) ^ int(p) for b, p in zip(cw15, pat)]
    info = fixed[:11]
    ok = bch15_11_encode(info) == fixed
    return info, s != 0, ok


def interleave_30(cw_a, cw_b) -> list:
    """两组 15 bit 码字逐比特交错：X1_1 X2_1 X1_2 X2_2 ... P1_4 P2_4（ICD 第 19 页）。"""
    return [x for pair in zip(cw_a, cw_b) for x in pair]


def deinterleave_30(word30) -> tuple:
    return list(word30[0::2]), list(word30[1::2])


def encode_word(info, first_word: bool) -> list:
    """把一个字的信息位编码成 30 bit。首字 26 bit 信息：前 15 bit 不编码，后 11 bit 单码字。"""
    info = [int(b) for b in info]
    if first_word:
        if len(info) != 26:
            raise ValueError("首字需要 26 位信息")
        return info[:15] + bch15_11_encode(info[15:])
    if len(info) != 22:
        raise ValueError("第 2-10 字需要 22 位信息")
    return interleave_30(bch15_11_encode(info[:11]), bch15_11_encode(info[11:]))


def decode_word(word30, first_word: bool) -> tuple:
    """返回 (信息位, 纠错次数, 全部码字合法)。"""
    word30 = [int(b) for b in word30]
    if first_word:
        info, c, ok = bch15_11_decode(word30[15:])
        return word30[:15] + info, int(c), ok
    a, b = deinterleave_30(word30)
    ia, ca, oka = bch15_11_decode(a)
    ib, cb, okb = bch15_11_decode(b)
    return ia + ib, int(ca) + int(cb), oka and okb


# ---------------------------------------------------------------- 自检
def _gold_values() -> set:
    vals = set()
    full = {p: 2 * np.array(prn_code(p, 2047)) - 1 for p in (1, 6, 9, 20, 37)}
    fft = {p: np.fft.fft(v) for p, v in full.items()}
    for p in full:
        for q in full:
            x = np.real(np.fft.ifft(fft[p] * np.conj(fft[q]))).round().astype(int)
            if p == q:
                x = x[1:]
            vals |= set(np.unique(x).tolist())
    return vals


def _bch_rom_consistent() -> bool:
    """单比特错误的伴随式必须与表 5-2 一致（验证除法电路方向与 ROM 位序）。"""
    rng = np.random.default_rng(1)
    for _ in range(20):
        info = rng.integers(0, 2, 11).tolist()
        cw = bch15_11_encode(info)
        if _bch_divide(cw) != 0:
            return False
        for i in range(15):
            bad = list(cw)
            bad[i] ^= 1
            fixed, corrected, ok = bch15_11_decode(bad)
            if fixed != info or not corrected or not ok:
                return False
    return True


def selftest() -> dict:
    c = np.array(prn_code(1))
    return {
        "len": int(c.size),
        "ones_prn1": int(c.sum()),
        "gold_3_valued": sorted(_gold_values()) == [-65, -1, 63],
        "bch_rom_consistent": _bch_rom_consistent(),
        "nh_len": len(NH20),
        "prns": len(G2_TAPS),
    }


if __name__ == "__main__":
    import json
    print(json.dumps(selftest(), ensure_ascii=False, indent=2))
