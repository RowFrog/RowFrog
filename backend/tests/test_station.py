from rowfrog import api, locations


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
    station = api._station_json(lakes["l"])
    assert station == {
        "name": "Town",
        "lat": 48.01,
        "lon": 11.02,
        "distanceM": None,
        "url": "https://www.gkd.bayern.de/en/lakes/watertemperature/bayern/town-123/current-values",
    }
    assert api._station_json(lakes["m"]) is None
