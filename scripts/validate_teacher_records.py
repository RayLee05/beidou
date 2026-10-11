"""Stream-check RTL records using the teacher's independent decoder and BCH.

Does not load the entire decoded capture into memory or use signal-source truth.
"""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def validate(path: Path, release: Path, expected_samples: int,
             minimum_acquisitions: int = 0, require_signal_results: bool = False) -> dict:
    tools_dir = release / "tools"
    sys.path.insert(0, str(tools_dir))
    from decode_records import decode
    from prompt_d1 import decode_word

    size = path.stat().st_size
    if not size or size % 32:
        raise ValueError("empty or unaligned BIN")
    counts: Counter = Counter()
    detected: set[int] = set()
    epoch_prns: set[tuple[int, int]] = set()
    navigation: dict[tuple[int, int, int], dict] = {}
    locked_tracking = valid_common = complete_subframes = 0
    ended = False
    with path.open("rb") as stream:
        for number in range(size // 32):
            row = decode(stream.read(32))
            kind, p, ch = int(row["type_id"]), int(row["prn"]), int(row["channel"])
            sample = int(row["sample_index"])
            if ended or kind not in range(1, 7) or sample > expected_samples:
                raise ValueError(f"record {number}: invalid type, time or record after END")
            counts[row["type"]] += 1
            if kind in (1, 2, 3, 4) and (p not in range(1, 64) or ch not in range(12)):
                raise ValueError(f"record {number}: invalid PRN/channel")
            if kind in (1, 2, 4) and int(row["code_chip"]) >= 2046:
                raise ValueError(f"record {number}: invalid code phase")
            if kind == 1:
                if int(row["schema_version"]) != 3:
                    raise ValueError("expected tracking schema 3")
                locked_tracking += int(bool(row["locked"]))
            elif kind == 2:
                w = int(row["word_number"])
                if w not in range(1, 11) or not row["bch_valid"]:
                    raise ValueError("invalid navigation word number/BCH validity")
                raw = int(row["raw_word"])
                information, corrections = decode_word([(raw >> (29-b)) & 1 for b in range(30)], w == 1)
                value = 0
                for bit in information:
                    value = (value << 1) | bit
                if value != int(row["information"]) or corrections != int(row["corrected_bits"]):
                    raise ValueError(f"record {number}: raw word, decoded information or BCH count disagree")
                key = (p, ch, int(row["generation"]))
                previous = navigation.get(key)
                if w == 1:
                    if previous and len(previous["information"]) != 224:
                        raise ValueError("new subframe replaced unfinished navigation words")
                    if raw >> 19 != 0b11100010010:
                        raise ValueError("navigation preamble mismatch")
                    previous = {"information": [], "next_word": 1, "sample": -1,
                                "sow": int(row["sow"]), "id": int(row["subframe_id"])}
                    navigation[key] = previous
                if not previous or previous["next_word"] != w or sample <= previous["sample"]:
                    raise ValueError("navigation word sequence or measured END time mismatch")
                if previous["sow"] != int(row["sow"]) or previous["id"] != int(row["subframe_id"]):
                    raise ValueError("navigation subframe identity changed between words")
                previous["information"].extend(information)
                previous["sample"] = sample
                previous["next_word"] += 1
                if w == 10:
                    info = previous["information"]
                    id_value = sow_value = 0
                    for bit in info[15:18]: id_value = (id_value << 1) | bit
                    for bit in info[18:38]: sow_value = (sow_value << 1) | bit
                    if id_value != previous["id"] or sow_value != previous["sow"]:
                        raise ValueError("subframe fields disagree with independently decoded information")
                    complete_subframes += 1
            elif kind == 4:
                epoch = int(row["common_epoch_id"])
                key = (epoch, p)
                if sample != epoch * 16_368_000 or key in epoch_prns or not row["active"]:
                    raise ValueError("common epoch time, duplicate or inactive observation")
                epoch_prns.add(key)
                if row["measurement_valid"]:
                    if not all(row[k] for k in ("locked", "nh_valid", "frame_valid", "time_valid", "bch_valid")):
                        raise ValueError("measurement validity exceeds actual channel/nav validity")
                    valid_common += 1
            elif kind == 5:
                if row["detected"]:
                    if p not in range(1, 64) or row["incomplete"]:
                        raise ValueError("invalid successful acquisition")
                    detected.add(p)
            elif kind == 6:
                if sample != expected_samples or row["underrun"] or row["overflow"] or row["missing_ticks"]:
                    raise ValueError("END count or errors")
                ended = True
    if not ended or any(len(sf["information"]) != 224 for sf in navigation.values()):
        raise ValueError("missing END or unfinished navigation subframe")
    if len(detected) < minimum_acquisitions:
        raise ValueError(f"only {len(detected)} detected PRNs, need {minimum_acquisitions}")
    if require_signal_results and not (locked_tracking and valid_common and complete_subframes):
        raise ValueError("missing locked tracking, valid common observation or complete navigation subframe")
    return {"records": size // 32, "types": dict(counts), "detected_prns": sorted(detected),
            "locked_tracking": locked_tracking, "valid_common": valid_common,
            "independently_decoded_subframes": complete_subframes}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--release", type=Path, default=ROOT / "student_release")
    parser.add_argument("--expected-samples", type=int, required=True)
    parser.add_argument("--minimum-acquisitions", type=int, default=0)
    parser.add_argument("--require-signal-results", action="store_true")
    args = parser.parse_args()
    if args.expected_samples <= 0 or args.minimum_acquisitions < 0:
        parser.error("invalid expected samples or acquisition minimum")
    try:
        result = validate(args.input.resolve(), args.release.resolve(), args.expected_samples,
                          args.minimum_acquisitions, args.require_signal_results)
    except (OSError, ImportError, ValueError) as error:
        raise SystemExit(f"FAIL: {error}")
    print("PASS independent teacher record/BCH validation:", result)


if __name__ == "__main__":
    main()
