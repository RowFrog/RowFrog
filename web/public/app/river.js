// Row Frog website: the river at a river club (RiverCurrent.swift, RiverModels.swift).
// The forecast's "river" block (backend/rowfrog/river.py) holds the nearest
// gauge's water level and the current; on river clubs the Current tile takes
// the ice tile's place.

import { t, num } from "./i18n.js";
import { icon } from "./icons.js";
import { h, dot, dayTime, conditionIcon } from "./shared.js";
import { pace as paceText } from "./lake.js";

/** The still-water pace the table works from, as the app's route planner starts (RWRoutePace). */
const PACE = 150;

/** "1.3 m/s" (always m/s: flow speeds are given so on rivers). */
export const riverSpeed = (ms) => (ms == null ? "–" : `${num(ms, 1)} m/s`);

/** "3.20 m" for a gauge level in cm. */
export const riverLevel = (cm) => (cm == null ? "–" : `${num(cm / 100, 2)} m`);

/** Time per 500 m over ground with the current helping or against; null when the boat cannot make way. */
export function paceOnCurrent(secondsPer500, current, downstream) {
  const speed = 500 / secondsPer500 + (downstream ? current : -current);
  return speed > 0.2 ? 500 / speed : null;
}

export function stateTitle(state) {
  return { normal: t("Normal water"), raised: t("Raised water"), high: t("High water"), shipping_stopped: t("Shipping stopped") }[state] ?? t("Water level");
}

export function trendTitle(trend) {
  return { rising: t("rising"), falling: t("falling"), steady: t("steady") }[trend] ?? null;
}

const trendIcon = (trend) => ({ rising: "arrow-up-right", falling: "arrow-down-right" }[trend] ?? "arrow-right");

const speedText = (now) => (now.speedMeasured ? "" : "≈ ") + riverSpeed(now.speedMs);

/** The tile's value and line under it (CurrentTile.value, detail). */
export function currentValue(river) {
  const now = river.now;
  if (!now) return [river.gauge ? t("No reading") : t("No gauge"), river.gauge ? t("Gauge %@", river.gauge.name) : t("Check the river yourself")];
  const value = now.state === "shipping_stopped" ? t("Shipping stopped") : now.speedMs != null ? speedText(now) : stateTitle(now.state);
  return [value, [riverLevel(now.levelCm), trendTitle(now.trend)].filter(Boolean).join(" · ")];
}

/** The level between mean water and the shipping mark: a vertical bar like a gauge board (LevelBar). */
export function levelBar(levelCm, gauge) {
  const low = (gauge?.meanCm ?? levelCm) - 100;
  const top = gauge?.shippingStopsCm ?? (gauge?.meanHighCm != null ? gauge.meanHighCm + 100 : levelCm + 100);
  const fraction = Math.max(0, Math.min(1, (levelCm - low) / Math.max(top - low, 1)));
  const colour = gauge?.shippingStopsCm != null && levelCm >= gauge.shippingStopsCm ? "var(--red)"
    : gauge?.meanHighCm != null && levelCm >= gauge.meanHighCm ? "var(--orange)" : "#30b0c7";
  return `<span class="level-bar" aria-hidden="true"><i style="height:${Math.max(10 / 44, fraction) * 100}%;background:${colour}"></i></span>`;
}

/** The tile in Current conditions, in the ice tile's place (CurrentTile). */
export function currentTile(river) {
  const light = river.now?.light;
  const [value, detail] = currentValue(river);
  const bar = river.now?.levelCm != null ? levelBar(river.now.levelCm, river.gauge) : "";
  return `<button class="tile" data-current aria-description="${h(t("Opens the water level and current"))}">
    <span class="tile-head">${conditionIcon("current")}<span>${h(t("Current"))}</span>${light && light !== "green" ? dot(light, 8) : ""}${icon("chevron-right")}</span>
    <span class="tile-body"><span><strong>${h(value)}</strong><small>${h(detail)}</small></span><span class="graphic">${bar}</span></span></button>`;
}

/** The last two days' level with the mean water and shipping marks, as a small line chart. */
function levelChart(history, gauge) {
  const W = 320;
  const H = 150;
  const pad = { l: 34, r: 8, t: 14, b: 20 };
  const times = history.map((x) => new Date(x.time).getTime());
  const marks = [gauge?.meanCm, gauge?.shippingStopsCm].filter((v) => v != null);
  const levels = history.map((x) => x.levelCm);
  let lo = Math.min(...levels, ...marks);
  let hi = Math.max(...levels, ...marks);
  if (hi - lo < 20) [lo, hi] = [lo - 10, hi + 10];
  const x = (ms) => pad.l + ((ms - times[0]) / Math.max(times[times.length - 1] - times[0], 1)) * (W - pad.l - pad.r);
  const y = (cm) => pad.t + (1 - (cm - lo) / (hi - lo)) * (H - pad.t - pad.b);
  const line = history.map((p, i) => `${i ? "L" : "M"}${x(times[i]).toFixed(1)},${y(p.levelCm).toFixed(1)}`).join("");
  const rule = (cm, label, colour) => `<line x1="${pad.l}" x2="${W - pad.r}" y1="${y(cm)}" y2="${y(cm)}" stroke="${colour}" stroke-dasharray="4 3" />
    <text x="${pad.l + 2}" y="${y(cm) - 3}" fill="${colour}" font-size="10">${h(label)}</text>`;
  const ticks = [lo, (lo + hi) / 2, hi].map((cm) => `<text x="${pad.l - 4}" y="${y(cm) + 3}" text-anchor="end" font-size="10" fill="var(--sub)">${h(num(cm / 100, 1))}</text>`).join("");
  return `<svg class="level-chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="${h(t("Water level, last two days"))}">
    ${ticks}<text x="4" y="${pad.t - 4}" font-size="10" fill="var(--sub)">m</text>
    ${gauge?.meanCm != null ? rule(gauge.meanCm, t("Mean water"), "var(--sub)") : ""}
    ${gauge?.shippingStopsCm != null ? rule(gauge.shippingStopsCm, t("Shipping stops"), "var(--red)") : ""}
    <path d="${line}" fill="none" stroke="#30b0c7" stroke-width="2" />
    <text x="${pad.l}" y="${H - 4}" font-size="10" fill="var(--sub)">${h(dayTime(history[0].time))}</text>
    <text x="${W - pad.r}" y="${H - 4}" text-anchor="end" font-size="10" fill="var(--sub)">${h(dayTime(history[history.length - 1].time))}</text>
  </svg>`;
}

/** Opened from the Current tile: speed, level and its last two days, and how the current changes a crew's pace (CurrentDetailView). */
export function currentBody(river) {
  const now = river.now;
  let main;
  if (now) {
    const warning = now.state === "shipping_stopped"
      ? `<p class="red strong">${icon("circle-alert")} ${h(t("Above the shipping mark: even motor ships stay in. Do not row."))}</p>`
      : now.state === "high" ? `<p class="orange strong">${icon("triangle-alert")} ${h(t("High water: strong current, flotsam and flooded banks. Only experienced crews, with care."))}</p>` : "";
    const up = now.speedMs != null ? paceOnCurrent(PACE, now.speedMs, false) : null;
    const down = now.speedMs != null ? paceOnCurrent(PACE, now.speedMs, true) : null;
    main = `<p class="current-big"><strong>${h(now.speedMs != null ? speedText(now) : stateTitle(now.state))}</strong>${now.light !== "green" ? dot(now.light, 14) : ""}</p>
      ${now.speedMs != null ? `<p class="small sub">${h(now.speedMeasured ? t("Flow speed measured at the gauge") : t("Estimated mid-river; near the bank the water is slower"))}</p>` : ""}
      <p class="strong">${icon(trendIcon(now.trend))} ${h([stateTitle(now.state), riverLevel(now.levelCm), trendTitle(now.trend)].filter(Boolean).join(" · "))}</p>
      ${warning}
      ${now.history?.length > 1 ? `<h3 class="section">${h(t("Water level, last two days"))}</h3>${levelChart(now.history, river.gauge)}` : ""}
      ${now.speedMs != null ? `<h3 class="section">${h(t("Your pace %@ /500 m on this current", paceText(PACE)))}</h3>
        <dl class="pace-table"><dt>${h(t("Upstream"))}</dt><dd>${h(up ? `${paceText(up)} /500 m` : t("No headway"))}</dd>
          <dt>${h(t("Downstream"))}</dt><dd>${h(down ? `${paceText(down)} /500 m` : "–")}</dd></dl>
        <p class="small sub">${h(t("Over ground. The route planner on the river view uses the same current."))}</p>` : ""}`;
  } else {
    main = `<p class="sub">${h(river.gauge
      ? t("The gauge has sent no recent reading. Check the water level and current yourself.")
      : t("No federal gauge measures this river near the club. Check the water level and current yourself, and ask your club when the river runs high."))}</p>`;
  }
  const g = river.gauge;
  const notes = [
    g ? `${t("Gauge %@ (%@)", g.name, g.water)}${g.riverKm != null ? ` · ${t("river km %@", num(g.riverKm, 1))}` : ""} · ${t("%@ km from the club", num(g.distanceKm, 1))}` : null,
    g && now?.time ? t("Reading %@", dayTime(now.time)) : null,
    river.limits ? t("Current amber from %@, red above %@. Shipping stopped is red, high water amber.", riverSpeed(river.limits.currentAmberMs), riverSpeed(river.limits.currentRedMs)) : null,
    t("Data: %@", river.attribution ?? "WSV PEGELONLINE"),
  ].filter(Boolean);
  return `${main}<div class="small sub current-notes">${notes.map((n) => `<p>${h(n)}</p>`).join("")}</div>`;
}

