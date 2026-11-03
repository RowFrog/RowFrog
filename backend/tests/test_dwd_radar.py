"""DWD radar readings for the widget's radar line (sources/dwd_radar.py)."""

import asyncio
import ssl
from datetime import datetime, timedelta, timezone

import httpx

from rowfrog.sources import dwd_radar

REFERENCE = datetime(2026, 10, 25, 9, 40, tzinfo=timezone.utc)


def answer(time: datetime, value):
    return {
        "features": [
            {
                "properties": {
                    "RV_ANALYSIS": value,
                    "TIME": time.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
                    "REFERENCE_TIME": REFERENCE.strftime("%Y-%m-%dT%H:%M:%SZ"),
                }
            }
        ]
    }


def test_no_rain_comes_back_as_zero():
    at, mm, reference = dwd_radar.parse_reading(answer(REFERENCE, -0.0003))
    assert (at, mm, reference) == (REFERENCE, 0.0, REFERENCE)


def test_nowcast_reads_two_hours_from_the_reference():
    def handler(request: httpx.Request) -> httpx.Response:
        time = request.url.params.get("TIME")
        at = datetime.fromisoformat(time.replace("Z", "+00:00")) if time else REFERENCE
        # Rain from 30 minutes after the latest picture.
        return httpx.Response(200, json=answer(at, 1.5 if at >= REFERENCE + timedelta(minutes=30) else None))

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await dwd_radar.nowcast(client, 47.99, 11.34)

    block = asyncio.run(run())
    assert block["reference"] == REFERENCE.isoformat()
    assert len(block["steps"]) == 9
    assert block["steps"][0] == {"time": REFERENCE.isoformat(), "mmPerHour": 0.0}
    assert block["steps"][2]["mmPerHour"] == 1.5
    assert block["steps"][-1]["time"] == (REFERENCE + timedelta(hours=2)).isoformat()


def test_a_dropped_connection_skips_only_that_club(monkeypatch):
    async def reading(client, lat, lon, time):
        await asyncio.sleep(0)
        if lat == 2:
            # As on 27 Oct 2026: a raw TLS error, not wrapped in an httpx error.
            raise ssl.SSLError("record layer failure")
        if lat == 3 and time is not None:
            # One step fails at once, a sibling later: both must end inside nowcast.
            if time == REFERENCE:
                raise httpx.ReadError("read")
            await asyncio.sleep(0.01)
            raise ssl.SSLError("record layer failure")
        return (time or REFERENCE), 0.0, REFERENCE

    monkeypatch.setattr(dwd_radar, "_reading", reading)
    blocks = asyncio.run(dwd_radar.nowcasts({"a": (1, 1), "b": (2, 2), "c": (3, 3)}))
    assert list(blocks) == ["a"]


EXCEPTION_REPORT = '<?xml version="1.0" ?><ServiceExceptionReport version="1.3.0"><ServiceException>Error rendering</ServiceException></ServiceExceptionReport>'


def _run_nowcast(handler):
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await dwd_radar.nowcast(client, 47.99, 11.34)

    return asyncio.run(run())


def _time_of(request: httpx.Request):
    time = request.url.params.get("TIME")
    return datetime.fromisoformat(time.replace("Z", "+00:00")) if time else None


def test_a_reading_dwd_refuses_once_is_asked_again():
    # As on 3 Nov 2026: DWD answered 2 of 9 readings with a ServiceExceptionReport.
    refused: set = set()

    def handler(request: httpx.Request) -> httpx.Response:
        at = _time_of(request)
        if at in (REFERENCE + timedelta(minutes=30), REFERENCE + timedelta(minutes=90)) and at not in refused:
            refused.add(at)
            return httpx.Response(200, text=EXCEPTION_REPORT, headers={"content-type": "text/xml"})
        return httpx.Response(200, json=answer(at or REFERENCE, 0.4))

    block = _run_nowcast(handler)
    assert len(refused) == 2
    assert len(block["steps"]) == 9


def test_a_reading_that_keeps_failing_keeps_the_steps_before_it():
    def handler(request: httpx.Request) -> httpx.Response:
        at = _time_of(request)
        if at is not None and at >= REFERENCE + timedelta(minutes=60) and at != REFERENCE + timedelta(minutes=105):
            return httpx.Response(200, text=EXCEPTION_REPORT)
        if at == REFERENCE + timedelta(minutes=105):
            return httpx.Response(200, json=answer(at, 3.0))
        return httpx.Response(200, json=answer(at or REFERENCE, 0.0))

    block = _run_nowcast(handler)
    # No gap: the step at +105 min is left out because +60 to +90 are unknown.
    assert [s["time"] for s in block["steps"]] == [(REFERENCE + timedelta(minutes=m)).isoformat() for m in (0, 15, 30, 45)]


def test_no_radar_when_the_first_step_keeps_failing():
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        at = _time_of(request)
        calls.append(at)
        if at == REFERENCE:
            return httpx.Response(200, text=EXCEPTION_REPORT)
        return httpx.Response(200, json=answer(at or REFERENCE, 0.0))

    try:
        _run_nowcast(handler)
    except ValueError:
        pass
    else:
        raise AssertionError("expected no radar block")
    assert calls.count(REFERENCE) == dwd_radar.TRIES
