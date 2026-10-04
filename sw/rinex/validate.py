"""独立回读 RINEX 3.05 OBS/NAV（不依赖写文件时的内存对象）。"""

from __future__ import annotations

from pathlib import Path

C2I_MIN_M = 1.0e6
C2I_MAX_M = 6.0e7


def validate_obs(path) -> list:
    """返回错误字符串列表；空列表即通过。"""
    err = []
    p = Path(path)
    if not p.is_file():
        return [f"OBS 不存在: {path}"]
    lines = p.read_text(encoding="ascii").splitlines()
    if not lines:
        return ["OBS 空文件"]
    if "3.05" not in lines[0] or "OBSERVATION" not in lines[0]:
        err.append("OBS 首行不是 RINEX 3.05 OBSERVATION")
    if "MIXED" in lines[0]:
        err.append("OBS 系统标识仍是 MIXED，应为 C: BDS")
    if "C: BDS" not in lines[0] and "C:BDS" not in lines[0]:
        err.append("OBS 首行缺少 C: BDS")
    if not any("TIME SYSTEM ID" in ln and "BDT" in ln for ln in lines):
        err.append("OBS 缺少 TIME SYSTEM ID BDT")
    n_epoch = sum(1 for ln in lines if ln.startswith(">"))
    n_sat = 0
    for ln in lines:
        if ln.startswith("C") and len(ln) > 3 and ln[1:3].isdigit():
            n_sat += 1
            parts = ln.split()
            if len(parts) >= 2:
                try:
                    pr = float(parts[1])
                except ValueError:
                    err.append(f"OBS 伪距无法解析: {ln}")
                    continue
                if not (C2I_MIN_M <= pr <= C2I_MAX_M):
                    err.append(f"OBS 伪距超范围 {pr}: {ln}")
    if n_epoch < 1:
        err.append("OBS 没有历元行")
    if n_sat < 1:
        err.append("OBS 没有卫星观测")
    return err


def validate_nav(path) -> list:
    err = []
    p = Path(path)
    if not p.is_file():
        return [f"NAV 不存在: {path}"]
    lines = p.read_text(encoding="ascii").splitlines()
    if not lines:
        return ["NAV 空文件"]
    if "3.05" not in lines[0] or "NAV" not in lines[0]:
        err.append("NAV 首行不是 RINEX 3.05 NAV")
    if "MIXED" in lines[0]:
        err.append("NAV 系统标识仍是 MIXED")
    return err
