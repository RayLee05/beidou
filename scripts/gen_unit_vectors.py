"""生成 RTL 单元测试向量（参考值全部来自 sw/b1i_ref 的 ICD 实现）。

用法: python scripts/gen_unit_vectors.py
输出（tb/vectors/）:
  prn_codes.hex        PRN 1..63，每行 2046 bit（首码片在 bit 2045）
  nav_bits.hex         帧同步测试的输入比特流（含极性翻转与注入的单比特错误）
  nav_expected.txt     帧同步测试的期望子帧（FraID、SOW、起始比特序号、224 位信息位）
  sync_frames.hex      周内秒回绕及不连续/非法字段的合法 BCH 编码子帧
  sync_frames_expected.txt  上述子帧的 FraID、SOW 和 224 位信息
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import ROOT, bootstrap, write_text  # noqa: E402

bootstrap()

import numpy as np  # noqa: E402
from b1i_ref import d1_nav, prn_b1i  # noqa: E402

OUT = os.path.join(ROOT, "tb", "vectors")
PRN_LIST = tuple(range(1, 64))


def gen_prn() -> None:
    lines = []
    for prn in PRN_LIST:
        bits = "".join(str(b) for b in prn_b1i.prn_code(prn))
        lines.append(f"{int(bits, 2):0512x}")  # 一行一个完整 PRN，首码片在 bit 2045。
    write_text(os.path.join(OUT, "prn_codes.hex"), "\n".join(lines) + "\n")
    print(f"prn_codes.hex: PRN {PRN_LIST}")


def gen_nav() -> None:
    """一段 D1 比特流：随机前缀 + 连续 7 个子帧；后半段整体反相，模拟 PLL 180° 模糊。"""
    rng = np.random.default_rng(3)
    eph = d1_nav.Ephemeris(prn=11, WN=950, toe=345600, toc=345600, sqrtA=5282.6, e=0.0012,
                           i0=0.963, OMEGA0=-1.2, omega=0.5, M0=2.1, dn=4.0e-9,
                           OMEGADOT=-6.8e-9, IDOT=1.0e-10, Cuc=1e-6, Cus=8e-6, Crc=200.0,
                           Crs=20.0, Cic=1e-8, Cis=-2e-8, a0=1.2e-4, a1=3e-11, TGD1=5.3e-9,
                           AODE=1, AODC=1).quantized()
    sow0 = 345600 + 6 * 3          # 从子帧 4 开始
    prefix = rng.integers(0, 2, 137).tolist()
    bits, subframes = list(prefix), []
    for k in range(7):
        sow = sow0 + 6 * k
        sf_id = (sow // 6) % 5 + 1
        vals = eph.subframe_values(sow)[sf_id] if sf_id <= 3 else {"SOW": sow, "Pnum": 3}
        sf = d1_nav.encode_subframe(sf_id, vals)
        start = len(bits)
        info, _, ok = d1_nav.decode_subframe(sf)
        if not ok:
            raise RuntimeError(f"编码子帧自检失败 id={sf_id}")
        sf = list(sf)
        if k == 2:
            sf[100] ^= 1           # 字 4 内单比特错误，应被 BCH 纠正
        bits += sf
        subframes.append((start, sf_id, sow, info))
    flip_from = subframes[4][0] - 40           # 第 5 个子帧前 40 bit 起整体反相
    tx = [b ^ (1 if i >= flip_from else 0) for i, b in enumerate(bits)]
    write_text(os.path.join(OUT, "nav_bits.hex"), "".join(f"{b}\n" for b in tx))
    lines = [f"{len(tx)} {len(subframes)} {flip_from}"]
    for start, sf_id, sow, info in subframes:
        word = int("".join(map(str, info)), 2)
        lines.append(f"{start} {sf_id} {sow} {word:056x}")
    write_text(os.path.join(OUT, "nav_expected.txt"), "\n".join(lines) + "\n")
    print(f"nav_bits.hex: {len(tx)} bits, {len(subframes)} subframes, flip at {flip_from}")


def gen_bitsync() -> None:
    """Prompt I 序列：第 0 个窗口为不完整窗口；位起点标签 ≡ P0 (mod 20)。"""
    rng = np.random.default_rng(5)
    p0, n_win, amp, sigma = 13, 1400, 200000.0, 100000.0
    nh = np.array(prn_b1i.NH20)
    n_bits = n_win // 20 + 2
    data = rng.integers(0, 2, n_bits)
    vals = []
    for m in range(n_win):
        b = (m - p0) // 20 + 1                 # m < p0 时属于第 0 个（不完整）比特
        k = (m - p0) % 20
        chip = data[b] ^ nh[k]
        vals.append(int(round(amp * (1 - 2 * chip) + rng.normal(0, sigma))))
    write_text(os.path.join(OUT, "bs_input.hex"),
               "".join(f"{v & 0xFFFFFFFF:08x}\n" for v in vals))
    # 期望：每个完整比特（起始标签 s ≡ p0）及其数据值
    lines = [f"{p0} {n_win}"]
    for s in range(p0, n_win - 19, 20):
        lines.append(f"{s} {int(data[(s - p0) // 20 + 1])}")
    write_text(os.path.join(OUT, "bs_expected.txt"), "\n".join(lines) + "\n")
    print(f"bs_input.hex: {n_win} windows, bit phase {p0}")


def gen_sync_frames() -> None:
    """D1 robustness: week rollover and BCH-valid but inconsistent headers."""
    frames, infos = [], []
    for k in range(12):
        fid = (3 + k) % 5 + 1
        sow = (604788 + 6*k) % 604800
        frame = d1_nav.encode_subframe(fid, {"SOW": sow, "WN": 951, "Pnum": 3})
        info, fixes, ok = d1_nav.decode_subframe(frame)
        assert ok and fixes == 0
        frames.append(frame)
        infos.append((fid, sow, info))
    # Re-encode all affected codewords: range and continuity tests must not
    # rely on corrupt parity or on an uncorrectable two-bit BCH assumption.
    for fid, sow in [(5, 604788), (3, 604794), (0, 604794), (5, 604800)]:
        info = list(infos[1][2])
        info[15:18] = [int(b) for b in f"{fid:03b}"]
        info[18:38] = [int(b) for b in f"{sow:020b}"]
        frame = prn_b1i.encode_word(info[:26], first_word=True)
        for w in range(9):
            frame += prn_b1i.encode_word(info[26+22*w:48+22*w], first_word=False)
        frames.append(frame)
        infos.append((fid, sow, info))
    write_text(os.path.join(OUT, "sync_frames.hex"), "".join(
        f"{int(''.join(map(str, frame)), 2):075x}\n" for frame in frames))
    write_text(os.path.join(OUT, "sync_frames_expected.txt"), "".join(
        f"{fid} {sow} {int(''.join(map(str, info)), 2):056x}\n" for fid, sow, info in infos))
    print(f"sync_frames.hex: {len(frames)} frames (12 consecutive, 4 invalid headers)")


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    gen_prn()
    gen_nav()
    gen_bitsync()
    gen_sync_frames()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
