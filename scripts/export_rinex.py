"""把 RTL 导出的 256 bit 十六进制记录转成 RINEX 3.05 OBS/NAV。

用法:
  python scripts/export_rinex.py reports/sim/records.hex --obs out.obs --nav out.nav
"""

from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import ROOT, SW_DIR, bootstrap  # noqa: E402

bootstrap()
sys.path.insert(0, SW_DIR)

from rinex.records import filter_current_generation, load_hex_dump  # noqa: E402
from rinex.writer import write_nav, write_obs  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("hex_file")
    ap.add_argument("--obs", default="reports/rinex/out.obs")
    ap.add_argument("--nav", default="reports/rinex/out.nav")
    args = ap.parse_args()
    recs = filter_current_generation(
        load_hex_dump(os.path.join(ROOT, args.hex_file) if not os.path.isabs(args.hex_file) else args.hex_file))
    os.makedirs(os.path.dirname(os.path.join(ROOT, args.obs)), exist_ok=True)
    write_obs(recs, os.path.join(ROOT, args.obs))
    write_nav(recs, os.path.join(ROOT, args.nav))
    print(f"OBS {args.obs}  NAV {args.nav}  records={len(recs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
