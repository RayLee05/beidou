"""单通道跟踪链路的定点参考模型 —— 与 RTL 逐位等价（golden model）。

对应 RTL：rtl/track/tracking_channel.sv 及其子模块
  carrier_mixer_nco.sv  载波 NCO + 混频（32 bit 相位，10 bit 查表）
  code_nco.sv           码 NCO（48 bit，Q(11.37)），越过码周期即"码周期边界"
  code_ram.sv           E/P/L 三抽头（E = P + spacing/8 chip，L = P - spacing/8 chip）
  correlator_epl.sv     E/P/L × I/Q 相干累加
  track_loop.sv         归一化鉴别器 + PLL/FLL/DLL + 锁定检测（单乘法器状态机）

时序约定（与 RTL 一致）：
  * 积分窗口按本通道的码周期划分：窗口 = 上一个"越界样本"之后，到下一个越界样本（含）。
    越界样本的码相位已经回绕到新周期的码片 0，但仍计入上一窗口（每窗口只差 1 个样本）。
  * 一个窗口内载波频率字与码增量保持不变；窗口 j 的观测量计算出的新参数，
    在窗口 j+1 结束时（下一个越界样本）生效，即用于窗口 j+2。
  * 装载后的第 0 个窗口是不完整窗口：照常输出观测量，但不参与环路更新。
  * ms_count：装载时清零，每个越界样本加 1；窗口 j 的观测量带标签 j。
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from . import params as _p
from .carrier_lut import COS, SIN

P = _p.P

PHASE_MASK = (1 << 32) - 1
CODE_PERIOD = P.code_nco_period
CODE_INC_NOMINAL = P.code_nco_inc_nominal
CODE_FRAC = P.code_nco_frac_w
FREQ_WORD_IF = P.freq_word_if
DOP_MAX = P.freq_word_dop_max


def _recip_table() -> list:
    return [int(round(2 ** 15 / (1.0 + (m + 0.5) / 32.0))) for m in range(32)]


RECIP = _recip_table()


def sat16(v: int) -> int:
    return -32768 if v < -32768 else (32767 if v > 32767 else v)


def clamp(v: int, lim: int) -> int:
    return -lim if v < -lim else (lim if v > lim else v)


def to_s32(v: int) -> int:
    v &= PHASE_MASK
    return v - (1 << 32) if v >= (1 << 31) else v


def doppler_to_word(hz: float) -> int:
    return int(round(hz / P.f_s_hz * (1 << P.nco_phase_w)))


def word_to_doppler(w: int) -> float:
    return to_s32(w) * P.f_s_hz / (1 << P.nco_phase_w)


def chips_to_code_phase(chips: float) -> int:
    return int(round(chips * (1 << CODE_FRAC))) % CODE_PERIOD


@dataclass
class LoopConfig:
    pll_kp: int = P.pll_kp_default
    pll_ki: int = P.pll_ki_default
    fll_k: int = P.fll_k_default
    dll_kp: int = P.dll_kp_default
    dll_ki: int = P.dll_ki_default
    fll_en: bool = True
    spacing: int = P.code_spacing_default


class LoopState:
    """track_loop.sv 的逐位模型。"""

    def __init__(self, cfg: LoopConfig, init_dop_word: int):
        self.cfg = cfg
        self.facc = clamp(init_dop_word, DOP_MAX)
        self.dacc = 0
        self.amp = 0
        self.have_amp = False
        self.have_prev = False
        self.ipn_prev = 0
        self.qpn_prev = 0
        self.blk_i = 0
        self.blk_q = 0
        self.blk_n = 0
        self.lock_cnt = 0
        self.locked = False
        self.dbg = {}

    @staticmethod
    def _mag(i: int, q: int) -> int:
        return abs(i) + (abs(q) >> 1)

    def outputs(self, p_pll: int = 0, p_dll: int = 0) -> tuple:
        freq_word = (FREQ_WORD_IF + self.facc + p_pll) & PHASE_MASK
        aid = (self.facc * P.code_aid_coef) >> P.code_aid_shift
        code_inc = CODE_INC_NOMINAL + aid + p_dll + self.dacc
        return freq_word, code_inc

    def update(self, ie, qe, ip, qp, il, ql) -> tuple:
        c = self.cfg
        mag_p = self._mag(ip, qp)
        mag_e = self._mag(ie, qe)
        mag_l = self._mag(il, ql)
        # 幅度估计与归一化系数
        if not self.have_amp:
            amp = mag_p
            self.have_amp = True
        else:
            amp = self.amp + ((mag_p - self.amp) >> P.amp_shift)
        self.amp = amp
        amp_eff = max(amp, P.amp_min)
        L = amp_eff.bit_length() - 1
        m = (amp_eff >> (L - 5)) & 31
        recip = RECIP[m]
        sh = L + 15 - P.norm_w

        def norm(x):
            return (x * recip) >> sh

        ipn = sat16(norm(ip))
        qpn = sat16(norm(qp))
        d_dll = sat16(norm(mag_e - mag_l))
        d_pll = sat16(qpn if ipn >= 0 else -qpn)
        if self.have_prev:
            cross = self.ipn_prev * qpn - ipn * self.qpn_prev
            dot = self.ipn_prev * ipn + self.qpn_prev * qpn
            d_fll = sat16((cross if dot >= 0 else -cross) >> 12)
        else:
            d_fll = 0
        self.ipn_prev, self.qpn_prev, self.have_prev = ipn, qpn, True

        p_pll = (c.pll_kp * d_pll) >> 14
        i_pll = (c.pll_ki * d_pll) >> 14
        f_fll = ((c.fll_k * d_fll) >> 14) if c.fll_en else 0
        self.facc = clamp(self.facc + i_pll + f_fll, DOP_MAX)

        p_dll = (c.dll_kp * d_dll) >> 8
        i_dll = (c.dll_ki * d_dll) >> 8
        self.dacc = clamp(self.dacc + i_dll, P.dll_acc_max)

        # 锁定检测：每 lock_block 个窗口比较一次 Σ|I| 与 2Σ|Q|
        self.blk_i += abs(ip)
        self.blk_q += abs(qp)
        self.blk_n += 1
        if self.blk_n == P.lock_block:
            ok = self.blk_i > 2 * self.blk_q
            if ok:
                self.lock_cnt = min(self.lock_cnt + 1, P.lock_max)
            else:
                self.lock_cnt = max(self.lock_cnt - 1, 0)
            if self.lock_cnt >= P.lock_on:
                self.locked = True
            elif self.lock_cnt == 0:
                self.locked = False
            self.blk_i = self.blk_q = self.blk_n = 0

        self.dbg = {"amp": amp, "d_pll": d_pll, "d_fll": d_fll, "d_dll": d_dll,
                    "ipn": ipn, "qpn": qpn}
        return self.outputs(p_pll, p_dll)


class TrackingChannel:
    """定点单通道跟踪模型：按样本流推进，按码周期输出观测量。"""

    def __init__(self, code_bits, cfg: LoopConfig = None):
        self.code = 2 * np.asarray(code_bits, dtype=np.int64) - 1
        self.cfg = cfg or LoopConfig()
        self.cos = np.asarray(COS, dtype=np.int64)
        self.sin = np.asarray(SIN, dtype=np.int64)
        self.reset()

    def reset(self, code_phase_chips: float = 0.0, doppler_hz: float = 0.0,
              carrier_phase: int = 0, code_phase_word: int = None, dop_word: int = None):
        dop = doppler_to_word(doppler_hz) if dop_word is None else int(dop_word)
        self.loop = LoopState(self.cfg, dop)
        self.carrier_phase = int(carrier_phase) & PHASE_MASK
        self.code_phase = (chips_to_code_phase(code_phase_chips) if code_phase_word is None
                           else int(code_phase_word) % CODE_PERIOD)
        self.freq_word, self.code_inc = self.loop.outputs()
        self.pending = (self.freq_word, self.code_inc)
        self.ms_count = 0
        self.n_samples = 0
        self.acc = np.zeros(6, dtype=np.int64)
        self.partial = True

    # ------------------------------------------------------------------
    def _window_len(self, avail: int) -> tuple:
        """当前参数下，从下一个样本起到越界样本（含）的样本数；超过 avail 返回 (avail, False)。"""
        k = (CODE_PERIOD - self.code_phase + self.code_inc - 1) // self.code_inc
        if k <= avail:
            return k, True
        return avail, False

    def _accumulate(self, s: np.ndarray):
        n = s.size
        k = np.arange(1, n + 1, dtype=np.int64)
        ph = (self.carrier_phase + self.freq_word * k) & PHASE_MASK
        lut = ph >> (P.nco_phase_w - P.carr_lut_addr_w)
        mix_i = s * self.cos[lut]
        mix_q = -(s * self.sin[lut])
        cp = (self.code_phase + self.code_inc * k) % CODE_PERIOD
        d = self.cfg.spacing << (CODE_FRAC - 3)
        chip_p = cp >> CODE_FRAC
        chip_e = ((cp + d) % CODE_PERIOD) >> CODE_FRAC
        chip_l = ((cp - d) % CODE_PERIOD) >> CODE_FRAC
        ce, cpp, cl = self.code[chip_e], self.code[chip_p], self.code[chip_l]
        self.acc += np.array([(mix_i * ce).sum(), (mix_q * ce).sum(),
                              (mix_i * cpp).sum(), (mix_q * cpp).sum(),
                              (mix_i * cl).sum(), (mix_q * cl).sum()], dtype=np.int64)
        self.carrier_phase = int(ph[-1])
        self.code_phase = int(cp[-1])

    def process(self, samples) -> list:
        """推进一段样本，返回期间完成的窗口观测量列表。"""
        s_all = np.asarray(samples, dtype=np.int64)
        out = []
        pos = 0
        while pos < s_all.size:
            n, done = self._window_len(s_all.size - pos)
            self._accumulate(s_all[pos:pos + n])
            pos += n
            self.n_samples += n
            if not done:
                break
            ie, qe, ip, qp, il, ql = (int(v) for v in self.acc)
            # dump 时刻 RTL 可观测的量：环路状态仍是上一次更新的结果
            lp = self.loop
            rec = {"ms": self.ms_count, "i_e": ie, "q_e": qe, "i_p": ip, "q_p": qp,
                   "i_l": il, "q_l": ql, "partial": self.partial,
                   "win_freq_word": self.freq_word, "win_code_inc": self.code_inc,
                   "dop_word": lp.facc, "locked": lp.locked, "lock_cnt": lp.lock_cnt,
                   "d_pll": lp.dbg.get("d_pll", 0), "d_fll": lp.dbg.get("d_fll", 0),
                   "d_dll": lp.dbg.get("d_dll", 0)}
            # 越界样本：生效上一轮计算好的参数，计数加一
            self.freq_word, self.code_inc = self.pending
            self.ms_count += 1
            if not self.partial:
                self.pending = self.loop.update(ie, qe, ip, qp, il, ql)
            rec["freq_word"] = self.freq_word            # 已切换到下一窗口的值
            rec["code_phase"] = self.code_phase >> (CODE_FRAC - P.code_frac_w)
            rec["sample_end"] = self.n_samples - 1      # 越界样本在本通道样本流中的序号
            self.partial = False
            self.acc[:] = 0
            out.append(rec)
        return out
