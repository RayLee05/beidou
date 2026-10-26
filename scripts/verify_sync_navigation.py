"""Run NH/D1 regressions and save logs, a real waveform, and independent checks.

Usage: python scripts/verify_sync_navigation.py
Requires ModelSim. Teacher decoding is additionally checked when its local
release is available; the summary records explicitly when it is unavailable.
"""
from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time
from datetime import datetime

from _common import ROOT, env_banner, git_revision
import rtl_tools
from run_rtl_unit import ModelSim, SIM_TIMEOUT_S, _judge, _run, rtl_sources

ROOT_PATH = Path(ROOT)
TESTS = [
    "tb/unit/tb_nh_bit_sync.sv", "tb/unit/tb_nh_clear.sv",
    "tb/unit/tb_nh_continuity.sv", "tb/unit/tb_d1_frame_sync.sv",
    "tb/unit/tb_d1_clear.sv", "tb/unit/tb_d1_robustness.sv",
    "tb/integration/tb_sync_navigation.sv",
]
SIGNALS = ["dump_valid", "dump_partial", "dump_ms", "i_p", "synced", "bit_phase",
           "bit_valid", "bit_val", "bit_ms", "sf_valid", "sf_id", "sf_sow",
           "sf_start_ms", "sf_fixes", "sf_inverted", "frame_synced", "anchor_valid",
           "week", "week_valid", "sf_err"]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def independent_checks(output: Path) -> dict:
    from teacher_release import resolve_release
    try:
        release = resolve_release(root=ROOT_PATH)
    except ValueError:
        return {"available": False, "passed": None, "reason": "local teacher release unavailable"}
    if not (release / "tools/prompt_d1.py").is_file():
        return {"available": False, "passed": None, "reason": "local teacher decoder unavailable"}
    import sys
    sys.path.insert(0, str(release / "tools"))
    from prompt_d1 import decode_word
    from validate_teacher_records import validate

    def decode_frame(raw: str) -> tuple[str, int]:
        bits = [int(b) for b in f"{int(raw, 16):0300b}"]
        information, fixes = [], 0
        for w in range(10):
            data, count = decode_word(bits[w*30:w*30+30], w == 0)
            information.extend(data)
            fixes += count
        return f"{int(''.join(map(str, information)), 2):056x}", fixes

    with (output / "navigation_chain.csv").open(encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    if len(rows) != 5:
        raise ValueError("expected five Prompt-to-D1 subframes")
    for row in rows:
        info, fixes = decode_frame(row["raw"])
        if info != row["information"] or fixes != int(row["fixes"]):
            raise ValueError("teacher decoder disagrees with integrated RTL output")

    # Also check all deliberately inconsistent headers have valid BCH parity,
    # so their rejection genuinely exercises range/continuity checks.
    golden = (ROOT_PATH / "tb/vectors/sync_frames_expected.txt").read_text().splitlines()
    vectors = (ROOT_PATH / "tb/vectors/sync_frames.hex").read_text().splitlines()
    for raw, expected in zip(vectors, golden, strict=True):
        info, fixes = decode_frame(raw)
        if info != expected.split()[2] or fixes != 0:
            raise ValueError("teacher decoder disagrees with robustness vectors")

    n_bits = int((ROOT_PATH / "tb/vectors/nav_expected.txt").read_text().split()[0])
    last = n_bits - 1
    record_check = validate(output / "public_navigation.bin", release,
                            100000 + last*327360 + (last % 7)*10)
    if record_check["independently_decoded_subframes"] != 5:
        raise ValueError("missing independently verified public navigation records")
    return {"available": True, "passed": True, "chain_subframes": len(rows),
            "chain_words": len(rows)*10, "robustness_vectors": len(vectors),
            "public_records": record_check,
            "decoder_sha256": digest(release / "tools/prompt_d1.py")}


def main() -> int:
    tools = rtl_tools.modelsim()
    if not tools:
        raise SystemExit("ModelSim unavailable; set MODELSIM_HOME to vlib/vlog/vsim directory")
    parent = ROOT_PATH / "reports/sim/navigation"
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    output = parent / f"run_{stamp}"
    output.mkdir(parents=True)
    ms = ModelSim(tools)
    ms.lib = (output / "work").relative_to(ROOT_PATH).as_posix()
    if not ms.compile(TESTS):
        (output / "compile.log").write_text(ms.compile_log, encoding="utf-8")
        raise SystemExit(f"compile failed; see {output / 'compile.log'}")
    (output / "compile.log").write_text(ms.compile_log, encoding="utf-8")
    results = []
    for tb in TESTS:
        name = Path(tb).stem
        if name != "tb_sync_navigation":
            result = ms.run(tb)
        else:
            result = {"name": name, "tb": tb, "tool": "modelsim", "compile_ok": True,
                      "compile_log": "", "run_ok": False, "passed": False, "run_log": ""}
            command = "; ".join(f"log /{name}/{s}" for s in SIGNALS)
            start = time.monotonic()
            try:
                run = _run([tools[2], "-c", "-lib", ms.lib, "-voptargs=+acc", name,
                            "-wlf", (output / "navigation.wlf").as_posix(), "-do",
                            "onfinish exit; " + command + "; run -all; quit -f"], SIM_TIMEOUT_S)
                log = (run.stdout or "") + (run.stderr or "")
                _judge(result, log, run.returncode)
                if "** Fatal" in log or "** Error" in log:
                    result["passed"] = result["run_ok"] = False
            except subprocess.TimeoutExpired:
                result["run_log"] = f"simulation timed out after {SIM_TIMEOUT_S}s"
            result["seconds"] = round(time.monotonic() - start, 3)
        (output / f"{name}.log").write_text(result["run_log"], encoding="utf-8")
        results.append(result)
        print(f"{'PASS' if result['passed'] else 'FAIL'} {name}", flush=True)
        if name == "tb_d1_frame_sync" and result["passed"]:
            shutil.copy2(ROOT_PATH / "reports/sim/public_navigation.bin", output)
        if name == "tb_sync_navigation" and result["passed"]:
            shutil.copy2(ROOT_PATH / "reports/sim/navigation_chain.csv", output)

    passed = all(r["passed"] for r in results)
    try:
        independent = independent_checks(output) if passed else {"passed": None, "reason": "RTL failure"}
    except (ValueError, ImportError, OSError) as exc:
        independent = {"available": True, "passed": False, "reason": str(exc)}
    passed = passed and independent.get("passed") is not False
    hashes = {rel: digest(ROOT_PATH / rel) for rel in rtl_sources() + TESTS + [
        "rtl/filelist.f", "tb/filelist.f", "rtl/include/b1i_params.svh",
        "tb/vectors/nav_bits.hex", "tb/vectors/nav_expected.txt",
        "tb/vectors/bs_input.hex", "tb/vectors/bs_expected.txt",
        "tb/vectors/sync_frames.hex", "tb/vectors/sync_frames_expected.txt",
        "scripts/gen_unit_vectors.py", "scripts/verify_sync_navigation.py"]}
    wave_do = output / "wave.do"
    wave_do.write_text("onerror {resume}\nquietly WaveActivateNextPane {} 0\n" +
                       "\n".join(f"add wave -radix decimal /tb_sync_navigation/{s}" for s in SIGNALS) +
                       "\nconfigure wave -namecolwidth 200\nconfigure wave -valuecolwidth 140\nwave zoom full\n",
                       encoding="utf-8")
    (output / "open_wave.cmd").write_text(
        f'@echo off\n"{Path(tools[2]).as_posix()}" -view "{(output / "navigation.wlf").as_posix()}" '
        f'-do "do {{{wave_do.as_posix()}}}"\n', encoding="utf-8")
    summary = {"banner": env_banner(), "base_revision": git_revision(), "passed": passed,
               "simulator": "ModelSim", "total": len(results),
               "passed_tests": sum(r["passed"] for r in results), "results": results,
               "independent": independent, "source_sha256": hashes,
               "scope": "1 ms Prompt I through NH to D1; synthetic deterministic noise; not an RF or full receiver run",
               "time_compression": "61 simulation clocks per nominal 1 ms Prompt; code-time labels are authoritative",
               "waveform": str(output / "navigation.wlf"), "output": str(output)}
    content = json.dumps(summary, ensure_ascii=False, indent=2) + "\n"
    (output / "summary.json").write_text(content, encoding="utf-8")
    (parent / "latest.json").write_text(content, encoding="utf-8")
    print(f"{'PASS' if passed else 'FAIL'}: {summary['passed_tests']}/{len(results)} tests; independent={independent.get('passed')}")
    print(f"Evidence: {output}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
