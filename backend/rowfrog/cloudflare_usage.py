"""Daily Cloudflare figures for the free-plan limits: Worker requests, D1 rows, R2 operations.

Every request to api.rowfrog.com passes the usage counter Worker, and each
club or lake load writes a row to its D1 database. On the free plan both
stop at a daily limit (see limits.LIMITS), so the daily Usage limits check
reads them from Cloudflare's GraphQL analytics with the deploy token
(CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID) and warns before they run out.

Since Nov 2026 the published files live in the R2 bucket the Pi fills and the
Worker reads, so R2's free monthly operations count too: writes and listings
(class A, the Pi's uploads) and reads (class B, one per /v1 file served).
R2 has its own query, so a token without R2 analytics still gets the rest.

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

R2_QUERY = """query($a: String!, $s: Date!, $e: Date!) { viewer { accounts(filter: {accountTag: $a}) {
  r2OperationsAdaptiveGroups(limit: 10000, filter: {date_geq: $s, date_leq: $e}) { sum { requests } dimensions { date actionType } }
} } }"""

# Cloudflare's R2 price list: class A changes or lists, class B reads; deletes are free.
R2_CLASS_A = {
    "ListBuckets", "PutBucket", "ListObjects", "PutObject", "CopyObject", "CompleteMultipartUpload",
    "CreateMultipartUpload", "UploadPart", "UploadPartCopy", "ListMultipartUploads", "ListParts",
    "PutBucketEncryption", "PutBucketCors", "PutBucketLifecycleConfiguration", "PutBucketStorageClass",
    "LifecycleStorageTierTransition",
}
R2_CLASS_B = {
    "HeadBucket", "HeadObject", "GetObject", "UsageSummary", "GetBucketEncryption", "GetBucketLocation",
    "GetBucketCors", "GetBucketLifecycleConfiguration",
}


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


def parse_r2(answer: dict) -> list[dict]:
    """Class A and class B rows per day from the R2 answer (unknown kinds count as class A, to be safe)."""
    if answer.get("errors"):
        raise ValueError(answer["errors"][0].get("message", "GraphQL error"))
    totals: dict[tuple[str, str], int] = {}
    for account in answer["data"]["viewer"]["accounts"]:
        for r in account.get("r2OperationsAdaptiveGroups") or []:
            action = r["dimensions"]["actionType"]
            if action.startswith("Delete") or action == "AbortMultipartUpload":
                continue
            service = "cloudflare-r2-reads" if action in R2_CLASS_B else "cloudflare-r2-writes"
            key = (r["dimensions"]["date"], service)
            totals[key] = totals.get(key, 0) + r["sum"]["requests"]
    return [{"day": day, "service": service, "job": "all", "calls": n} for (day, service), n in sorted(totals.items())]


def _ask(query: str, variables: dict, token: str, client: httpx.Client | None) -> dict:
    c = client or httpx.Client()
    resp = c.post(GRAPHQL_URL, json={"query": query, "variables": variables}, headers={"Authorization": f"Bearer {token}"}, timeout=30)
    resp.raise_for_status()
    return resp.json()


def r2_daily(today: date, days: int = 35, client: httpx.Client | None = None) -> list[dict] | None:
    """R2 operations for the last `days` days (enough for the month); None when they cannot be read."""
    token, account = os.environ.get("CLOUDFLARE_API_TOKEN"), os.environ.get("CLOUDFLARE_ACCOUNT_ID")
    if not token or not account:
        return None
    variables = {"a": account, "s": (today - timedelta(days=days)).isoformat(), "e": today.isoformat()}
    try:
        return parse_r2(_ask(R2_QUERY, variables, token, client))
    except (httpx.HTTPError, ValueError, KeyError, TypeError) as e:
        print(f"Cloudflare R2 analytics: {e!r}")
        return None


def daily(today: date, days: int = 14, client: httpx.Client | None = None) -> list[dict] | None:
    """The last `days` days; None without the token or when Cloudflare does not answer."""
    token, account = os.environ.get("CLOUDFLARE_API_TOKEN"), os.environ.get("CLOUDFLARE_ACCOUNT_ID")
    if not token or not account:
        return None
    variables = {"a": account, "s": (today - timedelta(days=days)).isoformat(), "e": today.isoformat()}
    try:
        return parse(_ask(QUERY, variables, token, client))
    except (httpx.HTTPError, ValueError, KeyError, TypeError) as e:
        print(f"Cloudflare analytics: {e!r}")
        return None
