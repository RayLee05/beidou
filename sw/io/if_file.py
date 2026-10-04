"""2 bit 中频样本文件（与 INTERFACES.md / sample_unpacker 一致）。"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

from b1i_ref.params import B1IParams, P

LEVELS = P.sample_levels  # (-3, -1, 1, 3)
SHIFTS = P.sample_code_shift  # (6, 4, 2, 0)


@dataclass
class SampleStream:
    metadata: dict
    samples: list

    def __iter__(self) -> Iterator[tuple[int, int]]:
        for i, s in enumerate(self.samples):
            yield i, s


def _decode_byte(b: int) -> list:
    out = []
    for sh in SHIFTS:
        out.append(LEVELS[(b >> sh) & 3])
    return out


def _encode_byte(four: list) -> int:
    inv = {v: i for i, v in enumerate(LEVELS)}
    b = 0
    for sh, s in zip(SHIFTS, four):
        b |= inv[int(s)] << sh
    return b


def read_2bit_if(path, metadata_path=None) -> SampleStream:
    p = Path(path)
    raw = p.read_bytes()
    meta = {}
    mp = Path(metadata_path) if metadata_path else p.with_suffix(p.suffix + ".json")
    if not mp.exists():
        mp = p.with_suffix(".json")
    if mp.exists():
        meta = json.loads(mp.read_text(encoding="utf-8"))
        n = int(meta.get("sample_count") or 0)
        if n and len(raw) * 4 < n:
            raise ValueError(f"TRUNCATED_INPUT: file has {len(raw)*4} samples, metadata {n}")
    samples = []
    for b in raw:
        samples.extend(_decode_byte(b))
    if meta.get("sample_count"):
        samples = samples[: int(meta["sample_count"])]
    return SampleStream(metadata=meta, samples=samples)


def write_2bit_if(path, samples, metadata=None) -> None:
    p = Path(path)
    buf = bytearray()
    xs = list(samples)
    for i in range(0, len(xs), 4):
        chunk = xs[i:i + 4]
        while len(chunk) < 4:
            chunk.append(1)
        buf.append(_encode_byte(chunk))
    p.write_bytes(buf)
    meta = {
        "format_version": 1,
        "sample_encoding": "2bit-pair",
        "sample_rate_hz": int(B1IParams().f_s_hz),
        "if_hz": int(B1IParams().f_if_hz),
        "byte_order": "sample0_msb",
        "start_sample": 0,
        "sample_count": len(xs),
    }
    if metadata:
        meta.update(metadata)
    p.with_suffix(".json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
