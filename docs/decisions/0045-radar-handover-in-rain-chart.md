# 0045. The rain chart marks where the radar hands over to the forecast

- Date: 2026-11-17
- Status: decided (owner, thread "Show rain hours and radar handover clearly", 17 Nov 2026 11:24 CET: option B of the mock-ups)
- Where: app `ios/RowFrog/ConditionsCard.swift` (`ConditionDetail.handover`, `ChartLine.fade`, drawn in the chart's marker overlay); website `web/public/app/values.js` (`handover`, `fade`), `web/public/app/chart.js`, `web/public/app/style.css` (`.handover`)

## Decision

- While the radar is read, the rain detail chart draws a grey line where the radar ends, half a quarter hour past its last step, so the line stands just after the last radar bar. "Radar" sits on the left of the line and "Forecast" on the right.
- The forecast's bars are paler than the radar's (60 % of their usual strength), as in the rain tile's small bars.
- Without radar, the chart is unchanged.
- The bars stay thin and stand in the middle of their hour (decision 0043). The mock-up of bars as wide as their hour was not taken: they would dwarf the radar's quarter-hour bars.

## Why

The rain tile already shows this handover with a grey divider and paler forecast bars. Until now the detail chart showed it only by the bars' colour, so the same picture meant less on the bigger view. Mock-ups: https://claude.ai/artifact/YUeNH1me1vSTW65UFz1rex (options A line only, B line and paler forecast, C tinted band).
