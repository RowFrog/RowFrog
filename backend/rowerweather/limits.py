"""Checks the jobs' call totals against the free limits of the outside services.

Used by scripts/budget_check.py with the rows from usage.budget(). Warns at
70 % of a limit and raises an alert at 85 %, both for the busiest recent day
and for the month as projected from the last week, and says how many days
are left at the current growth.
"""

from __future__ import annotations

import calendar
from dataclasses import dataclass
from datetime import date, timedelta

# Free limits: Open-Meteo's non-commercial API (open-meteo.com/en/pricing) and
# the free Copernicus Data Space account (about 10,000 Sentinel Hub requests a month).
LIMITS = {
    "open-meteo": {"day": 10_000, "month": 300_000},
    "copernicus": {"month": 10_000},
}
WARN = 0.70
ALERT = 0.85
LEVELS = ("ok", "warn", "alert")


@dataclass(frozen=True)
class Finding:
    service: str
    level: str  # ok, warn, alert
    text: str


def _level(share: float) -> str:
    return "alert" if share >= ALERT else "warn" if share >= WARN else "ok"


def per_day(rows: list[dict], service: str) -> dict[date, float]:
    totals: dict[date, float] = {}
    for r in rows:
        if r["service"] == service:
            d = date.fromisoformat(r["day"])
            totals[d] = totals.get(d, 0.0) + float(r["calls"])
    return totals


def check(rows: list[dict], today: date) -> list[Finding]:
    findings = []
    for service, limits in LIMITS.items():
        totals = per_day(rows, service)
        complete = [today - timedelta(days=i) for i in range(1, 8)]  # the last 7 full days
        last7 = [totals.get(d, 0.0) for d in complete]
        prev7 = [totals.get(today - timedelta(days=i), 0.0) for i in range(8, 15)]
        if not any(totals.get(today - timedelta(days=i)) for i in range(0, 3)):
            findings.append(Finding(service, "warn", f"{service}: no calls reported for 2 days. Is the usage counter set up and the job running?"))
            continue
        avg = sum(last7) / 7
        if "day" in limits:
            busiest = max(last7)
            share = busiest / limits["day"]
            findings.append(Finding(
                service, _level(share),
                f"{service}: busiest day of the last week {busiest:,.0f} calls = {share:.0%} of {limits['day']:,} a day.",
            ))
            growth = (avg - sum(prev7) / 7) / 7 if any(prev7) else 0.0
            room = ALERT * limits["day"] - avg
            if growth > 0 and room > 0:
                findings.append(Finding(
                    service, "ok" if room / growth > 60 else "warn",
                    f"{service}: growing by about {growth:,.0f} calls a day each day; {ALERT:.0%} of the daily limit in about {room / growth:,.0f} days.",
                ))
        if "month" in limits:
            month_days = calendar.monthrange(today.year, today.month)[1]
            so_far = sum(v for d, v in totals.items() if d.year == today.year and d.month == today.month and d < today)
            projected = so_far + avg * (month_days - today.day + 1)
            share = projected / limits["month"]
            findings.append(Finding(
                service, _level(share),
                f"{service}: this month projected {projected:,.0f} calls = {share:.0%} of {limits['month']:,} a month.",
            ))
    return findings


def worst(findings: list[Finding]) -> str:
    return max((f.level for f in findings), key=LEVELS.index, default="ok")


def report(findings: list[Finding], today: date) -> str:
    marks = {"ok": "OK", "warn": "Warning", "alert": "ALERT"}
    lines = [f"# Usage limits, {today.isoformat()}", "", f"Overall: **{marks[worst(findings)]}**", ""]
    lines += [f"- {marks[f.level]}: {f.text}" for f in findings]
    lines += [
        "",
        f"Warning from {WARN:.0%} of a limit, alert from {ALERT:.0%}. Next steps when it rises: "
        "refresh unused clubs less often, or take Open-Meteo's paid plan (see the regional weather models doc).",
    ]
    return "\n".join(lines)
