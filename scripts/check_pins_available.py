#!/usr/bin/env python3
"""Checks that every tool pin can be installed on all three systems (owner rule,
21 Nov 2026: pin and install only versions that GitHub, the Pi and the Mac all
offer). Run by .github/workflows/pins.yml on every PR that changes a pin, and by
the monthly dependency check.

  .uv-version      uv: on PyPI (GitHub, Pi) and not newer than the Mac's uv
  .python-version  CPython: uv at .uv-version (the Mac's uv) can download it for
                   Linux x86_64, Linux aarch64 and macOS arm64 (Pi, Mac, GitHub's
                   Mac runners), and GitHub's setup-python has it for Linux
                   (setup-python has no Mac build of security-only patches such
                   as 3.12.15, so the Mac runner jobs install Python with uv)
  .nvmrc           Node: GitHub's setup-node has it and the Mac's nodejsNN /
                   node@NN is that version (the Pi runs no Node)
  .xcodegen-version XcodeGen: the Mac's xcodegen (MacPorts port or Homebrew
                   formula) is that version and XcodeGen's GitHub release has
                   xcodegen.zip for it (GitHub's Mac runners,
                   .github/actions/xcodegen; the Pi builds no app)

Where the Mac gets its tools is set in one place, MAC_SOURCE below (owner,
27 Nov 2026: MacPorts for now; the choice between MacPorts and Homebrew is made
later). "macports" reads MacPorts' Portfiles, "homebrew" Homebrew's formula
files; MAC_UV_SOURCE = "uv-installer" takes uv from uv's own installer instead
(every release, as on PyPI). Switching is a one-line PR; --mac-source and
--mac-uv-source try another source without changing the file.

The packages need no check here: uv.lock can only be written when every package
has a build for all three systems ([tool.uv] required-environments).
Exits 1 when a pin is missing somewhere. Needs network; standard library only.
"""
import argparse
import json
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Where the Mac's uv and Node come from: "macports" or "homebrew".
MAC_SOURCE = "macports"
# uv alone: None = the same as MAC_SOURCE, or "uv-installer" (uv's own installer, like the Pi).
MAC_UV_SOURCE = None

PORTS = "https://raw.githubusercontent.com/macports/macports-ports/master"
FORMULAE = "https://raw.githubusercontent.com/Homebrew/homebrew-core/main/Formula"
SOURCE_NAMES = {"macports": "MacPorts", "homebrew": "Homebrew", "uv-installer": "uv installer"}
PY_MANIFEST = "https://raw.githubusercontent.com/actions/python-versions/main/versions-manifest.json"
NODE_MANIFEST = "https://raw.githubusercontent.com/actions/node-versions/main/versions-manifest.json"
UV_PLATFORMS = ["linux-x86_64-gnu", "linux-aarch64-gnu", "macos-aarch64-none"]


def get(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return r.read().decode()


def vtuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", v))


def macports_version(portfile_path):
    text = get(f"{PORTS}/{portfile_path}/Portfile")
    m = re.search(r"^github\.setup\s+\S+\s+\S+\s+(\S+)", text, re.M) or re.search(r"^version\s+(\S+)", text, re.M)
    return m.group(1)


def homebrew_version(formula):
    text = get(f"{FORMULAE}/{formula[0]}/{formula}.rb")
    m = re.search(r'^  version "([^"]+)"', text, re.M)
    if m:
        return m.group(1)
    url = re.search(r'^  url "([^"]+)"', text, re.M).group(1)
    return re.findall(r"\d+\.\d+\.\d+", url)[-1]


def mac_uv_version(source):
    if source == "macports":
        return macports_version("devel/uv")
    if source == "homebrew":
        return homebrew_version("uv")
    return json.loads(get("https://pypi.org/pypi/uv/json"))["info"]["version"]  # uv-installer: every release


def mac_node_version(source, major):
    if source == "macports":
        return macports_version(f"lang/nodejs{major}")
    return homebrew_version(f"node@{major}")


def mac_xcodegen_version(source):
    if source == "macports":
        return macports_version("devel/xcodegen")
    return homebrew_version("xcodegen")


def release_has(url):
    req = urllib.request.Request(url, method="HEAD")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status == 200
    except Exception:
        return False


def manifest_has(url, version, wanted):
    for rel in json.loads(get(url)):
        if rel["version"] == version:
            have = {(f["platform"], f["arch"]) for f in rel["files"]}
            return [w for w in wanted if w not in have]
    return wanted


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--uv", default="uv", help="uv binary, the version in .uv-version")
    ap.add_argument("--summary", help="append a Markdown table to this file (GITHUB_STEP_SUMMARY)")
    ap.add_argument("--mac-source", choices=["macports", "homebrew"], default=MAC_SOURCE,
                    help=f"where the Mac gets uv and Node (default: MAC_SOURCE, {MAC_SOURCE})")
    ap.add_argument("--mac-uv-source", choices=["macports", "homebrew", "uv-installer"], default=MAC_UV_SOURCE,
                    help="where the Mac gets uv, if not from --mac-source (default: MAC_UV_SOURCE)")
    args = ap.parse_args()
    uv_source = args.mac_uv_source or args.mac_source
    rows, bad = [], False

    def row(what, pin, ok, note):
        nonlocal bad
        bad |= not ok
        rows.append((what, pin, "ok" if ok else "MISSING", note))

    # uv
    uv_pin = (ROOT / ".uv-version").read_text().strip()
    mac_uv = mac_uv_version(uv_source)
    try:
        get(f"https://pypi.org/pypi/uv/{uv_pin}/json")
        on_pypi = True
    except Exception:
        on_pypi = False
    ok = on_pypi and vtuple(uv_pin) <= vtuple(mac_uv)
    row("uv", uv_pin, ok, f"{SOURCE_NAMES[uv_source]} (Mac) {mac_uv}; PyPI (GitHub, Pi) {'yes' if on_pypi else 'no'}")

    # Python
    py_pin = (ROOT / ".python-version").read_text().strip()
    out = subprocess.run([args.uv, "--version"], capture_output=True, text=True).stdout.split()
    if len(out) < 2 or out[1] != uv_pin:
        print(f"warning: {args.uv} is {' '.join(out)}, not uv {uv_pin} from .uv-version", file=sys.stderr)
    listing = subprocess.run(
        [args.uv, "python", "list", "--all-versions", "--only-downloads", "--all-platforms", "--all-arches"],
        capture_output=True, text=True, check=True).stdout
    names = {line.split()[0] for line in listing.splitlines() if line.strip()}
    missing = [p for p in UV_PLATFORMS if f"cpython-{py_pin}-{p}" not in names]
    gh_missing = manifest_has(PY_MANIFEST, py_pin, [("linux", "x64")])
    note = "uv downloads (Mac, Pi): " + ("all three" if not missing else "missing " + ", ".join(missing))
    note += "; GitHub setup-python (Linux): " + ("yes" if not gh_missing else "missing " + ", ".join("/".join(m) for m in gh_missing))
    row("Python", py_pin, not missing and not gh_missing, note)

    # Node
    node_pin = (ROOT / ".nvmrc").read_text().strip().lstrip("v")
    major = node_pin.split(".")[0]
    mac_node = mac_node_version(args.mac_source, major)
    node_name = f"nodejs{major}" if args.mac_source == "macports" else f"node@{major}"
    gh_missing = manifest_has(NODE_MANIFEST, node_pin, [("linux", "x64"), ("darwin", "arm64")])
    ok = not gh_missing and mac_node == node_pin
    note = f"{SOURCE_NAMES[args.mac_source]} {node_name} (Mac) {mac_node}; GitHub setup-node: " + ("yes" if not gh_missing else "missing")
    if vtuple(mac_node) > vtuple(node_pin) and not gh_missing:
        note += f" ({SOURCE_NAMES[args.mac_source]} moved on: raise .nvmrc to {mac_node} once GitHub has it)"
    row("Node", node_pin, ok, note)

    # XcodeGen
    xg_pin = (ROOT / ".xcodegen-version").read_text().strip()
    mac_xg = mac_xcodegen_version(args.mac_source)
    on_gh = release_has(f"https://github.com/yonaskolb/XcodeGen/releases/download/{xg_pin}/xcodegen.zip")
    note = f"{SOURCE_NAMES[args.mac_source]} xcodegen (Mac) {mac_xg}; XcodeGen release zip (GitHub) " + ("yes" if on_gh else "no")
    if vtuple(mac_xg) > vtuple(xg_pin):
        note += f" ({SOURCE_NAMES[args.mac_source]} moved on: raise .xcodegen-version to {mac_xg})"
    row("XcodeGen", xg_pin, on_gh and mac_xg == xg_pin, note)

    lines = ["| Pin | Version | All systems | Where |", "| --- | --- | --- | --- |"]
    lines += [f"| {a} | {b} | {c} | {d} |" for a, b, c, d in rows]
    print("\n".join(lines))
    if args.summary:
        with open(args.summary, "a") as f:
            f.write("### Pins installable everywhere\n\n" + "\n".join(lines) + "\n")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
