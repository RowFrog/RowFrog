#!/usr/bin/env python3
"""Checks that this system runs the versions the repository pins ("same versions
everywhere", decision 0055) and prints one line per item:

    same   Python 3.12.16 (.python-version)
    DIFF   Node v22.23.4, pinned 22.23.5 (.nvmrc)

    python3 scripts/check_versions.py [--env DIR] [--extras dev,satellite]
                                      [--node] [--npm] [--summary FILE]

--env      the Python environment to check against backend/uv.lock (its Python
           version and every package, with `uv sync --locked --check`); without
           it the Python checks are skipped.
--extras   the extras that environment is meant to have (default: satellite).
--node     check `node --version` against .nvmrc.
--npm      check node_modules against package-lock.json.
--summary  also append the lines as a Markdown table to FILE (GitHub's
           $GITHUB_STEP_SUMMARY).
Exits 1 if anything differs, 0 if all is the same. Runs on Python 3.9+ with
the standard library only (macOS's own python3 is 3.9); needs uv on PATH (or
$UV) for --env. Used by CI, the Pi's gate and the Mac's update.sh.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

TOP = Path(__file__).resolve().parent.parent


def pinned(name: str) -> str:
    return (TOP / name).read_text().strip()


def check_python(env: Path, extras: list[str]) -> list[tuple[bool, str]]:
    rows = []
    want = pinned(".python-version")
    py = env / "bin" / "python"
    if not py.exists():
        return [(False, f"Python: no environment at {env}")]
    have = subprocess.run([str(py), "-c", "import platform; print(platform.python_version())"],
                          capture_output=True, text=True).stdout.strip()
    rows.append((have == want, f"Python {have}" + ("" if have == want else f", pinned {want}") + " (.python-version)"))
    uv = os.environ.get("UV") or shutil.which("uv")
    if not uv:
        return rows + [(False, "Python packages: uv not found, not checked")]
    cmd = [uv, "sync", "--locked", "--check", "--no-install-project", "--python", str(py)]
    for extra in extras:
        cmd += ["--extra", extra]
    run = subprocess.run(cmd, cwd=TOP / "backend", capture_output=True, text=True,
                         env={**os.environ, "UV_PROJECT_ENVIRONMENT": str(env)})
    changes = [ln.strip() for ln in (run.stdout + run.stderr).splitlines() if ln.strip()[:2] in ("+ ", "- ")]
    # The backend itself (rowfrog, installed from backend/ by the Pi's publisher
    # and the Mac) is the project, not a locked package: not a difference.
    changes = [c for c in changes if "(from file://" not in c]
    if run.returncode == 0 or (run.returncode != 0 and not changes and "(from file://" in run.stdout + run.stderr):
        rows.append((True, f"Python packages match backend/uv.lock (extras: {', '.join(extras) or 'none'})"))
    else:
        rows.append((False, "Python packages differ from backend/uv.lock: " + ("; ".join(changes[:12]) or run.stderr.strip()[-300:])))
    return rows


def check_node() -> list[tuple[bool, str]]:
    want = pinned(".nvmrc").lstrip("v")
    node = shutil.which("node")
    if not node:
        return [(False, f"Node: not installed, pinned {want} (.nvmrc)")]
    have = subprocess.run([node, "--version"], capture_output=True, text=True).stdout.strip().lstrip("v")
    return [(have == want, f"Node {have}" + ("" if have == want else f", pinned {want}") + " (.nvmrc)")]


def check_npm() -> list[tuple[bool, str]]:
    lock = json.loads((TOP / "package-lock.json").read_text())["packages"]
    installed_file = TOP / "node_modules" / ".package-lock.json"
    if not installed_file.exists():
        return [(False, "npm tools: node_modules missing; run `npm run setup`")]
    installed = json.loads(installed_file.read_text())["packages"]
    wrong = []
    for path, meta in lock.items():
        if not path:
            continue
        have = installed.get(path, {}).get("version")
        if have is None and meta.get("optional"):
            continue  # another platform's build (esbuild, workerd)
        if have != meta.get("version"):
            wrong.append(f"{path.split('node_modules/')[-1]} {have or 'missing'} (lock {meta.get('version')})")
    if wrong:
        return [(False, "npm tools differ from package-lock.json: " + "; ".join(wrong[:12]) + "; run `npm run setup`")]
    return [(True, "npm tools match package-lock.json")]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--env", type=Path)
    ap.add_argument("--extras", default="satellite")
    ap.add_argument("--node", action="store_true")
    ap.add_argument("--npm", action="store_true")
    ap.add_argument("--summary", type=Path)
    a = ap.parse_args()
    rows: list[tuple[bool, str]] = []
    if a.env:
        rows += check_python(a.env, [e for e in a.extras.split(",") if e])
    if a.node:
        rows += check_node()
    if a.npm:
        rows += check_npm()
    for ok, text in rows:
        print(("same   " if ok else "DIFF   ") + text)
    if a.summary:
        with a.summary.open("a") as f:
            f.write("\n| Versions | |\n| --- | --- |\n")
            for ok, text in rows:
                f.write(f"| {'same' if ok else '**DIFF**'} | {text} |\n")
    return 0 if all(ok for ok, _ in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
