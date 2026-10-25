from datetime import datetime, timezone

import pytest

from rowfrog import api


@pytest.fixture(autouse=True)
def fixed_clock(monkeypatch):
    """The endpoints show the forecast from the current hour on; the sample forecasts start on 18 Oct 2026."""
    monkeypatch.setattr(api, "_now", lambda: datetime(2026, 10, 18, 6, tzinfo=timezone.utc))


@pytest.fixture(autouse=True)
def no_saved_water():
    """A water reading kept by one test must not stand in for another's."""
    api._last_water.clear()
    yield
    api._last_water.clear()


@pytest.fixture(autouse=True)
def no_river_gauges(monkeypatch):
    """Clubs on federal waterways and Swiss rivers read PEGELONLINE and BAFU; tests stay offline."""

    async def quiet(client, station, now):
        return None, []

    monkeypatch.setattr(api.pegelonline, "fetch_recent", quiet)
    monkeypatch.setattr(api.bafu, "fetch_recent", quiet)
