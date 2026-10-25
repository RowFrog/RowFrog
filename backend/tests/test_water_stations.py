import asyncio
from datetime import datetime, timezone

from rowfrog import api, water_stations
from rowfrog.sources import bafu, pegelonline


def test_each_club_reads_its_nearest_station():
    data = api._locations
    # Ammersee has no station of its own in locations.json; both clubs read Stegen.
    herrsching = water_stations.for_club(data.clubs["tsv-herrsching-abt-wassersport"], data.lakes["ammersee"])
    assert (herrsching.network, herrsching.id, herrsching.kind) == ("gkd", "stegen-16602008", "lake")
    assert herrsching.distance_km == 11.7
    # Bodensee: the clubs nearest to Lindau read it, the far western clubs do not.
    arbon = data.clubs["seeclub-arbon"]
    assert water_stations.for_club(arbon, data.lakes[arbon.lake_id]).id == "lindau-20001001"
    near = ("seeclub-arbon", "seeclub-rorschach", "ruderverein-wiking-bregenz", "ruderverein-friedrichshafen")
    assert all(water_stations.for_club(data.clubs[c], data.lakes["bodensee"]).id == "lindau-20001001" for c in near)
    far = [c for c in data.clubs_on(arbon.lake_id) if c.id not in near]
    assert far and all(water_stations.for_club(c, data.lakes[c.lake_id]) is None for c in far)
    # A river station on the Main.
    wuerzburg = water_stations.for_club(data.clubs["akademischer-ruderclub-wuerzburg"], data.lakes["river-main"])
    assert (wuerzburg.network, wuerzburg.kind) == ("gkd", "river")
    # The lake view of the Ammersee uses the lake station a club reads.
    lake_station = water_stations.for_lake(data.lakes["ammersee"], data.clubs_on("ammersee"))
    assert lake_station.id == "stegen-16602008"
    assert water_stations.for_lake(data.lakes["starnberger-see"]).id == "starnberg-16663002"


def test_only_used_networks_are_listed():
    networks = {s.network for s in water_stations._load().values()}
    assert networks == {"gkd", "pegelonline", "bafu"}


def test_pegelonline_rows_newest_first():
    rows = [
        {"timestamp": "2026-10-25T11:45:00+02:00", "value": 11.7},
        {"timestamp": "2026-10-25T12:00:00+02:00", "value": 11.8},
        {"timestamp": "2026-10-25T12:15:00+02:00", "value": None},
    ]
    found = pegelonline.parse(rows)
    assert [r.celsius for r in found] == [11.8, 11.7]
    assert found[0].time == datetime(2026, 10, 25, 10, tzinfo=timezone.utc)


def test_pegelonline_station_credit_and_place(monkeypatch):
    reading = pegelonline.WaterTemperature(datetime(2026, 10, 18, 5, 45, tzinfo=timezone.utc), 12.4)

    async def gauge(client, station, now):
        return reading, [reading]

    monkeypatch.setattr(api.pegelonline, "fetch_recent", gauge)
    club = next(c for c, s in water_stations._load().items() if s.network == "pegelonline")
    station = water_stations._load()[club]
    assert asyncio.run(api._water(None, station, datetime(2026, 10, 18, 6, tzinfo=timezone.utc)))[0] == reading
    assert api._water_station_json(station) == {"network": "pegelonline", "name": station.name, "distanceKm": station.distance_km}
    assert api._water_station_json(water_stations.Station("gkd", "starnberg-16663002")) is None


def test_bafu_values_newest_first_and_credited(monkeypatch):
    payload = [
        {"timestamp": 1792922400, "loc": "2135", "par": "temperature", "val": 10.9},
        {"timestamp": 1792923000, "loc": "2135", "par": "temperature", "val": 11.0},
        {"timestamp": 1792923000, "loc": "2135", "par": "flow", "val": 120.0},
    ]
    found = bafu.parse(payload)
    assert [r.celsius for r in found] == [11.0, 10.9]
    bern = api._locations.clubs["rowing-club-bern"]
    station = water_stations.for_club(bern, api._locations.lakes[bern.lake_id])
    assert (station.network, station.id) == ("bafu", "2135")
    assert api.STATION_CREDIT["bafu"].startswith("Water temperature: Bundesamt für Umwelt BAFU")
