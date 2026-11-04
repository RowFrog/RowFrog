# Finished probes (moved aside)

One-off research scripts and workflows whose question is answered. They were
moved here on 2026-11-04 (code review finding 11) so `scripts/` and
`.github/workflows/` show only what is still in use. Nothing in the app, the
backend or a running workflow uses them. They still run as they did.

| What | Answered | Result now lives in |
|---|---|---|
| `river_section_probe.py`, `river_section_survey.py`, `river_section_ends.py`, `river_section_summary.py`, `water_kind_probe.py` and `workflows/river-section-survey.yml` | How far the next weir or lock is up- and downstream of every river club, and how OpenStreetMap tags club waters (Oct 2026) | `scripts/build_river_sections.py`, workflow "River sections", `data/river-sections.json` |
| `river_gauge_probe.py` and `workflows/river-gauge-probe.yml` | Which river gauges and flow forecasts could tell river clubs about current and high water (Oct 2026) | `scripts/river_gauge_survey.py`, workflow "River gauges", `data/river-gauges.json` |

## Using one again

- Script: run it from the repository root, e.g. `python3 scripts/probes/river_gauge_probe.py`.
- Workflow: GitHub only runs workflows in `.github/workflows/`. Copy the file
  back there (`git mv scripts/probes/workflows/river-gauge-probe.yml .github/workflows/`)
  on a branch, then start it in the Actions tab.
