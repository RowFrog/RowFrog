import json

import httpx

from rowfrog import usage


def _client(handler):
    return httpx.Client(transport=httpx.MockTransport(handler))


def test_without_a_key_nothing_is_asked(monkeypatch):
    monkeypatch.delenv("RW_USAGE_KEY", raising=False)

    def fail(request):
        raise AssertionError("no request expected")

    assert usage.used(client=_client(fail)) is None
    assert usage.report_calls("open-meteo", 10, "publish", client=_client(fail)) is False


def test_used_and_report(monkeypatch):
    monkeypatch.setenv("RW_USAGE_KEY", "secret")
    seen = []

    def handler(request):
        assert request.headers["authorization"] == "Bearer secret"
        seen.append((request.method, request.url.path, request.content))
        if request.url.path == "/usage":
            return httpx.Response(200, json={"days": 7, "clubs": {"mrc-1880": 12}, "lakes": {"starnberger-see": 3}})
        return httpx.Response(200, json={"ok": True})

    u = usage.used(client=_client(handler))
    assert u.clubs == {"mrc-1880": 12} and u.lakes == {"starnberger-see": 3}
    assert usage.report_calls("open-meteo", 75.004, "publish", client=_client(handler))
    assert json.loads(seen[-1][2]) == {"service": "open-meteo", "job": "publish", "calls": 75.0}


def test_counter_down_means_fixed_schedule(monkeypatch):
    monkeypatch.setenv("RW_USAGE_KEY", "secret")
    assert usage.used(client=_client(lambda r: httpx.Response(503))) is None
    assert usage.budget(client=_client(lambda r: httpx.Response(401))) is None
