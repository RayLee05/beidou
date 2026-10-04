"""从 RTL 格式 256 bit 记录做单频码定位。

用法:
  python scripts/pvt_from_records.py reports/rinex/local_chain.hex \\
      --eph reports/rinex/local_chain_eph.json

星历来自 sidecar（SF1-3 未齐时）或记录里成套 NAV。不读跟踪内部状态。
"""

from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import ROOT, SW_DIR, bootstrap, write_json  # noqa: E402

bootstrap()
sys.path.insert(0, SW_DIR)

import numpy as np  # noqa: E402
from b1i_ref import d1_nav, params as _p  # noqa: E402
from pvt.lsq import refine_sagnac  # noqa: E402
from rinex.records import (  # noqa: E402
    REC_EPOCH, REC_MEAS, REC_NAV, C_LIGHT,
    filter_current_generation, load_hex_dump, meas_pseudorange_m, tx_time_s,
)

P = _p.P
EPH_KEYS = (
    "prn", "WN", "toe", "toc", "sqrtA", "e", "i0", "OMEGA0", "omega", "M0",
    "dn", "OMEGADOT", "IDOT", "Cuc", "Cus", "Crc", "Crs", "Cic", "Cis",
    "a0", "a1", "a2", "TGD1", "TGD2", "AODE", "AODC", "URAI", "SatH1",
)


def _eph_from_obj(obj: dict) -> d1_nav.Ephemeris:
    kw = {k: obj[k] for k in EPH_KEYS if k in obj}
    if "iono" in obj:
        kw["iono"] = obj["iono"]
    return d1_nav.Ephemeris(**kw)


def _eph_from_nav(recs) -> dict:
    have = {}
    for r in recs:
        if r.kind != REC_NAV:
            continue
        f = r.fields
        have[(f["prn"], f["sf_id"])] = f
    out = {}
    prns = sorted({p for p, _ in have})
    for prn in prns:
        if not all((prn, s) in have for s in (1, 2, 3)):
            continue
        bits = {}
        for s in (1, 2, 3):
            info = have[(prn, s)]["info"]
            bits[s] = d1_nav.unpack_fields(s, [(info >> (223 - i)) & 1 for i in range(224)])
        out[prn] = d1_nav.Ephemeris.from_subframes(prn, bits[1], bits[2], bits[3])
    return out


def solve_from_records(recs, eph_by_prn: dict, sow0: float, xyz0=None) -> dict:
    recs = filter_current_generation(recs)
    epochs = {r.fields["epoch_id"]: r for r in recs if r.kind == REC_EPOCH}
    groups = {}
    for r in recs:
        if r.kind == REC_MEAS and r.fields.get("meas_valid") and r.fields.get("time_valid"):
            groups.setdefault(r.fields["epoch_id"], []).append(r)
    if not groups:
        return {"ok": False, "err_m": float("nan"), "note": "无有效 MEAS"}
    eid = max(groups)
    ep = epochs.get(eid)
    sats = groups[eid]
    if ep and ep.fields.get("rx_time_s") is not None:
        t_rx = float(ep.fields["rx_time_s"])
    elif ep and ep.fields.get("sow0_ms"):
        t_rx = ep.fields["sow0_ms"] / 1000.0 + max(
            (ep.fields["sample_count"] if ep else 0) - 1, 0) / P.f_s_hz
    else:
        scnt = ep.fields["sample_count"] if ep else 0
        t_rx = sow0 + max(scnt - 1, 0) / P.f_s_hz
    ephs, ttxs, prs, used = [], [], [], []
    rx0 = np.zeros(3) if xyz0 is None else np.asarray(xyz0, dtype=float)
    for m in sats:
        prn = int(m.fields["prn"])
        eph = eph_by_prn.get(prn)
        if eph is None:
            continue
        t_tx_sv = tx_time_s(m.fields["tx_ms"], m.fields["code_phase"])
        dtsv = eph.clock_bias(t_tx_sv)
        ephs.append(eph)
        ttxs.append(t_tx_sv - dtsv)
        prs.append(meas_pseudorange_m(m.fields["tx_ms"], m.fields["code_phase"], t_rx) + C_LIGHT * dtsv)
        used.append(prn)
    pvt = refine_sagnac(ephs, ttxs, prs, xyz0=xyz0)
    err = float(np.linalg.norm(pvt.xyz - rx0)) if pvt.ok and xyz0 is not None else float("nan")
    return {
        "ok": pvt.ok, "used_prns": used, "xyz": pvt.xyz.tolist(),
        "dt_s": pvt.dt_s, "rms_m": pvt.rms_m, "err_m": err,
        "t_rx": t_rx, "n_sats": len(used),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("hex_file")
    ap.add_argument("--eph", default="")
    ap.add_argument("--out", default="reports/pvt_from_records.json")
    a = ap.parse_args()
    hex_p = a.hex_file if os.path.isabs(a.hex_file) else os.path.join(ROOT, a.hex_file)
    recs = load_hex_dump(hex_p)
    sow0, xyz0, ephs = 0.0, None, _eph_from_nav(recs)
    if a.eph:
        ep = a.eph if os.path.isabs(a.eph) else os.path.join(ROOT, a.eph)
        meta = json.load(open(ep, encoding="utf-8"))
        sow0 = float(meta.get("sow0", 0.0))
        if sow0 == 0.0:
            for r in recs:
                if r.kind == REC_EPOCH and r.fields.get("sow0_ms"):
                    sow0 = r.fields["sow0_ms"] / 1000.0
                    break
        if meta.get("rx_ecef"):
            xyz0 = np.array(meta["rx_ecef"], dtype=float)
        for s in meta.get("sats", []):
            e = _eph_from_obj(s)
            ephs[e.prn] = e
    result = solve_from_records(recs, ephs, sow0, xyz0)
    out_p = a.out if os.path.isabs(a.out) else os.path.join(ROOT, a.out)
    os.makedirs(os.path.dirname(out_p), exist_ok=True)
    write_json(out_p, {"hex": hex_p, "n_rec": len(recs), "pvt": result})
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print(f"报告: {out_p}")
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
