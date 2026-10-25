"""Which clubs and lakes are in use, and how many outside calls the jobs make.

Talks to the usage counter on api.rowfrog.com (cloudflare/usage/). The
forecast job asks used() for the clubs and lakes loaded in the last days and
refreshes those more often; every job reports its calls with report_calls(),
so scripts/budget_check.py can warn before Open-Meteo's or Copernicus' free
limits are reached. Needs the env RW_USAGE_KEY (GitHub secret USAGE_KEY);
without it, or when the counter does not answer, used() returns None and
report_calls() does nothing, so the jobs keep their fixed schedule.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass

import httpx

BASE_URL = os.environ.get("RW_USAGE_URL", "https://api.rowfrog.com")
log = logging.getLogger(__name__)


@dataclass(frozen=True)
class Usage:
    days: int
    clubs: dict[str, int]  # id -> loads
    lakes: dict[str, int]


def _key() -> str | None:
    return os.environ.get("RW_USAGE_KEY") or None


def call_weight(variables: int, models: int = 1, days: float = 2, locations: int = 1) -> float:
    """Open-Meteo's count for one request: more than 10 variables (times models)
    or more than 2 weeks count as several calls, each location separately."""
    weight = variables * max(models, 1) / 10
    return max(1.0, weight, weight * days / 14) * locations


def used(days: int = 7, client: httpx.Client | None = None) -> Usage | None:
    key = _key()
    if not key:
        return None
    try:
        c = client or httpx.Client()
        resp = c.get(f"{BASE_URL}/usage", params={"days": days}, headers={"Authorization": f"Bearer {key}"}, timeout=20)
        resp.raise_for_status()
        body = resp.json()
        return Usage(body["days"], dict(body["clubs"]), dict(body["lakes"]))
    except (httpx.HTTPError, ValueError, KeyError) as e:
        log.warning("usage counter: %s", e)
        return None


def report_calls(service: str, calls: float, job: str, client: httpx.Client | None = None) -> bool:
    key = _key()
    if not key or calls <= 0:
        return False
    try:
        c = client or httpx.Client()
        resp = c.post(
            f"{BASE_URL}/budget",
            json={"service": service, "job": job, "calls": round(calls, 2)},
            headers={"Authorization": f"Bearer {key}"},
            timeout=20,
        )
        resp.raise_for_status()
        return True
    except httpx.HTTPError as e:
        log.warning("usage counter: %s", e)
        return False


def budget(days: int = 35, client: httpx.Client | None = None) -> list[dict] | None:
    """Rows of {day, service, job, calls} for the last days."""
    key = _key()
    if not key:
        return None
    try:
        c = client or httpx.Client()
        resp = c.get(f"{BASE_URL}/budget", params={"days": days}, headers={"Authorization": f"Bearer {key}"}, timeout=20)
        resp.raise_for_status()
        return list(resp.json()["rows"])
    except (httpx.HTTPError, ValueError, KeyError) as e:
        log.warning("usage counter: %s", e)
        return None
