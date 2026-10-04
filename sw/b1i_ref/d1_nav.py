"""D1 导航电文：子帧编码/译码、字段表、星历缩放与卫星位置计算。

来源（references/北斗_B1I_B2I_ICD_2.1版_中文版.pdf，PDF 页码）：
  第 20 页 5.2.2 节 / 图 5-6  帧结构：子帧 300 bit = 10 字 × 30 bit
  第 22 页 图 5-8~5-10       子帧 1-3 字段位置（下表的位置即图中标注的比特序号）
  第 25 页 5.2.4.1-5.2.4.3   Pre = 11100010010；FraID；SOW 对应本子帧同步头第一个脉冲上升沿
  第 27/31/34 页 表 5-5/5-7/5-10  比例因子与补码约定
  第 35-36 页 表 5-11        MEO/IGSO 星历用户算法

位置约定：字段位置使用"去交织后、含校验位占位"的子帧比特序号（1..300），
与 ICD 图中标注完全一致。每个字的信息位为：
  字 1：比特 1..26（其后 27..30 为校验）
  字 k（k=2..10）：比特 30(k-1)+1 .. 30(k-1)+22（其后 8 bit 为校验）
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

from . import prn_b1i

PREAMBLE = (1, 1, 1, 0, 0, 0, 1, 0, 0, 1, 0)
SUBFRAME_BITS = 300
WORD_BITS = 30
INFO_BITS = 26 + 9 * 22          # 224

# (字段名, [(起始比特, 位数), ...], 是否补码)  多段按高位在前拼接
SF_COMMON = [
    ("Pre", [(1, 11)], False),
    ("Rev", [(12, 4)], False),
    ("FraID", [(16, 3)], False),
    ("SOW", [(19, 8), (31, 12)], False),
]
SF1 = SF_COMMON + [
    ("SatH1", [(43, 1)], False), ("AODC", [(44, 5)], False), ("URAI", [(49, 4)], False),
    ("WN", [(61, 13)], False), ("toc", [(74, 9), (91, 8)], False),
    ("TGD1", [(99, 10)], True), ("TGD2", [(109, 4), (121, 6)], True),
    ("alpha0", [(127, 8)], True), ("alpha1", [(135, 8)], True),
    ("alpha2", [(151, 8)], True), ("alpha3", [(159, 8)], True),
    ("beta0", [(167, 6), (181, 2)], True), ("beta1", [(183, 8)], True),
    ("beta2", [(191, 8)], True), ("beta3", [(199, 4), (211, 4)], True),
    ("a2", [(215, 11)], True), ("a0", [(226, 7), (241, 17)], True),
    ("a1", [(258, 5), (271, 17)], True), ("AODE", [(288, 5)], False),
]
SF2 = SF_COMMON + [
    ("dn", [(43, 10), (61, 6)], True), ("Cuc", [(67, 16), (91, 2)], True),
    ("M0", [(93, 20), (121, 12)], True), ("e", [(133, 10), (151, 22)], False),
    ("Cus", [(181, 18)], True), ("Crc", [(199, 4), (211, 14)], True),
    ("Crs", [(225, 8), (241, 10)], True), ("sqrtA", [(251, 12), (271, 20)], False),
    ("toe_hi", [(291, 2)], False),
]
SF3 = SF_COMMON + [
    ("toe_lo", [(43, 10), (61, 5)], False), ("i0", [(66, 17), (91, 15)], True),
    ("Cic", [(106, 7), (121, 11)], True), ("OMEGADOT", [(132, 11), (151, 13)], True),
    ("Cis", [(164, 9), (181, 9)], True), ("IDOT", [(190, 13), (211, 1)], True),
    ("OMEGA0", [(212, 21), (241, 11)], True), ("omega", [(252, 11), (271, 21)], True),
    ("Rev3", [(292, 1)], False),
]
SF45 = SF_COMMON + [("Pnum", [(44, 7)], False)]
LAYOUT = {1: SF1, 2: SF2, 3: SF3, 4: SF45, 5: SF45}

# 比例因子（LSB），与 ICD 表 5-5 / 5-7 / 5-10 一致；SC = 半周（π）
SCALE = {
    "toc": 2 ** 3, "a0": 2 ** -33, "a1": 2 ** -50, "a2": 2 ** -66, "TGD1": 0.1e-9,
    "TGD2": 0.1e-9, "alpha0": 2 ** -30, "alpha1": 2 ** -27, "alpha2": 2 ** -24,
    "alpha3": 2 ** -24, "beta0": 2 ** 11, "beta1": 2 ** 14, "beta2": 2 ** 16,
    "beta3": 2 ** 16, "toe": 2 ** 3, "sqrtA": 2 ** -19, "e": 2 ** -33,
    "omega": 2 ** -31, "dn": 2 ** -43, "M0": 2 ** -31, "OMEGA0": 2 ** -31,
    "OMEGADOT": 2 ** -43, "i0": 2 ** -31, "IDOT": 2 ** -43, "Cuc": 2 ** -31,
    "Cus": 2 ** -31, "Crc": 2 ** -6, "Crs": 2 ** -6, "Cic": 2 ** -31, "Cis": 2 ** -31,
}
#: 以"半周"为单位、需要乘 π 换算成弧度的字段
SEMICIRCLE = {"omega", "dn", "M0", "OMEGA0", "OMEGADOT", "i0", "IDOT"}

MU = 3.986004418e14
OMEGA_E = 7.2921150e-5
C_LIGHT = 2.99792458e8
PI = 3.1415926535898
F_REL = -2.0 * math.sqrt(MU) / C_LIGHT ** 2


def _width(parts) -> int:
    return sum(n for _, n in parts)


def info_positions() -> list:
    """去交织后的子帧比特序号（1..300）中，属于信息位的 224 个位置。"""
    pos = list(range(1, 27))
    for k in range(2, 11):
        base = 30 * (k - 1)
        pos += list(range(base + 1, base + 23))
    return pos


_INFO_INDEX = {p: i for i, p in enumerate(info_positions())}


# ---------------------------------------------------------------- 字段打包
def pack_fields(sf_id: int, values: dict) -> list:
    """按字段表生成 300 位"去交织布局"的比特（校验位留 0），返回列表。"""
    bits = [0] * SUBFRAME_BITS
    for name, parts, signed in LAYOUT[sf_id]:
        v = int(values.get(name, 0))
        w = _width(parts)
        if signed:
            if not -(1 << (w - 1)) <= v < (1 << (w - 1)):
                raise ValueError(f"{name}={v} 超出 {w} bit 补码范围")
            v &= (1 << w) - 1
        elif not 0 <= v < (1 << w):
            raise ValueError(f"{name}={v} 超出 {w} bit 范围")
        shift = w
        for start, n in parts:
            shift -= n
            seg = (v >> shift) & ((1 << n) - 1)
            for i in range(n):
                bits[start - 1 + i] = (seg >> (n - 1 - i)) & 1
    return bits


def unpack_fields(sf_id: int, layout_bits) -> dict:
    """从 300 位去交织布局（或 224 位信息位）提取字段原始整数（补码已还原为有符号）。"""
    if len(layout_bits) == INFO_BITS:
        full = [0] * SUBFRAME_BITS
        for p, i in _INFO_INDEX.items():
            full[p - 1] = layout_bits[i]
        layout_bits = full
    out = {}
    for name, parts, signed in LAYOUT[sf_id]:
        v = 0
        for start, n in parts:
            for i in range(n):
                v = (v << 1) | int(layout_bits[start - 1 + i])
        w = _width(parts)
        if signed and v >= (1 << (w - 1)):
            v -= 1 << w
        out[name] = v
    return out


def encode_subframe(sf_id: int, values: dict) -> list:
    """生成发射顺序的 300 bit（含 BCH 与交织）。Pre/FraID 自动填写。"""
    vals = dict(values)
    vals["Pre"] = int("".join(map(str, PREAMBLE)), 2)
    vals["FraID"] = sf_id
    layout = pack_fields(sf_id, vals)
    out = prn_b1i.encode_word(layout[0:26], first_word=True)
    for k in range(2, 11):
        base = 30 * (k - 1)
        out += prn_b1i.encode_word(layout[base:base + 22], first_word=False)
    return out


def decode_subframe(bits300) -> tuple:
    """发射顺序 300 bit -> (224 信息位, 纠错次数, 是否可输出)。

    BCH 再编码校验失败、FraID 不在 1..5、或 SOW≥604800 时 ok=False，
    调用方不得把它当作有效电文（REQ-SYN-004）。
    """
    info, fixes, ok = prn_b1i.decode_word(bits300[0:30], first_word=True)
    for k in range(1, 10):
        i, c, w_ok = prn_b1i.decode_word(bits300[30 * k:30 * k + 30], first_word=False)
        info += i
        fixes += c
        ok = ok and w_ok
    if len(info) != 224:
        return info, fixes, False
    fid = unpack_fields(1, info)["FraID"]
    sow = unpack_fields(1, info)["SOW"]
    if fid < 1 or fid > 5 or sow >= 604800:
        ok = False
    return info, fixes, ok


def subframe_id(info224) -> int:
    return unpack_fields(1, info224)["FraID"]


# ---------------------------------------------------------------- 星历
@dataclass
class Ephemeris:
    """以物理量保存的星历与钟差（单位：s、m、rad、rad/s）。"""
    prn: int
    WN: int = 0
    toe: float = 0.0
    toc: float = 0.0
    sqrtA: float = 0.0
    e: float = 0.0
    i0: float = 0.0
    OMEGA0: float = 0.0
    omega: float = 0.0
    M0: float = 0.0
    dn: float = 0.0
    OMEGADOT: float = 0.0
    IDOT: float = 0.0
    Cuc: float = 0.0
    Cus: float = 0.0
    Crc: float = 0.0
    Crs: float = 0.0
    Cic: float = 0.0
    Cis: float = 0.0
    a0: float = 0.0
    a1: float = 0.0
    a2: float = 0.0
    TGD1: float = 0.0
    TGD2: float = 0.0
    AODE: int = 0
    AODC: int = 0
    URAI: int = 0
    SatH1: int = 0
    iono: dict = field(default_factory=dict)

    # -------- 物理量 <-> 广播整数
    def _raw(self, name: str) -> int:
        v = getattr(self, name)
        if name in SEMICIRCLE:
            v = v / PI
        return int(round(v / SCALE[name]))

    def quantized(self) -> "Ephemeris":
        """返回按广播比例因子量化后的副本（仿真器与接收机应使用同一份值）。"""
        q = Ephemeris(prn=self.prn, WN=self.WN, AODE=self.AODE, AODC=self.AODC,
                      URAI=self.URAI, SatH1=self.SatH1, iono=dict(self.iono))
        for name in SCALE:
            if hasattr(q, name) and name not in ("toe",):
                raw = self._raw(name)
                v = raw * SCALE[name]
                setattr(q, name, v * PI if name in SEMICIRCLE else v)
        q.toe = self._raw("toe") * SCALE["toe"]
        return q

    def subframe_values(self, sow: int) -> dict:
        """生成子帧 1/2/3 的字段原始整数。"""
        toe_raw = self._raw("toe")
        common = {"SOW": sow, "Rev": 0}
        sf1 = dict(common, SatH1=self.SatH1, AODC=self.AODC, URAI=self.URAI, WN=self.WN,
                   toc=self._raw("toc"), TGD1=self._raw("TGD1"), TGD2=self._raw("TGD2"),
                   a0=self._raw("a0"), a1=self._raw("a1"), a2=self._raw("a2"), AODE=self.AODE)
        for k in ("alpha0", "alpha1", "alpha2", "alpha3", "beta0", "beta1", "beta2", "beta3"):
            sf1[k] = int(round(self.iono.get(k, 0.0) / SCALE[k]))
        sf2 = dict(common, dn=self._raw("dn"), Cuc=self._raw("Cuc"), M0=self._raw("M0"),
                   e=self._raw("e"), Cus=self._raw("Cus"), Crc=self._raw("Crc"),
                   Crs=self._raw("Crs"), sqrtA=self._raw("sqrtA"), toe_hi=toe_raw >> 15)
        sf3 = dict(common, toe_lo=toe_raw & 0x7FFF, i0=self._raw("i0"), Cic=self._raw("Cic"),
                   OMEGADOT=self._raw("OMEGADOT"), Cis=self._raw("Cis"),
                   IDOT=self._raw("IDOT"), OMEGA0=self._raw("OMEGA0"),
                   omega=self._raw("omega"), Rev3=0)
        return {1: sf1, 2: sf2, 3: sf3}

    @classmethod
    def from_subframes(cls, prn: int, f1: dict, f2: dict, f3: dict) -> "Ephemeris":
        """由子帧 1/2/3 的原始字段（unpack_fields 输出）还原物理量。"""
        eph = cls(prn=prn)
        eph.WN, eph.AODE, eph.AODC = f1["WN"], f1["AODE"], f1["AODC"]
        eph.URAI, eph.SatH1 = f1["URAI"], f1["SatH1"]
        raw = dict(f1)
        raw.update(f2)
        raw.update(f3)
        raw["toe"] = (f2["toe_hi"] << 15) | f3["toe_lo"]
        for name, sc in SCALE.items():
            if name.startswith(("alpha", "beta")):
                eph.iono[name] = raw[name] * sc
            elif hasattr(eph, name):
                v = raw[name] * sc
                setattr(eph, name, v * PI if name in SEMICIRCLE else v)
        return eph

    # -------- 用户算法（ICD 表 5-11，MEO/IGSO）
    def _ecc_anomaly(self, tk: float) -> tuple:
        A = self.sqrtA ** 2
        n = math.sqrt(MU / A ** 3) + self.dn
        M = self.M0 + n * tk
        E = M
        for _ in range(30):
            E_new = M + self.e * math.sin(E)
            if abs(E_new - E) < 1e-14:
                E = E_new
                break
            E = E_new
        return A, E

    @staticmethod
    def _wrap_tk(tk: float) -> float:
        if tk > 302400:
            tk -= 604800
        elif tk < -302400:
            tk += 604800
        return tk

    def position(self, t: float) -> tuple:
        """t 为信号发射时刻的 BDT 周内秒；返回 CGCS2000 地固系 (x, y, z)，单位 m。"""
        tk = self._wrap_tk(t - self.toe)
        A, E = self._ecc_anomaly(tk)
        e = self.e
        v = math.atan2(math.sqrt(1 - e * e) * math.sin(E), math.cos(E) - e)
        phi = v + self.omega
        s2, c2 = math.sin(2 * phi), math.cos(2 * phi)
        u = phi + self.Cus * s2 + self.Cuc * c2
        r = A * (1 - e * math.cos(E)) + self.Crs * s2 + self.Crc * c2
        i = self.i0 + self.IDOT * tk + self.Cis * s2 + self.Cic * c2
        x, y = r * math.cos(u), r * math.sin(u)
        Om = self.OMEGA0 + (self.OMEGADOT - OMEGA_E) * tk - OMEGA_E * self.toe
        return (x * math.cos(Om) - y * math.cos(i) * math.sin(Om),
                x * math.sin(Om) + y * math.cos(i) * math.cos(Om),
                y * math.sin(i))

    def clock_bias(self, t: float, single_freq_b1i: bool = True) -> float:
        """卫星钟差 Δtsv（含相对论项；B1I 单频再减 TGD1），单位 s。ICD 第 31-32 页。"""
        dt = self._wrap_tk(t - self.toc)
        _, E = self._ecc_anomaly(self._wrap_tk(t - self.toe))
        dtr = F_REL * self.e * self.sqrtA * math.sin(E)
        bias = self.a0 + self.a1 * dt + self.a2 * dt * dt + dtr
        return bias - self.TGD1 if single_freq_b1i else bias


def selftest() -> dict:
    eph = Ephemeris(prn=11, WN=950, toe=345600, toc=345600, sqrtA=5282.6, e=0.0012,
                    i0=0.963, OMEGA0=-1.2, omega=0.5, M0=2.1, dn=4.0e-9, OMEGADOT=-6.8e-9,
                    IDOT=1.0e-10, Cuc=1e-6, Cus=8e-6, Crc=200.0, Crs=20.0, Cic=1e-8, Cis=-2e-8,
                    a0=1.2e-4, a1=3e-11, a2=0.0, TGD1=5.3e-9, AODE=1, AODC=1)
    q = eph.quantized()
    vals = q.subframe_values(sow=345606)
    frames = {k: encode_subframe(k, v) for k, v in vals.items()}
    dec = {}
    fixes = 0
    for k, bits in frames.items():
        bad = list(bits)
        bad[40] ^= 1                         # 每个子帧注入一个单比特错误
        info, f, ok = decode_subframe(bad)
        fixes += f
        assert ok, f"单比特错误应可纠且仍合法 sf={k}"
        dec[k] = unpack_fields(k, info)
    back = Ephemeris.from_subframes(11, dec[1], dec[2], dec[3])
    pos_q = q.position(345600 + 30)
    pos_b = back.position(345600 + 30)
    return {
        "preamble_ok": frames[1][:11] == list(PREAMBLE),
        "fraid_ok": [dec[k]["FraID"] for k in (1, 2, 3)] == [1, 2, 3],
        "sow_ok": dec[2]["SOW"] == 345606,
        "bch_fixes": fixes,
        "roundtrip_pos_err_m": max(abs(a - b) for a, b in zip(pos_q, pos_b)),
        "radius_km": math.sqrt(sum(c * c for c in pos_q)) / 1e3,
        "parity_reject": not decode_subframe(list(PREAMBLE) + [0] * 289)[2],
    }


if __name__ == "__main__":
    import json
    print(json.dumps(selftest(), ensure_ascii=False, indent=2))
