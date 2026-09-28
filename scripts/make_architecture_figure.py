# -*- coding: utf-8 -*-
"""生成架构总览图 reports/figures/architecture.png（分层网格 + 正交连线，不穿越方框）。"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import FIGURES_DIR, bootstrap
bootstrap()

import matplotlib
matplotlib.use("Agg")
import matplotlib.font_manager as fm
import matplotlib.patches as mp
import matplotlib.pyplot as plt
from b1i_ref.params import P

C = {"in": "#D6E4F0", "acq": "#FBE7D0", "trk": "#DDEFD8", "sync": "#E4DCF2",
     "out": "#F7DDE4", "sw": "#EDEDED", "edge": "#2F4F6B"}
CX = [13, 38, 63, 88]
BW, BH = 21, 8.2
ROW = {1: 64.5, 2: 51.0, 3: 36.5, 4: 22.0, 5: 8.5}


def pick_font():
    avail = {f.name for f in fm.fontManager.ttflist}
    for n in ("Microsoft YaHei", "SimHei", "SimSun", "DejaVu Sans"):
        if n in avail:
            return n
    return "DejaVu Sans"


def box(ax, col, y, text, kind, fs=8.2):
    ax.add_patch(mp.FancyBboxPatch((CX[col] - BW / 2, y - BH / 2), BW, BH,
                 boxstyle="round,pad=0.25,rounding_size=1.0",
                 linewidth=1.1, edgecolor=C["edge"], facecolor=C[kind], zorder=2))
    ax.text(CX[col], y, text, ha="center", va="center", fontsize=fs, zorder=3, linespacing=1.5)


def seg(ax, pts, ls="-", color=None, head=True):
    col = color or C["edge"]
    for i in range(len(pts) - 1):
        p, q = pts[i], pts[i + 1]
        if i == len(pts) - 2 and head:
            ax.add_patch(mp.FancyArrowPatch(p, q, arrowstyle="-|>", mutation_scale=11,
                         linewidth=1.0, color=col, linestyle=ls, zorder=1))
        else:
            ax.plot([p[0], q[0]], [p[1], q[1]], color=col, linewidth=1.0,
                    linestyle=ls, zorder=1)


def hlink(ax, a, b, y, ls="-"):
    seg(ax, [(CX[a] + BW / 2, y), (CX[b] - BW / 2, y)], ls)


def main():
    font = pick_font()
    plt.rcParams["font.sans-serif"] = [font]
    plt.rcParams["axes.unicode_minus"] = False
    fig, ax = plt.subplots(figsize=(17, 10))
    ax.set_xlim(0, 100); ax.set_ylim(0, 74); ax.axis("off")

    ax.text(50, 72.2, "北斗 B1I 基带信号处理器 —— 总体架构（分层网格）",
            ha="center", fontsize=16, fontweight="bold", color="#1F3B57")
    ax.text(50, 69.5,
            "fIF 4.092 MHz / Fs 16.368 MHz（每码片 8 样本，1 ms = 16368 样本）/ 2 bit / "
            "12 通道 / 公共输出历元 1 s",
            ha="center", fontsize=9.5, color="#4A6B85")

    for k, t in [(1, "① 输入与公共时基"), (2, "② 捕获（后台，与跟踪并发）"),
                 (3, "③ 12 × 跟踪通道"), (4, "④ 同步与解调"), (5, "⑤ 测量与输出")]:
        ax.text(1.0, ROW[k] + BH / 2 + 1.0, t, ha="left", va="bottom", fontsize=10,
                fontweight="bold", color="#1F3B57")

    # ①
    box(ax, 0, ROW[1], "配套 SRAM 模型\n(2 bit 实中频)", "in")
    box(ax, 1, ROW[1], "sram_reader\n读地址/使能/数据 → s[2:0]", "in")
    box(ax, 2, ROW[1], "sample_timebase\n样本编号 / 1ms / 20ms / 6s / 1s", "in")
    box(ax, 3, ROW[1], "配置寄存器\nPRN 表·搜索范围·门限·环路系数\n(写入后立即生效)", "in", 7.4)
    hlink(ax, 0, 1, ROW[1]); hlink(ax, 1, 2, ROW[1])
    # 配置寄存器通过 cfg_valid/ready 写入后立即生效，不画连线以免穿越方框

    # 时基总线：sample_timebase -> 捕获引擎 / 跟踪通道
    ybus = 57.5
    seg(ax, [(CX[2], ROW[1] - BH / 2), (CX[2], ybus), (CX[1], ybus), (CX[1], ROW[2] + BH / 2)],
        head=True)
    ax.text(CX[2] - 8, ybus + 0.6, "时基 sample_valid / ms_tick", fontsize=7.2, color="#4A6B85")

    # ②
    box(ax, 0, ROW[2], "acquisition_manager\n任务调度 / 资源仲裁 / 峰值判决", "acq", 7.8)
    box(ax, 1, ROW[2], "acquisition_engine\n码相位 × 多普勒 × PRN\n(复用混频/相关结构)", "acq", 7.5)
    box(ax, 2, ROW[2], "search_result\n成败·PRN·task_id\n码相位·频偏·质量", "acq", 7.6)
    hlink(ax, 0, 1, ROW[2]); hlink(ax, 1, 2, ROW[2])
    seg(ax, [(CX[2], ROW[2] - BH / 2), (CX[2], ROW[3] + BH / 2)], color="#B06A00")
    ax.text(CX[2] + 0.8, ROW[2] - BH / 2 - 3.4, "allocate / init", fontsize=7.2, color="#B06A00")

    # ③
    box(ax, 0, ROW[3], "channel_manager\n分配 / generation / 重捕获", "trk", 7.8)
    box(ax, 1, ROW[3], "tracking_channel × 12\ncarrier_mixer_nco + code_nco\n"
                       "code_ram(E/P/L) + correlator_epl\ndll_loop + fll_pll_loop", "trk", 7.4)
    box(ax, 2, ROW[3], "channel_status\n分层有效位·质量\n失锁原因·发生时刻", "trk", 7.6)
    hlink(ax, 0, 1, ROW[3], ls="--"); hlink(ax, 1, 2, ROW[3])
    ax.text(CX[3], ROW[3], "共享资源（只读）\n载波 sin/cos ROM：全芯片 1 份\n"
                           "PRN 码 RAM：按 ICD 装载\n12 通道只读访问，不在数据流上",
            ha="center", va="center", fontsize=7.2, color="#4A6B85")

    # ③ -> ④
    seg(ax, [(CX[1], ROW[3] - BH / 2), (CX[1], ROW[4] + BH / 2)])
    ax.text(CX[1] + 0.8, ROW[3] - BH / 2 - 3.6, "correlator_result（每 1 ms）", fontsize=7.2, color="#4A6B85")

    # ④
    box(ax, 0, ROW[4], "nh_sync\n去 NH20 / 位同步", "sync", 7.8)
    box(ax, 1, ROW[4], "d1_frame_sync\n子帧同步 / 去交织 / BCH(15,11,1)", "sync", 7.5)
    box(ax, 2, ROW[4], "nav_decoder\nBDT时间 / 星历 / 钟差 / 健康", "sync", 7.6)
    box(ax, 3, ROW[4], "measurement_engine\n码相位 + 整周期 + 时间锚点", "sync", 7.6)
    hlink(ax, 0, 1, ROW[4]); hlink(ax, 1, 2, ROW[4]); hlink(ax, 2, 3, ROW[4])

    # ④ -> ⑤（正交下折到左侧）
    y4 = 15.3
    seg(ax, [(CX[3] - 6, ROW[4] - BH / 2), (CX[3] - 6, y4), (CX[0], y4), (CX[0], ROW[5] + BH / 2)])
    ax.text(CX[3] - 5.2, y4 + 0.7, "obs / nav / status", fontsize=7.2, color="#4A6B85")

    # ⑤
    box(ax, 0, ROW[5], "epoch_aggregator\n公共历元 / 有效性裁决", "out", 7.8)
    box(ax, 1, ROW[5], "record_fifo\nobs / nav / status + 背压", "out", 7.8)
    box(ax, 2, ROW[5], "RINEX 3.05 适配器\n(配套软件，非 RTL)", "sw", 7.8)
    box(ax, 3, ROW[5], "定位软件\n单频码定位(配套)", "sw", 7.8)
    hlink(ax, 0, 1, ROW[5]); hlink(ax, 1, 2, ROW[5], ls="--"); hlink(ax, 2, 3, ROW[5], ls="--")

    ax.text(50, 1.0, "实线：样本与结果　虚线：控制/复用　"
                     "失锁：撤销本通道本代次有效数据 → 重捕获（generation 自增）",
            ha="center", fontsize=9, color="#4A6B85")

    os.makedirs(FIGURES_DIR, exist_ok=True)
    out = os.path.join(FIGURES_DIR, "architecture.png")
    fig.savefig(out, dpi=150, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print("字体:", font, "->", out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
