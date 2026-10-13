"""复核历史软件参考的 10 ms 全 PRN 捕获；不执行 RTL 或读取信号真值。"""
from pathlib import Path
import sys,json,argparse
import numpy as np
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT))
from sw.b1i_ref.prn_b1i import prn_code
sys.path.insert(0,str(ROOT/'scripts'))
from teacher_release import resolve_release
FS = 16368000
IF = 4092000
RF = 1561098000
RATE = 2046000
N = 16368
LEVELS = np.array([-3, -1, 1, 3], dtype=np.int8)
BYTE_LUT = LEVELS[np.arange(256)[:, None] >> np.array([6, 4, 2, 0]) & 3]
COS = np.cos(np.arange(16384) * (2 * np.pi / 16384))
SIN = np.sin(np.arange(16384) * (2 * np.pi / 16384))

def unpack(packed):
    return BYTE_LUT[np.asarray(packed, dtype=np.uint8)].reshape(-1)

def acquire(samples, prns=range(1, 64), span=10000, step=500, ms=10, ratio_min=2.5):
    """Return all search candidates; lag is a received-code delay in samples."""
    s = np.asarray(samples[:ms * N], dtype=np.float64).reshape(ms, N)
    if s.shape[0] != ms:
        raise ValueError('not enough acquisition samples')
    prns = list(prns)
    lo_if = np.tile(np.array([1, -1j, -1, 1j]), N // 4)
    base = (s * lo_if).reshape(ms, N // 4, 4).sum(axis=2)
    replicas = np.asarray([np.repeat(2 * np.array(prn_code(p)) - 1, 2) for p in prns])
    spectra = np.conj(np.fft.fft(replicas, axis=1))
    t = np.arange(N // 4) / (FS / 4)
    best_power = np.zeros(len(prns))
    best_bins = np.zeros(len(prns))
    best_lags = np.zeros(len(prns), dtype=int)
    best_maps = np.zeros_like(replicas, dtype=float)
    for fd in np.arange(-span, span + step / 2, step):
        wiped = base * np.exp(-2j * np.pi * fd * t)
        signal_fft = np.fft.fft(wiped, axis=1)
        power = np.zeros_like(replicas, dtype=float)
        for row in signal_fft:
            corr = np.fft.ifft(spectra * row, axis=1)
            power += np.abs(corr) ** 2
        lags = np.argmax(power, axis=1)
        peaks = power[np.arange(len(prns)), lags]
        better = peaks > best_power
        best_power[better], best_lags[better] = (peaks[better], lags[better])
        best_bins[better], best_maps[better] = (fd, power[better])
    hits = []
    for k, prn in enumerate(prns):
        row = best_maps[k].copy()
        lag = best_lags[k]
        row[(lag + np.arange(-2, 3)) % len(row)] = 0
        ratio = float(best_power[k] / max(row.max(), 1e-30))
        code = 2 * np.array(prn_code(prn)) - 1
        fd = float(best_bins[k])
        full_lo = np.exp(-2j * np.pi * (IF + fd) * np.arange(N) / FS)
        values = []
        for shift in range(-4, 5):
            lag_full = (int(lag) * 4 + shift) % N
            idx = (np.arange(N) - lag_full) % N // 8
            z = np.sum(s * full_lo * code[idx], axis=1)
            values.append((float(np.sum(np.abs(z) ** 2)), lag_full))
        _, lag_full = max(values)
        hits.append(dict(prn=prn, doppler_hz=fd, lag_samples=lag_full, peak_power=float(best_power[k]), peak_ratio=ratio, detected=ratio >= ratio_min))
    return (sorted(hits, key=lambda x: -x['peak_ratio']), best_maps)
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release',type=Path)
    args=parser.parse_args()
    release=resolve_release(args.release)
    input_path=release/'input/scenario.if2'
    samples=unpack(np.fromfile(input_path,dtype=np.uint8,count=40920))
    hits,maps=acquire(samples)
    old=np.load(ROOT/'reports/public_run/acquisition_maps.npz')['power']
    same=bool(np.array_equal(maps,old))
    result={'map_exactly_matches_saved_reference':same,'hits':hits,'input_samples':len(samples),'input':str(input_path),'revision_date':'2026-10-13'}
    print(json.dumps(result,ensure_ascii=False,indent=2))
    if not same:raise SystemExit('捕获相关图与保存结果不一致')
