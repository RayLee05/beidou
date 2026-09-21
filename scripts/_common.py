"""脚本公共工具：项目根定位、输出与证据记录。"""

from __future__ import annotations

import hashlib
import json
import os
import platform
import subprocess
import sys
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SW_DIR = os.path.join(ROOT, "sw")
REPORTS_DIR = os.path.join(ROOT, "reports")
FIGURES_DIR = os.path.join(REPORTS_DIR, "figures")
LOGS_DIR = os.path.join(REPORTS_DIR, "logs")


def bootstrap() -> None:
    """把 sw/ 加入 import 路径，使脚本可直接 `import b1i_ref`。"""
    if SW_DIR not in sys.path:
        sys.path.insert(0, SW_DIR)
    for d in (REPORTS_DIR, FIGURES_DIR, LOGS_DIR):
        os.makedirs(d, exist_ok=True)


def git_revision() -> str:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=ROOT, capture_output=True, text=True, timeout=10,
        )
        return out.stdout.strip() or "no-commit"
    except Exception:
        return "no-git"


def git_dirty() -> bool:
    try:
        out = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=ROOT, capture_output=True, text=True, timeout=10,
        )
        return bool(out.stdout.strip())
    except Exception:
        return True


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def env_banner() -> dict:
    return {
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "python": sys.version.split()[0],
        "platform": platform.platform(),
        "machine": platform.machine(),
        "git_revision": git_revision(),
        "git_dirty": git_dirty(),
    }


def write_json(path: str, obj) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2, sort_keys=False)
        f.write("\n")


def write_text(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


class Check:
    """极简断言收集器（本项目不依赖 pytest，见 docs/PLAN.md 工具约定）。"""

    def __init__(self, name: str):
        self.name = name
        self.passed = 0
        self.failures: list[str] = []

    def eq(self, label: str, got, want) -> None:
        if got == want:
            self.passed += 1
        else:
            self.failures.append(f"{label}: got {got!r}, want {want!r}")

    def true(self, label: str, cond: bool, detail: str = "") -> None:
        if cond:
            self.passed += 1
        else:
            self.failures.append(f"{label}" + (f": {detail}" if detail else ""))

    def report(self) -> int:
        status = "PASS" if not self.failures else "FAIL"
        print(f"[{status}] {self.name}: {self.passed} checks passed, {len(self.failures)} failed")
        for f in self.failures:
            print(f"    - {f}")
        return 0 if not self.failures else 1
