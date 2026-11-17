"""What the publishing job loads ahead, in bulk, for the forecast code.

scripts/publish_static.py asks Open-Meteo, DWD and the satellites once for
many clubs and lakes, then hands the answers over here; the forecast code
(api.py) takes a club's entry instead of asking again, and asks itself for
anything missing. Running the API on its own (uvicorn, tests) leaves all of
this empty.

Until November 2026 these were ten private globals in api.py that the
publisher filled from outside; one named object keeps a rename from breaking
the publishing job without a test noticing (code review finding 4).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date


@dataclass
class Prepared:
    # Forecast hours per club (and per "club@model" for the model choices), used once.
    weather: dict[str, list] = field(default_factory=dict)
    # The same for the lake view's sample points, per lake.
    lake_weather: dict[str, list] = field(default_factory=dict)
    # The 8-day outlook behind the conditions charts; None means "none this
    # time" (the app then charts the next 48 hours), a missing club loads it.
    outlook: dict[str, list | None] = field(default_factory=dict)
    # Local DWD warnings per club; a missing club asks DWD itself.
    local_warnings: dict[str, list] = field(default_factory=dict)
    # The last good warnings check per club: (checked at, block for the app, warnings in force),
    # kept between runs so one failed DWD answer does not blank the card (api._kept_warnings).
    last_warnings: dict[str, tuple] = field(default_factory=dict)
    # Forecast points per lake where it differs from lake_view.MAX_SAMPLES (lakes people look at).
    lake_samples: dict[str, int] = field(default_factory=dict)
    # Satellite lake ice passes per lake (sources.lake_ice_satellite).
    satellite_ice: dict[str, list] = field(default_factory=dict)
    # Satellite lake temperature readings per lake (sources.lake_temperature_satellite).
    satellite_water: dict[str, list] = field(default_factory=dict)
    # The last good reading and history per water station (water_stations.Station.key),
    # kept between runs so one failed fetch does not blank the water temperature.
    last_water: dict[str, tuple] = field(default_factory=dict)
    # The same for a lake gauge's levels (lake_level.LevelLake.station -> levels, oldest first).
    last_levels: dict[str, list] = field(default_factory=dict)
    # Daily mean air temperatures per lake, loaded once a (German) day: (day, temperatures).
    ice_temps: dict[str, tuple[date, list]] = field(default_factory=dict)
