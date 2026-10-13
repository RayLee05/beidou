"""Locate a read-only teacher package and select its actual streaming contract."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODES = {"lsb16": (2, 16), "legacy16": (1, 4), "lsb4": (0, 4)}
# The first public package documented four samples but actually sent sixteen
# MSB-first file pairs and advanced tags by four. Limit that workaround to the
# verified original player rather than guessing an arbitrary producer's format.
LEGACY_PLAYER_SHA256 = "61db380bd1c439a088a94cb69e28dd76d151d3327eb28dd3b8de51d53a40e7b0"


def resolve_release(path: Path | None = None, *, root: Path = ROOT) -> Path:
    candidates = ([path, path / "student_release"] if path is not None else
                  [root / "student_release1/student_release", root / "student_release1",
                   root / "student_release", root / "student_rease/student_release"])
    for candidate in candidates:
        if ((candidate / "input/input_contract.json").is_file()
                and (candidate / "sim/if2_file_player.sv").is_file()):
            return candidate.resolve()
    raise ValueError("teacher package not found; pass --release with input/ and sim/ directories")


def stream_config(release: Path, mode: str = "auto", tag_stride: int | None = None) -> dict:
    contract = json.loads((release / "input/input_contract.json").read_text(encoding="utf-8"))
    if mode == "auto":
        public = contract.get("stream_player_contract", {})
        count = public.get("samples_per_transfer")
        earliest = public.get("stream_data_bit_1_0_is_earliest_sample")
        player_text = (release / "sim/if2_file_player.sv").read_text(encoding="utf-8")
        original = hashlib.sha256(player_text.encode()).hexdigest() == LEGACY_PLAYER_SHA256
        if original:
            mode = "legacy16"
        elif count == 16 and earliest is True:
            mode = "lsb16"
        elif count == 4 and earliest is True:
            mode = "lsb4"
        else:
            raise ValueError("unsupported stream contract; specify --stream-mode explicitly")
    if mode not in MODES:
        raise ValueError(f"unsupported stream mode: {mode}")
    rtl_mode, default_stride = MODES[mode]
    stride = default_stride if tag_stride is None else tag_stride
    samples = 4 if rtl_mode == 0 else 16
    if stride < 1 or samples % stride:
        raise ValueError("tag stride must be positive and divide samples per transfer")
    return {"mode": mode, "rtl_mode": rtl_mode, "tag_stride": stride,
            "samples_per_transfer": samples, "earliest_pair": "stream_data[1:0]" if rtl_mode != 1
            else "stream_data[7:6]", "package_id": contract.get("package_id")}
