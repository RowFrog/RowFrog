from rowfrog import api, locations, water_stations


def test_station_place_from_locations_json():
    raw = {
        "lakes": [
            {
                "id": "l",
                "name": "Lake",
                "center": {"lat": 48.0, "lon": 11.0},
                "gkdWaterTemperatureStation": "town-123",
                "gkdStationPlace": {"name": "Town", "lat": 48.01, "lon": 11.02},
            },
            {"id": "m", "name": "Other", "center": {"lat": 48.0, "lon": 11.0}},
        ],
        "clubs": [],
    }
    lakes: dict = {}
    locations._parse(raw, lakes, {})
    station = api._water_station_json(water_stations.Station("gkd", "town-123"), lakes["l"])
    assert station == {
        "network": "gkd",
        "name": "Town",
        "lat": 48.01,
        "lon": 11.02,
        "distanceKm": None,
        "distanceM": None,
        "url": "https://www.gkd.bayern.de/en/lakes/watertemperature/bayern/town-123/current-values",
    }
    assert api._water_station_json(None, lakes["m"]) is None
