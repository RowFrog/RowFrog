"""Which weather model a location's forecast comes from.

Each region has a chain: the best local model for the first hours, then
longer-range models. Every club is in Germany today, so there is one chain;
other regions are added once the model check (scripts/model_check.py) has
shown which model does best there. The app shows the chain as the forecast
source line at the bottom of a club page.

A few other models per region can be picked instead (CHOICES). This is a
test, hidden behind the app's developer options, and only the confirmed clubs
get these forecasts, because each model costs extra Open-Meteo calls. A
picked model is used as far ahead as it reaches; the automatic chain fills
the hours after that.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Model:
    name: str  # as shown in the app
    provider: str
    resolution_km: float


@dataclass(frozen=True)
class Part:
    model: Model
    from_hour: int
    to_hour: int


@dataclass(frozen=True)
class Chain:
    region: str
    open_meteo: str  # the Open-Meteo `models` value that gives this chain
    parts: tuple[Part, ...]

    def covering(self, hours: int) -> list[Part]:
        """The parts that a forecast of `hours` hours actually uses."""
        return [p for p in self.parts if p.from_hour < hours]


ICON_D2 = Model("ICON-D2", "Deutscher Wetterdienst (DWD)", 2.2)
ICON_EU = Model("ICON-EU", "Deutscher Wetterdienst (DWD)", 7.0)
ICON = Model("ICON", "Deutscher Wetterdienst (DWD)", 13.0)

ICON_CH1 = Model("ICON-CH1", "MeteoSwiss", 1.1)
AROME_AT = Model("AROME", "GeoSphere Austria", 2.5)
IFS = Model("IFS", "ECMWF", 25.0)

# icon_seamless on Open-Meteo: ICON-D2 for about two days, then ICON-EU, then global ICON.
GERMANY = Chain("germany", "icon_seamless", (Part(ICON_D2, 0, 48), Part(ICON_EU, 48, 120), Part(ICON, 120, 180)))




@dataclass(frozen=True)
class Choice:
    id: str  # the Open-Meteo `models` value, also used in the forecast's path
    model: Model
    hours: int  # how far ahead the model reaches
    advice: str  # "ok" or "notAdvised"; the automatic chain is always the recommended one
    note: str  # English; the app translates it


CHOICES = {
    "germany": (
        Choice(
            "meteoswiss_icon_ch1",
            ICON_CH1,
            33,
            "ok",
            "The finest grid near the Alps. It reaches 33 hours ahead; the hours after that come from the automatic choice.",
        ),
        Choice(
            "geosphere_arome_austria",
            AROME_AT,
            60,
            "ok",
            "Good with wind in the Alpine foothills. A little coarser than ICON-D2.",
        ),
        Choice(
            "ecmwf_ifs025",
            IFS,
            240,
            "notAdvised",
            "Very coarse grid: it does not see the lake or the hills, so the wind on the water is often wrong.",
        ),
    ),
}


def chain_for(lat: float, lon: float) -> Chain:
    return GERMANY


def choices_for(lat: float, lon: float) -> tuple[Choice, ...]:
    return CHOICES.get(chain_for(lat, lon).region, ())


def choice(lat: float, lon: float, model_id: str) -> Choice | None:
    return next((c for c in choices_for(lat, lon) if c.id == model_id), None)


def choices_json(lat: float, lon: float) -> list[dict]:
    return [
        {
            "id": c.id,
            "model": c.model.name,
            "provider": c.model.provider,
            "resolutionKm": c.model.resolution_km,
            "hours": c.hours,
            "advice": c.advice,
            "note": c.note,
        }
        for c in choices_for(lat, lon)
    ]


def picked_source_json(chain: Chain, picked: Choice, hours: int) -> dict:
    """The source line for a picked model: that model first, then the chain after it ends."""
    first = min(picked.hours, hours)
    parts = [
        {
            "model": picked.model.name,
            "provider": picked.model.provider,
            "resolutionKm": picked.model.resolution_km,
            "fromHour": 0,
            "toHour": first,
        }
    ]
    for p in chain.covering(hours):
        if p.to_hour > first:
            parts.append(
                {
                    "model": p.model.name,
                    "provider": p.model.provider,
                    "resolutionKm": p.model.resolution_km,
                    "fromHour": max(p.from_hour, first),
                    "toHour": min(p.to_hour, hours),
                }
            )
    return {"region": chain.region, "picked": picked.id, "parts": parts}


def source_json(chain: Chain, hours: int) -> dict:
    return {
        "region": chain.region,
        "parts": [
            {
                "model": p.model.name,
                "provider": p.model.provider,
                "resolutionKm": p.model.resolution_km,
                "fromHour": p.from_hour,
                "toHour": min(p.to_hour, hours),
            }
            for p in chain.covering(hours)
        ],
    }
