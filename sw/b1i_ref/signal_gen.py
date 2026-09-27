"""合成 B1I 实中频信号（2 bit 量化）——参考模型的输入源。

信号模型（与课程 PDF 一致）：
    s[n] = A · d · nh · prn · cos( 2π (f_IF + f_D) n / Fs + φ0 )

码值约定（与 RTL 一致，见 rtl/track/correlator_epl.sv）：
    bit = 1 -> +1 ；bit = 0 -> -1      （即 code_val = 2*bit - 1）
2 bit 量化：就近取 {-3, -1, +1, +3}，超幅截断。
"""

from __future__ import annotations

import numpy as np

from . import params as _p

P = _p.P

LEVELS = np.array([-3, -1, 1, 3], dtype=np.int64)


def quantize_2bit(x: np.ndarray) -> np.ndarray:
    """把浮点样本就近量化到 {-3,-1,+1,+3}。"""
    idx = np.argmin(np.abs(x[:, None] - LEVELS[None, :]), axis=1)
    return LEVELS[idx]


def code_value(bits) -> np.ndarray:
    return 2 * np.asarray(bits, dtype=np.int64) - 1


def make_if_signal(n_samples: int,
                   code_bits: list,
                   nh_bits: list,
                   data_bits: list,
                   code_phase_chips: float,
                   doppler_hz: float,
                   amplitude: float = 2.6,
                   carrier_phase_rad: float = 0.0,
                   noise_sigma: float = 0.0,
                   seed: int = 0,
                   quantize: bool = True) -> np.ndarray:
    """生成 n_samples 个样本（实中频，已 2 bit 量化）。"""
    n = np.arange(n_samples, dtype=np.int64)
    fs, f_if = P.f_s_hz, P.f_if_hz

    # 载波：相位按 (n+1) 步计，与接收机 NCO 的约定一致
    #   接收机在每个样本上先累加相位、再用新相位混频，故样本 n 用 (n+1) 个步进
    phase = 2.0 * np.pi * (f_if + doppler_hz) * (n + 1) / fs + carrier_phase_rad
    carrier = np.cos(phase)

    # 测距码：码相位以"码片"为单位随时间推进
    chips_per_sample = P.code_chips_per_period / P.samples_per_ms
    chip_pos = np.mod(code_phase_chips + chips_per_sample * n, P.code_chips_per_period)
    chip_idx = np.floor(chip_pos).astype(np.int64) % P.code_chips_per_period
    code = code_value(code_bits)[chip_idx]

    # NH20 与数据位：1 个数据位 = 20 个 PRN 周期 = 20 ms
    ms_idx = n // P.samples_per_ms
    nh_val = code_value(nh_bits)[ms_idx % len(nh_bits)]
    bit_idx = ms_idx // len(nh_bits)
    data = code_value(data_bits)[np.mod(bit_idx, len(data_bits))]

    x = amplitude * data * nh_val * code * carrier
    if noise_sigma > 0.0:
        rng = np.random.default_rng(seed)
        x = x + rng.normal(0.0, noise_sigma, size=n_samples)
    return quantize_2bit(x) if quantize else x


def pack_2bit(samples: np.ndarray) -> np.ndarray:
    """4 个样本打包成 1 字节，早样本在 [7:6]（与 REQ-SIG-005 一致）。"""
    s = np.asarray(samples, dtype=np.int64)
    if s.size % 4 != 0:
        pad = 4 - (s.size % 4)
        s = np.concatenate([s, np.zeros(pad, dtype=np.int64)])
    code = np.searchsorted(LEVELS, s).astype(np.uint8)   # -3,-1,+1,+3 -> 0,1,2,3
    code = code.reshape(-1, 4)
    return ((code[:, 0] << 6) | (code[:, 1] << 4) | (code[:, 2] << 2) | code[:, 3]).astype(np.uint8)


def cn0_to_amplitude(cn0_dbhz: float, bandwidth_hz: float = None) -> float:
    """粗略换算：给定期望 C/N0 时，量化前的信号幅度（便于性能扫描时设定）。"""
    bw = bandwidth_hz if bandwidth_hz else P.f_s_hz
    cn0 = 10.0 ** (cn0_dbhz / 10.0)
    # 噪声方差 σ² = Fs / (2*C/N0)（双边），幅度取 A=2.6 作为强信号参考
    return float(np.sqrt(2.0 * cn0)) if cn0 > 0 else 0.0
