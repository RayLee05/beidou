"""本机记录闭环自检：打包回读、generation 过滤、hex→PVT、RINEX 回读。

不跑 7 s 跟踪。若已有 reports/local_chain.json 则用其中的测量字段重打包。
"""

from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import REPORTS_DIR, ROOT, SW_DIR, bootstrap, write_json  # noqa: E402

bootstrap()
sys.path.insert(0, SW_DIR)

import numpy as np  # noqa: E402
from b1i_ref import d1_nav, params as _p, scenario  # noqa: E402
from rinex.records import (  # noqa: E402
    REC_EPOCH, REC_MEAS, REC_NAV, Rec,
    filter_current_generation, pack_record, parse_record, write_hex_dump,
)
from rinex.validate import validate_nav, validate_obs  # noqa: E402

from pvt_from_records import _eph_from_obj, solve_from_records  # noqa: E402

P = _p.P


def _roundtrip() -> None:
    recs = [
        Rec(REC_EPOCH, 0, {"epoch_id": 3, "sample_count": 16368, "n_valid": 2,
                           "input_done": 1, "sow0_ms": 345618000}),
        Rec(REC_MEAS, 0, {
            "channel": 1, "prn": 14, "generation": 2, "epoch_id": 3,
            "tx_ms": 345624000, "code_phase": 1 << 20, "dop_word": -7,
            "ms_count": 9, "meas_valid": 1, "locked": 1, "bit_synced": 1,
            "time_valid": 1, "ch_state": 2, "lock_cnt": 5, "week": 1000,
            "week_valid": 1,
        }),
        Rec(REC_NAV, 0, {
            "channel": 1, "prn": 14, "generation": 2, "sf_id": 4,
            "fixes": 1, "inverted": 0, "info": 0x1234,
        }),
    ]
    for r in recs:
        back = parse_record(pack_record(r))
        for k, v in r.fields.items():
            if back.fields.get(k) != v:
                raise SystemExit(f"roundtrip {r.kind} {k}: {v} -> {back.fields.get(k)}")


def _generation() -> None:
    recs = [
        Rec(REC_EPOCH, 0, {"epoch_id": 1, "sample_count": 1, "n_valid": 1, "input_done": 0}),
        Rec(REC_NAV, 0, {"channel": 0, "prn": 7, "generation": 1, "sf_id": 1,
                         "fixes": 0, "inverted": 0, "info": 1}),
        Rec(REC_NAV, 0, {"channel": 0, "prn": 7, "generation": 2, "sf_id": 1,
                         "fixes": 0, "inverted": 0, "info": 2}),
        Rec(REC_MEAS, 0, {"channel": 0, "prn": 7, "generation": 1, "epoch_id": 1,
                          "tx_ms": 0, "code_phase": 0, "dop_word": 0, "ms_count": 0,
                          "meas_valid": 1, "locked": 1, "bit_synced": 1, "time_valid": 1,
                          "ch_state": 2, "lock_cnt": 1, "week": 0, "week_valid": 0}),
        Rec(REC_MEAS, 0, {"channel": 0, "prn": 7, "generation": 2, "epoch_id": 1,
                          "tx_ms": 1, "code_phase": 0, "dop_word": 0, "ms_count": 0,
                          "meas_valid": 1, "locked": 1, "bit_synced": 1, "time_valid": 1,
                          "ch_state": 2, "lock_cnt": 1, "week": 0, "week_valid": 0}),
    ]
    kept = filter_current_generation(recs)
    navs = [r for r in kept if r.kind == REC_NAV]
    meas = [r for r in kept if r.kind == REC_MEAS]
    if len(navs) != 1 or navs[0].fields["generation"] != 2:
        raise SystemExit("generation 过滤未丢掉旧 NAV")
    if len(meas) != 1 or meas[0].fields["tx_ms"] != 1:
        raise SystemExit("generation 过滤未丢掉旧 MEAS")


def _pvt_from_json() -> None:
    jp = os.path.join(REPORTS_DIR, "local_chain.json")
    if not os.path.isfile(jp):
        print("SKIP hex→PVT（尚无 local_chain.json）")
        return
    doc = json.load(open(jp, encoding="utf-8"))
    sow0 = float(doc.get("sow0", 345618.0))
    seed = int(doc.get("seed", 3))
    rx = np.array(doc.get("rx_ecef") or scenario.geodetic_to_ecef(39.9, 116.4, 50.0))
    rows = [r for r in doc["rows"] if r.get("time_valid") and r.get("locked")]
    if len(rows) < 4:
        raise SystemExit("local_chain.json 有效星少于 4")
    ephs = scenario.make_constellation(rx, sow0, 1000, n_sats=len(rows), seed=seed)
    eph_by = {e.prn: e for e in ephs}
    sec = float(doc.get("sec", 7.0))
    n = int(sec * P.f_s_hz)
    recs = [Rec(REC_EPOCH, 0, {
        "epoch_id": 1, "sample_count": n, "n_valid": len(rows), "input_done": 1,
        "sow0_ms": int(round(sow0 * 1000.0)),
        "rx_time_s": sow0 + (n - 1) / P.f_s_hz,
    })]
    for i, r in enumerate(rows):
        recs.append(Rec(REC_MEAS, 0, {
            "channel": i, "prn": r["prn"], "generation": 1, "epoch_id": 1,
            "tx_ms": r["tx_ms"], "code_phase": r["code_phase"],
            "dop_word": 0, "ms_count": r.get("dumps", 0),
            "meas_valid": 1, "locked": 1, "bit_synced": 1, "time_valid": 1,
            "ch_state": 2, "lock_cnt": 1,
            "week": r.get("week", 0), "week_valid": r.get("week_valid", 0),
        }))
    out_dir = os.path.join(REPORTS_DIR, "rinex")
    os.makedirs(out_dir, exist_ok=True)
    hx = os.path.join(out_dir, "local_chain.hex")
    write_hex_dump(recs, hx)
    from dataclasses import asdict
    write_json(os.path.join(out_dir, "local_chain_eph.json"), {
        "sow0": sow0, "rx_ecef": rx.tolist(),
        "sats": [asdict(eph_by[r["prn"]]) for r in rows if r["prn"] in eph_by],
    })
    back = solve_from_records(
        [parse_record(pack_record(r)) for r in recs],
        eph_by, sow0, xyz0=rx)
    exp = float(doc["pvt"]["err_m"])
    if not back["ok"]:
        raise SystemExit(f"hex→PVT 失败: {back}")
    if abs(back["err_m"] - exp) > 15.0:
        raise SystemExit(f"hex→PVT |Δr|={back['err_m']:.3f} 与 json {exp:.3f} 差过大")
    print(f"hex→PVT |Δr|={back['err_m']:.3f} m  dt={back['dt_s']*1e6:.2f} µs")


def _rinex() -> None:
    obs = os.path.join(REPORTS_DIR, "rinex", "local_chain.obs")
    nav = os.path.join(REPORTS_DIR, "rinex", "local_chain.nav")
    if os.path.isfile(obs):
        err = validate_obs(obs)
        if err:
            raise SystemExit("OBS: " + "; ".join(err))
        print(f"OBS 回读通过: {obs}")
    if os.path.isfile(nav):
        err = validate_nav(nav)
        if err:
            raise SystemExit("NAV: " + "; ".join(err))
        print(f"NAV 回读通过: {nav}")


def main() -> int:
    _roundtrip()
    _generation()
    _pvt_from_json()
    _rinex()
    print("TEST PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
