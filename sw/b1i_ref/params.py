"""北斗 B1I 基带处理器全局参数（软件侧唯一定义处）。

本模块是"参数单一来源"：RTL 侧镜像为 `rtl/include/b1i_params.svh`，
运行期配置为 `configs/b1i_default.json`，三者由
`scripts/check_params_consistency.py` 强制保持一致。

数据来源与冻结状态：
  - 课程规格（集成电路EDA实验课_课程安排.pdf 第 7/11 页）：IF/Fs/量化/打包/12 通道/1 ms=16384 样本
  - B1I ICD 条目（PRN 码表、NH20 序列、D1 字段）：**待提供**，本文件只固定结构、不写入任何自创码表
  - 来源 PDF 第 10 页给出 IF=4.092 MHz / Fs=16.368 MSps，与课程冲突，见 `docs/requirements.md` 待确认表

任何修改必须同时更新：本文件、b1i_params.svh、configs/b1i_default.json、
docs/requirements.md 的版本记录，并重跑 `scripts/run_all.py`。
"""

from __future__ import annotations

from dataclasses import dataclass, asdict, field
from typing import Dict, Tuple

PARAMS_VERSION = "0.1.0"
PARAMS_DATE = "2026-09-21"


@dataclass(frozen=True)
class B1IParams:
    """物理与协议层参数（仅含已由课程材料明确给出的量）。"""

    # ---- 射频与中频 ----
    f_rf_hz: float = 1561.098e6          # B1I 标称射频
    f_if_hz: float = 4.096e6             # 课程规格；来源 PDF 为 4.092e6（待确认）
    f_s_hz: float = 16.384e6             # 采样率，课程规格；PDF 为 16.368e6（待确认）

    # ---- 量化与打包 ----
    sample_bits: int = 2
    samples_per_byte: int = 4
    sample_code_shift: Tuple[int, ...] = (6, 4, 2, 0)   # 早样本在高位
    sample_levels: Tuple[int, ...] = (-3, -1, 1, 3)     # 00/01/10/11

    # ---- 测距码 / 二级码 / 电文 ----
    code_rate_hz: float = 2.046e6        # PRN 码率
    code_chips_per_period: int = 2046    # 2046 chip / 1 ms
    nh_length: int = 20                  # 20 chip / 20 ms
    d1_bit_rate_bps: float = 50.0        # D1 数据率
    d1_subframe_period_s: int = 6
    d1_subframes_per_frame: int = 5
    d1_frame_period_s: int = 30          # 1 帧 = 5 子帧 = 30 s

    # ---- 接收机结构 ----
    n_channels: int = 12
    epoch_period_s: float = 1.0          # 默认公共接收历元间隔

    # ---- 定点设计（推导见 docs/FIXED_POINT.md）----
    sample_w: int = 3                    # signed，取值 -3..+3
    nco_phase_w: int = 32                # 载波/码 NCO 相位累加器
    carr_lut_addr_w: int = 10            # sin/cos 表地址位宽
    carr_lut_data_w: int = 10            # sin/cos 表数据位宽（signed）
    corr_acc_w: int = 26                 # 1 ms E/P/L 相干累加器（signed）
    bit_acc_w: int = 32                  # 20 ms NH 合并 / 数据位判决累加器
    loop_coef_w: int = 16                # 环路滤波系数（Q2.14）
    loop_coef_frac_w: int = 14
    freq_word_w: int = 32                # 多普勒频率字（signed，f_s 归一化）
    code_phase_w: int = 32               # 码相位（chip 归一化）
    sample_index_w: int = 32             # 官方接口定义；回绕周期见 FIXED_POINT.md
    epoch_id_w: int = 32
    channel_id_w: int = 4                # 12 通道 -> ceil(log2(12)) = 4
    prn_w: int = 6                       # BDS PRN 1..63

    # ---- 吞吐与时钟（目标值，待后端冻结）----
    target_clk_hz: float = 100.0e6
    clk_uncertainty: float = 0.30        # 预留比例：CDC/后端膨胀/裕量

    # ------------------------------------------------------------------
    # 派生量
    # ------------------------------------------------------------------
    @property
    def samples_per_ms(self) -> int:
        return int(round(self.f_s_hz * 1e-3))

    @property
    def samples_per_code_period(self) -> float:
        return self.f_s_hz / (self.code_chips_per_period * 1e3)

    @property
    def ms_per_byte(self) -> float:
        return self.samples_per_byte / self.f_s_hz

    @property
    def input_bytes_per_s(self) -> float:
        return self.f_s_hz / self.samples_per_byte

    @property
    def samples_per_bit(self) -> int:
        return int(round(self.f_s_hz / self.d1_bit_rate_bps))

    @property
    def samples_per_subframe(self) -> int:
        return int(round(self.f_s_hz * self.d1_subframe_period_s))

    @property
    def samples_per_frame(self) -> int:
        return int(round(self.f_s_hz * self.d1_frame_period_s))

    @property
    def sample_index_wrap_s(self) -> float:
        return (2 ** self.sample_index_w) / self.f_s_hz

    @property
    def clk_per_sample(self) -> float:
        """目标时钟下每个输入样本可用的时钟周期数。"""
        return self.target_clk_hz / self.f_s_hz

    @property
    def clk_per_ms(self) -> int:
        return int(round(self.target_clk_hz * 1e-3))

    @property
    def sample_clk_utilization(self) -> float:
        """样本级处理占用目标时钟的比例（1 样本/时钟的朴素实现）。"""
        return self.f_s_hz / self.target_clk_hz

    # ------------------------------------------------------------------
    # NCO 调谐字（定点精确性论证见 docs/FIXED_POINT.md 第 2 节）
    # ------------------------------------------------------------------
    def tuning_word(self, f_hz: float) -> int:
        """把频率转换为 nco_phase_w 位相位累加增量（四舍五入）。"""
        return int(round(f_hz / self.f_s_hz * (2 ** self.nco_phase_w)))

    @property
    def if_tuning_word(self) -> int:
        return self.tuning_word(self.f_if_hz)

    @property
    def code_tuning_word(self) -> int:
        return self.tuning_word(self.code_rate_hz)

    def to_dict(self) -> Dict[str, object]:
        d = asdict(self)
        d["params_version"] = PARAMS_VERSION
        return d


#: 全局唯一实例；其它模块请 `from b1i_ref.params import P`
P = B1IParams()

__all__ = ["B1IParams", "P", "PARAMS_VERSION", "PARAMS_DATE"]
