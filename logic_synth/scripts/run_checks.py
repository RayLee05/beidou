"""Run independent synthesis-project RTL checks with the existing ModelSim tools."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / 'scripts'))
import rtl_tools

def run(cmd, timeout=180):
    r = subprocess.run([str(x) for x in cmd], cwd=ROOT, capture_output=True,
                       encoding='utf-8', errors='replace', timeout=timeout)
    log = r.stdout + r.stderr
    return r.returncode == 0 and not re.search(r'\*\* (Error|Fatal)', log), log

def main():
    tools = rtl_tools.modelsim()
    if not tools:
        raise SystemExit('ModelSim not found; set MODELSIM_HOME')
    logs = ROOT / 'logs'; logs.mkdir(exist_ok=True)
    (ROOT / 'build').mkdir(exist_ok=True)
    lib = 'build/work'
    if not (ROOT / lib).exists():
        ok, log = run([tools[0], lib])
        if not ok: raise SystemExit(log)
    tests = sorted((ROOT / 'sim').glob('tb_*.sv'))
    if len(sys.argv) > 1:
        tests = [t for t in tests if any(x in t.stem for x in sys.argv[1:])]
    if not tests: raise SystemExit('No tests selected')
    ok, log = run([tools[1], '-sv', '-work', lib, '-timescale', '1ns/1ps',
                   '-f', 'rtl/core.f', *tests])
    (logs / 'compile.log').write_text(log, encoding='utf-8')
    if not ok: raise SystemExit(log)
    results = []
    for test in tests:
        start = time.monotonic()
        ok, log = run([tools[2], '-c', '-lib', lib, test.stem,
                       '-do', 'onfinish exit; run -all; quit -f'], timeout=600)
        passed = bool(ok and 'TEST PASSED' in log and 'TEST FAILED' not in log)
        (logs / (test.stem + '.log')).write_text(log, encoding='utf-8')
        results.append({'name': test.stem, 'passed': passed,
                        'seconds': round(time.monotonic()-start, 2)})
        print(test.stem, 'PASS' if passed else 'FAIL', flush=True)
        if not passed: print(log)
    hashes = {p.relative_to(ROOT.parent).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted((ROOT / 'rtl').glob('*')) if p.is_file()}
    dependency_files = [ROOT.parent/'rtl/include/b1i_params.svh',
                        ROOT.parent/'rtl/common/carrier_lut_table.svh']
    dependency_files += [(ROOT/line).resolve() for line in (ROOT/'rtl/core.f').read_text().splitlines()
                         if line.strip() and not line.startswith(('+','//'))]
    hashes.update({p.relative_to(ROOT.parent).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in dependency_files})
    report = {'tool': str(tools[2]), 'results': results, 'rtl_sha256': hashes}
    (ROOT / 'reports/rtl_checks.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    for result in results:
        per_test = {**report, 'results': [result], 'tb_sha256': hashlib.sha256(
            (ROOT/'sim'/(result['name']+'.sv')).read_bytes()).hexdigest()}
        (ROOT / ('reports/'+result['name']+'.json')).write_text(json.dumps(per_test, indent=2), encoding='utf-8')
    return 0 if all(r['passed'] for r in results) else 1

if __name__ == '__main__':
    sys.exit(main())
