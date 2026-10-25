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
