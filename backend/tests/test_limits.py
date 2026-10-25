from datetime import date, timedelta

from rowfrog import limits
from rowfrog.usage import call_weight

TODAY = date(2026, 11, 20)


def _rows(per_day, service="open-meteo", days=14):
    return [{"day": (TODAY - timedelta(days=i)).isoformat(), "service": service, "job": "publish", "calls": per_day(i)} for i in range(days + 1)]


def test_call_weight_follows_open_meteo():
    assert call_weight(5) == 1.0
    assert call_weight(15) == 1.5
    assert call_weight(15, locations=50) == 75.0
    assert call_weight(5, models=10) == 5.0
    assert call_weight(1, days=99) == 1.0  # 1 variable: 0.1 x 7.07 is still under one call
    assert round(call_weight(15, days=28), 2) == 3.0


def test_quiet_use_is_ok():
    rows = _rows(lambda i: 5000) + _rows(lambda i: 100, service="copernicus")
    findings = limits.check(rows, TODAY)
    assert limits.worst(findings) == "ok"


def test_busy_day_warns_and_growth_gives_days_left():
    rows = _rows(lambda i: 7500 if i == 2 else 6000 - 50 * i) + _rows(lambda i: 100, service="copernicus")
    findings = limits.check(rows, TODAY)
    om = [f for f in findings if f.service == "open-meteo"]
    assert om[0].level == "warn" and "75%" in om[0].text
    assert any("days." in f.text for f in om)


def test_month_projection_alerts():
    rows = _rows(lambda i: 2000) + _rows(lambda i: 400, service="copernicus", days=25)
    cop = [f for f in limits.check(rows, TODAY) if f.service == "copernicus"]
    assert cop[-1].level == "alert"  # about 12,000 projected of 10,000


def test_missing_counts_warn():
    findings = limits.check(_rows(lambda i: 3000), TODAY)
    assert [f.level for f in findings if f.service == "copernicus"] == ["warn"]
    assert "no calls reported" in limits.report(findings, TODAY)
