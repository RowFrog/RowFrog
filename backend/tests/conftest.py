from datetime import datetime, timezone

import pytest

from rowerweather import api


@pytest.fixture(autouse=True)
def fixed_clock(monkeypatch):
    """The endpoints show the forecast from the current hour on; the sample forecasts start on 18 Oct 2026."""
    monkeypatch.setattr(api, "_now", lambda: datetime(2026, 10, 18, 6, tzinfo=timezone.utc))
