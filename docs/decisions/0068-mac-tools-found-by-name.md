# 0068. The Mac's scripts find their tools by name, MacPorts first

- Date: 2026-11-27
- Status: decided (owner, thread "Review the other project's doc", 27 Nov 2026 16:25 CET (15:25 UTC): agreed answers 1-4 of the Pi project's doc "RowFrog scripts: path-neutral tools on the Mac", https://claude.ai/artifact/1MujE4KbEYDm4DXftn6nnU)
- Where: `scripts/local/tool-path.sh`, `scripts/local/hooks/pre-push`, `scripts/local/backup.sh`, `scripts/local/screenshots.sh`, `scripts/local/app-size.sh`, `scripts/check_pins_available.py` (`MAC_SOURCE`), the local `update.sh` (not in git).

## Decision

- One helper, `scripts/local/tool-path.sh`, puts the Mac's tool folders on PATH in a fixed order: MacPorts, then Homebrew, then `~/.local/bin` (uv's own installer). Scripts call the tools by name.
- The pin check names the Mac's source in one place, `MAC_SOURCE = "macports"`. MacPorts stays for now; the choice between MacPorts and Homebrew is made later, in the Pi project's thread on it. Switching the check is then a one-line PR.
- Install hints name both MacPorts and Homebrew.

## Why

Several scripts called MacPorts tools by full path or put only `/opt/local/bin` on PATH, which ties the Mac to MacPorts. With MacPorts first nothing changes today, and a later move needs no script edits. A missing tool stops with "not found" instead of running another copy.

## Turned down

- Each script keeping its own inline PATH lines (the same list in five places).
- Homebrew or `~/.local/bin` first (would change which tools run today).
