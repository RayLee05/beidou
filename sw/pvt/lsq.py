"""B1I 单频码伪距最小二乘定位（4 星起算）。

观测：P_i = |r_i - r| + c · dt
不改正电离层/对流层（与 scenario 信号源约定一致）。
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from b1i_ref.d1_nav import C_LIGHT


@dataclass
class CodePVT:
    xyz: np.ndarray
    dt_s: float
    residuals_m: list
    rms_m: float
    iters: int
    n_sats: int
    ok: bool
    notes: str = ""
    extra: dict = field(default_factory=dict)


def solve_code_pvt(sat_xyz, pr_m, xyz0=None, max_iter: int = 12) -> CodePVT:
    sats = np.asarray(sat_xyz, dtype=float)
    pr = np.asarray(pr_m, dtype=float)
    n = len(pr)
    if n < 4:
        return CodePVT(np.zeros(3), 0.0, [], float("nan"), 0, n, False, "卫星少于 4 颗")
    x = np.zeros(4)
    if xyz0 is not None:
        x[:3] = xyz0
    last = None
    for it in range(max_iter):
        geo = sats - x[:3]
        r = np.linalg.norm(geo, axis=1)
        pred = r + C_LIGHT * x[3]
        dz = pr - pred
        H = np.zeros((n, 4))
        H[:, :3] = -geo / r[:, None]
        H[:, 3] = C_LIGHT
        dx, *_ = np.linalg.lstsq(H, dz, rcond=None)
        x = x + dx
        last = it + 1
        if float(np.linalg.norm(dx[:3])) < 1e-3 and abs(dx[3]) < 1e-12:
            break
    res = (pr - (np.linalg.norm(sats - x[:3], axis=1) + C_LIGHT * x[3])).tolist()
    rms = float(np.sqrt(np.mean(np.square(res))))
    return CodePVT(x[:3].copy(), float(x[3]), res, rms, last or 0, n, True)


def refine_sagnac(ephs, t_tx, pr_m, xyz0=None, max_outer: int = 4) -> CodePVT:
    """用当前接收机位置重算 Sagnac，再 LSQ，避免卫星位置绑死真值坐标。"""
    from b1i_ref import scenario

    x = np.zeros(3) if xyz0 is None else np.asarray(xyz0, dtype=float)
    last = None
    for _ in range(max_outer):
        sats = []
        for eph, tt in zip(ephs, t_tx):
            tau = 0.075
            pos = None
            for _k in range(6):
                pos = scenario.sagnac_rotate(eph.position(tt), tau)
                den = float(np.linalg.norm(pos - x))
                tau = den / C_LIGHT if den > 1.0 else 0.075
            sats.append(pos)
        last = solve_code_pvt(sats, pr_m, xyz0=x)
        if not last.ok:
            return last
        if float(np.linalg.norm(last.xyz - x)) < 0.05:
            break
        x = last.xyz
    return last
