"""Checks the jobs' call totals against the free limits of the outside services.

Used by scripts/budget_check.py with the rows from usage.budget(). Warns at
70 % of a limit and raises an alert at 85 %, both for the busiest recent day
and for the month as projected from the last week, and says how many days
are left at the current growth.
"""

from __future__ import annotations

import calendar
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone

# Free limits: Open-Meteo's non-commercial API (open-meteo.com/en/pricing),
# the free Copernicus Data Space account (about 10,000 Sentinel Hub requests a
# month) and Cloudflare's free Workers plan (100,000 Worker requests a day for
# the whole account; D1 100,000 rows written and 5 million read a day; R2
# 1 million class A and 10 million class B operations a month).
LIMITS = {
    "open-meteo": {"day": 10_000, "month": 300_000},
    "copernicus": {"month": 10_000},
    "cloudflare-workers": {"day": 100_000},
    "cloudflare-d1-writes": {"day": 100_000},
    "cloudflare-d1-reads": {"day": 5_000_000},
    "cloudflare-r2-writes": {"month": 1_000_000},
    "cloudflare-r2-reads": {"month": 10_000_000},
}
WARN = 0.70
ALERT = 0.85
LEVELS = ("ok", "warn", "alert")


# Names for people (budget-latest.json, the Pi's RowFrog tile).
NAMES = {
    "open-meteo": "Weather API (Open-Meteo)",
    "copernicus": "Satellite pictures (Copernicus)",
    "cloudflare-workers": "Worker requests",
    "cloudflare-d1-writes": "D1 rows written",
    "cloudflare-d1-reads": "D1 rows read",
    "cloudflare-r2-writes": "R2 writes (class A)",
    "cloudflare-r2-reads": "R2 reads (class B)",
}


@dataclass(frozen=True)
class Finding:
    service: str
    level: str  # ok, warn, alert
    text: str
    # For a limit check: "day" (busiest of the last 7 full days) or "month" (projected),
    # with the calls and the limit they are measured against. Empty for other findings.
    period: str = ""
    used: float = 0.0
    limit: int = 0


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
        if service.startswith("cloudflare") and not totals:
            continue  # read from Cloudflare, not reported by the jobs; budget_check says when it failed
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
                "day", busiest, limits["day"],
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
                "month", projected, limits["month"],
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
        "refresh unused clubs less often, or take Open-Meteo's paid plan (see the regional weather models doc); "
        "for Cloudflare, count each club once an hour instead of on every load, or take Workers Paid.",
    ]
    return "\n".join(lines)


def summary(findings: list[Finding] | None, now: datetime) -> dict:
    """The check's numbers as data (budget-latest.json on the Pi, read by its RowFrog tile).
    `findings` None: the usage counter did not answer."""
    services = [
        {"key": f.service, "name": NAMES.get(f.service, f.service), "period": f.period,
         "used": round(f.used), "limit": f.limit, "share": round(f.used / f.limit, 4), "level": f.level, "unit": "calls"}
        for f in findings or [] if f.period
    ]
    notes = [{"key": f.service, "level": f.level, "text": f.text} for f in findings or [] if not f.period and f.level != "ok"]
    if findings is None:
        notes.append({"key": "usage-counter", "level": "warn", "text": "The usage counter did not answer, or RW_USAGE_KEY is not set."})
    level = worst(findings or []) if findings is not None else "warn"
    return {
        "version": 1,
        "time": now.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "level": level,
        "warn_from": WARN,
        "alert_from": ALERT,
        "services": services,
        "notes": notes,
    }
