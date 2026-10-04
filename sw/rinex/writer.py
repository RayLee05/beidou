"""RINEX 3.05 OBS / NAV 文本。RTL 不拼文本，只在这里生成。"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from b1i_ref import d1_nav
from b1i_ref.params import P
from .records import (
    REC_MEAS, REC_NAV, REC_EPOCH,
    common_rx_s, filter_current_generation, meas_pseudorange_m, tx_time_s,
)


def _header_obs(n_epoch: int) -> str:
    now = datetime.now(timezone.utc).strftime("%Y%m%d %H%M%S UTC")
    return "\n".join([
        f"     3.05           OBSERVATION DATA    C: BDS              RINEX VERSION / TYPE",
        f"BEIDOU B1I          beidou              {now} PGM / RUN BY / DATE",
        f"C    1 C2I                                                  SYS / # / OBS TYPES",
        f"     1.000                                                  INTERVAL",
        f"{n_epoch:6d}                                                      # OF EPOCHS",
        f"     BDT                                                    TIME SYSTEM ID",
        f"                                                            END OF HEADER",
    ])


def write_obs(recs: list, path, fs_hz: float | None = None) -> None:
    recs = filter_current_generation(recs)
    fs = fs_hz or P.f_s_hz
    epochs = {}
    for r in recs:
        if r.kind == REC_EPOCH:
            epochs[r.fields["epoch_id"]] = r
    groups = {}
    for r in recs:
        if r.kind != REC_MEAS:
            continue
        groups.setdefault(r.fields["epoch_id"], []).append(r)

    lines = [_header_obs(len(groups))]
    for eid in sorted(groups):
        ep = epochs.get(eid)
        scnt = ep.fields["sample_count"] if ep else 0
        sats = [m for m in groups[eid] if m.fields.get("meas_valid") and m.fields.get("time_valid")]
        txs = [tx_time_s(m.fields["tx_ms"], m.fields["code_phase"]) for m in sats]
        if ep and ep.fields.get("rx_time_s") is not None:
            t_rx = float(ep.fields["rx_time_s"])
        elif ep and ep.fields.get("sow0_ms"):
            t_rx = ep.fields["sow0_ms"] / 1000.0 + max(scnt - 1, 0) / fs
        else:
            t_rx = common_rx_s(txs) if txs else (scnt / fs)
        sow = int(t_rx) % 604800
        hh, rem = divmod(sow, 3600)
        mm, ss = divmod(rem, 60)
        week = next((m.fields["week"] for m in sats if m.fields.get("week_valid")), 0)
        epoch = datetime(2006, 1, 1, tzinfo=timezone.utc) + timedelta(weeks=int(week), seconds=sow)
        lines.append(
            f"> {epoch.year:4d} {epoch.month:02d} {epoch.day:02d} "
            f"{hh:02d} {mm:02d} {ss:11.7f}  0 {len(sats):2d}"
        )
        for m in sorted(sats, key=lambda x: x.fields["prn"]):
            f = m.fields
            if f["meas_valid"] and f["time_valid"]:
                pr = meas_pseudorange_m(f["tx_ms"], f["code_phase"], t_rx)
                lines.append(f"C{f['prn']:02d}  {pr:14.3f}")
            else:
                lines.append(f"C{f['prn']:02d}")
    path = str(path)
    open(path, "w", encoding="ascii").write("\n".join(lines) + "\n")


def _info_bits(info: int) -> list:
    return [(info >> (223 - i)) & 1 for i in range(224)]


def write_nav(recs: list, path) -> None:
    recs = filter_current_generation(recs)
    now = datetime.now(timezone.utc).strftime("%Y%m%d %H%M%S UTC")
    lines = [
        f"     3.05           N: GNSS NAV DATA    C: BDS              RINEX VERSION / TYPE",
        f"BEIDOU B1I          beidou              {now} PGM / RUN BY / DATE",
        "                                                            END OF HEADER",
    ]
    have = {}
    for r in recs:
        if r.kind != REC_NAV:
            continue
        f = r.fields
        key = (f["prn"], f["sf_id"])
        have[key] = f

    # 只在子帧 1-3 都到齐时写一颗星（课程最低要求：真实解调字段）
    prns = sorted({p for p, s in have})
    for prn in prns:
        if not all((prn, s) in have for s in (1, 2, 3)):
            continue
        bits = {}
        for s in (1, 2, 3):
            bits[s] = d1_nav.unpack_fields(s, _info_bits(have[(prn, s)]["info"]))
        eph = d1_nav.Ephemeris.from_subframes(prn, bits[1], bits[2], bits[3])
        lines.append(
            f"C{prn:02d} {eph.WN} {eph.toc:.1f} {eph.a0:.12e} {eph.a1:.12e} {eph.a2:.12e}"
        )
        lines.append(
            f"    {eph.AODE} {eph.Crs:.6e} {eph.dn:.12e} {eph.M0:.12e}"
        )
    open(path, "w", encoding="ascii").write("\n".join(lines) + "\n")
