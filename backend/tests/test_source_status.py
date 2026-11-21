"""sources-status.json: what the jobs' own requests say about the outside services (rowfrog.source_status)."""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
import pytest

from rowfrog import source_status

MODULE = Path(source_status.__file__)
FIELDS = {"job", "last_try", "last_ok", "last_fail", "reason", "tries", "failed", "expect_min"}


@pytest.fixture
def fake_net(monkeypatch):
    """httpx's real transports, answered without a network: by host, as `answers` says."""
    answers: dict[str, object] = {}

    def answer(request):
        what = answers.get(request.url.host, 200)
        if isinstance(what, Exception):
            raise what
        if isinstance(what, str):
            return httpx.Response(200, text=what, request=request)
        return httpx.Response(what, request=request)

    async def answer_async(self, request):
        return answer(request)

    monkeypatch.setattr(httpx.HTTPTransport, "handle_request", lambda self, request: answer(request))
    monkeypatch.setattr(httpx.AsyncHTTPTransport, "handle_async_request", answer_async)
    monkeypatch.setattr(source_status, "_HOOKED", False)
    monkeypatch.setattr(source_status, "RECORDER", None)
    monkeypatch.setattr(source_status.atexit, "register", lambda f: None)
    return answers


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def test_a_run_with_one_failing_source(fake_net, tmp_path, monkeypatch):
    status = tmp_path / "state" / "sources-status.json"
    monkeypatch.setenv("SOURCES_STATUS", str(status))
    fake_net["www.gkd.bayern.de"] = httpx.ConnectError("[Errno -3] Temporary failure in name resolution")
    fake_net["api.existenz.ch"] = 503
    recorder = source_status.start("publish")
    assert recorder is not None and recorder.path == status
    with httpx.Client() as client:
        for _ in range(3):
            client.get("https://api.open-meteo.com/v1/forecast?latitude=47.9&apikey=SECRET")
        client.get("https://opendata.dwd.de/weather/alerts/x.zip")
        client.get("https://maps.dwd.de/geoserver/dwd/ows")
        client.get("https://api.existenz.ch/apiv1/hydro/latest")
        with pytest.raises(httpx.ConnectError):
            client.get("https://www.gkd.bayern.de/en/lakes/watertemperature/bayern/18201303/current-values/table")
        client.get("http://localhost:8000/v1/clubs")  # local: never counted
    source_status.note_command(["rclone", "copy", "a", "r2:b"], 0)
    source_status.note_command(["echo", "hi"], 0)  # not an upload: not counted
    source_status.flush()

    body = read(status)
    assert body["version"] == 1 and body["updated"].endswith("Z")
    sources = body["sources"]
    assert set(sources) == {"openmeteo", "dwd", "bafu", "gkd", "r2"}
    for entry in sources.values():
        assert set(entry) == FIELDS and entry["job"] == "publish" and entry["last_try"].endswith("Z")
    assert sources["openmeteo"] == {**sources["openmeteo"], "tries": 3, "failed": 0, "last_fail": None, "reason": "",
                                    "expect_min": 30, "last_ok": sources["openmeteo"]["last_try"]}
    assert sources["dwd"]["tries"] == 2 and sources["dwd"]["failed"] == 0
    assert sources["gkd"] == {**sources["gkd"], "tries": 1, "failed": 1, "reason": "dns", "last_ok": None,
                              "last_fail": sources["gkd"]["last_try"], "expect_min": 30}
    assert sources["bafu"]["reason"] == "http-503" and sources["bafu"]["failed"] == 1
    assert sources["r2"]["tries"] == 1 and sources["r2"]["last_ok"]
    text = status.read_text()
    assert "SECRET" not in text and "http" not in text.replace('"http-503"', "") and "18201303" not in text
    assert oct(status.stat().st_mode & 0o777) == "0o644"


def test_async_requests_count_too(fake_net, tmp_path, monkeypatch):
    import asyncio

    monkeypatch.setenv("SOURCES_STATUS", str(tmp_path / "s.json"))
    fake_net["api.open-meteo.com"] = 429
    source_status.start("publish")

    async def go():
        async with httpx.AsyncClient() as client:
            await client.get("https://api.open-meteo.com/v1/forecast")
            await client.get("https://www.pegelonline.wsv.de/webservices/x")

    asyncio.run(go())
    source_status.flush()
    sources = read(tmp_path / "s.json")["sources"]
    assert sources["openmeteo"]["reason"] == "http-429" and sources["openmeteo"]["last_ok"] is None
    assert sources["pegelonline"]["failed"] == 0


def test_a_second_job_keeps_the_first_jobs_entries(fake_net, tmp_path, monkeypatch):
    status = tmp_path / "sources-status.json"
    monkeypatch.setenv("SOURCES_STATUS", str(status))
    source_status.start("publish")
    with httpx.Client() as client:
        client.get("https://api.open-meteo.com/v1/forecast")
        client.get("https://sh.dataspace.copernicus.eu/api/v1/process")
    source_status.flush()
    first = read(status)["sources"]

    fake_net["api.cloudflare.com"] = httpx.ConnectTimeout("timed out")
    source_status.start("budget-check")
    with httpx.Client() as client:
        client.get("https://api.rowfrog.com/v1/usage/budget")
        with pytest.raises(httpx.ConnectTimeout):
            client.post("https://api.cloudflare.com/client/v4/graphql")
        client.get("https://api.open-meteo.com/v1/forecast")
    source_status.flush()
    second = read(status)["sources"]

    assert second["copernicus"] == first["copernicus"]  # untouched: kept as it was
    assert second["copernicus"]["expect_min"] is None
    assert second["cloudflare"]["reason"] == "timeout" and second["cloudflare"]["expect_min"] == 1440
    assert second["rowfrogapi"]["job"] == "budget-check" and second["rowfrogapi"]["expect_min"] == 1440
    # Open-Meteo's interval is the publisher's, whichever job read it last.
    assert second["openmeteo"]["job"] == "budget-check" and second["openmeteo"]["expect_min"] == 30


def test_a_failure_after_a_part_way_write_takes_last_ok_back(fake_net, tmp_path, monkeypatch):
    status = tmp_path / "sources-status.json"
    old = {"version": 1, "updated": "2026-11-21T17:00:00Z", "sources": {"dwd": {
        "job": "publish", "last_try": "2026-11-21T17:00:00Z", "last_ok": "2026-11-21T17:00:00Z", "last_fail": None,
        "reason": "", "tries": 4, "failed": 0, "expect_min": 30}}}
    status.write_text(json.dumps(old))
    monkeypatch.setenv("SOURCES_STATUS", str(status))
    source_status.start("publish")
    with httpx.Client() as client:
        client.get("https://maps.dwd.de/geoserver/dwd/wms")
        source_status.flush()  # once the club forecasts are online
        assert read(status)["sources"]["dwd"]["last_ok"] != "2026-11-21T17:00:00Z"
        fake_net["maps.dwd.de"] = 502
        client.get("https://maps.dwd.de/geoserver/dwd/wms")
    source_status.flush()
    dwd = read(status)["sources"]["dwd"]
    assert dwd["last_ok"] == "2026-11-21T17:00:00Z"  # the run had a failure: last_ok names the run before
    assert dwd["reason"] == "http-502" and dwd["tries"] == 2 and dwd["failed"] == 1


def test_gkd_refusal_page_counts_as_firewall(fake_net, tmp_path, monkeypatch):
    import asyncio

    from rowfrog.sources import gkd

    monkeypatch.setenv("SOURCES_STATUS", str(tmp_path / "s.json"))
    fake_net["www.gkd.bayern.de"] = "<html>Request Rejected</html>"
    source_status.start("publish")

    async def go():
        async with httpx.AsyncClient() as client:
            with pytest.raises(gkd.Rejected):
                await gkd._page(client, "18201303")

    asyncio.run(go())
    source_status.flush()
    entry = read(tmp_path / "s.json")["sources"]["gkd"]
    assert entry["tries"] == 1 and entry["failed"] == 1 and entry["reason"] == "firewall"


def test_nothing_written_without_a_place(fake_net, monkeypatch):
    monkeypatch.delenv("SOURCES_STATUS", raising=False)
    assert source_status.start("model-check") is None
    with httpx.Client() as client:
        client.get("https://api.open-meteo.com/v1/forecast")
    source_status.flush()  # nothing to do, no error


def test_the_file_is_whole_at_all_times(tmp_path):
    """Writers in parallel (each with its own lock file handle, like separate jobs) and a reader:
    the reader never sees half a file, and no writer's source gets lost."""
    status = tmp_path / "sources-status.json"
    stop = threading.Event()
    bad: list[str] = []

    def reader():
        while not stop.is_set():
            try:
                text = status.read_text(encoding="utf-8")
            except FileNotFoundError:
                continue
            try:
                json.loads(text)
            except ValueError:
                bad.append(text)

    def writer(n: int):
        for i in range(15):
            tally = source_status.Tally()
            tally.add(i % 3 != 0, "timeout")
            source_status.write(status, f"job{n}", {f"src{n}": tally})

    r = threading.Thread(target=reader)
    r.start()
    writers = [threading.Thread(target=writer, args=(n,)) for n in range(6)]
    for w in writers:
        w.start()
    for w in writers:
        w.join()
    stop.set()
    r.join()
    assert not bad
    assert set(read(status)["sources"]) == {f"src{n}" for n in range(6)}
    assert [p.name for p in tmp_path.iterdir() if p.name.endswith(".tmp")] == []


def test_a_write_that_breaks_leaves_the_old_file(tmp_path, monkeypatch):
    status = tmp_path / "sources-status.json"
    tally = source_status.Tally()
    tally.add(True)
    source_status.write(status, "publish", {"openmeteo": tally})
    before = status.read_text()

    def broken(*args, **kwargs):
        raise OSError("disk full")

    monkeypatch.setattr(source_status.json, "dump", broken)
    with pytest.raises(OSError):
        source_status.write(status, "publish", {"dwd": tally})
    assert status.read_text() == before
    assert [p.name for p in tmp_path.iterdir() if p.name.endswith(".tmp")] == []


def test_a_broken_or_old_file_is_started_again(tmp_path):
    status = tmp_path / "sources-status.json"
    status.write_text('{"version": 1, "sour')
    tally = source_status.Tally()
    tally.add(True)
    body = source_status.write(status, "publish", {"openmeteo": tally})
    assert list(body["sources"]) == ["openmeteo"] and read(status) == body


def test_shell_jobs_record_with_the_file_alone(tmp_path):
    """follow.sh and run-publish.sh run this file with the system Python, no packages, isolated (-I)."""
    status = tmp_path / "sources-status.json"
    env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"} | {"SOURCES_STATUS": str(status)}
    run = [sys.executable, "-I", str(MODULE), "record"]
    subprocess.run(run + ["--job", "follow", "--source", "github", "--failed", "1", "--reason", "dns"], env=env, check=True)
    subprocess.run(run + ["--job", "publish", "--source", "r2"], env=env, check=True)
    sources = read(status)["sources"]
    assert sources["github"] == {**sources["github"], "job": "follow", "tries": 1, "failed": 1, "reason": "dns",
                                 "last_ok": None, "expect_min": 30}
    assert sources["r2"]["failed"] == 0 and sources["r2"]["last_ok"] and sources["r2"]["expect_min"] == 30
    # Without a place to write it does nothing and never fails the job.
    del env["SOURCES_STATUS"]
    assert subprocess.run(run + ["--job", "follow", "--source", "github"], env=env).returncode == 0


@pytest.mark.parametrize("host, key", [
    ("api.open-meteo.com", "openmeteo"), ("historical-forecast-api.open-meteo.com", "openmeteo"),
    ("opendata.dwd.de", "dwd"), ("maps.dwd.de", "dwd"), ("identity.dataspace.copernicus.eu", "copernicus"),
    ("download.dataspace.copernicus.eu", "copernicus"), ("www.gkd.bayern.de", "gkd"),
    ("www.pegelonline.wsv.de", "pegelonline"), ("api.existenz.ch", "bafu"), ("api.rowfrog.com", "rowfrogapi"),
    ("github.com", "github"), ("feeds.meteoalarm.org", "meteoalarm"), ("warnungen.zamg.at", "geosphere"),
    ("planetarycomputer.microsoft.com", "planetary"), ("landsateuwest.blob.core.windows.net", "planetary"),
    ("api.cloudflare.com", "cloudflare"), ("example.org", "other"), ("localhost", None), ("127.0.0.1", None),
    ("notdwd.de", "other"),
])
def test_hosts(host, key):
    assert source_status.source_for(host) == key


def test_reasons():
    assert source_status.reason_for_error(httpx.ReadTimeout("x")) == "timeout"
    dns = httpx.ConnectError("x")
    dns.__cause__ = socket.gaierror(-2, "Name or service not known")
    assert source_status.reason_for_error(dns) == "dns"
    assert source_status.reason_for_error(httpx.ConnectError("[SSL: CERTIFICATE_VERIFY_FAILED]")) == "tls"
    assert source_status.reason_for_error(httpx.ConnectError("[Errno 111] Connection refused")) == "refused"
    assert source_status.reason_for_error(httpx.ProxyError("403")) == "proxy"
    assert source_status.status_failed(503) and source_status.status_failed(429) and source_status.status_failed(403)
    assert not source_status.status_failed(404) and not source_status.status_failed(304)


def test_the_shortest_interval_stays_while_its_job_is_at_it(tmp_path):
    status = tmp_path / "s.json"
    tally = source_status.Tally()
    tally.add(True)
    every = {k: source_status.ALL_CLUBS_EVERY for k in source_status.CLUB_DEPENDENT}
    t0 = datetime(2026, 11, 21, 4, 0, tzinfo=timezone.utc)

    def at(minutes, job, **kw):
        tally.last = t0 + timedelta(minutes=minutes)
        return source_status.write(status, job, {"bafu": tally, "openmeteo": tally}, now=tally.last, **kw)["sources"]

    # Only the all-clubs runs read BAFU: every 6 hours.
    assert at(0, "publish", expect=every)["bafu"]["expect_min"] == 360
    # A used Swiss club: the regular runs read it every 30 minutes, and an all-clubs run keeps that ...
    assert at(30, "publish")["bafu"]["expect_min"] == 30
    assert at(60, "publish", expect=every)["bafu"]["expect_min"] == 30
    # ... and so does the model check (twice a day) for Open-Meteo.
    assert at(70, "model-check")["openmeteo"]["expect_min"] == 30
    # Nobody reads it every 30 minutes any more: the next all-clubs run, 6 hours on, says 360 again.
    assert at(420, "publish", expect=every)["bafu"]["expect_min"] == 360
    # The budget check alone reads the usage counter: once a day.
    assert source_status.write(status, "budget-check", {"rowfrogapi": tally}, now=tally.last)["sources"]["rowfrogapi"]["expect_min"] == 1440


def test_utc_text():
    assert source_status.utc_text(datetime(2026, 11, 21, 18, 0, 12, 345, tzinfo=timezone.utc)) == "2026-11-21T18:00:12Z"
