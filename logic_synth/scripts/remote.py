"""Isolated immutable core DC jobs using the existing SSH transport and identity."""
from pathlib import Path
import argparse
import hashlib
import io
import json
import re
import shlex
import socket
import subprocess
import sys
import tarfile
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / 'reports/remote'

def token(value):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', value) or value in ('.','..'):
        raise ValueError(f'Invalid name: {value}')
    return value

def options():
    return ['-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',
            '-o','ConnectTimeout=12','-o','ConnectionAttempts=1',
            '-o','ServerAliveInterval=20','-o','ServerAliveCountMax=3',
            '-o','HostKeyAlgorithms=+ssh-rsa','-o','PubkeyAcceptedAlgorithms=+ssh-rsa']

def payload(path):
    return path.read_bytes().replace(b'\r\n', b'\n')

def command(argv, timeout=60):
    r=subprocess.run(argv,cwd=ROOT,capture_output=True,encoding='utf-8',errors='replace',timeout=timeout)
    if r.returncode: raise RuntimeError(f'Exit {r.returncode}: {r.stderr.strip()} {r.stdout.strip()}')
    return r

def ssh(host, script):
    return command(['ssh',*options(),host,script]).stdout

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=['pack','submit','status','fetch','audit'])
    p.add_argument('--job')
    p.add_argument('--host', default='vm-ic')
    p.add_argument('--top', choices=['bds_channel','bds_bb_6ch_core'], default='bds_channel')
    args = p.parse_args()
    if args.action == 'audit':
        script = (ROOT / 'logic_synth/scripts/audit_libraries.sh').read_text(encoding='utf-8')
        r = subprocess.run(['ssh', *options(), args.host, 'bash -s'],
                           input=script, capture_output=True, encoding='utf-8', timeout=120)
        dest = ROOT / 'logic_synth/logs/library_audit.log'
        dest.write_text(r.stdout+r.stderr, encoding='utf-8')
        print(r.stdout+r.stderr)
        return r.returncode
    if not args.job: p.error('--job is required')
    job = token(args.job)
    local = LOCAL / job
    if args.action == 'pack':
        if local.exists(): raise ValueError('Choose a new job; snapshot already exists')
        paths = {ROOT/'logic_synth/rtl/core.f', ROOT/'rtl/include/b1i_params.svh',
                 ROOT/'rtl/common/carrier_lut_table.svh', ROOT/'logic_synth/.gitignore'}
        for line in (ROOT/'logic_synth/rtl/core.f').read_text().splitlines():
            if line.strip() and not line.startswith(('+','//')):
                paths.add((ROOT/'logic_synth'/line).resolve())
        for dirname in ('scripts','constraints'):
            paths.update(x for x in (ROOT/'logic_synth'/dirname).iterdir() if x.is_file())
        hashes = {f.relative_to(ROOT).as_posix(): hashlib.sha256(payload(f)).hexdigest()
                  for f in sorted(paths)}
        remote = f'/home/7902_13/beidou_runs/{token(socket.gethostname().lower())}/{job}'
        manifest = {'job':job,'host':args.host,'remote':remote,'top':args.top,
                    'created_utc':datetime.now(timezone.utc).isoformat(),
                    'git_head':command(['git','rev-parse','HEAD']).stdout.strip(),
                    'files':hashes,'scope':'exploratory core only; no final PAD acceptance'}
        local.mkdir(parents=True)
        extra = {'job_config.sh':f'CORE_TOP={shlex.quote(args.top)}\n',
                 'SOURCE_SHA256SUMS':''.join(f'{v}  {k}\n' for k,v in hashes.items()),
                 'manifest.json':json.dumps(manifest,indent=2)}
        with tarfile.open(local/'source.tgz','w:gz') as tar:
            for path in sorted(paths):
                data=payload(path)
                info=tarfile.TarInfo(path.relative_to(ROOT).as_posix());info.size=len(data);info.mode=0o644;info.mtime=int(path.stat().st_mtime)
                tar.addfile(info,io.BytesIO(data))
            for name,value in extra.items():
                data=value.encode();info=tarfile.TarInfo(name);info.size=len(data);info.mode=0o644;info.mtime=int(time.time())
                tar.addfile(info,io.BytesIO(data))
        manifest['archive_sha256']=hashlib.sha256((local/'source.tgz').read_bytes()).hexdigest()
        (local/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
        print(f'PACKED {job} files={len(paths)} remote={remote}')
        return 0
    m=json.loads((local/'manifest.json').read_text())
    remote=shlex.quote(m['remote']); wrapper='logic_synth/scripts/job.sh'
    if args.action=='submit':
        remote_command=(f'set -e; test "$(id -un)" = 7902_13; test "$(hostname)" = IC; '
                 f'mkdir -p {remote}; cd {remote}; exec 8>upload.lock; flock -x 8; '
                 f'if test -e job_state/pid; then cat >/dev/null; bash {wrapper} status; exit; fi; '
                 'cat > source.tgz.part; '
                 f'echo "{m["archive_sha256"]}  source.tgz.part" | sha256sum -c -; '
                 'tar xzf source.tgz.part; sha256sum -c SOURCE_SHA256SUMS >/dev/null; '
                 f'mv source.tgz.part source.tgz; bash {wrapper} start')
        r=subprocess.run(['ssh',*options(),m['host'],remote_command],
                         input=(local/'source.tgz').read_bytes(),capture_output=True,timeout=120)
        output=(r.stdout+r.stderr).decode('utf-8','replace')
        (local/'submit.log').write_text(output,encoding='utf-8');print(output)
        return r.returncode
    if args.action=='status':
        print(ssh(m['host'],f'cd {remote} && bash {wrapper} status'))
        return 0
    script=(f'set -eo pipefail; cd {remote}; '
            'tar czf - job_state manifest.json logic_synth/reports logic_synth/logs logic_synth/output')
    r=subprocess.run(['ssh',*options(),m['host'],script],capture_output=True,timeout=180)
    if r.returncode: raise RuntimeError(r.stderr.decode('utf-8','replace'))
    dest=local/'results';dest.mkdir(exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(r.stdout)) as tar:
        tar.extractall(dest,filter='data')
    print(f'FETCHED {dest}')
    return 0

if __name__=='__main__':
    try: sys.exit(main())
    except (OSError,ValueError,RuntimeError,subprocess.TimeoutExpired) as e:
        print(f'ERROR: {e}',file=sys.stderr);sys.exit(1)
