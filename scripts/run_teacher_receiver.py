"""Run the RTL receiver against the supplied teacher player and validate its BIN.

Default: entire input. --max-bytes 4092 runs a 1 ms interface smoke test;
this does not establish acquisition/tracking/navigation on the 100 s scenario.
The reference package is read only. No software-generated observations are used.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rtl_tools
from run_rtl_unit import ModelSim
from validate_teacher_records import validate
from teacher_release import MODES, resolve_release, stream_config

ROOT = Path(__file__).resolve().parents[1]


def positive_int(value: str) -> int:
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", type=Path, help="Teacher package or its parent; newest local package by default")
    parser.add_argument("--input", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "reports/sim/teacher_records.bin")
    parser.add_argument("--max-bytes", type=positive_int)
    parser.add_argument("--timeout", type=positive_int, default=14400)
    parser.add_argument("--stall-period", type=int, default=0)
    parser.add_argument("--stream-mode", choices=("auto", *MODES), default="auto")
    parser.add_argument("--tag-stride", type=positive_int)
    parser.add_argument("--check-stream-only", action="store_true",
                        help="Independently compare unpacked samples with chronological IF2 file pairs")
    parser.add_argument("--require-signal-results", action="store_true",
                        help="Require 4 acquisitions plus tracking, navigation and common observations")
    args = parser.parse_args()
    try:
        release = resolve_release(args.release)
        stream = stream_config(release, args.stream_mode, args.tag_stride)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    if args.check_stream_only and args.require_signal_results:
        parser.error("--check-stream-only cannot require receiver signal results")
    input_path = (args.input or release / "input/scenario.if2").resolve()
    player = release / "sim/if2_file_player.sv"
    checker = release / "tools/check_records.py"
    if not input_path.is_file() or not player.is_file() or not checker.is_file():
        parser.error("teacher input, file player and checker must exist under --release")
    size = input_path.stat().st_size
    nbytes = args.max_bytes if args.max_bytes is not None else size
    if nbytes > size or nbytes % 4 or not nbytes:
        parser.error("processed byte count must be positive, divisible by 4 and within the input")
    if args.stall_period < 0:
        parser.error("--stall-period must be nonnegative")
    tool_paths = rtl_tools.modelsim()
    if not tool_paths:
        parser.error("ModelSim/Questa is required; configure MODELSIM_HOME or PATH")
    output = args.output.resolve()
    if output == input_path or output.suffix.lower() != ".bin":
        parser.error("--output must be a .bin path distinct from the input")
    if args.require_signal_results and not (release / "tools/self_check.py").is_file():
        parser.error("teacher self_check.py is required for signal-result validation")
    os.chdir(ROOT)
    output.parent.mkdir(parents=True, exist_ok=True)
    stream_manifest = output.with_suffix(".stream.json")
    # Do not leave a previous successful check looking current after a failed rerun.
    stream_manifest.write_text(json.dumps({"release": str(release), **stream,
                                          "passed": False, "status": "pending"}, indent=2), encoding="utf-8")
    partial = output.with_name(output.stem + ".partial" + output.suffix)
    sim = ModelSim(tool_paths)
    if not sim.compile([str(player), "tb/integration/tb_teacher_receiver.sv",
                        "tb/integration/tb_teacher_player_order.sv"]):
        print(sim.compile_log)
        raise SystemExit("RTL compile failed")
    print(f"Teacher package: {release}; stream {stream['mode']} / tag stride {stream['tag_stride']}", flush=True)
    generics = [f"-gSTREAM_MODE={stream['rtl_mode']}", f"-gTAG_STRIDE={stream['tag_stride']}"]
    # Verify the real player-to-frontend mapping before starting a long run.
    # With --check-stream-only, check the entire requested input rather than a prefix.
    check_bytes = nbytes if args.check_stream_only else min(nbytes, 65540)
    order_cmd = [sim.vsim, "-c", "-lib", sim.lib, *generics, "tb_teacher_player_order",
                 "+INPUT=" + input_path.as_posix(), f"+MAX_BYTES={check_bytes}",
                 f"+EXPECTED_SAMPLES={check_bytes * 4}", "-do", "onfinish exit; run -all; quit -f"]
    try:
        order = subprocess.run(order_cmd, cwd=ROOT, capture_output=True, text=True,
                               encoding="utf-8", errors="replace", timeout=args.timeout)
    except subprocess.TimeoutExpired:
        raise SystemExit("Teacher stream ordering check timed out")
    order_log = order.stdout + order.stderr
    output.with_suffix(".stream.log").write_text(order_log, encoding="utf-8")
    if order.returncode or "TEST PASSED" not in order_log or "TEST FAILED" in order_log or "** Fatal" in order_log or "** Error" in order_log:
        stream_manifest.write_text(json.dumps({"release": str(release), **stream,
                                              "passed": False, "status": "failed"}, indent=2), encoding="utf-8")
        print(order_log)
        raise SystemExit("Teacher stream ordering check failed; receiver run not started")
    for line in order_log.splitlines():
        if "TEST PASSED" in line:
            print(line)
    stream_check = {"release": str(release), "input": str(input_path), **stream,
                    "compared_samples": check_bytes * 4, "passed": True, "status": "passed",
                    "reference": "chronological MSB-first file pairs, independent of stream bus layout"}
    stream_manifest.write_text(json.dumps(stream_check, indent=2), encoding="utf-8")
    if args.check_stream_only:
        return
    # Always supply MAX_BYTES: the teacher player's last-word detection fails
    # at exact 64 KiB multiples when it discovers EOF on the following read.
    cmd = [sim.vsim, "-c", "-lib", sim.lib, *generics, "tb_teacher_receiver",
           "+INPUT=" + input_path.as_posix(), "+OUTPUT=" + partial.as_posix(),
           f"+MAX_BYTES={nbytes}", f"+EXPECTED_SAMPLES={nbytes * 4}",
           f"+STALL_PERIOD={args.stall_period}", "-do", "onfinish exit; run -all; quit -f"]
    print(f"RTL input: {nbytes} bytes / {nbytes * 4} actual samples", flush=True)
    try:
        result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=args.timeout)
    except subprocess.TimeoutExpired:
        raise SystemExit("RTL simulation timed out; any partial BIN is not a completed submission")
    log = result.stdout + result.stderr
    output.with_suffix(".log").write_text(log, encoding="utf-8")
    if result.returncode or "TEST PASSED" not in log or "TEST FAILED" in log or "** Fatal" in log or "** Error" in log:
        print(log)
        raise SystemExit("RTL simulation failed; BIN is not valid")
    for line in log.splitlines():
        if "TEST PASSED" in line:
            print(line)
    try:
        validation = validate(partial, release, nbytes * 4,
                              4 if args.require_signal_results else 0, args.require_signal_results)
    except (ValueError, ImportError, OSError) as error:
        raise SystemExit(f"RTL BIN validation failed: {error}; capture remains {partial}")
    print("PASS streaming teacher decoder/BCH checks:", validation, flush=True)
    cmd = [sys.executable, str(checker), str(partial), "--expected-samples", str(nbytes * 4),
           "--minimum-acquisitions", "4" if args.require_signal_results else "0"]
    if args.require_signal_results:
        cmd += ["--require-tracking", "--require-navigation", "--require-common-observation"]
    subprocess.run(cmd, cwd=ROOT, check=True)
    if args.require_signal_results:
        subprocess.run([sys.executable, str(release / "tools/self_check.py"), str(partial),
                        "--expected-samples", str(nbytes * 4), "--minimum-acquisitions", "4",
                        "--require-tracking", "--require-navigation", "--require-common-observation"],
                       cwd=ROOT, check=True)
    partial.replace(output)
    manifest = {
        "origin": "RTL student_receiver_core with original teacher file player",
        "release": str(release), "stream": stream, "stream_check": stream_check,
        "input": str(input_path), "input_bytes": nbytes, "accepted_samples": nbytes * 4,
        "full_input": nbytes == size, "signal_results_required": args.require_signal_results,
        "output": str(output), "record_count": output.stat().st_size // 32,
        "validation": validation,
    }
    output.with_suffix(".json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print("Validated RTL BIN:", output)
    if not args.require_signal_results:
        print("Interface validation only; signal acquisition/tracking/navigation were not required.")


if __name__ == "__main__":
    main()
