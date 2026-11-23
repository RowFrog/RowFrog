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


def test_cloudflare_figures_warn_near_the_free_plan():
    from rowfrog import cloudflare_usage

    answer = {"data": {"viewer": {"accounts": [{
        "workersInvocationsAdaptive": [
            {"dimensions": {"date": (TODAY - timedelta(days=i)).isoformat()}, "sum": {"requests": 80_000 if i == 1 else 1000}} for i in range(8)
        ],
        "d1AnalyticsAdaptiveGroups": [
            {"dimensions": {"date": (TODAY - timedelta(days=i)).isoformat()}, "sum": {"rowsWritten": 500, "rowsRead": 900}} for i in range(8)
        ],
    }]}}}
    cf = cloudflare_usage.parse(answer)
    rows = _rows(lambda i: 3000) + _rows(lambda i: 100, service="copernicus") + cf
    findings = limits.check(rows, TODAY)
    workers = [f for f in findings if f.service == "cloudflare-workers"]
    assert workers[0].level == "warn" and "80%" in workers[0].text
    assert [f.level for f in findings if f.service == "cloudflare-d1-writes"][0] == "ok"


def test_cloudflare_is_left_out_when_not_read():
    findings = limits.check(_rows(lambda i: 3000) + _rows(lambda i: 100, service="copernicus"), TODAY)
    assert not [f for f in findings if f.service.startswith("cloudflare")]
    assert limits.worst(findings) == "ok"


def test_cloudflare_errors_raise():
    import pytest

    from rowfrog import cloudflare_usage

    with pytest.raises(ValueError):
        cloudflare_usage.parse({"errors": [{"message": "not authorized"}], "data": None})


def test_r2_operations_count_against_the_monthly_free_plan():
    from rowfrog import cloudflare_usage

    def day(i):
        return (TODAY - timedelta(days=i)).isoformat()

    answer = {"data": {"viewer": {"accounts": [{"r2OperationsAdaptiveGroups": [
        *({"dimensions": {"date": day(i), "actionType": "PutObject"}, "sum": {"requests": 45_000}} for i in range(8)),
        *({"dimensions": {"date": day(i), "actionType": "ListObjects"}, "sum": {"requests": 100}} for i in range(8)),
        *({"dimensions": {"date": day(i), "actionType": "GetObject"}, "sum": {"requests": 2_000}} for i in range(8)),
        *({"dimensions": {"date": day(i), "actionType": "DeleteObject"}, "sum": {"requests": 9_999}} for i in range(8)),
    ]}]}}}
    r2 = cloudflare_usage.parse_r2(answer)
    writes = {r["day"]: r["calls"] for r in r2 if r["service"] == "cloudflare-r2-writes"}
    reads = {r["day"]: r["calls"] for r in r2 if r["service"] == "cloudflare-r2-reads"}
    assert writes[day(1)] == 45_100  # puts and listings are class A; deletes are free
    assert reads[day(1)] == 2_000
    findings = limits.check(_rows(lambda i: 3000) + _rows(lambda i: 100, service="copernicus") + r2, TODAY)
    month = [f for f in findings if f.service == "cloudflare-r2-writes"]
    assert month and month[0].level in ("warn", "alert") and "1,000,000 a month" in month[0].text
    assert [f.level for f in findings if f.service == "cloudflare-r2-reads"] == ["ok"]


def test_r2_errors_raise():
    import pytest

    from rowfrog import cloudflare_usage

    with pytest.raises(ValueError):
        cloudflare_usage.parse_r2({"errors": [{"message": "not authorized"}], "data": None})


def test_published_sizes(tmp_path):
    from rowfrog import published_sizes

    for club, n in (("a", 100), ("b", 300)):
        (tmp_path / "clubs" / club).mkdir(parents=True)
        (tmp_path / "clubs" / club / "forecast").write_text("{" + '"x":1,' * n + '"y":0}')
    (tmp_path / "lakes" / "l1").mkdir(parents=True)
    (tmp_path / "lakes" / "l1" / "view").write_text("{}")
    rows = {r["kind"]: r for r in published_sizes.measure(tmp_path)}
    assert rows["Club forecast"]["files"] == 2
    assert rows["Club forecast"]["median_gzip_kb"] < rows["Club forecast"]["median_kb"]
    assert rows["Lake view"]["files"] == 1 and "Lake list" not in rows
    text = published_sizes.report(list(rows.values()))
    assert "## Download sizes" in text and "| Club forecast | 2 |" in text
    assert published_sizes.report([]) == ""


def test_summary_gives_the_numbers_as_data():
    from datetime import datetime, timezone
    rows = _rows(lambda i: 7500 if i == 2 else 6000 - 50 * i)  # copernicus silent -> a note
    data = limits.summary(limits.check(rows, TODAY), datetime(2026, 11, 20, 6, 10, tzinfo=timezone.utc))
    assert data["version"] == 1 and data["time"] == "2026-11-20T06:10:00Z" and data["level"] == "warn"
    om = {s["period"]: s for s in data["services"] if s["key"] == "open-meteo"}
    assert om["day"]["used"] == 7500 and om["day"]["limit"] == 10_000 and om["day"]["share"] == 0.75
    assert om["day"]["level"] == "warn" and om["day"]["name"] == "Weather API (Open-Meteo)"
    assert om["month"]["limit"] == 300_000
    assert {n["key"] for n in data["notes"]} == {"open-meteo", "copernicus"}  # growth warning, silent service


def test_summary_without_the_usage_counter():
    from datetime import datetime, timezone
    data = limits.summary(None, datetime(2026, 11, 20, tzinfo=timezone.utc))
    assert data["level"] == "warn" and data["services"] == [] and data["notes"][0]["key"] == "usage-counter"
