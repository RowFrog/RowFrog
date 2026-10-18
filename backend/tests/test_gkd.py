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


def test_parse_reads_rows_newest_first_in_cet():
    readings = gkd.parse(PAGE)
    assert [r.celsius for r in readings] == [15.8, 15.8, 15.9]
    assert readings[0].time == datetime(2026, 10, 18, 11, 45, tzinfo=timezone.utc)


def test_latest_ignores_stale_station():
    newest = datetime(2026, 10, 18, 11, 45, tzinfo=timezone.utc)
    assert gkd.latest(PAGE, newest + timedelta(hours=1)).celsius == 15.8
    assert gkd.latest(PAGE, newest + timedelta(hours=7)) is None


def test_page_without_values():
    assert gkd.latest("<p>Keine Daten</p>", datetime.now(timezone.utc)) is None
