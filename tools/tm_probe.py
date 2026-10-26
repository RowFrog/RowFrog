"""Temporary: trademark screening for mascot names. Prints raw register answers to the job log."""
import json, urllib.request

TERMS = ["ROWI", "ROWY", "ROVI", "ROWIE"]
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15",
      "Accept": "application/json, text/plain, */*", "Content-Type": "application/json"}


def call(name, url, body=None, n=6000):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=UA, method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            txt = r.read().decode("utf-8", "replace")
            print(f"### {name} {r.status} len={len(txt)}")
            print(txt[:n])
            return txt
    except Exception as e:
        err = getattr(e, "read", lambda: b"")()
        print(f"### {name} ERROR {e} {err[:800]!r}")


for t in TERMS:
    call(f"tmview {t}", "https://www.tmdn.org/tmview/api/search/results",
         {"page": "1", "pageSize": "100", "criteria": "C", "basicSearch": t.lower(),
          "fTMStatus": ["Filed", "Registered"]}, 12000)
    call(f"uspto {t}", "https://tmsearch.uspto.gov/api-v1-0-0/tmsearch",
         {"query": {"bool": {"must": [{"query_string": {"query": t, "default_operator": "AND", "fields": ["wordmark"]}}]}},
          "size": 100, "_source": ["wordmark", "alive", "statusCode", "ownerName", "internationalClass", "registrationDate", "goodsAndServices"]}, 6000)
call("dpma page", "https://register.dpma.de/DPMAregister/marke/einsteiger", None, 500)
call("wipo page", "https://branddb.wipo.int/en/similarname", None, 500)
