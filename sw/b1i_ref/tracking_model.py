"""单通道跟踪链路的定点参考模型 —— 与 RTL 逐拍等价（golden model）。

对应 RTL 模块:
  rtl/track/carrier_mixer_nco.sv   (载波 NCO + 混频)
  rtl/track/code_nco.sv            (码相位 NCO, Q(11.21))
  rtl/track/code_ram.sv            (E/P/L 三抽头)
  rtl/track/correlator_epl.sv      (1 ms 相干累加)
  rtl/track/dll_loop.sv            (码环)
  rtl/track/fll_pll_loop.sv        (载波环)

时序约定（与 RTL 一致）:
  * 一个 1 ms 窗口内的 16384 个样本共用同一组 (freq_word, code_inc)；
  * 窗口最后一个样本完成后做环路更新，RTL 通过"旁路"让新窗口第一个样本
    立即使用新系数 —— 模型里就是先算和、再更新、下一步用新值。
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from . import params as _p
from .carrier_lut import COS, SIN

P = _p.P

FREQ_WORD_IF = 1 << 30
CODE_PERIOD_WORD = P.code_period_word
CODE_INC_NOMINAL = P.code_inc_nominal
CODE_INC_MIN = P.code_inc_min
CODE_INC_MAX = P.code_inc_max
DOP_MAX = int(P.f_s_hz and 2621440)
SIGN32 = 0xFFFFFFFF


def sat16(v: int) -> int:
    """与 RTL 的 sat16 一致：算术右移后饱和到 16 bit 有符号。"""
    return -32768 if v < -32768 else (32767 if v > 32767 else v)


def doppler_to_word(hz: float) -> int:
    return int(round(hz / P.f_s_hz * (1 << P.nco_phase_w)))


def word_to_doppler(w: int) -> float:
    if w >= (1 << (P.nco_phase_w - 1)):
        w -= (1 << P.nco_phase_w)
    return w * P.f_s_hz / (1 << P.nco_phase_w)


@dataclass
class LoopConfig:
    dll_kp: int = None
    dll_ki: int = None
    pll_kp: int = None
    pll_ki: int = None
    fll_kp: int = None
    disc_shift: int = None
    fll_en: bool = False
    lock_thresh: int = None

    def __post_init__(self):
        self.dll_kp = P.dll_kp_default if self.dll_kp is None else self.dll_kp
        self.dll_ki = P.dll_ki_default if self.dll_ki is None else self.dll_ki
        self.pll_kp = P.pll_kp_default if self.pll_kp is None else self.pll_kp
        self.pll_ki = P.pll_ki_default if self.pll_ki is None else self.pll_ki
        self.fll_kp = P.fll_kp_default if self.fll_kp is None else self.fll_kp
        self.disc_shift = (P.disc_shift_default if self.disc_shift is None
                           else self.disc_shift)
        self.lock_thresh = (P.lock_thresh_default if self.lock_thresh is None
                            else self.lock_thresh)


class TrackingChannel:
    """定点单通道跟踪模型。"""

    def __init__(self, code_bits, spacing: int = 1, cfg: LoopConfig = None):
        self.code = (2 * np.asarray(code_bits, dtype=np.int64) - 1)   # ±1
        self.code_len = int(self.code.size)
        self.spacing = int(spacing)
        self.cfg = cfg or LoopConfig()
        self.cos = np.asarray(COS, dtype=np.int64)
        self.sin = np.asarray(SIN, dtype=np.int64)
        self.reset()

    def reset(self, code_phase_chips: float = 0.0, doppler_hz: float = 0.0,
              carrier_phase: int = 0):
        self.carrier_phase = int(carrier_phase) & SIGN32
        # 初始多普勒装入频率积分器（对应 RTL fll_pll_loop 的 init_doppler 装载），
        # 否则环路会在第一个窗口后把捕获给出的多普勒丢掉
        self.pll_facc = doppler_to_word(doppler_hz)
        self.freq_word = (FREQ_WORD_IF + self.pll_facc) & SIGN32
        self.code_phase = int(round(code_phase_chips * (1 << P.code_frac_w))) % CODE_PERIOD_WORD
        self.code_inc = CODE_INC_NOMINAL
        self.dll_integ = 0
        self.pll_disc_prev = 0
        self.lock_cnt = 0
        self.ms_index = 0

    # ------------------------------------------------------------------
    def step_ms(self, samples: np.ndarray) -> dict:
        """处理恰好 1 ms（16384 个样本）并做一次环路更新，返回本窗口观测量。"""
        s = np.asarray(samples, dtype=np.int64)
        n = s.size
        k = np.arange(1, n + 1, dtype=np.int64)

        # --- 载波 NCO + 混频（与 carrier_mixer_nco.sv 等价）---
        ph = (self.carrier_phase + self.freq_word * k) & SIGN32
        lut = (ph >> (P.nco_phase_w - 10)) & 0x3FF
        mix_i = s * self.cos[lut]
        mix_q = -(s * self.sin[lut])

        # --- 码 NCO（与 code_nco.sv 等价：模 CODE_PERIOD_WORD 累加）---
        cp = (self.code_phase + self.code_inc * k) % CODE_PERIOD_WORD
        chip = cp >> P.code_frac_w
        e_idx = (chip - self.spacing) % self.code_len
        p_idx = chip % self.code_len
        l_idx = (chip + self.spacing) % self.code_len

        i_e = int((mix_i * self.code[e_idx]).sum())
        q_e = int((mix_q * self.code[e_idx]).sum())
        i_p = int((mix_i * self.code[p_idx]).sum())
        q_p = int((mix_q * self.code[p_idx]).sum())
        i_l = int((mix_i * self.code[l_idx]).sum())
        q_l = int((mix_q * self.code[l_idx]).sum())

        self.carrier_phase = int(ph[-1])
        self.code_phase = int(cp[-1])

        self._update_loops(i_e, q_e, i_p, q_p, i_l, q_l)
        self.ms_index += 1

        return {"ms": self.ms_index, "i_e": i_e, "q_e": q_e,
                "i_p": i_p, "q_p": q_p, "i_l": i_l, "q_l": q_l,
                "code_phase": self.code_phase, "code_inc": self.code_inc,
                "freq_word": self.freq_word,
                "doppler_hz": word_to_doppler((self.freq_word - FREQ_WORD_IF) & SIGN32),
                "dll_disc": self.dll_disc, "pll_disc": self.pll_disc,
                "lock_cnt": self.lock_cnt, "locked": self.lock_cnt >= 200}

    # ------------------------------------------------------------------
    def _update_loops(self, i_e, q_e, i_p, q_p, i_l, q_l):
        cfg = self.cfg
        # --- DLL ---
        mag_e = abs(i_e) + (abs(q_e) >> 1)
        mag_l = abs(i_l) + (abs(q_l) >> 1)
        self.dll_disc = sat16((mag_e - mag_l) >> cfg.disc_shift)
        d = self.dll_disc
        p_term = (cfg.dll_kp * d) >> P.loop_coef_frac_w
        i_step = (cfg.dll_ki * d) >> P.loop_coef_frac_w
        self.dll_integ = max(-3840, min(3840, self.dll_integ + i_step))
        # 负反馈：本地码超前 => disc>0 => 降低码率
        self.code_inc = max(CODE_INC_MIN, min(CODE_INC_MAX,
                                              CODE_INC_NOMINAL - p_term - self.dll_integ))

        # --- PLL / FLL ---
        raw = q_p if i_p >= 0 else -q_p
        self.pll_disc = sat16(raw >> cfg.disc_shift)
        d = self.pll_disc
        fll_disc = d - self.pll_disc_prev
        self.pll_disc_prev = d
        p_term = (cfg.pll_kp * d) >> P.loop_coef_frac_w
        i_step = (cfg.pll_ki * d) >> P.loop_coef_frac_w
        f_step = (cfg.fll_kp * fll_disc) >> P.loop_coef_frac_w if cfg.fll_en else 0
        self.pll_facc = max(-DOP_MAX, min(DOP_MAX, self.pll_facc + i_step + f_step))
        self.freq_word = (FREQ_WORD_IF + self.pll_facc + p_term) & SIGN32

        # --- 锁定判决 ---
        mag_p = abs(i_p) + (abs(q_p) >> 1)
        if mag_p > cfg.lock_thresh:
            self.lock_cnt = min(255, self.lock_cnt + 1)
        else:
            self.lock_cnt = max(0, self.lock_cnt - 1)
