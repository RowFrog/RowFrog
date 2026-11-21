"""What the jobs' own fetches say about the outside services (sources-status.json).

The Pi's connection monitor reads this file to tell whether the
services RowFrog depends on answer, without sending them anything itself while
the data keeps arriving. Nothing here makes a request: it only writes down the
requests the jobs make anyway.

    {"version": 1, "updated": "2026-11-21T18:00:12Z",
     "sources": {"openmeteo": {"job": "publish", "last_try": "...Z", "last_ok": "...Z",
                               "last_fail": null, "reason": "", "tries": 14, "failed": 0,
                               "expect_min": 30}, ...}}

- last_try: end of the last request to the source in the job's last run.
- last_ok: the last run in which at least one request succeeded and none failed.
- last_fail / reason: the last run in which a request failed, and why (timeout, dns,
  tls, refused, network, http-503, http-429, firewall, ...; the most frequent one).
- tries / failed: requests to the source in that run (counts only: no URLs, keys or clubs).
- expect_min: how often the source is normally fetched (minutes), null when irregular.

A request counts as failed when it got no answer or an answer that says the service is
unavailable or refused us (5xx, 429, 401, 403, 407, 408). Other answers (200, 304, 404,
...) show the service is up and count as successes. Sources the job did not touch keep
their entries. The file is replaced atomically (temp file + os.replace) under a lock on
sources-status.json.lock, so several jobs can update it and a reader never sees half a file.

Where: SOURCES_STATUS (rowfrog.env); without it the publisher writes next to its --state
file and the other jobs write nothing (GitHub, tests, the Mac).

Standard library only, so the Pi's shell jobs can run this file directly:
    python3 -I backend/rowfrog/source_status.py record --job follow --source github --tries 1 --failed 1 --reason dns
"""

from __future__ import annotations

import argparse
import atexit
import fcntl
import json
import os
import socket
import ssl
import sys
import tempfile
import threading
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

VERSION = 1
FILE_NAME = "sources-status.json"

# Host (or the end of it) -> source key. The first match wins; the keys are the Pi's names.
HOSTS = (
    ("open-meteo.com", "openmeteo"),
    ("dwd.de", "dwd"),
    ("dataspace.copernicus.eu", "copernicus"),
    ("gkd.bayern.de", "gkd"),
    ("pegelonline.wsv.de", "pegelonline"),
    ("existenz.ch", "bafu"),
    ("api.rowfrog.com", "rowfrogapi"),
    ("github.com", "github"),
    ("githubusercontent.com", "github"),
    ("meteoalarm.org", "meteoalarm"),       # Swiss warnings
    ("zamg.at", "geosphere"),               # Austrian warnings (GeoSphere Austria)
    ("geosphere.at", "geosphere"),
    ("planetarycomputer.microsoft.com", "planetary"),  # Landsat lake temperatures
    ("blob.core.windows.net", "planetary"),            # the Landsat files themselves
    ("api.cloudflare.com", "cloudflare"),   # budget check: Worker and D1 figures
    ("r2.cloudflarestorage.com", "r2"),
)
# Requests to these never count (test servers, the Mac's local servers).
LOCAL_HOSTS = ("localhost", "127.0.0.1", "::1", "testserver")

# How often each job normally fetches each source, in minutes (None: irregular). Where
# several jobs read a source, the file keeps the shortest interval as long as the job with
# it is still fetching (its last_try younger than 1.5 times that interval), so the model
# check's twice-a-day Open-Meteo reads never hide the publisher's every 30 minutes, and an
# interval that ended (e.g. no used club reads BAFU any more) gives way by itself.
EXPECT: dict[str, dict[str, int | None]] = {
    "publish": {
        "openmeteo": 30,      # the newest model run is asked in every run
        "dwd": 30,            # warnings and radar in every run
        "gkd": 30,            # water temperatures of the used clubs
        "pegelonline": 30,
        "bafu": 30,
        "meteoalarm": 30,     # Swiss warnings, for used Swiss clubs
        "geosphere": 30,      # Austrian warnings, for used Austrian clubs
        "rowfrogapi": 30,     # the usage counter, read at the start of every run
        "r2": 30,             # uploads during and after every run
        "copernicus": None,   # only when a satellite passed, ice maps twice a day in season
        "planetary": 1440,    # Landsat looked for once a day
    },
    "model-check": {"openmeteo": 720, "dwd": 720, "gkd": 720, "rowfrogapi": 720},  # 04:40 and 16:40 UTC
    "gkd-log": {"gkd": 1440},                                                       # 01:05 UTC
    "budget-check": {"rowfrogapi": 1440, "cloudflare": 1440},                       # 06:10 UTC
    # rowfrog-follow.timer runs every 15 minutes but skips while a forecast run is active.
    "follow": {"github": 30},
}
# Fetched by the publisher only for some clubs: every 30 minutes when a used club needs them,
# else only in the all-clubs runs (every 6 hours), which say so with expect=.
CLUB_DEPENDENT = frozenset({"gkd", "pegelonline", "bafu", "meteoalarm", "geosphere"})
ALL_CLUBS_EVERY = 360

FAILING_STATUS = {401, 403, 407, 408, 429}


def utc_text(t: datetime) -> str:
    return t.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def source_for(host: str | None) -> str | None:
    """The source key for a host; None for local hosts, "other" for an unknown outside host."""
    if not host:
        return None
    host = host.lower().rstrip(".")
    if host in LOCAL_HOSTS or host.endswith(".local"):
        return None
    for end, key in HOSTS:
        if host == end or host.endswith("." + end):
            return key
    return "other"


def status_failed(code: int) -> bool:
    return code >= 500 or code in FAILING_STATUS


def reason_for_status(code: int) -> str:
    return f"http-{code}"


def reason_for_error(error: BaseException) -> str:
    """A short reason for a request that got no answer: timeout, dns, tls, refused, proxy, network."""
    name = type(error).__name__.lower()
    seen: list[BaseException] = []
    e: BaseException | None = error
    while e is not None and len(seen) < 8:
        seen.append(e)
        e = e.__cause__ or e.__context__
    text = " ".join(str(x).lower() for x in seen)
    if "timeout" in name or any(isinstance(x, (TimeoutError, socket.timeout)) for x in seen) or "timed out" in text:
        return "timeout"
    if any(isinstance(x, socket.gaierror) for x in seen) or "name or service not known" in text \
            or "name resolution" in text or "nodename nor servname" in text or "getaddrinfo" in text:
        return "dns"
    if any(isinstance(x, ssl.SSLError) for x in seen) or "ssl" in text or "certificate" in text:
        return "tls"
    if "proxy" in name:
        return "proxy"
    if any(isinstance(x, ConnectionRefusedError) for x in seen) or "refused" in text:
        return "refused"
    if any(isinstance(x, ConnectionResetError) for x in seen) or "reset by peer" in text:
        return "reset"
    return "network"


class Tally:
    """Requests to one source in this run."""

    def __init__(self) -> None:
        self.tries = 0
        self.failed = 0
        self.reasons: Counter[str] = Counter()
        self.last: datetime | None = None

    def add(self, ok: bool, reason: str = "", when: datetime | None = None) -> None:
        self.tries += 1
        self.last = when or datetime.now(timezone.utc)
        if not ok:
            self.failed += 1
            self.reasons[reason or "error"] += 1

    def reject(self, reason: str) -> None:
        """A request already counted as answered turned out to be a refusal (GKD's 200 "Request Rejected" page)."""
        if self.tries == 0:
            self.add(False, reason)
            return
        if self.failed < self.tries:
            self.failed += 1
        self.reasons[reason] += 1

    @property
    def reason(self) -> str:
        return self.reasons.most_common(1)[0][0] if self.reasons else ""


def _parse(text) -> datetime | None:
    try:
        return datetime.fromisoformat(str(text).replace("Z", "+00:00"))
    except ValueError:
        return None


def merge(old: dict | None, job: str, tallies: dict[str, Tally], now: datetime,
          expect: dict[str, int | None] | None = None, before: dict[str, str | None] | None = None) -> dict:
    """The new file contents: `old` with the sources of `tallies` updated, everything else kept.

    `before` keeps each source's last_ok from before this run's first write: a run that
    writes part way (the publisher, once the club forecasts are online) and fails later
    goes back to it, so last_ok always names a run without a failure."""
    sources = dict((old or {}).get("sources") or {}) if isinstance(old, dict) and old.get("version") == VERSION else {}
    for key, tally in sorted(tallies.items()):
        if tally.tries == 0:
            continue
        entry = dict(sources.get(key) or {})
        old_min, old_try = entry.get("expect_min"), _parse(entry.get("last_try"))
        if before is not None and key not in before:
            before[key] = entry.get("last_ok")
        when = utc_text(tally.last or now)
        entry["job"] = job
        entry["last_try"] = when
        entry.setdefault("last_ok", None)
        entry.setdefault("last_fail", None)
        entry.setdefault("reason", "")
        if tally.failed == 0:
            entry["last_ok"] = when
            if before is not None:
                before[key + " (ours)"] = when
        else:
            # Only our own part-way last_ok goes back; one another job wrote since stays.
            if before is not None and key + " (ours)" in before and entry.get("last_ok") == before[key + " (ours)"]:
                entry["last_ok"] = before[key]
            entry["last_fail"] = when
            entry["reason"] = tally.reason
        entry["tries"] = tally.tries
        entry["failed"] = tally.failed
        minutes = (expect or {}).get(key, EXPECT.get(job, {}).get(key))
        if isinstance(old_min, int) and (minutes is None or old_min < minutes) and old_try is not None \
                and (now - old_try).total_seconds() < 1.5 * 60 * old_min:
            minutes = old_min  # a job that fetches it more often is still at it
        entry["expect_min"] = minutes
        sources[key] = {k: entry[k] for k in
                        ("job", "last_try", "last_ok", "last_fail", "reason", "tries", "failed", "expect_min")}
    return {"version": VERSION, "updated": utc_text(now), "sources": dict(sorted(sources.items()))}


def write(path: Path, job: str, tallies: dict[str, Tally], now: datetime | None = None,
          expect: dict[str, int | None] | None = None, before: dict[str, str | None] | None = None) -> dict:
    """Reads the file, merges this job's sources and replaces it atomically, under the lock."""
    path = Path(path)
    now = now or datetime.now(timezone.utc)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path.with_name(path.name + ".lock"), "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            old = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            old = None
        body = merge(old, job, tallies, now, expect, before)
        fd, tmp = tempfile.mkstemp(prefix="." + path.name + ".", suffix=".tmp", dir=path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(body, f, indent=1)
                f.write("\n")
                f.flush()
                os.fsync(f.fileno())
            os.chmod(tmp, 0o644)
            os.replace(tmp, path)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
    return body


class Recorder:
    """Counts one job run's requests per source and writes them to the status file."""

    def __init__(self, job: str, path: Path, expect: dict[str, int | None] | None = None) -> None:
        self.job = job
        self.path = Path(path)
        self.expect = expect
        self.tallies: dict[str, Tally] = {}
        self.before: dict[str, str | None] = {}  # last_ok before this run (see merge)
        self.lock = threading.Lock()
        self.pid = os.getpid()  # worker processes (fork) never write

    def note(self, source: str | None, ok: bool, reason: str = "") -> None:
        if source is None:
            return
        with self.lock:
            self.tallies.setdefault(source, Tally()).add(ok, reason)

    def reject(self, source: str, reason: str) -> None:
        with self.lock:
            self.tallies.setdefault(source, Tally()).reject(reason)

    def flush(self) -> None:
        if os.getpid() != self.pid:
            return
        with self.lock:
            tallies = {k: v for k, v in self.tallies.items() if v.tries}
        if not tallies:
            return
        try:
            write(self.path, self.job, tallies, expect=self.expect, before=self.before)
        except OSError as e:  # bookkeeping must never stop a job
            print(f"  sources status not written: {e!r}", file=sys.stderr)


RECORDER: Recorder | None = None


def status_path(default_dir: Path | None = None) -> Path | None:
    """SOURCES_STATUS, else sources-status.json in `default_dir`, else None (nothing written)."""
    configured = os.environ.get("SOURCES_STATUS", "").strip()
    if configured:
        return Path(configured).expanduser()
    if default_dir is not None:
        return Path(default_dir) / FILE_NAME
    return None


def start(job: str, default_dir: Path | None = None, expect: dict[str, int | None] | None = None) -> Recorder | None:
    """Starts counting this process's httpx requests for `job`; written at exit (and by flush()).
    Returns None, and counts nothing, when no status file is set."""
    global RECORDER
    path = status_path(default_dir)
    if path is None:
        return None
    RECORDER = Recorder(job, path, expect)
    _hook_httpx()
    atexit.register(flush)
    return RECORDER


def note(source: str | None, ok: bool, reason: str = "") -> None:
    """Counts one request the job made without httpx (rclone, git)."""
    if RECORDER is not None:
        RECORDER.note(source, ok, reason)


def note_command(args: list[str], returncode: int | None = None, error: BaseException | None = None) -> None:
    """Counts one run of an upload command: rclone is the R2 bucket (r2); other commands are not counted."""
    if not args or os.path.basename(args[0]) != "rclone":
        return
    if error is not None:
        note("r2", False, "timeout" if "timeout" in type(error).__name__.lower() else "start-failed")
    else:
        note("r2", returncode == 0, f"exit-{returncode}")


def reject(source: str, reason: str) -> None:
    """Turns the last answer from `source` into a failure (an answer that was a refusal in disguise)."""
    if RECORDER is not None:
        RECORDER.reject(source, reason)


def flush() -> None:
    if RECORDER is not None:
        RECORDER.flush()


_HOOKED = False


def _hook_httpx() -> None:
    """Wraps httpx's real transports once, so every request any client makes is counted.
    Mock transports (tests) are other classes and stay untouched."""
    global _HOOKED
    if _HOOKED:
        return
    import httpx

    sync_send = httpx.HTTPTransport.handle_request
    async_send = httpx.AsyncHTTPTransport.handle_async_request

    def counted(request, response=None, error=None):
        if RECORDER is None:
            return
        source = source_for(request.url.host)
        if error is not None:
            RECORDER.note(source, False, reason_for_error(error))
        elif status_failed(response.status_code):
            RECORDER.note(source, False, reason_for_status(response.status_code))
        else:
            RECORDER.note(source, True)

    def handle_request(self, request):
        try:
            response = sync_send(self, request)
        except Exception as e:
            counted(request, error=e)
            raise
        counted(request, response)
        return response

    async def handle_async_request(self, request):
        try:
            response = await async_send(self, request)
        except Exception as e:
            counted(request, error=e)
            raise
        counted(request, response)
        return response

    httpx.HTTPTransport.handle_request = handle_request
    httpx.AsyncHTTPTransport.handle_async_request = handle_async_request
    _HOOKED = True


def main(argv: list[str] | None = None) -> int:
    """For the shell jobs (rclone, git fetch): records one run's counts for one source."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    rec = sub.add_parser("record", help="record one run's requests to one source")
    rec.add_argument("--job", required=True)
    rec.add_argument("--source", required=True)
    rec.add_argument("--tries", type=int, default=1)
    rec.add_argument("--failed", type=int, default=0)
    rec.add_argument("--reason", default="")
    rec.add_argument("--file", type=Path, help="default: SOURCES_STATUS")
    args = parser.parse_args(argv)
    path = args.file or status_path()
    if path is None:
        return 0  # nowhere to write: nothing to do
    tally = Tally()
    for i in range(max(args.tries, 1)):
        tally.add(i >= args.failed, args.reason or "error")
    try:
        write(path, args.job, {args.source: tally})
    except OSError as e:
        print(f"sources status not written: {e!r}", file=sys.stderr)
    return 0  # bookkeeping never fails a job


if __name__ == "__main__":
    # Run as a file with python3 -I, so this folder's modules never shadow the standard library's.
    sys.exit(main())
