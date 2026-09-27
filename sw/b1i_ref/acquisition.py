"""捕获参考模型：码相位 × 多普勒二维搜索（浮点"真值"搜索）。

RTL `acquisition_engine` 在同一假设网格上串行搜索；本模块用 FFT 圆相关
一次性给出全部码相位的相关值，作为捕获结果的参考（golden）。

判决统计量：1 ms 相干积分后的 |I| + |Q|/2（与跟踪环路的幅度估计一致）。
"""

from __future__ import annotations

import numpy as np

from . import params as _p

P = _p.P


def code_pm1(code_bits) -> np.ndarray:
    return 2 * np.asarray(code_bits, dtype=np.float64) - 1.0


def code_replica(code_bits, n_samples: int) -> np.ndarray:
    """把 ±1 码表升采样到采样率（每码片 16384/2046 ≈ 8.0078 个样本）。"""
    code = code_pm1(code_bits)
    L = code.size
    idx = (np.arange(n_samples, dtype=np.int64) * L // n_samples) % L
    return code[idx]


def correlate_1ms(samples: np.ndarray, code_bits, doppler_hz: float,
                  carrier_phase_rad: float = 0.0) -> np.ndarray:
    """循环相关，返回长度 = 1 ms 样本数；索引 = 样本偏移。

    码相位(chip) = 峰值样本索引 * 码长 / 样本数。
    """
    n = samples.size
    fs, f_if = P.f_s_hz, P.f_if_hz
    k = np.arange(n, dtype=np.float64)
    lo = np.exp(-1j * (2.0 * np.pi * (f_if + doppler_hz) * k / fs + carrier_phase_rad))
    base = samples.astype(np.float64) * lo
    rep = code_replica(code_bits, n)
    return np.fft.ifft(np.fft.fft(base) * np.conj(np.fft.fft(rep)))


def peak_to_code_phase(peak_sample: int, n_samples: int, code_len: int) -> float:
    return float(peak_sample) * code_len / float(n_samples)


def magnitude(iq: np.ndarray) -> np.ndarray:
    return np.abs(iq.real) + 0.5 * np.abs(iq.imag)


def serial_search(samples: np.ndarray, code_bits, doppler_list, threshold: float = 0.0):
    """在给定的多普勒列表上搜索码相位，返回峰值列表（按幅度降序）。"""
    hits = []
    for fd in doppler_list:
        corr = correlate_1ms(samples, code_bits, fd)
        mag = magnitude(corr)
        idx = int(np.argmax(mag))
        hits.append({"doppler_hz": float(fd), "code_phase_chips": float(idx),
                     "peak_mag": float(mag[idx]), "threshold": float(threshold),
                     "detected": bool(mag[idx] > threshold)})
    hits.sort(key=lambda h: -h["peak_mag"])
    return hits


def coarse_doppler_grid(span_hz: float = 10000.0, step_hz: float = 500.0):
    n = int(round(span_hz / step_hz))
    return [i * step_hz for i in range(-n, n + 1)]


def doppler_search(samples: np.ndarray, code_bits, span_hz: float = 10000.0,
                   step_hz: float = 500.0, threshold: float = 0.0):
    return serial_search(samples, code_bits, coarse_doppler_grid(span_hz, step_hz), threshold)
