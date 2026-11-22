# 0057. Dependabot may be the author of its own commits on main

- Date: 2026-11-22
- Status: decided (owner, thread "Keep software versions the same everywhere", 22 Nov 2026 01:06 CET (00:06 UTC), card "Exception: bot may be author")
- Where: `.github/workflows/dependabot-merge.yml`, `.github/dependabot.yml`; the git identity rule in the project instructions and `docs/handbook.md`.

## Why

Every commit on main has RowFrog as author and committer, so that no personal name or account shows in the public history. Dependabot #574 (Playwright 1.65.1, Wrangler 4.162.0) was merged as it was on 22 Nov 2026, so its commit 47f6dc0 has `dependabot[bot]` as author. dependabot[bot] is GitHub's bot, not a person: it shows no personal data, and the author field itself says that the change came from Dependabot.

## Decision

- `dependabot[bot]` may be the author of a commit on main. Every other commit still has RowFrog as author and committer (GitHub's merge button may still be the committer).
- Dependabot PRs may be merged as they are. `dependabot-merge.yml` keeps merging backend minor/patch and security updates on its own; majors and npm/Actions PRs still wait for the owner.
- 47f6dc0 stays as it is.

## Turned down

- Redo every Dependabot PR as a RowFrog PR titled "Dependabot: …": the rule would stay without exception, but every update would need a hand-made PR, also the security fixes.
