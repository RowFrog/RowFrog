from datetime import datetime, timedelta, timezone

from rowerweather.sources import gkd

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
