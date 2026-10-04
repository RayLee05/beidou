"""解析 256 bit 记录（字段与 rtl/include/b1i_records.svh 一致）。"""

from __future__ import annotations

import math
from dataclasses import dataclass

from b1i_ref.params import P

C_LIGHT = 299792458.0
CODE_FRAC_W = 21
MEO_TRAVEL_S = 0.080

REC_EPOCH, REC_MEAS, REC_NAV, REC_STATUS = 1, 2, 3, 4


def tx_time_s(tx_ms: int, code_phase: int, code_rate_hz: float | None = None) -> float:
    """发射时刻（秒）：整数毫秒 + 码相位小数 / 码率。码相位为 Q(11.21)。"""
    rate = code_rate_hz or P.code_rate_hz
    frac_chips = code_phase / float(1 << CODE_FRAC_W)
    return tx_ms / 1000.0 + frac_chips / rate


def tx_time_from_sow(sow_s: float, dump_ms: int, anchor_ms: int,
                     t_rx_dump_s: float, t_rx_epoch_s: float) -> float:
    """与 RTL `tx_ms = SOW*1000 + (dump_ms - anchor_ms) + 1` 对齐，再外推到历元。

    码周期越界时 NCO 已回绕，Q(11.21) 残差几乎是 0；精细距离在越界样本
    `sample_end`（t_rx_dump）。外推：t_sv(历元) = t_sv(dump) + (t_rx_历元 − t_rx_dump)。
    """
    # dump_ms 是窗口起点标签；越界（窗口结束）时卫星时间已再走 1 ms
    t_sv_dump = float(sow_s) + (int(dump_ms) - int(anchor_ms) + 1) / 1000.0
    return t_sv_dump + (t_rx_epoch_s - t_rx_dump_s)


def pack_tx_fields(t_tx_s: float, code_rate_hz: float | None = None) -> tuple:
    """把发射时刻拆成整数毫秒 + Q(11.21) 码相位，供 MEAS / RINEX 共用。"""
    rate = code_rate_hz or P.code_rate_hz
    tx_ms = int(math.floor(t_tx_s * 1000.0 + 1e-15))
    frac_s = t_tx_s - tx_ms / 1000.0
    if frac_s < 0.0:
        tx_ms -= 1
        frac_s += 1e-3
    word = int(round(frac_s * rate * (1 << CODE_FRAC_W)))
    period = int(P.code_chips_per_period) << CODE_FRAC_W
    return tx_ms, word % period


def common_rx_s(tx_times, travel_s: float = MEO_TRAVEL_S) -> float:
    """公共接收时刻：最晚发射时刻 + 标称传播，使各星伪距在同一历元。"""
    xs = [t for t in tx_times if t is not None]
    if not xs:
        return 0.0
    return max(xs) + travel_s


def meas_pseudorange_m(tx_ms: int, code_phase: int, t_rx_s: float,
                       code_rate_hz: float | None = None) -> float:
    """PR = c × (t_rx − t_tx)。t_rx / t_tx 必须同一时间尺度（BDT 秒）。"""
    return (t_rx_s - tx_time_s(tx_ms, code_phase, code_rate_hz)) * C_LIGHT


def _bits(v: int, hi: int, lo: int) -> int:
    return (v >> lo) & ((1 << (hi - lo + 1)) - 1)


@dataclass
class Rec:
    kind: int
    raw: int
    fields: dict


def parse_record(word: int) -> Rec:
    kind = _bits(word, 255, 252)
    if kind == REC_EPOCH:
        f = {
            "epoch_id": _bits(word, 251, 220),
            "sample_count": _bits(word, 219, 188),
            "n_valid": _bits(word, 187, 176),
            "input_done": _bits(word, 175, 175),
            "sow0_ms": _bits(word, 174, 143),
        }
    elif kind == REC_MEAS:
        f = {
            "channel": _bits(word, 251, 248),
            "prn": _bits(word, 247, 242),
            "generation": _bits(word, 241, 234),
            "epoch_id": _bits(word, 233, 202),
            "tx_ms": _bits(word, 201, 170),
            "code_phase": _bits(word, 169, 138),
            "dop_word": _signed(_bits(word, 137, 106), 32),
            "ms_count": _bits(word, 105, 74),
            "meas_valid": _bits(word, 73, 73),
            "locked": _bits(word, 72, 72),
            "bit_synced": _bits(word, 71, 71),
            "time_valid": _bits(word, 70, 70),
            "ch_state": _bits(word, 69, 67),
            "lock_cnt": _bits(word, 66, 63),
            "week": _bits(word, 62, 50),
            "week_valid": _bits(word, 49, 49),
        }
    elif kind == REC_NAV:
        f = {
            "channel": _bits(word, 251, 248),
            "prn": _bits(word, 247, 242),
            "generation": _bits(word, 241, 238),
            "sf_id": _bits(word, 237, 235),
            "fixes": _bits(word, 234, 230),
            "inverted": _bits(word, 229, 229),
            "info": _bits(word, 223, 0),
        }
    else:
        f = {
            "channel": _bits(word, 251, 248),
            "prn": _bits(word, 247, 242),
            "generation": _bits(word, 241, 234),
            "sample_count": _bits(word, 233, 202),
            "event": _bits(word, 201, 198),
            "a1": _bits(word, 197, 166),
            "a2": _bits(word, 165, 134),
            "a3": _bits(word, 133, 122),
        }
    return Rec(kind=kind, raw=word, fields=f)


def _signed(v: int, w: int) -> int:
    if v & (1 << (w - 1)):
        return v - (1 << w)
    return v


def _u(v: int, w: int) -> int:
    return int(v) & ((1 << w) - 1)


def pack_record(rec: Rec) -> int:
    """按 b1i_records.svh 把字段打成 256 bit。软件专用字段（如 rx_time_s）丢弃。"""
    f = rec.fields
    if rec.kind == REC_EPOCH:
        w = _u(REC_EPOCH, 4) << 252
        w |= _u(f.get("epoch_id", 0), 32) << 220
        w |= _u(f.get("sample_count", 0), 32) << 188
        w |= _u(f.get("n_valid", 0), 12) << 176
        w |= _u(f.get("input_done", 0), 1) << 175
        w |= _u(f.get("sow0_ms", 0), 32) << 143
        return w
    if rec.kind == REC_MEAS:
        w = _u(REC_MEAS, 4) << 252
        w |= _u(f.get("channel", 0), 4) << 248
        w |= _u(f.get("prn", 0), 6) << 242
        w |= _u(f.get("generation", 0), 8) << 234
        w |= _u(f.get("epoch_id", 0), 32) << 202
        w |= _u(f.get("tx_ms", 0), 32) << 170
        w |= _u(f.get("code_phase", 0), 32) << 138
        w |= _u(f.get("dop_word", 0), 32) << 106
        w |= _u(f.get("ms_count", 0), 32) << 74
        w |= _u(f.get("meas_valid", 0), 1) << 73
        w |= _u(f.get("locked", 0), 1) << 72
        w |= _u(f.get("bit_synced", 0), 1) << 71
        w |= _u(f.get("time_valid", 0), 1) << 70
        w |= _u(f.get("ch_state", 0), 3) << 67
        w |= _u(f.get("lock_cnt", 0), 4) << 63
        w |= _u(f.get("week", 0), 13) << 50
        w |= _u(f.get("week_valid", 0), 1) << 49
        return w
    if rec.kind == REC_NAV:
        w = _u(REC_NAV, 4) << 252
        w |= _u(f.get("channel", 0), 4) << 248
        w |= _u(f.get("prn", 0), 6) << 242
        w |= _u(f.get("generation", 0), 4) << 238
        w |= _u(f.get("sf_id", 0), 3) << 235
        w |= _u(f.get("fixes", 0), 5) << 230
        w |= _u(f.get("inverted", 0), 1) << 229
        w |= _u(f.get("info", 0), 224)
        return w
    w = _u(REC_STATUS, 4) << 252
    w |= _u(f.get("channel", 0), 4) << 248
    w |= _u(f.get("prn", 0), 6) << 242
    w |= _u(f.get("generation", 0), 8) << 234
    w |= _u(f.get("sample_count", 0), 32) << 202
    w |= _u(f.get("event", 0), 4) << 198
    w |= _u(f.get("a1", 0), 32) << 166
    w |= _u(f.get("a2", 0), 32) << 134
    w |= _u(f.get("a3", 0), 12) << 122
    return w


def write_hex_dump(recs: list, path) -> None:
    """每行 64 个十六进制字符（256 bit），与 load_hex_dump 对拍。"""
    lines = [f"{pack_record(r):064x}" for r in recs]
    open(path, "w", encoding="ascii").write("\n".join(lines) + "\n")


def latest_generation(recs) -> dict:
    """每通道见到的最大 generation。"""
    latest = {}
    for r in recs:
        if r.kind == REC_EPOCH:
            continue
        ch = r.fields.get("channel")
        if ch is None:
            continue
        g = int(r.fields.get("generation", 0))
        latest[ch] = max(latest.get(ch, 0), g)
    return latest


def filter_current_generation(recs) -> list:
    """丢掉失锁重捕前的旧代次 MEAS/NAV/STATUS。EPOCH 原样保留。"""
    latest = latest_generation(recs)
    out = []
    for r in recs:
        if r.kind == REC_EPOCH:
            out.append(r)
            continue
        ch = r.fields.get("channel")
        if ch is None or int(r.fields.get("generation", 0)) == latest.get(ch, 0):
            out.append(r)
    return out


def load_hex_dump(path) -> list:
    """每行一个 64 位十六进制（256 bit）。"""
    recs = []
    for line in open(path, encoding="utf-8"):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        recs.append(parse_record(int(s, 16)))
    return recs
