"""生成架构总览图 reports/figures/architecture.png。

用法: python scripts/make_architecture_figure.py
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import FIGURES_DIR, bootstrap  # noqa: E402

bootstrap()

import matplotlib  # noqa: E402
matplotlib.use("Agg")
import matplotlib.font_manager as fm  # noqa: E402
import matplotlib.patches as mp  # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402
from b1i_ref.params import P  # noqa: E402


def pick_font() -> str:
    available = {f.name for f in fm.fontManager.ttflist}
    for name in ("Microsoft YaHei", "SimHei", "SimSun", "Noto Sans CJK SC", "DejaVu Sans"):
        if name in available:
            return name
    return "DejaVu Sans"


COLORS = {
    "in": "#DCE9F7",
    "rtl": "#E8F4E8",
    "nav": "#FBEFD8",
    "sw": "#F3E4F3",
    "cfg": "#EDEDED",
    "edge": "#33506B",
}


def box(ax, x, y, w, h, text, kind="rtl", fs=9.0, bold=False):
    ax.add_patch(mp.FancyBboxPatch(
        (x, y), w, h,
        boxstyle="round,pad=0.35,rounding_size=1.2",
        linewidth=1.1, edgecolor=COLORS["edge"], facecolor=COLORS[kind], zorder=2))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center",
            fontsize=fs, zorder=3, wrap=True,
            fontweight="bold" if bold else "normal")


def arrow(ax, p1, p2, style="-|>", color=None, ls="-", rad=0.0):
    ax.add_patch(mp.FancyArrowPatch(
        p1, p2, arrowstyle=style, mutation_scale=12,
        linewidth=1.1, color=color or COLORS["edge"],
        linestyle=ls, zorder=1,
        connectionstyle=f"arc3,rad={rad}"))


def main() -> int:
    font = pick_font()
    plt.rcParams["font.sans-serif"] = [font]
    plt.rcParams["axes.unicode_minus"] = False

    fig, ax = plt.subplots(figsize=(16.5, 9.2))
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 60)
    ax.axis("off")

    ax.text(50, 58.6, "北斗 B1I 基带处理与电文解调 —— 数字核心架构（阶段 P0/P1 基线）",
            ha="center", va="center", fontsize=15, fontweight="bold", color="#1F3B57")
    ax.text(50, 56.4,
            f"IF {P.f_if_hz/1e6:.3f} MHz / Fs {P.f_s_hz/1e6:.3f} MHz（8 样本/码片）/ 2 bit / "
            f"{P.n_channels} 通道 / 1 ms = {P.samples_per_ms} 样本 / 载波表全芯片共享 / 输出历元 {P.epoch_period_s:g} s",
            ha="center", va="center", fontsize=10, color="#4A6B85")

    # 列标题
    for x, t in ((11, "输入与公共时基"), (36, "捕获与通道管理"), (62, "同步与解调"),
                 (88, "输出与软件适配")):
        ax.text(x, 53.6, t, ha="center", va="center", fontsize=10.5,
                fontweight="bold", color="#1F3B57")

    # --- 列 1 ---
    box(ax, 2, 46, 18, 6, "配套 SRAM 模型（2 bit 实中频）\n读地址 / 读使能 / 读数据", "in")
    box(ax, 2, 37.5, 18, 6, "sram_reader\n按配套字宽取数 → s[2:0]", "rtl")
    box(ax, 2, 29, 18, 6, "sample_timebase\nn, sample_valid, 1 ms tick", "rtl")
    box(ax, 2, 18, 18, 8, "配置接口（cfg_valid/addr/wdata/ready）\nPRN 候选表 · 搜索范围 · 门限\n环路系数 · 历元周期 · debug", "cfg", fs=8.5)

    arrow(ax, (11, 46), (11, 43.5))
    arrow(ax, (11, 37.5), (11, 35))
    arrow(ax, (20, 22), (26, 22), ls="--")
    ax.text(23, 23.2, "控制", fontsize=8, color="#4A6B85")

    # --- 列 2 ---
    box(ax, 26, 44, 20, 8, "acquisition_manager\nP × acquisition_engine\n码相位 × 多普勒 × PRN", "rtl", fs=8.8)
    box(ax, 26, 34, 20, 6, "channel_manager\nCH0..CH11 分配 / 状态 / 重捕获", "rtl", fs=8.8)
    box(ax, 26, 16, 20, 15,
        "12 × tracking_channel\n\ncarrier_mixer_nco  (sin/cos LUT)\n"
        "code_nco  (PRN / NH 码相位)\ncorrelator_epl  (E/P/L 积分)\n"
        "dll_loop  ·  fll_pll_loop\n锁定判决 / 失锁撤销", "rtl", fs=8.4)

    arrow(ax, (20, 40.5), (26, 46))
    arrow(ax, (20, 32), (26, 38))
    arrow(ax, (36, 44), (36, 40))
    arrow(ax, (36, 34), (36, 31))
    arrow(ax, (46, 20), (52, 20), rad=-0.15)

    # --- 列 3 ---
    box(ax, 52, 46, 20, 6, "nh_sync\n20 ms 位同步 / 去 NH20", "nav", fs=8.8)
    box(ax, 52, 37, 20, 6, "d1_frame_sync\n子帧同步 / 去交织 / BCH", "nav", fs=8.8)
    box(ax, 52, 28, 20, 6, "nav_decoder\n时间 / 星历 / 钟差 / 健康", "nav", fs=8.8)
    box(ax, 52, 12, 20, 6, "measurement_engine\n码相位 + 整周期 + 时间锚点", "nav", fs=8.5)
    box(ax, 52, 4, 20, 5.5, "全局记录汇聚（无丢失/无伪造）", "nav", fs=8.5)

    arrow(ax, (46, 30), (52, 49), rad=0.12)
    ax.text(47.6, 38.0, "Prompt", fontsize=7.5, color="#4A6B85")
    arrow(ax, (62, 46), (62, 43))
    arrow(ax, (62, 37), (62, 34))
    arrow(ax, (46, 24), (52, 15), rad=-0.12)
    arrow(ax, (62, 28), (62, 25))

    # --- 列 4 ---
    box(ax, 78, 44, 20, 6, "epoch_aggregator\n公共历元 1 s / 有效性裁决", "sw", fs=8.8)
    box(ax, 78, 35, 20, 6, "record_fifo → 结构化记录\nrec_valid / ready / last", "sw", fs=8.8)
    box(ax, 78, 24, 20, 6, "RINEX 3.05 适配器（软件）\nOBS: C2I…  NAV: 星历/钟差", "sw", fs=8.8)
    box(ax, 78, 13, 20, 6, "配套定位软件（教师提供）\n单频码定位 PVT", "sw", fs=8.8)
    box(ax, 78, 4, 20, 5.5, "验证证据：波形 / 日志 / 报告", "cfg", fs=8.5)

    arrow(ax, (72, 15), (78, 46), rad=-0.18)
    arrow(ax, (72, 49), (78, 47), rad=0.1)
    arrow(ax, (72, 31), (78, 45), rad=-0.1)
    arrow(ax, (72, 6.8), (78, 38), rad=-0.2)
    arrow(ax, (88, 44), (88, 41))
    arrow(ax, (88, 35), (88, 30))
    arrow(ax, (88, 24), (88, 19))
    arrow(ax, (88, 13), (88, 9.5))

    ax.text(50, 1.0,
            "实线：样本 / 结果   虚线：控制 / 状态    失锁：撤销本通道有效数据 → 重新捕获",
            ha="center", fontsize=9, color="#4A6B85")

    os.makedirs(FIGURES_DIR, exist_ok=True)
    out = os.path.join(FIGURES_DIR, "architecture.png")
    fig.savefig(out, dpi=160, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print(f"中文字体: {font}")
    print(f"已生成 {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
