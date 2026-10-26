"""Temporary: trademark screening for mascot names via TMview (covers EUIPO, DPMA, USPTO, WIPO and more)."""
import json, urllib.request

TERMS = ["ROWI", "ROWY", "ROVI", "ROWIE", "ROWBY"]
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15",
      "Accept": "application/json, text/plain, */*", "Content-Type": "application/json"}


def search(term, page):
    body = {"page": str(page), "pageSize": "100", "criteria": "C", "basicSearch": term.lower(),
            "fTMStatus": ["Filed", "Registered"]}
    req = urllib.request.Request("https://www.tmdn.org/tmview/api/search/results",
                                 data=json.dumps(body).encode(), headers=UA, method="POST")
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


for t in TERMS:
    first = search(t, 1)
    total = first.get("totalResults") or first.get("total") or "?"
    marks = first.get("tradeMarks", [])
    page = 2
    while len(marks) < 400 and len(first.get("tradeMarks", [])) == 100:
        first = search(t, page)
        marks += first.get("tradeMarks", [])
        page += 1
    print(f"\n### {t}: total={total} fetched={len(marks)} keys={list(first.keys())[:8]}")
    exact = [m for m in marks if (m.get("tmName") or "").strip().upper().replace(" ", "") .startswith(t)]
    for m in exact:
        print("|".join(str(x) for x in (m.get("tmName"), m.get("tmOffice"), ",".join(m.get("tProtection") or []),
              m.get("tradeMarkStatus"), ",".join(str(c) for c in m.get("niceClass") or []), m.get("tradeMarkType"),
              ";".join(m.get("applicantName") or []), (m.get("applicationDate") or "")[:10])))
