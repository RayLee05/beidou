"""位宽与周期预算推导（架构与定点设计阶段的核心证据）。

用法: python scripts/fixed_point_budget.py
输出:
  reports/fixed_point_budget.md   人类可读推导报告
  reports/fixed_point_budget.json 机器可读结果（供 RTL/CI 引用）

完整论证与取舍说明见 docs/FIXED_POINT.md；本脚本是它的可复算实现，
文档中的每个数字都应能由本脚本重现。
"""

from __future__ import annotations

import json
import math
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import (  # noqa: E402
    ROOT, REPORTS_DIR, Check, bootstrap, env_banner, git_revision, sha256_file, write_json, write_text,
)

bootstrap()
from b1i_ref.params import P, PARAMS_VERSION  # noqa: E402

C_LIGHT = 299792458.0
MD_PATH = os.path.join(REPORTS_DIR, "fixed_point_budget.md")
JSON_PATH = os.path.join(REPORTS_DIR, "fixed_point_budget.json")


def signed_width(value: float) -> int:
    """容纳有符号整数 ±value 所需的最小补码位宽。"""
    v = abs(value)
    if v == 0:
        return 1
    return int(math.floor(math.log2(v))) + 2


def hz_word(f_hz: float) -> tuple:
    """归一化频率字 (round, exact)。"""
    raw = f_hz / P.f_s_hz * (2 ** P.nco_phase_w)
    r = round(raw)
    exact = abs(raw - r) < 1e-6 * max(1.0, abs(raw))
    return r, exact


def nco_analysis() -> dict:
    res_hz = P.f_s_hz / (2 ** P.nco_phase_w)
    rows = []
    for label, f in (("中频 IF", P.f_if_hz), ("码率 PRN", P.code_rate_hz),
                     ("多普勒 +10 kHz", 10e3), ("多普勒 -10 kHz", -10e3)):
        word, exact = hz_word(f)
        rows.append({
            "label": label, "f_hz": f, "word": word, "exact": bool(exact),
            "word_bits_needed": signed_width(word) if word else 1,
        })
    return {
        "phase_w": P.nco_phase_w,
        "freq_resolution_hz": res_hz,
        "rows": rows,
        "lut_addr_w": P.carr_lut_addr_w,
        "phase_trunc_spur_dbc": -6.02 * P.carr_lut_addr_w,
        "lut_data_w": P.carr_lut_data_w,
        "amplitude_snr_db": 6.02 * P.carr_lut_data_w + 1.76,
    }


def accumulator_analysis() -> dict:
    max_sample = max(abs(v) for v in P.sample_levels)
    max_cos = 2 ** (P.carr_lut_data_w - 1)
    per_ms = P.samples_per_ms * max_sample * max_cos
    per_bit = per_ms * P.nh_length
    w_corr = signed_width(per_ms)
    w_bit = signed_width(per_bit)
    return {
        "max_sample_abs": max_sample,
        "max_cos_abs": max_cos,
        "per_ms_bound": per_ms,
        "per_ms_required_w": w_corr,
        "corr_acc_w": P.corr_acc_w,
        "corr_acc_headroom_bits": P.corr_acc_w - w_corr,
        "prod_w": P.sample_w + P.carr_lut_data_w,
        "per_bit_bound": per_bit,
        "per_bit_required_w": w_bit,
        "bit_acc_w": P.bit_acc_w,
        "bit_acc_headroom_bits": P.bit_acc_w - w_bit,
        "acc_bits_per_channel": 6 * P.corr_acc_w + 2 * P.bit_acc_w,
        "acc_bits_total": P.n_channels * (6 * P.corr_acc_w + 2 * P.bit_acc_w),
    }


def timebase_analysis() -> dict:
    sample_ns = 1e9 / P.f_s_hz
    sample_m = C_LIGHT / P.f_s_hz
    chip_m = C_LIGHT / P.code_rate_hz
    chip_ns = 1e9 / P.code_rate_hz
    frac_rows = []
    for f in (6, 10, 12, 16, 20):
        res_chip = 2.0 ** (-f)
        frac_rows.append({
            "frac_bits": f,
            "res_chip": res_chip,
            "res_m": res_chip * chip_m,
        })
    return {
        "sample_period_ns": sample_ns,
        "sample_range_m": sample_m,
        "chip_period_ns": chip_ns,
        "chip_range_m": chip_m,
        "samples_per_chip": P.samples_per_code_period,
        "sample_index_w": P.sample_index_w,
        "sample_index_wrap_s": P.sample_index_wrap_s,
        "epoch_id_wrap_s": (2 ** P.epoch_id_w) * P.epoch_period_s,
        "frac_table": frac_rows,
        "internal_code_phase_w": P.code_phase_w,
    }


def cycle_budget() -> dict:
    clk = P.target_clk_hz
    rows = []
    for label, t_s in (("1 ms（积分/Prompt 边界）", 1e-3),
                       ("20 ms（1 个 D1 数据位）", 20e-3),
                       ("1 s（公共输出历元）", 1.0),
                       ("6 s（1 个子帧）", float(P.d1_subframe_period_s)),
                       ("30 s（1 个 D1 帧）", float(P.d1_frame_period_s))):
        avail = clk * t_s
        samples = P.f_s_hz * t_s
        rows.append({
            "label": label,
            "available_clk": int(round(avail)),
            "samples": int(round(samples)),
            "sample_slot_util": samples / avail,
            "loop_updates": samples / P.samples_per_ms,
        })
    return {
        "target_clk_hz": clk,
        "clk_per_sample": P.clk_per_sample,
        "sample_clk_utilization": P.sample_clk_utilization,
        "rows": rows,
        "per_channel_loop_clk_budget": 512,
        "loop_utilization": 512 / (clk * 1e-3),
    }


def resource_budget() -> dict:
    mix_mults_per_ch = 2          # I/Q 混频：x*cos, x*sin
    base_mults = mix_mults_per_ch * P.n_channels
    ops_per_sample = P.n_channels * (2 + 6 + 3)   # 混频 2 + 6 个累加 + 3 个码抽头
    options = []
    for mux in (1, 2, 3, 6):
        mults = base_mults / mux
        req_clk = mux * P.f_s_hz
        options.append({
            "mux": mux,
            "mults": int(mults),
            "required_clk_hz": req_clk,
            "feasible_at_target": req_clk <= P.target_clk_hz,
            "note": "全并行，状态全在触发器" if mux == 1 else
                    f"每 {mux} 个通道共享一套混频乘法器",
        })
    return {
        "mix_mults_per_channel": mix_mults_per_ch,
        "base_mults": base_mults,
        "mac_rate_s": base_mults * P.f_s_hz,
        "ops_per_sample": ops_per_sample,
        "op_rate_s": ops_per_sample * P.f_s_hz,
        "accumulator_rw_per_sample": P.n_channels * 6,
        "accumulator_rw_per_clk": P.n_channels * 6 / P.clk_per_sample,
        "options": options,
    }


def build_markdown(nco, acc, tb, cyc, res, banner) -> str:
    L = []
    A = L.append
    A("# 位宽与周期预算报告（自动生成）")
    A("")
    A("> 本文件由 scripts/fixed_point_budget.py 生成，请勿手工修改；")
    A("> 论证与取舍说明见 docs/FIXED_POINT.md。")
    A("")
    A("| 项 | 值 |")
    A("|---|---|")
    A(f"| 生成时间 | {banner['generated_at']} |")
    A(f"| 参数版本 | {PARAMS_VERSION} |")
    A(f"| git revision | {banner['git_revision']}（未提交改动: {banner['git_dirty']}）|")
    A(f"| python | {banner['python']} |")
    A(f"| 参数文件 sha256 | {sha256_file(os.path.join(ROOT, 'sw', 'b1i_ref', 'params.py'))[:16]}… |")
    A("")
    A("## 1. NCO 调谐字与频率分辨率")
    A("")
    A(f"- 相位累加器位宽 W = **{nco['phase_w']}**；频率分辨率 = Fs/2^W = **{nco['freq_resolution_hz']:.9f} Hz**")
    A(f"- 相位截断（LUT 地址 {nco['lut_addr_w']} 位）最坏杂散约 **{nco['phase_trunc_spur_dbc']:.1f} dBc**（经验式 -6.02·P）")
    A(f"- sin/cos 表数据 {nco['lut_data_w']} 位，幅度量化 SNR ≈ **{nco['amplitude_snr_db']:.1f} dB**")
    A("")
    A("| 频率 | 标称值 | 调谐字 | 精确可表示 | 字宽需求 |")
    A("|---|---:|---:|:---:|---:|")
    for r in nco["rows"]:
        A(f"| {r['label']} | {r['f_hz']:.6g} Hz | {r['word']} | "
          f"{'是' if r['exact'] else '否'} | {r['word_bits_needed']} bit |")
    A("")
    A("**结论**：IF/Fs = 0.25、码率/Fs = 1023/8192 在 W=32 下均可整数表示，")
    A("混频与码发生器无频率截断误差；W=32 与 W=28 的加法器面积差异可忽略，故选 32。")
    A("")
    A("## 2. 累加器位宽（最坏情况推导）")
    A("")
    A(f"- 样本幅度上界 |x| = {acc['max_sample_abs']}；载波幅度上界 |cos| = {acc['max_cos_abs']}")
    A(f"- 1 ms 相干累加上界 = {P.samples_per_ms} × {acc['max_sample_abs']} × {acc['max_cos_abs']} = **{acc['per_ms_bound']:,}**")
    A(f"  → 需要 {acc['per_ms_required_w']} bit 补码；实配 CORR_ACC_W = **{acc['corr_acc_w']}**（裕量 {acc['corr_acc_headroom_bits']} bit）")
    A(f"- 混频乘积位宽 = SAMPLE_W + CARR_LUT_DATA_W = **{acc['prod_w']} bit**")
    A(f"- 20 ms NH 合并上界 = 20 × {acc['per_ms_bound']:,} = **{acc['per_bit_bound']:,}**")
    A(f"  → 需要 {acc['per_bit_required_w']} bit；实配 BIT_ACC_W = **{acc['bit_acc_w']}**（裕量 {acc['bit_acc_headroom_bits']} bit）")
    A(f"- 每通道相关状态 = 6×{acc['corr_acc_w']} + 2×{acc['bit_acc_w']} = **{acc['acc_bits_per_channel']} bit**；")
    A(f"  12 通道合计 **{acc['acc_bits_total']:,} bit**（触发器）")
    A("")
    A("**说明**：26 bit 是 1 ms 累加的精确最小补码位宽（上界可由 +3 样本与满幅 cos 同时构造，属合法输入），")
    A("因此没有额外裕量；若后续定点/浮点对比需要 2 bit 保护位，可提升到 28 bit，代价为 12×6×2 = 144 个触发器。")
    A("BIT_ACC_W=32 已含 2 bit 裕量，兼顾 20 ms 合并与后续扩展。")
    A("")
    A("## 3. 时基、码相位与伪距分辨率")
    A("")
    A(f"- 采样周期 = {tb['sample_period_ns']:.6f} ns ↔ 距离 **{tb['sample_range_m']:.4f} m**（1 个样本的时间误差）")
    A(f"- 码片周期 = {tb['chip_period_ns']:.4f} ns ↔ 距离 **{tb['chip_range_m']:.4f} m**；每码片 {tb['samples_per_chip']:.6f} 个样本")
    A(f"- 内部码相位保留 {tb['internal_code_phase_w']} bit 归一化相位（约 {2.0**-22:.3g} 码片分辨率），测量记录只需截取高位。")
    A(f"- SAMPLE_INDEX_W = {tb['sample_index_w']} → 回绕周期 = {tb['sample_index_wrap_s']:.3f} s")
    A(f"- EPOCH_ID_W = {P.epoch_id_w} → 历元回绕 = {tb['epoch_id_wrap_s']:.3g} s")
    A("")
    A("| 码相位小数位 | 分辨率(码片) | 分辨率(m) |")
    A("|---:|---:|---:|")
    for r in tb["frac_table"]:
        A(f"| {r['frac_bits']} | 2^-{r['frac_bits']} = {r['res_chip']:.3g} | {r['res_m']:.4f} |")
    A("")
    A("## 4. 周期预算")
    A("")
    A(f"- 目标时钟 **{cyc['target_clk_hz']/1e6:.1f} MHz**；每样本可用 **{cyc['clk_per_sample']:.4f}** 个时钟")
    A(f"- 1 样本/时钟的朴素数据通路只占用 {cyc['sample_clk_utilization']*100:.2f}% 的时钟")
    A("")
    A("| 时间窗口 | 可用时钟 | 样本数 | 样本槽占用 | 环路更新机会 |")
    A("|---|---:|---:|---:|---:|")
    for r in cyc["rows"]:
        A(f"| {r['label']} | {r['available_clk']:,} | {r['samples']:,} | "
          f"{r['sample_slot_util']*100:.2f}% | {r['loop_updates']:.0f} 次 |")
    A("")
    A(f"- 每通道每 1 ms 的环路更新预算 = {cyc['per_channel_loop_clk_budget']} 时钟（占 "
      f"{cyc['loop_utilization']*100:.3f}%），12 通道并行更新，余量充足。")
    A("")
    A("## 5. 吞吐与资源预算")
    A("")
    A(f"- 每样本定点运算数（12 通道合计）= {res['ops_per_sample']}；总运算率 = **{res['op_rate_s']/1e9:.3f} Gop/s**")
    A(f"- 基准乘法器数（每通道 2 个混频乘）= **{res['base_mults']}**；MAC 率 = {res['mac_rate_s']/1e6:.1f} MMAC/s")
    A(f"- 相关累加器访问 = 每样本 {res['accumulator_rw_per_sample']} 次读写 → 每时钟 "
      f"{res['accumulator_rw_per_clk']:.2f} 次（时钟复用方案的真正瓶颈）")
    A("")
    A("| 方案 | 复用因子 | 乘法器 | 需要时钟 | 目标时钟可行 | 说明 |")
    A("|---|---:|---:|---:|:---:|---|")
    for tag, o in zip(("A", "B", "C", "D"), res["options"]):
        feasible = "是" if o["feasible_at_target"] else "否"
        A(f"| 方案 {tag} | {o['mux']} | {o['mults']} | "
          f"{o['required_clk_hz']/1e6:.3f} MHz | {feasible} | {o['note']} |")
    A("")
    A("**建议**：首版采用方案 A（12 通道各一套混频/相关数据通路，1 样本/时钟），")
    A("原因是累加器端口数随复用线性增长，复用省下的乘法器会被多端口寄存器堆吃掉，")
    A("且全并行更利于逐通道定位 bug。面积优化留到 P6 综合后再评估。")
    A("")
    A("## 6. 舍入与饱和策略")
    A("")
    A("| 位置 | 策略 |")
    A("|---|---|")
    A("| NCO 相位累加 | 模 2^W 自然回绕，属定义行为 |")
    A("| LUT 寻址 | 取相位高 CARR_LUT_ADDR_W 位（截断），误差已量化为杂散预算 |")
    A("| 混频乘积 | 全精度保留（13 bit），不截位 |")
    A("| 1 ms 相关累加 | 26 bit 全精度，不做截断，1 ms 边界清零 |")
    A("| 20 ms NH 合并 | 32 bit 全精度；数据位极性由 |I| 判定后丢弃符号 |")
    A("| 环路滤波系数 | Q2.14 定点；乘积累加后右移 14 位，采用就近舍入（round-half-up） |")
    A("| 环路输出频率字 | 32 bit 有符号，越界饱和到 ±(2^31−1)，并置位 fault |")
    A("| 码相位 | 32 bit，码周期边界回绕到 2046 码片并递增整周期计数 |")
    A("")
    A("## 7. 待确认项（不阻塞本阶段，但冻结前必须闭合）")
    A("")
    A("1. 目标时钟频率、工艺与标准单元库未给定 —— 本报告用 100 MHz 作占位值。")
    A("2. IF/Fs 冲突（4.096/16.384 vs 4.092/16.368）影响调谐字与 CODE 归一化，须教师/ICD 确认。")
    A("3. 捕获搜索范围/步长决定捕获引擎的周期与面积，当前配置仅为起始建议。")
    A("4. 环路带宽与积分时长未冻结，影响系数位宽与锁定判决门限。")
    A("")
    return "\n".join(L) + "\n"


def main() -> int:
    banner = env_banner()
    nco = nco_analysis()
    acc = accumulator_analysis()
    tb = timebase_analysis()
    cyc = cycle_budget()
    res = resource_budget()

    c = Check("定点预算自洽性")
    c.true("CORR_ACC_W 覆盖 1 ms 上界", P.corr_acc_w >= acc["per_ms_required_w"],
           f"{P.corr_acc_w} < {acc['per_ms_required_w']}")
    c.true("BIT_ACC_W 覆盖 20 ms 上界", P.bit_acc_w >= acc["per_bit_required_w"],
           f"{P.bit_acc_w} < {acc['per_bit_required_w']}")
    c.true("IF 调谐字精确", nco["rows"][0]["exact"])
    c.true("码率调谐字精确", nco["rows"][1]["exact"])
    c.true("SAMPLE_INDEX 覆盖 30 s 帧", tb["sample_index_wrap_s"] >= P.d1_frame_period_s)
    c.true("目标时钟 ≥ 4×采样率（复用余量）", P.target_clk_hz >= 4 * P.f_s_hz)

    md = build_markdown(nco, acc, tb, cyc, res, banner)
    write_text(MD_PATH, md)
    write_json(JSON_PATH, {
        "banner": banner,
        "params_version": PARAMS_VERSION,
        "nco": nco, "accumulator": acc, "timebase": tb,
        "cycle": cyc, "resource": res,
    })
    print(f"已生成 {MD_PATH}")
    print(f"已生成 {JSON_PATH}")
    rc = c.report()
    if rc:
        return rc
    print("关键结论：")
    print(f"  NCO 频率分辨率      : {nco['freq_resolution_hz']:.9f} Hz")
    print(f"  CORR_ACC_W 需求/实配 : {acc['per_ms_required_w']} / {P.corr_acc_w} bit")
    print(f"  BIT_ACC_W  需求/实配 : {acc['per_bit_required_w']} / {P.bit_acc_w} bit")
    print(f"  1 样本对应距离      : {tb['sample_range_m']:.3f} m")
    print(f"  SAMPLE_INDEX 回绕   : {tb['sample_index_wrap_s']:.3f} s")
    print(f"  MAC 率              : {res['mac_rate_s']/1e6:.1f} MMAC/s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
