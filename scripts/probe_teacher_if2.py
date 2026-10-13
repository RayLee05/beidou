"""在教师 student_release 的 scenario.if2 上做全 PRN 粗捕获（只读样本，不用任何真值）。

用法: python scripts/probe_teacher_if2.py [--ms 10] [--offset-ms 0]
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import ROOT, SW_DIR, bootstrap, write_json  # noqa: E402
from teacher_release import resolve_release  # noqa: E402

bootstrap()
sys.path.insert(0, SW_DIR)

import numpy as np  # noqa: E402
from b1i_ref import params as _p, prn_b1i  # noqa: E402
from b1i_ref.acquisition import ncoh_on_grid, coarse_doppler_grid  # noqa: E402

P = _p.P
LUT = np.array([-3, -1, 1, 3], dtype=np.int8)


def read_samples(path: str, offset_ms: int, n_ms: int) -> np.ndarray:
    spm = P.samples_per_ms
    start_b = offset_ms * spm // 4
    n_b = n_ms * spm // 4
    with open(path, "rb") as f:
        f.seek(start_b)
        raw = np.frombuffer(f.read(n_b), dtype=np.uint8)
    codes = np.stack([(raw >> s) & 3 for s in (6, 4, 2, 0)], axis=1).reshape(-1)
    return LUT[codes]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ms", type=int, default=10)
    ap.add_argument("--offset-ms", type=int, default=0)
    ap.add_argument("--span", type=float, default=10000.0)
    ap.add_argument("--release", type=Path)
    ap.add_argument("--input", type=Path)
    ap.add_argument("--out", default="reports/teacher_probe.json")
    a = ap.parse_args()
    try:
        input_path = a.input or resolve_release(a.release) / "input/scenario.if2"
    except ValueError as error:
        ap.error(str(error))
    if a.ms < 1 or a.offset_ms < 0:
        ap.error("--ms must be positive and --offset-ms nonnegative")
    x = read_samples(str(input_path), a.offset_ms, a.ms)
    if len(x) != a.ms * P.samples_per_ms:
        ap.error("requested IF2 interval exceeds available input")
    grid = coarse_doppler_grid(a.span, 500.0)
    rows = []
    for prn in sorted(prn_b1i.G2_TAPS):
        hit = ncoh_on_grid(x, prn_b1i.prn_code(prn), grid, n_ms=a.ms)[0]
        rows.append({"prn": prn, "fd": hit["doppler_hz"], "cp": hit["code_phase_chips"],
                     "peak": hit["peak_mag"]})
    peaks = np.array([r["peak"] for r in rows])
    floor = float(np.median(peaks))
    for r in rows:
        r["ratio"] = r["peak"] / floor
    rows.sort(key=lambda r: -r["ratio"])
    for r in rows[:10]:
        print(f"PRN{r['prn']:02d}  ratio={r['ratio']:.2f}  fd={r['fd']:+.0f} Hz  "
              f"cp={r['cp']:.2f} chip")
    out = a.out if os.path.isabs(a.out) else os.path.join(ROOT, a.out)
    write_json(out, {"ms": a.ms, "offset_ms": a.offset_ms, "median_peak": floor, "rows": rows})
    print(f"report: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
