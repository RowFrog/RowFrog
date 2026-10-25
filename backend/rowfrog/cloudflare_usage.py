"""Daily Cloudflare figures for the free-plan limits: Worker requests and D1 rows.

Every request to api.rowfrog.com passes the usage counter Worker, and each
club or lake load writes a row to its D1 database. On the free plan both
stop at a daily limit (see limits.LIMITS), so the daily Usage limits check
reads them from Cloudflare's GraphQL analytics with the deploy token
(CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID) and warns before they run out.

Rows come back in the same shape as usage.budget(): day, service, calls.
"""

from __future__ import annotations

import os
from datetime import date, timedelta

import httpx

GRAPHQL_URL = "https://api.cloudflare.com/client/v4/graphql"

QUERY = """query($a: String!, $s: Date!, $e: Date!) { viewer { accounts(filter: {accountTag: $a}) {
  workersInvocationsAdaptive(limit: 1000, filter: {date_geq: $s, date_leq: $e}) { sum { requests } dimensions { date } }
  d1AnalyticsAdaptiveGroups(limit: 1000, filter: {date_geq: $s, date_leq: $e}) { sum { rowsWritten rowsRead } dimensions { date } }
} } }"""


def parse(answer: dict) -> list[dict]:
    """Budget-shaped rows from the GraphQL answer; all Workers of the account count together."""
    if answer.get("errors"):
        raise ValueError(answer["errors"][0].get("message", "GraphQL error"))
    rows = []
    for account in answer["data"]["viewer"]["accounts"]:
        for r in account.get("workersInvocationsAdaptive") or []:
            rows.append({"day": r["dimensions"]["date"], "service": "cloudflare-workers", "job": "all", "calls": r["sum"]["requests"]})
        for r in account.get("d1AnalyticsAdaptiveGroups") or []:
            day = r["dimensions"]["date"]
            rows.append({"day": day, "service": "cloudflare-d1-writes", "job": "all", "calls": r["sum"]["rowsWritten"]})
            rows.append({"day": day, "service": "cloudflare-d1-reads", "job": "all", "calls": r["sum"]["rowsRead"]})
    return rows


def daily(today: date, days: int = 14, client: httpx.Client | None = None) -> list[dict] | None:
    """The last `days` days; None without the token or when Cloudflare does not answer."""
    token, account = os.environ.get("CLOUDFLARE_API_TOKEN"), os.environ.get("CLOUDFLARE_ACCOUNT_ID")
    if not token or not account:
        return None
    variables = {"a": account, "s": (today - timedelta(days=days)).isoformat(), "e": today.isoformat()}
    try:
        c = client or httpx.Client()
        resp = c.post(GRAPHQL_URL, json={"query": QUERY, "variables": variables}, headers={"Authorization": f"Bearer {token}"}, timeout=30)
        resp.raise_for_status()
        return parse(resp.json())
    except (httpx.HTTPError, ValueError, KeyError, TypeError) as e:
        print(f"Cloudflare analytics: {e!r}")
        return None
