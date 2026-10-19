"""Verify acquisition with the teacher's simplified signed BDI source.

The supplied source is read only and snapshotted into an ASCII build directory.
This is a single-PRN, noiseless acquisition experiment, not the full D1/IF2 test.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
sys.path.insert(0, str(ROOT))
import rtl_tools
from run_rtl_unit import ModelSim, rtl_sources
from _common import env_banner
from sw.b1i_ref.prn_b1i import prn_code, NH20

DEFAULT_RELEASE = ROOT / '简化BDI信号模拟源及捕获成功判断标准'
TOPS = ['tb_bdi_teacher_capture', 'tb_bdi_buffered_acquisition']


def teacher_code(release: Path) -> list[int]:
    text = (release / 'bdi_prn_code_pkg.sv').read_text(encoding='utf-8-sig')
    match = re.search(r"MEO6_CODE\s*=\s*2046'b([01_\s]+);", text)
    if not match:
        raise ValueError('Missing 2046-chip teacher MEO6 table')
    bits = [int(b) for b in match.group(1) if b in '01']
    if len(bits) != 2046 or bits != prn_code(6):
        raise ValueError('Teacher MEO6 table differs from independently generated ICD PRN6')
    return bits


def expected_windows(code: list[int]) -> list[dict]:
    """Independent per-chip cyclic correlation; 4 nonzero samples/chip × 7.

    All 13 windows are within the first 20 ms navigation bit (value 1).
    The one-quarter-cycle local carrier rotation puts the result in Q.
    """
    rows = []
    for window in range(1, 14):
        phase = min(window - 1, 10)
        dot = sum((1 - 2 * code[(10 + k) % 2046]) *
                  (1 - 2 * code[(phase + k) % 2046]) for k in range(2046))
        q = (-1 if NH20[window - 1] == 0 else 1) * 28 * dot
        rows.append(dict(window=window, phase=phase, i=0, q=q, magnitude=abs(q),
                         capture=int(window >= 11), accepted_samples=window * 16368))
    return rows


def validate_capture(path: Path, code: list[int]) -> dict:
    with path.open(encoding='utf-8', newline='') as stream:
        rows = [{key: int(value) for key, value in row.items()} for row in csv.DictReader(stream)]
    expected = expected_windows(code)
    if rows != expected:
        mismatch = next((i + 1 for i, (a, b) in enumerate(zip(rows, expected)) if a != b), None)
        raise ValueError(f'Independent BDI correlation/window validation failed: rows={len(rows)}, first mismatch={mismatch}')
    return {'windows': 13, 'first_capture_window': 11, 'capture_phase': 10,
            'peak': 57288, 'threshold': 8192,
            'maximum_wrong_phase_magnitude': max(row['magnitude'] for row in rows[:10]),
            'confirmation_windows': 2, 'aligned_code_samples_compared': 49104,
            'accepted_samples': 13 * 16368, 'rows': rows}


def run_logged(command: list[str], path: Path, timeout: int, cwd: Path = ROOT) -> str:
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                            encoding='utf-8', errors='replace', timeout=timeout)
    log = result.stdout + result.stderr
    path.write_text(log, encoding='utf-8')
    if result.returncode or 'TEST PASSED' not in log or re.search(r'TEST FAILED|\*\* (Fatal|Error)', log):
        raise RuntimeError(f'Simulation failed; inspect {path}')
    return log


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', type=Path, default=DEFAULT_RELEASE)
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'reports/sim/bdi_teacher')
    parser.add_argument('--sim', choices=('modelsim', 'vivado', 'vcs', 'iverilog'), default='modelsim')
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--waves', action='store_true', help='Save a VCD for the continuous source case')
    args = parser.parse_args()
    release = args.release.resolve(); output = args.output_dir.resolve()
    if args.timeout < 1 or output.is_relative_to(release):
        parser.error('timeout must be positive and output must be outside the read-only source package')
    output.mkdir(parents=True, exist_ok=True)
    manifest_path = output / 'bdi_results.json'
    manifest = {'status': 'pending', 'passed': False, 'banner': env_banner(), 'simulator': args.sim,
                'release': str(release), 'scope': 'single-PRN noiseless acquisition; no full D1/BCH validation'}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    try:
        code = teacher_code(release)
        build = ROOT / 'reports/build/bdi_teacher'; build.mkdir(parents=True, exist_ok=True)
        source_paths = []
        hashes = {}
        for name in ('bdi_prn_code_pkg.sv', 'bdi_signal_source.sv'):
            source = release / name
            hashes[name] = hashlib.sha256(source.read_bytes()).hexdigest()
            target = build / name; shutil.copy2(source, target); source_paths.append(str(target))
        manifest['source_sha256'] = hashes
        manifest['teacher_prn_matches_independent_generator'] = True
        manifest['source_first_twenty_chips'] = ''.join(map(str, code[10:30]))
        tbs = [ROOT / 'tb/integration' / (top + '.sv') for top in TOPS]
        sim = None; commands = {}
        if args.sim == 'modelsim':
            tool_paths = rtl_tools.modelsim()
            if not tool_paths: raise RuntimeError('ModelSim/Questa not found')
            sim = ModelSim(tool_paths); sim.lib = 'reports/sim/bdi_msim/work'
            # Package must precede both the source and the testbench imports.
            if not sim.compile(source_paths + [str(p) for p in tbs]):
                (output / 'compile.log').write_text(sim.compile_log, encoding='utf-8')
                raise RuntimeError('BDI compilation failed')
            (output / 'compile.log').write_text(sim.compile_log, encoding='utf-8')
        else:
            # Other backends use the same source snapshot and benches; this host's
            # recorded results name the backend actually run, not every option.
            sources = source_paths + [str(ROOT / p) for p in rtl_sources()] + [str(p) for p in tbs]
            inc = [str(ROOT / 'rtl/include'), str(ROOT / 'rtl/common')]
            for top in TOPS:
                cwd = build / (args.sim + '_' + top); cwd.mkdir(exist_ok=True)
                if args.sim == 'vcs':
                    compiler = rtl_tools.vcs()
                    if not compiler: raise RuntimeError('VCS not found')
                    binary = cwd / 'simv'
                    cmd = [compiler, '-full64', '-sverilog', '-timescale=1ns/1ps', *['+incdir+'+p for p in inc], *sources, '-top', top, '-o', str(binary)]
                    commands[top] = ([str(binary)], cwd)
                elif args.sim == 'iverilog':
                    compiler, vvp = rtl_tools.iverilog(), rtl_tools.vvp()
                    if not compiler or not vvp: raise RuntimeError('Icarus not found')
                    binary = cwd / 'sim.vvp'
                    cmd = [compiler, '-g2012', '-s', top, *sum((['-I', p] for p in inc), []), *sources, '-o', str(binary)]
                    commands[top] = ([vvp, str(binary)], cwd)
                else:
                    paths = rtl_tools.vivado()
                    if not paths: raise RuntimeError('Vivado simulator not found')
                    xvlog, xelab, xsim = paths
                    cmd = [xvlog, '-sv', *sum((['--include', p] for p in inc), []), *sources]
                    commands[top] = ([xsim, top + '_sim', '-runall'], cwd)
                compiled = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=args.timeout)
                log = compiled.stdout + compiled.stderr
                if compiled.returncode: raise RuntimeError(f'{args.sim} compile failed: {log[-3000:]}')
                if args.sim == 'vivado':
                    elaborated = subprocess.run([xelab, top, '-s', top + '_sim'], cwd=cwd, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=args.timeout)
                    log += elaborated.stdout + elaborated.stderr
                    if elaborated.returncode: raise RuntimeError(f'Vivado elaboration failed: {log[-3000:]}')
                (output / ('compile_' + top + '.log')).write_text(log, encoding='utf-8')
        results = {}
        for name, top, gap in [('continuous', TOPS[0], 0), ('gapped', TOPS[0], 17), ('parallel', TOPS[1], 0)]:
            plus = []
            if top == TOPS[0]:
                plus = ['+OUTPUT=' + (output / (name + '.csv')).as_posix(),
                        '+TRACE=' + (output / (name + '_trace.csv')).as_posix(), f'+GAP_PERIOD={gap}']
                if args.waves and name == 'continuous':
                    plus += ['+WAVE=' + (output / 'bdi_capture.vcd').as_posix()]
            if args.sim == 'modelsim':
                command = [sim.vsim, '-c', '-lib', sim.lib, top, *plus, '-do', 'onfinish exit; run -all; quit -f']; cwd = ROOT
            else:
                command, cwd = commands[top]; command = list(command)
                if args.sim == 'vivado':
                    for value in plus: command += ['-testplusarg', value[1:]]
                else: command += plus
            log = run_logged(command, output / (name + '.log'), args.timeout, cwd)
            if top == TOPS[0]:
                if '49104 aligned code samples' not in log: raise ValueError('Missing complete code-period evidence')
                results[name] = validate_capture(output / (name + '.csv'), code)
            else:
                match = re.search(r'BDI PARALLEL found=(\d+) h=(\d+) dop=(-?\d+) peak=(\d+) mean=(\d+) samples=(\d+)', log)
                if not match: raise ValueError('Missing parallel acquisition evidence')
                results[name] = dict(zip(('found', 'half_chip_phase', 'doppler_word', 'peak', 'mean', 'samples'), map(int, match.groups())))
            print(f'PASS {name}: {results[name].get("capture_phase",results[name].get("half_chip_phase"))}', flush=True)
        manifest.update(status='passed', passed=True, results=results)
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        manifest.update(status='failed', passed=False, error=str(error))
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
        raise SystemExit(str(error))
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Validated BDI acquisition evidence:', manifest_path)


if __name__ == '__main__':
    main()
