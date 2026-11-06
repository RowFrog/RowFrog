from datetime import datetime, timezone

import pytest

from rowfrog import api


@pytest.fixture(autouse=True)
def fixed_clock(monkeypatch):
    """The endpoints show the forecast from the current hour on; the sample forecasts start on 18 Oct 2026."""
    monkeypatch.setattr(api, "_now", lambda: datetime(2026, 10, 18, 6, tzinfo=timezone.utc))


@pytest.fixture(autouse=True)
def no_saved_water():
    """A water reading or lake level kept by one test must not stand in for another's."""
    for kept in (api.prepared.last_water, api.prepared.last_levels, api._water_cache, api._gkd_rejected_until, api._failed_at):
        kept.clear()
    yield
    for kept in (api.prepared.last_water, api.prepared.last_levels, api._water_cache, api._gkd_rejected_until, api._failed_at):
        kept.clear()


@pytest.fixture(autouse=True)
def no_river_gauges(monkeypatch):
    """Clubs on federal waterways and Swiss rivers read PEGELONLINE and BAFU; tests stay offline."""

    async def quiet(client, station, now):
        return None, []

    monkeypatch.setattr(api.pegelonline, "fetch_recent", quiet)
    monkeypatch.setattr(api.bafu, "fetch_recent", quiet)


@pytest.fixture(autouse=True)
def no_paused_sources(monkeypatch):
    """Calls that failed in one test must not pause Open-Meteo or the daily temperatures for the next."""
    from rowfrog.sources import open_meteo

    monkeypatch.setattr(api, "_air_days_failed", 0)
    monkeypatch.setattr(api, "_air_days_paused_until", 0.0)
    monkeypatch.setattr(open_meteo, "_failed_in_row", 0)
    monkeypatch.setattr(open_meteo, "_down_until", 0.0)


@pytest.fixture(autouse=True)
def quick_radar_retries(monkeypatch):
    """A radar reading that fails is asked again without the real pause."""
    from rowfrog.sources import dwd_radar

    monkeypatch.setattr(dwd_radar, "RETRY_SECONDS", 0.0)
