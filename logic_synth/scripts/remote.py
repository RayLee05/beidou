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
    p.add_argument('--top', choices=['bds_channel','channel_hold_repair','bds_bb_6ch_core','bds_bb_6ch_pad_top','pad_probe','pad_delay_probe','hier_power_probe','pad_probe_repair','pad_probe_pt','pad_probe_gls','pad_connectivity','pad_six_signal'], default='bds_channel')
    p.add_argument('--after-job', help='Wait for an already packaged job to succeed before starting EDA')
    p.add_argument('--base-job', help='Mapped-channel snapshot used for bottom-up full-top integration')
    p.add_argument('--base-rtl', action='store_true', help='Archive the exact channel RTL used by base-job')
    p.add_argument('--repair-channel', action='store_true', help='Repair the channel before full-top integration')
    p.add_argument('--ss-checkpoint-job', help='Reuse the SS-rebound channel saved by a prior full-top job')
    p.add_argument('--probe-job', help='Completed powered PAD probe supplying the netlist and SDF')
    p.add_argument('--max-cores', type=int, default=4)
    p.add_argument('--compile-mode', choices=['basic','ultra'], default='basic')
    p.add_argument('--memory-limit-mb', type=int, default=0, help='Optional per-process virtual memory ceiling')
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
        paths.update(x for x in (ROOT/'logic_synth/rtl').glob('*.sv'))
        paths.update(x for x in (ROOT/'logic_synth/sim').iterdir() if x.is_file())
        overrides={}
        if args.base_rtl:
            if not args.base_job: raise ValueError('base-rtl requires base-job')
            origin=LOCAL/token(args.base_job)
            origin_manifest=json.loads((origin/'manifest.json').read_text())
            archive=origin/'source.tgz'
            if hashlib.sha256(archive.read_bytes()).hexdigest()!=origin_manifest['archive_sha256']:
                raise ValueError('Base archive checksum mismatch')
            with tarfile.open(archive) as base_tar:
                for name,digest in origin_manifest['files'].items():
                    if name.startswith('rtl/') or name in ('logic_synth/rtl/bds_acquisition.sv','logic_synth/rtl/bds_channel.sv'):
                        data=base_tar.extractfile(name).read()
                        if hashlib.sha256(data).hexdigest()!=digest: raise ValueError(f'Base RTL checksum mismatch: {name}')
                        overrides[name]=data
        def pack_bytes(path):
            name=path.relative_to(ROOT).as_posix()
            return overrides[name] if name in overrides else payload(path)
        hashes = {f.relative_to(ROOT).as_posix(): hashlib.sha256(pack_bytes(f)).hexdigest()
                  for f in sorted(paths)}
        remote = f'/home/7902_13/beidou_runs/{token(socket.gethostname().lower())}/{job}'
        manifest = {'job':job,'host':args.host,'remote':remote,'top':args.top,
                    'created_utc':datetime.now(timezone.utc).isoformat(),
                    'git_head':command(['git','rev-parse','HEAD']).stdout.strip(),
                    'files':hashes,'scope':'exploratory core only; no final PAD acceptance'}
        if args.base_rtl: manifest['rtl_origin']=args.base_job
        if args.max_cores<1 or args.max_cores>32: raise ValueError('max-cores must be 1..32')
        if args.memory_limit_mb and args.memory_limit_mb<512: raise ValueError('memory-limit-mb must be 0 or >=512')
        config=f'CORE_TOP={shlex.quote(args.top)}\nMAX_CORES={args.max_cores}\nSYNTH_MODE={args.compile_mode}\nMEMORY_LIMIT_MB={args.memory_limit_mb}\nREPAIR_CHANNEL={int(args.repair_channel)}\n'
        manifest['resources']={'max_cores':args.max_cores,'mode':args.compile_mode,'memory_limit_mb':args.memory_limit_mb}
        if args.after_job:
            dep=json.loads((LOCAL/token(args.after_job)/'manifest.json').read_text())
            if dep['host']!=args.host: raise ValueError('Dependency and job must use the same SSH host')
            config+=f'AFTER_DIR={shlex.quote(dep["remote"])}\n'
            manifest['after_job']=args.after_job
        if args.base_job:
            base=json.loads((LOCAL/token(args.base_job)/'manifest.json').read_text())
            if base['host']!=args.host: raise ValueError('Base and job must use the same SSH host')
            for name,digest in hashes.items():
                if name.startswith('rtl/') or name in ('logic_synth/rtl/bds_acquisition.sv','logic_synth/rtl/bds_channel.sv'):
                    if base['files'].get(name)!=digest:
                        raise ValueError(f'Base mapped-channel RTL does not match snapshot: {name}')
            base_ddc=base['remote']+'/logic_synth/output/core_bds_channel/baseline.ddc'
            config+=f'BASE_DDC={shlex.quote(base_ddc)}\n'
            manifest['base_job']=args.base_job
            manifest['base_ddc']=base_ddc
        if args.ss_checkpoint_job:
            checkpoint=json.loads((LOCAL/token(args.ss_checkpoint_job)/'manifest.json').read_text())
            if checkpoint['host']!=args.host or checkpoint.get('base_job')!=args.base_job:
                raise ValueError('SS checkpoint must derive from the selected base job on the same host')
            for name in ('logic_synth/rtl/bds_acquisition.sv','logic_synth/rtl/bds_channel.sv'):
                if checkpoint['files'].get(name)!=hashes.get(name):raise ValueError('SS checkpoint RTL mismatch')
            base_ddc=checkpoint['remote']+'/logic_synth/output/channel_ss.ddc'
            config+=f'BASE_DDC={shlex.quote(base_ddc)}\nBASE_IS_SS=1\n'
            manifest['ss_checkpoint_job']=args.ss_checkpoint_job
            manifest['base_ddc']=base_ddc
        if args.probe_job:
            probe=json.loads((LOCAL/token(args.probe_job)/'manifest.json').read_text())
            if probe['host']!=args.host: raise ValueError('Probe and job must use the same SSH host')
            config+=f'PROBE_DIR={shlex.quote(probe["remote"]+"/logic_synth/output/pad_probe")}\n'
            manifest['probe_job']=args.probe_job
        local.mkdir(parents=True)
        extra = {'job_config.sh':config,
                 'SOURCE_SHA256SUMS':''.join(f'{v}  {k}\n' for k,v in hashes.items()),
                 'manifest.json':json.dumps(manifest,indent=2)}
        with tarfile.open(local/'source.tgz','w:gz') as tar:
            for path in sorted(paths):
                data=pack_bytes(path)
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
            "tar --exclude='*/library.rpt' -czf - job_state manifest.json logic_synth/reports logic_synth/logs logic_synth/output")
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
