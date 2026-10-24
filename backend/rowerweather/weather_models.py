"""Which weather model a location's forecast comes from.

Each region has a chain: the best local model for the first hours, then
longer-range models. Every club is in Germany today, so there is one chain;
other regions are added once the model check (scripts/model_check.py) has
shown which model does best there. The app shows the chain as the forecast
source line at the bottom of a club page.
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

# icon_seamless on Open-Meteo: ICON-D2 for about two days, then ICON-EU, then global ICON.
GERMANY = Chain("germany", "icon_seamless", (Part(ICON_D2, 0, 48), Part(ICON_EU, 48, 120), Part(ICON, 120, 180)))


def chain_for(lat: float, lon: float) -> Chain:
    return GERMANY


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
