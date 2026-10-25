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
