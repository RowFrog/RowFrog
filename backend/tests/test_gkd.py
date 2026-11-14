from datetime import datetime, timedelta, timezone

from rowfrog.sources import gkd

# Shape of the GKD "current values" table: a date cell and a value cell per row.
PAGE = """
<table class="tblsort">
  <thead><tr><th>Date</th><th>Water temperature [&deg;C]</th></tr></thead>
  <tbody>
    <tr class="row"><td>18.10.2026 12:45</td><td class="center">15.8</td></tr>
    <tr class="row2"><td>18.10.2026 12:30</td><td class="center">15.8</td></tr>
    <tr class="row"><td>18.10.2026 12:15</td><td class="center">15,9</td></tr>
  </tbody>
</table>
"""


def test_parse_reads_rows_newest_first_in_local_time():
    readings = gkd.parse(PAGE)
    assert [r.celsius for r in readings] == [15.8, 15.8, 15.9]
    # 18 October is still summer time (UTC+2).
    assert readings[0].time == datetime(2026, 10, 18, 10, 45, tzinfo=timezone.utc)


def test_parse_winter_time():
    page = "<tr><td>15.01.2027 08:00</td><td>3.4</td></tr>"
    assert gkd.parse(page)[0].time == datetime(2027, 1, 15, 7, 0, tzinfo=timezone.utc)


def test_latest_ignores_stale_station():
    newest = datetime(2026, 10, 18, 10, 45, tzinfo=timezone.utc)
    assert gkd.latest(PAGE, newest + timedelta(hours=1)).celsius == 15.8
    assert gkd.latest(PAGE, newest + timedelta(hours=7)) is None


def test_page_without_values():
    assert gkd.latest("<p>Keine Daten</p>", datetime.now(timezone.utc)) is None


def test_hourly_keeps_the_first_reading_of_each_hour_oldest_first():
    readings = gkd.parse(PAGE.replace("18.10.2026 12:45", "18.10.2026 13:05"))
    hours = gkd.hourly(readings)
    assert [(r.time.hour, r.celsius) for r in hours] == [(12, 15.9), (13, 15.8)]


def test_failed_fetch_keeps_the_last_good_reading(monkeypatch):
    import asyncio

    import httpx

    from rowfrog import api

    reading = gkd.WaterTemperature(datetime(2026, 10, 18, 5, 45, tzinfo=timezone.utc), 12.8)
    pages = iter([(reading, [reading])])

    async def flaky(client, station, now, kind="lake"):
        try:
            return next(pages)
        except StopIteration:
            raise httpx.ConnectTimeout("GKD did not answer")

    async def no_wait(_):
        pass

    monkeypatch.setattr(api.gkd, "fetch_recent", flaky)
    monkeypatch.setattr(api.asyncio, "sleep", no_wait)
    now = datetime(2026, 10, 18, 6, tzinfo=timezone.utc)
    assert asyncio.run(api._water(None, api.water_stations.Station("gkd", "starnberg-16663002"), now))[0] == reading
    # GKD fails twice: the reading from the last run stands in, until it is too old.
    assert asyncio.run(api._water(None, api.water_stations.Station("gkd", "starnberg-16663002"), now))[0] == reading
    assert asyncio.run(api._water(None, api.water_stations.Station("gkd", "starnberg-16663002"), now + timedelta(hours=7))) == (None, [])


def test_rejected_page_is_asked_once_and_the_last_reading_stands_in(monkeypatch):
    import asyncio

    from rowfrog import api

    reading = gkd.WaterTemperature(datetime(2026, 10, 18, 5, 45, tzinfo=timezone.utc), 12.8)
    station = api.water_stations.Station("gkd", "starnberg-16663002")
    api.prepared.last_water[station.key] = (reading, [reading])
    asked = []

    async def rejected(client, station, now, kind="lake"):
        asked.append(station)
        raise gkd.Rejected("GKD firewall rejected the request")

    monkeypatch.setattr(api.gkd, "fetch_recent", rejected)
    now = datetime(2026, 10, 18, 6, tzinfo=timezone.utc)
    # Three clubs read Starnberg: GKD is asked once, without a retry, and the kept reading stands in.
    for _ in range(3):
        assert asyncio.run(api._water(None, station, now))[0] == reading
    assert asked == ["starnberg-16663002"]


def test_clubs_on_one_station_share_its_answer(monkeypatch):
    import asyncio

    from rowfrog import api

    reading = gkd.WaterTemperature(datetime(2026, 10, 18, 5, 45, tzinfo=timezone.utc), 12.8)
    asked = []

    async def answer(client, station, now, kind="lake"):
        asked.append(station)
        return reading, [reading]

    monkeypatch.setattr(api.gkd, "fetch_recent", answer)
    now = datetime(2026, 10, 18, 6, tzinfo=timezone.utc)
    station = api.water_stations.Station("gkd", "starnberg-16663002")
    assert asyncio.run(api._water(None, station, now))[0] == reading
    assert asyncio.run(api._water(None, station, now))[0] == reading
    assert len(asked) == 1


def test_failed_level_fetch_keeps_the_last_good_levels(monkeypatch):
    import asyncio

    from rowfrog import api, lake_level

    lake = next(iter(lake_level._load().values()))
    levels = [(datetime(2026, 10, 18, 5, 0, tzinfo=timezone.utc), 780.1), (datetime(2026, 10, 18, 5, 45, tzinfo=timezone.utc), 780.2)]
    answers = iter([levels])

    async def flaky(client, station):
        try:
            return next(answers)
        except StopIteration:
            raise gkd.Rejected("GKD firewall rejected the request")

    monkeypatch.setattr(api.gkd, "fetch_levels", flaky)
    assert asyncio.run(api._lake_levels(None, lake)) == levels
    api._gauge_cache.clear()  # the next run starts without the in-memory cache
    assert asyncio.run(api._lake_levels(None, lake)) == levels
    api._gauge_cache.clear()
    api.prepared.last_levels[lake.station] = [(datetime(2026, 10, 16, 5, 0, tzinfo=timezone.utc), 780.0)]
    assert asyncio.run(api._lake_levels(None, lake)) is None  # older than a day


def test_a_station_that_fails_is_asked_once_per_run_and_the_kept_reading_stands_in(monkeypatch):
    """Any failure (timeout, server error), not only GKD's firewall: the next
    club or lake view of the same run takes the kept reading instead of asking
    the station again."""
    import asyncio

    import httpx

    from rowfrog import api

    kept = gkd.WaterTemperature(datetime(2026, 10, 18, 4, 0, tzinfo=timezone.utc), 12.1)
    asked = []

    async def down(client, station_id, now):
        asked.append(station_id)
        raise httpx.ConnectTimeout("timed out")

    async def no_sleep(_):
        return None

    monkeypatch.setattr(api.pegelonline, "fetch_recent", down)
    monkeypatch.setattr(api.asyncio, "sleep", no_sleep)
    api.prepared.last_water["pegelonline:abc"] = (kept, [kept])
    now = datetime(2026, 10, 18, 6, tzinfo=timezone.utc)
    station = api.water_stations.Station("pegelonline", "abc")
    for _ in range(3):  # three clubs on the same station
        assert asyncio.run(api._water(None, station, now))[0] == kept
    assert len(asked) == 2  # the first club's two tries, nobody after it


def test_a_failing_lake_level_is_asked_once_per_run(monkeypatch):
    import asyncio

    import httpx

    from rowfrog import api, lake_level

    lake = next(iter(lake_level._load().values()))
    asked = []

    async def down(client, station):
        asked.append(station)
        raise httpx.ReadTimeout("timed out")

    monkeypatch.setattr(api.gkd, "fetch_levels", down)
    for _ in range(3):
        assert asyncio.run(api._lake_levels(None, lake)) is None
    assert len(asked) == 1


def test_each_network_counts_what_its_stations_did_in_the_run(monkeypatch):
    """The publisher's water lines (one per network): stations asked, requests
    sent, readings got and what was skipped, so a log shows whether each
    station was asked at most once a run (#414)."""
    import asyncio

    import httpx

    from rowfrog import api

    api.reset_water_counts()
    now = datetime(2026, 10, 18, 6, tzinfo=timezone.utc)
    reading = gkd.WaterTemperature(datetime(2026, 10, 18, 5, 45, tzinfo=timezone.utc), 12.8)
    kept = gkd.WaterTemperature(datetime(2026, 10, 18, 4, 0, tzinfo=timezone.utc), 12.1)

    async def gkd_page(client, station_id, now, kind="lake"):
        if station_id == "walled":
            raise gkd.Rejected("GKD firewall rejected the request")
        return reading, [reading]

    async def down(client, station_id, now):
        raise httpx.ConnectTimeout("timed out")

    async def no_sleep(_):
        return None

    monkeypatch.setattr(api.gkd, "fetch_recent", gkd_page)
    monkeypatch.setattr(api.pegelonline, "fetch_recent", down)
    monkeypatch.setattr(api.asyncio, "sleep", no_sleep)
    api.prepared.last_water["gkd:walled"] = (kept, [kept])
    for _ in range(3):  # three clubs on each station
        for station in (api.water_stations.Station("gkd", "good"), api.water_stations.Station("gkd", "walled"),
                        api.water_stations.Station("pegelonline", "abc")):
            asyncio.run(api._water(None, station, now))

    g, p, b = (api.water_counts[n] for n in ("gkd", "pegelonline", "bafu"))
    assert (len(g.asked), sum(g.requests.values()), len(g.readings), len(g.kept)) == (2, 2, 2, 1)
    assert g.failed == {"gkd:walled"} and g.paused == {"gkd:walled"} and not g.after_failure
    assert (len(p.asked), sum(p.requests.values()), len(p.readings)) == (1, 2, 0)
    assert p.failed == p.after_failure == {"pegelonline:abc"}
    assert g.line("gkd") == (
        "GKD: 2 stations asked, 2 requests (at most 1 per station), 2 with a value"
        " (newest 18 Oct 05:45 UTC, oldest 18 Oct 04:00 UTC), 1 of them the last good reading, 1 failed,"
        " 1 skipped (firewall pause), 0 skipped (recent failure)"
    )
    assert p.line("pegelonline").startswith("PEGELONLINE: 1 stations asked, 2 requests (at most 2 per station), 0 with a value,")
    assert b.line("bafu").startswith("BAFU: 0 stations asked, 0 requests")
    api.reset_water_counts()
