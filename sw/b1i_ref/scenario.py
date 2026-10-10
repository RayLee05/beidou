"""多星 B1I 中频场景生成器（软件信号源，用于参考模型与 RTL 测试向量）。

信号模型（以卫星时间驱动，NH/数据位与测距码周期严格同步）：
  t_rx(n)  = t0 + n / Fs                      接收机本地时间（BDT 周内秒）
  t_true   = t_rx - b_rx                      真实时间（b_rx 为接收机钟差）
  t_sv     = t_true - tau + dt_sv(t_tx)       卫星钟时间（tau 为几何传播时延，含 Sagnac）
  码片     = floor(t_sv × 2.046e6) mod 2046
  NH 码片  = floor(t_sv × 1000) mod 20；数据位 = D1 电文第 floor(t_sv × 50) 位
  中频相位 = fIF·t_rx + f_B1·(t_sv - t_rx) + φ0   （单位：周）
  x[n]     = Σ A_k · d · nh · c · cos(2π·相位) + 噪声，再 2 bit 量化

钟差 dt_sv 按广播参数（含相对论项，并扣 TGD1）生成，定位端用同一公式改正后即还原真值。
不加电离层/对流层延迟（定位端也不做这两项改正），使端到端误差只来自接收处理。
"""
from __future__ import annotations

import json
import math
import os
from dataclasses import dataclass, field

import numpy as np

from . import d1_nav, prn_b1i
from . import params as _p

P = _p.P
C = d1_nav.C_LIGHT
F_B1 = P.f_rf_hz
FS = P.f_s_hz
F_IF = P.f_if_hz
WGS_A = 6378137.0
WGS_F = 1.0 / 298.257222101


def geodetic_to_ecef(lat_deg: float, lon_deg: float, h: float) -> np.ndarray:
    lat, lon = math.radians(lat_deg), math.radians(lon_deg)
    e2 = WGS_F * (2 - WGS_F)
    n = WGS_A / math.sqrt(1 - e2 * math.sin(lat) ** 2)
    return np.array([(n + h) * math.cos(lat) * math.cos(lon),
                     (n + h) * math.cos(lat) * math.sin(lon),
                     (n * (1 - e2) + h) * math.sin(lat)])


def ecef_to_geodetic(xyz) -> tuple:
    x, y, z = xyz
    e2 = WGS_F * (2 - WGS_F)
    lon = math.atan2(y, x)
    p = math.hypot(x, y)
    lat = math.atan2(z, p * (1 - e2))
    h = 0.0
    for _ in range(10):
        n = WGS_A / math.sqrt(1 - e2 * math.sin(lat) ** 2)
        h = p / math.cos(lat) - n
        lat = math.atan2(z, p * (1 - e2 * n / (n + h)))
    return math.degrees(lat), math.degrees(lon), h


def elevation_deg(rx: np.ndarray, sat: np.ndarray) -> float:
    lat, lon, _ = ecef_to_geodetic(rx)
    la, lo = math.radians(lat), math.radians(lon)
    up = np.array([math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la)])
    d = sat - rx
    return math.degrees(math.asin(float(np.dot(d, up)) / float(np.linalg.norm(d))))


def sagnac_rotate(pos, tau: float) -> np.ndarray:
    """把发射时刻的地固系坐标转到接收时刻的地固系（地球在 tau 内转过的角度）。"""
    th = d1_nav.OMEGA_E * tau
    c, s = math.cos(th), math.sin(th)
    x, y, z = pos
    return np.array([c * x + s * y, -s * x + c * y, z])


# ---------------------------------------------------------------- 星座
def make_constellation(rx: np.ndarray, sow0: float, wn: int, n_sats: int = 8,
                       seed: int = 7, min_elev: float = 15.0) -> list:
    """随机生成 MEO/IGSO 星历，挑选在 sow0 时刻仰角高于 min_elev 的卫星。"""
    rng = np.random.default_rng(seed)
    toe = float(int(sow0 // 3600) * 3600)
    prns = list(range(6, 38))
    rng.shuffle(prns)
    out = []
    for prn in prns:
        igso = prn <= 10
        for _ in range(400):
            eph = d1_nav.Ephemeris(
                prn=prn, WN=wn, toe=toe, toc=toe,
                sqrtA=(6493.5 if igso else 5282.6) + rng.normal(0, 0.5),
                e=abs(rng.normal(0.002, 0.001)), i0=math.radians(55.0 + rng.normal(0, 0.5)),
                OMEGA0=rng.uniform(-math.pi, math.pi), omega=rng.uniform(-math.pi, math.pi),
                M0=rng.uniform(-math.pi, math.pi), dn=rng.normal(4e-9, 5e-10),
                OMEGADOT=rng.normal(-6.8e-9, 2e-10), IDOT=rng.normal(0, 1e-10),
                Cuc=rng.normal(0, 5e-6), Cus=rng.normal(0, 5e-6), Crc=rng.normal(150, 50),
                Crs=rng.normal(0, 50), Cic=rng.normal(0, 5e-8), Cis=rng.normal(0, 5e-8),
                a0=rng.normal(0, 3e-4), a1=rng.normal(0, 3e-11), a2=0.0,
                TGD1=rng.normal(5e-9, 3e-9), TGD2=0.0, AODE=int(rng.integers(0, 24)),
                AODC=int(rng.integers(0, 24)), URAI=1, SatH1=0,
                iono={"alpha0": 1.4e-8, "alpha1": 0.0, "alpha2": -6e-8, "alpha3": 0.0,
                      "beta0": 90112.0, "beta1": 0.0, "beta2": -196608.0, "beta3": 0.0})
            eph = eph.quantized()
            if elevation_deg(rx, np.array(eph.position(sow0))) >= min_elev:
                out.append(eph)
                break
        if len(out) >= n_sats:
            break
    return out


# ---------------------------------------------------------------- D1 比特流
class NavBits:
    """按 BDT 周内比特序号给出 D1 电文比特（子帧 1-3 为真实星历，4/5 为带 BCH 的占位页）。"""

    def __init__(self, eph: d1_nav.Ephemeris):
        self.eph = eph
        self._cache = {}

    def subframe(self, sf_index: int) -> list:
        """sf_index = 周内子帧序号（SOW // 6）。"""
        if sf_index not in self._cache:
            sow = sf_index * 6
            sf_id = sf_index % 5 + 1
            if sf_id <= 3:
                vals = self.eph.subframe_values(sow)[sf_id]
            else:
                vals = {"SOW": sow, "Pnum": (sf_index // 5) % 24 + 1}
            self._cache[sf_index] = np.array(d1_nav.encode_subframe(sf_id, vals), dtype=np.int8)
        return self._cache[sf_index]

    def bits(self, bit_idx: np.ndarray) -> np.ndarray:
        """bit_idx：周内比特序号数组。"""
        out = np.empty(bit_idx.size, dtype=np.int8)
        sf = bit_idx // 300
        for s in np.unique(sf):
            m = sf == s
            out[m] = self.subframe(int(s))[bit_idx[m] - s * 300]
        return out


# ---------------------------------------------------------------- 场景
@dataclass
class SatConfig:
    eph: d1_nav.Ephemeris
    cn0_dbhz: float = 45.0
    phase0_cycles: float = 0.0
    amplitude: float = None      # 不为 None 时直接指定幅度（无噪声确定性测试用）


@dataclass
class Scenario:
    rx_ecef: np.ndarray
    sow0: float                  # 第 0 个样本的接收机本地时间（周内秒）
    wn: int
    sats: list
    rx_clock_bias: float = 0.0   # 接收机钟差 b_rx（s）
    noise_sigma: float = 1.0     # 0 = 无噪声
    quant_threshold: float = 1.0
    seed: int = 1
    grid_dt: float = 1e-3
    _tau_cache: dict = field(default_factory=dict, repr=False)
    _nav: dict = field(default_factory=dict, repr=False)

    # -------- 传播时延
    def geometry(self, eph, t_true: float) -> tuple:
        """返回 (tau, t_tx, sat_pos_rx_frame)。"""
        tau = 0.075
        for _ in range(6):
            t_tx = t_true - tau
            pos = sagnac_rotate(eph.position(t_tx), tau)
            tau = float(np.linalg.norm(pos - self.rx_ecef)) / C
        return tau, t_true - tau, pos

    def sv_offset(self, eph, t_true: np.ndarray) -> np.ndarray:
        """d(t) = t_sv - t_rx（秒），在 grid_dt 网格上精确求解后线性插值。"""
        t0 = float(t_true[0]) - self.grid_dt
        t1 = float(t_true[-1]) + self.grid_dt
        g = np.arange(math.floor(t0 / self.grid_dt), math.ceil(t1 / self.grid_dt) + 1) * self.grid_dt
        vals = []
        for tg in g:
            key = (eph.prn, round(tg / self.grid_dt))
            if key not in self._tau_cache:
                tau, t_tx, _ = self.geometry(eph, tg)
                self._tau_cache[key] = -tau + eph.clock_bias(t_tx) - self.rx_clock_bias
            vals.append(self._tau_cache[key])
        return np.interp(t_true, g, np.array(vals))

    # -------- 样本
    def samples(self, n0: int, n: int, *, noise_rng=None) -> np.ndarray:
        """生成第 n0..n0+n-1 个样本（int8，取值 ±1/±3）。"""
        idx = np.arange(n0, n0 + n, dtype=np.int64)
        t_rel = idx / FS                                    # 相对 sow0 的本地时间
        sow_int = math.floor(self.sow0)
        frac0 = self.sow0 - sow_int
        x = np.zeros(n, dtype=np.float64)
        for sc in self.sats:
            eph = sc.eph
            d = self.sv_offset(eph, self.sow0 + t_rel - self.rx_clock_bias)
            tsv_rel = frac0 + t_rel + d                     # t_sv - sow_int
            chips = np.floor(tsv_rel * P.code_rate_hz).astype(np.int64)
            code = np.asarray(prn_b1i.prn_code(eph.prn), dtype=np.int8)[chips % 2046]
            ms = np.floor(tsv_rel * 1000.0).astype(np.int64)
            nh = np.asarray(prn_b1i.NH20, dtype=np.int8)[ms % 20]
            bit_idx = sow_int * 50 + np.floor(tsv_rel * 50.0).astype(np.int64)
            if eph.prn not in self._nav:
                self._nav[eph.prn] = NavBits(eph)
            data = self._nav[eph.prn].bits(bit_idx)
            chip = code ^ nh ^ data                          # 模二加
            sign = 1.0 - 2.0 * chip                          # 0 -> +1, 1 -> -1
            ph = (idx % 4) / 4.0 + frac0 * F_IF + F_B1 * d + sc.phase0_cycles
            amp = sc.amplitude
            if amp is None:
                cn0 = 10 ** (sc.cn0_dbhz / 10.0)
                amp = self.noise_sigma * math.sqrt(4.0 * cn0 / FS)
            x += amp * sign * np.cos(2.0 * np.pi * ph)
        if self.noise_sigma > 0:
            # 分块调用可传入同一个 RNG，保持与一次性生成完全相同的噪声序列。
            rng = noise_rng if noise_rng is not None else np.random.default_rng([self.seed, n0])
            x += rng.normal(0.0, self.noise_sigma, n)
        th = self.quant_threshold * (self.noise_sigma if self.noise_sigma > 0 else 1.0)
        q = np.where(x >= 0, np.where(x >= th, 3, 1), np.where(x < -th, -3, -1))
        return q.astype(np.int8)

    # -------- 真值
    def truth(self, n: int) -> dict:
        """第 n 个样本时刻的真值：每星码相位（chip）、多普勒（Hz）、伪距（m）。"""
        t_rx = self.sow0 + n / FS
        t_true = t_rx - self.rx_clock_bias
        out = {}
        for sc in self.sats:
            eph = sc.eph
            d = float(self.sv_offset(eph, np.array([t_true]))[0])
            d2 = float(self.sv_offset(eph, np.array([t_true + 1e-3]))[0])
            t_sv = t_rx + d
            out[eph.prn] = {
                "code_phase_chips": (t_sv * P.code_rate_hz) % 2046.0,
                "doppler_hz": F_B1 * (d2 - d) / 1e-3,
                "pseudorange_m": -d * C,
                "t_sv": t_sv,
            }
        return out


def write_sram_image(path: str, samples: np.ndarray) -> None:
    """写 SRAM 字节镜像（每字节 4 样本，早样本在 [7:6]）。"""
    from .signal_gen import pack_2bit
    pack_2bit(samples.astype(np.int64)).tofile(path)


def scenario_metadata(sc: Scenario, n_samples: int) -> dict:
    return {
        "format_version": 1, "sample_encoding": "2bit-pair",
        "sample_rate_hz": FS, "if_hz": F_IF, "byte_order": "sample0_msb",
        "sample_count": int(n_samples), "start_sow_local": sc.sow0, "week": sc.wn,
        "noise_sigma": sc.noise_sigma, "quant_threshold": sc.quant_threshold,
        "seed": sc.seed,
    }


def scenario_truth(sc: Scenario) -> dict:
    lat, lon, h = ecef_to_geodetic(sc.rx_ecef)
    return {
        "rx_ecef": [float(v) for v in sc.rx_ecef], "rx_lat": lat, "rx_lon": lon, "rx_h": h,
        "rx_clock_bias_s": sc.rx_clock_bias, "sow0": sc.sow0, "week": sc.wn,
        "sats": [{"prn": s.eph.prn, "cn0_dbhz": s.cn0_dbhz,
                  "elev_deg": elevation_deg(sc.rx_ecef, np.array(s.eph.position(sc.sow0)))}
                 for s in sc.sats],
    }


def save_truth(path: str, sc: Scenario) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(scenario_truth(sc), f, indent=2)
