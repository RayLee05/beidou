"""本机软件全链路：场景 → 定点跟踪 → NH/电文抽比特 → 伪距 → 单频码定位 → RINEX。

不依赖 EDA 仿真器。输出 reports/local_chain.md 与 reports/rinex/。
用法: python scripts/run_local_chain.py [--sec 8]
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import REPORTS_DIR, ROOT, SW_DIR, bootstrap, env_banner, write_json, write_text  # noqa: E402

bootstrap()
sys.path.insert(0, SW_DIR)

import numpy as np  # noqa: E402
from b1i_ref import d1_nav, params as _p, prn_b1i, scenario  # noqa: E402
from b1i_ref.tracking_model import LoopConfig, TrackingChannel, word_to_doppler  # noqa: E402
from b1i_ref.acquisition import ncoh_search  # noqa: E402
from pvt.lsq import refine_sagnac  # noqa: E402
from rinex.records import (  # noqa: E402
    Rec, REC_EPOCH, REC_MEAS, REC_NAV,
    pack_tx_fields, tx_time_from_sow, write_hex_dump,
)
from rinex.writer import write_nav, write_obs  # noqa: E402

P = _p.P
C = d1_nav.C_LIGHT
CHIP_M = C / P.code_rate_hz
NH = np.array(prn_b1i.NH20, dtype=np.int8)
_EPH_KEYS = (
    "prn", "WN", "toe", "toc", "sqrtA", "e", "i0", "OMEGA0", "omega", "M0",
    "dn", "OMEGADOT", "IDOT", "Cuc", "Cus", "Crc", "Crs", "Cic", "Cis",
    "a0", "a1", "a2", "TGD1", "TGD2", "AODE", "AODC", "URAI", "SatH1",
)


def _eph_dict(eph) -> dict:
    d = {k: getattr(eph, k) for k in _EPH_KEYS}
    d["iono"] = dict(eph.iono)
    return d


def nh_bits_from_prompt(ip: list) -> tuple:
    """用 |corr| 最大相位抽 NH，返回 (synced, phase, bits, bit_starts)。"""
    ip = np.asarray(ip, dtype=np.float64)
    if ip.size < 40:
        return False, 0, [], []
    best_p, best_e = 0, -1.0
    for p in range(20):
        e = 0.0
        for m in range(19, ip.size):
            if (m + 1) % 20 != p:
                continue
            sl = ip[m - 19:m + 1]
            sgn = np.where(NH == 0, 1.0, -1.0)
            e += abs(float(np.dot(sgn, sl)))
        if e > best_e:
            best_e, best_p = e, p
    bits, starts = [], []
    for m in range(19, ip.size):
        if (m + 1) % 20 != best_p:
            continue
        sl = ip[m - 19:m + 1]
        sgn = np.where(NH == 0, 1.0, -1.0)
        corr = float(np.dot(sgn, sl))
        bits.append(1 if corr < 0 else 0)
        starts.append(m - 19)
    return True, best_p, bits, starts


def handover(samples, code) -> tuple:
    """FFT 粗捕获码相位，再用短跟踪在 ±500 Hz 里挑能拉入的多普勒。

    1 ms 相干在 NH/混星下会偏到相邻 500 Hz 格，FLL 容易假锁在 NH 边带。
    """
    hits = ncoh_search(samples, code, 10000.0, 500.0, n_ms=8)
    cp = float(hits[0]["code_phase_chips"]) if hits else 0.0
    fd0 = float(hits[0]["doppler_hz"]) if hits else 0.0
    win = samples[:120 * P.samples_per_ms]
    best_fd, best_s = fd0, -1.0
    for fd in (fd0 + d for d in (-500.0, -250.0, 0.0, 250.0, 500.0)):
        ch = TrackingChannel(code, LoopConfig(fll_en=True))
        ch.reset(code_phase_chips=cp, doppler_hz=fd)
        dumps = [d for d in ch.process(win) if not d["partial"]]
        if len(dumps) < 20:
            continue
        ip = float(np.mean([abs(d["i_p"]) for d in dumps[-30:]]))
        if ip > best_s:
            best_s, best_fd = ip, fd
    return cp, best_fd


def decode_from_bits(bits: list) -> list:
    """在比特流里找前导码并译码子帧。"""
    pre = list(d1_nav.PREAMBLE)
    inv = [1 - b for b in pre]
    out = []
    b = list(bits)
    i = 0
    while i + 311 <= len(b):
        w = b[i:i + 311]
        if w[:11] == pre and w[300:311] == pre:
            info, fixes, ok = d1_nav.decode_subframe(w[:300])
            if ok:
                out.append((i, 0, info, fixes))
            i += 280
        elif w[:11] == inv and w[300:311] == inv:
            flip = [1 - x for x in w[:300]]
            info, fixes, ok = d1_nav.decode_subframe(flip)
            if ok:
                out.append((i, 1, info, fixes))
            i += 280
        else:
            i += 1
    return out


def samples_in_blocks(sc, n: int, block_ms: int = 100) -> np.ndarray:
    """保留 int8 输入流，按块生成浮点中间量，避免 7 s 场景占用数 GB。"""
    if n < 1 or block_ms < 1:
        raise ValueError("sample count and block_ms must be positive")
    out = np.empty(n, dtype=np.int8)
    rng = np.random.default_rng([sc.seed, 0])
    block = block_ms * P.samples_per_ms
    for start in range(0, n, block):
        stop = min(start + block, n)
        out[start:stop] = sc.samples(start, stop - start, noise_rng=rng)
    return out


def track_in_blocks(ch, samples, block_ms: int = 100) -> list:
    """维持通道状态，避免 process 将整个输入复制成 int64。"""
    if block_ms < 1:
        raise ValueError("block_ms must be positive")
    out = []
    block = block_ms * P.samples_per_ms
    for start in range(0, len(samples), block):
        out.extend(ch.process(samples[start:start + block]))
    return out


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--sec", type=float, default=8.0)
    ap.add_argument("--sats", type=int, default=5)
    ap.add_argument("--cn0", type=float, default=45.0)
    ap.add_argument("--seed", type=int, default=3)
    ap.add_argument("--block-ms", type=int, default=100, help="场景生成和跟踪的分块长度")
    a = ap.parse_args()

    rx = scenario.geodetic_to_ecef(39.9, 116.4, 50.0)
    sow0 = 345618.0
    ephs = scenario.make_constellation(rx, sow0, 1000, n_sats=a.sats, seed=a.seed)
    sc = scenario.Scenario(
        rx_ecef=rx, sow0=sow0, wn=1000, rx_clock_bias=1.2e-4, seed=a.seed,
        sats=[scenario.SatConfig(e, cn0_dbhz=a.cn0, phase0_cycles=0.15 * (i + 1))
              for i, e in enumerate(ephs)])
    n = int(a.sec * P.f_s_hz)
    samples = samples_in_blocks(sc, n, a.block_ms)
    epoch_n = n - 1
    truth = sc.truth(epoch_n)

    rows = []
    recs = []
    epoch_s = epoch_n / P.f_s_hz
    t_rx_local = sow0 + epoch_s
    recs.append(Rec(REC_EPOCH, 0, {
        "epoch_id": 1, "sample_count": epoch_n + 1, "n_valid": 0, "input_done": 1,
        "sow0_ms": int(round(sow0 * 1000.0)),
        "rx_time_s": t_rx_local}))
    nav_recs = []

    for i, sat in enumerate(sc.sats):
        eph = sat.eph
        code = prn_b1i.prn_code(eph.prn)
        cp_ho, fd_ho = handover(samples, code)
        ch = TrackingChannel(code, LoopConfig(fll_en=True))
        ch.reset(code_phase_chips=cp_ho, doppler_hz=fd_ho)
        dumps = [d for d in track_in_blocks(ch, samples, a.block_ms) if not d["partial"]]
        ip = [d["i_p"] for d in dumps]
        synced, phase, bits, starts = nh_bits_from_prompt(ip)
        frames = decode_from_bits(bits) if synced else []
        last = dumps[-1] if dumps else None
        t1 = truth[eph.prn]
        fd_err = word_to_doppler(last["dop_word"]) - t1["doppler_hz"] if last else float("nan")
        decoded = []
        week, week_valid = 0, 0
        tx_ms, time_valid, code_phase = 0, 0, 0
        t_tx_sv = None
        for bit_i, inv, info, fixes in frames:
            fid = d1_nav.subframe_id(info)
            fields = d1_nav.unpack_fields(fid, info)
            decoded.append({"sf_id": fid, "sow": fields.get("SOW"), "fixes": fixes, "inv": inv})
            info_int = 0
            for b in info:
                info_int = (info_int << 1) | int(b)
            nav_recs.append(Rec(REC_NAV, 0, {
                "channel": i, "prn": eph.prn, "generation": 1, "sf_id": fid,
                "fixes": fixes, "inverted": inv, "info": info_int}))
            if fid == 1 and "WN" in fields:
                week, week_valid = int(fields["WN"]), 1
            if last is not None and bit_i < len(starts):
                sf_dump = dumps[starts[bit_i]]
                sow_anc = int(fields.get("SOW") or 0)
                t_rx_dump = sow0 + last["sample_end"] / P.f_s_hz
                t_tx_sv = tx_time_from_sow(
                    sow_anc, last["ms"], sf_dump["ms"], t_rx_dump, t_rx_local)
                tx_ms, code_phase = pack_tx_fields(t_tx_sv)
                time_valid = 1
        rows.append({
            "prn": eph.prn, "locked": bool(last and last["locked"]),
            "dumps": len(dumps), "fd_err_hz": fd_err, "d_dll": last["d_dll"] if last else None,
            "bit_synced": synced, "n_bits": len(bits), "n_sf": len(frames),
            "decoded": decoded, "tx_ms": tx_ms, "time_valid": time_valid,
            "t_tx_sv": t_tx_sv, "code_phase": code_phase,
            "pr_truth_m": t1["pseudorange_m"],
            "week": week, "week_valid": week_valid,
            "elev": scenario.elevation_deg(rx, np.array(eph.position(sow0))),
        })
        recs.append(Rec(REC_MEAS, 0, {
            "channel": i, "prn": eph.prn, "generation": 1, "epoch_id": 1,
            "tx_ms": tx_ms, "code_phase": code_phase,
            "dop_word": last["dop_word"] if last else 0, "ms_count": last["ms"] if last else 0,
            "meas_valid": 1 if last and last["locked"] else 0,
            "locked": 1 if last and last["locked"] else 0,
            "bit_synced": int(synced), "time_valid": time_valid,
            "ch_state": 2 if last and last["locked"] else 1,
            "lock_cnt": last["lock_cnt"] if last else 0,
            "week": week, "week_valid": week_valid,
        }))

    usable = [r for r in rows if r["locked"] and r["time_valid"] and r["t_tx_sv"] is not None]
    ephs_u, ttxs, prs, used = [], [], [], []
    for r, sat in zip(rows, sc.sats):
        if r not in usable:
            r["pr_m"] = None
            continue
        t_tx_sv = r["t_tx_sv"]
        dtsv = sat.eph.clock_bias(t_tx_sv)
        t_tx = t_tx_sv - dtsv
        pr = (t_rx_local - t_tx_sv) * C + C * dtsv
        r["pr_m"] = pr
        r["dpr_m"] = pr - (r["pr_truth_m"] + C * dtsv)
        ephs_u.append(sat.eph)
        ttxs.append(t_tx)
        prs.append(pr)
        used.append(r["prn"])
    recs[0].fields["n_valid"] = len(used)
    pvt = refine_sagnac(ephs_u, ttxs, prs, xyz0=rx)
    err = float(np.linalg.norm(pvt.xyz - rx)) if pvt.ok else float("nan")

    out_dir = os.path.join(REPORTS_DIR, "rinex")
    os.makedirs(out_dir, exist_ok=True)
    obs_p = os.path.join(out_dir, "local_chain.obs")
    nav_p = os.path.join(out_dir, "local_chain.nav")
    write_obs(recs, obs_p)
    write_nav(recs + nav_recs, nav_p)
    hex_p = os.path.join(out_dir, "local_chain.hex")
    eph_p = os.path.join(out_dir, "local_chain_eph.json")
    write_hex_dump(recs + nav_recs, hex_p)
    eph_dump = {
        "sow0": sow0, "rx_ecef": rx.tolist(), "rx_clock_bias": sc.rx_clock_bias,
        "sats": [_eph_dict(s.eph) for s in sc.sats],
    }
    write_json(eph_p, eph_dump)

    banner = env_banner()
    lines = [
        "# 本机软件全链路（自动生成）", "",
        f"- 时间: {banner['generated_at']}",
        f"- git: {banner['git_revision']}",
        f"- 场景: {a.sec}s, {len(sc.sats)} 星, C/N0={a.cn0} dB-Hz, sow0={sow0}",
        f"- 接收机真值 ECEF: {rx.tolist()}",
        f"- 接收机钟差: {sc.rx_clock_bias*1e6:.1f} µs", "",
        "## 每星跟踪 / 电文", "",
        "| PRN | 锁定 | 窗口 | 多普勒误差(Hz) | 测量伪距(m) | 真值伪距(m) | ΔPR(m) | 子帧 |",
        "|---:|:---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        pr = r.get("pr_m")
        pt = r.get("pr_truth_m")
        dpr = r.get("dpr_m", float("nan"))
        pr_s = f"{pr:.3f}" if pr is not None else "-"
        pt_s = f"{pt:.3f}" if pt is not None else "-"
        lines.append(
            f"| {r['prn']} | {int(r['locked'])} | {r['dumps']} | "
            f"{r['fd_err_hz']:+.2f} | {pr_s} | {pt_s} | {dpr:+.3f} | {r['n_sf']} |")
    lines += [
        "", "## 单频码定位", "",
        f"- 参与卫星: {used}",
        f"- 迭代: {pvt.iters}  残差 RMS: {pvt.rms_m:.3f} m",
        f"- 位置误差 |Δr|: {err:.3f} m",
        f"- 钟差估计: {pvt.dt_s*1e6:.2f} µs（真值 {sc.rx_clock_bias*1e6:.2f} µs）",
        f"- 捕获移交：8 ms 非相干 FFT 码相位 + 短跟踪挑选多普勒（不用真值）",
        f"- 伪距：SOW 锚点 + dump 越界样本外推（不是场景几何真值）",
        f"- 卫星位置：refine_sagnac 用当前接收机解迭代（{a.sec}s 通常收不齐 SF1-3，星历用场景）",
        "", f"OBS: `{os.path.relpath(obs_p, ROOT)}`",
        f"NAV: `{os.path.relpath(nav_p, ROOT)}`",
        f"HEX: `{os.path.relpath(hex_p, ROOT)}`", "",
    ]
    md = os.path.join(REPORTS_DIR, "local_chain.md")
    write_text(md, "\n".join(lines))
    write_json(os.path.join(REPORTS_DIR, "local_chain.json"), {
        "banner": banner, "rows": rows, "used_prns": used,
        "pvt": {"xyz": pvt.xyz.tolist(), "dt_s": pvt.dt_s, "rms_m": pvt.rms_m,
                "err_m": err, "ok": pvt.ok},
        "obs": obs_p, "nav": nav_p, "hex": hex_p, "eph": eph_p,
        "sow0": sow0, "rx_ecef": rx.tolist(), "seed": a.seed, "sec": a.sec,
    })
    print("\n".join(lines))
    print(f"报告: {md}")
    return 0 if pvt.ok and err < 50.0 and all(r["locked"] for r in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
