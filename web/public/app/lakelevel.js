// Row Frog website: a lake lowered on purpose (LakeLevelTile.swift, RiverModels.swift LakeLevel).
// The forecast's "waterLevel" block (backend/rowfrog/lake_level.py) holds the
// lake's gauge and its marks in m above sea level; while the lake is lowered
// (Forggensee every winter) the Water level tile takes the ice tile's place.

import { t, num } from "./i18n.js";
import { icon } from "./icons.js";
import { h, dot, dayTime, conditionIcon } from "./shared.js";

/** Whether the tile shows in the ice tile's place (LakeLevel.isLowered). */
export const isLowered = (level) => level?.now != null && level.now.state !== "full";

/** "4.2 m". */
const metres = (m) => `${num(m, 1)} m`;
/** "776.40 m" above sea level. */
const height = (m) => `${num(m, 2)} m`;

export const stateTitle = (state) => ({ drained: t("Drained"), lowered: t("Lowered") }[state] ?? t("Full"));
const trendTitle = (trend) => ({ rising: t("rising"), falling: t("falling"), steady: t("steady") }[trend] ?? null);

/** The basin's drawing in a 44 x 44 box (BasinShape in LakeLevelTile.swift): the sides from the rim (y 4) to the
 * floor (y 40), the water between them from its bottom (38.5) up to full (9), 0 at 2 m under the drained mark. */
const B = { size: 44, rimY: 4, floorY: 40, rimX: 2, floorX: 13.2, fullY: 9, emptyY: 38.5 };
const leftX = (y) => B.rimX + (B.floorX - B.rimX) * (y - B.rimY) / (B.floorY - B.rimY) + 1.5;
const levelY = (fraction) => B.emptyY - (B.emptyY - B.fullY) * fraction;

/** The basin's parts for a level, in the 44 x 44 box (exported for the tests). */
export function basinShape(levelM, level) {
  const low = level.drainedBelowM - 2;
  const fraction = (m) => Math.max(0, Math.min(1, (m - low) / Math.max(level.fullM - low, 0.1)));
  const top = Math.min(levelY(fraction(levelM)), B.emptyY - 2);
  const mark = (m, whole = false) => {
    const y = levelY(fraction(m));
    const right = B.size - leftX(y) + 1;
    return [[whole ? leftX(y) - 1 : right - 7, y], [right, y]];
  };
  return {
    water: [[leftX(B.emptyY), B.emptyY], [B.size - leftX(B.emptyY), B.emptyY], [B.size - leftX(top), top], [leftX(top), top]],
    full: mark(level.fullM, true), lowered: mark(level.loweredBelowM), drained: mark(level.drainedBelowM),
  };
}

/** A basin with the water in it and its marks: full dashed across, lowered (amber) and drained (red) on the right
 * side; the water follows the sloping sides (BasinGauge; owner, 12 Nov 2026: a box over the sides, and no marks,
 * made 1.1 m below full look nearly full). */
function basin(levelM, level) {
  const shape = basinShape(levelM, level);
  const colour = levelM < level.drainedBelowM ? "var(--red)" : levelM < level.loweredBelowM ? "var(--orange)" : "#30b0c7";
  const pts = (list) => list.map(([x, y]) => `${num2(x)},${num2(y)}`).join(" ");
  return `<svg class="basin" viewBox="0 0 44 44" width="44" height="44" aria-hidden="true">
    <polygon points="${pts(shape.water)}" fill="${colour}" />
    <path d="M2 4 L13.2 40 L30.8 40 L42 4" fill="none" stroke="var(--sub)" stroke-opacity=".5" stroke-width="2" />
    <polyline points="${pts(shape.full)}" fill="none" stroke="var(--sub)" stroke-width="1" stroke-dasharray="2 2" />
    <polyline points="${pts(shape.lowered)}" fill="none" stroke="var(--orange)" stroke-width="1.5" />
    <polyline points="${pts(shape.drained)}" fill="none" stroke="var(--red)" stroke-width="1.5" /></svg>`;
}
const num2 = (v) => Math.round(v * 100) / 100;

/** The tile in Current conditions, in the ice tile's place (WaterLevelTile). */
export function waterLevelTile(level) {
  const now = level.now;
  const detail = now ? [t("%@ below full", metres(now.belowFullM)), trendTitle(now.trend)].filter(Boolean).join(" · ") : t("Gauge %@", level.gauge);
  return `<button class="tile" data-water-level aria-description="${h(t("Opens the lake's water level"))}">
    <span class="tile-head">${conditionIcon("waterLevel")}<span>${h(t("Water level"))}</span>${now?.light && now.light !== "green" ? dot(now.light, 8) : ""}${icon("chevron-right")}</span>
    <span class="tile-body"><span><strong>${h(now ? stateTitle(now.state) : t("No reading"))}</strong><small>${h(detail)}</small></span><span class="graphic">${now ? basin(now.levelM, level) : ""}</span></span></button>`;
}

/** The last week's level with the Full and Drained marks, as a small line chart. */
function levelChart(history, level) {
  const W = 320;
  const H = 160;
  const pad = { l: 44, r: 8, t: 14, b: 20 };
  const times = history.map((x) => new Date(x.time).getTime());
  const levels = history.map((x) => x.levelM);
  let lo = Math.min(...levels, level.drainedBelowM);
  let hi = Math.max(...levels, level.fullM);
  if (hi - lo < 1) [lo, hi] = [lo - 0.5, hi + 0.5];
  const x = (ms) => pad.l + ((ms - times[0]) / Math.max(times[times.length - 1] - times[0], 1)) * (W - pad.l - pad.r);
  const y = (m) => pad.t + (1 - (m - lo) / (hi - lo)) * (H - pad.t - pad.b);
  const line = history.map((p, i) => `${i ? "L" : "M"}${x(times[i]).toFixed(1)},${y(p.levelM).toFixed(1)}`).join("");
  const rule = (m, label, colour) => `<line x1="${pad.l}" x2="${W - pad.r}" y1="${y(m)}" y2="${y(m)}" stroke="${colour}" stroke-dasharray="4 3" />
    <text x="${pad.l + 2}" y="${y(m) - 3}" fill="${colour}" font-size="10">${h(label)}</text>`;
  const ticks = [lo, (lo + hi) / 2, hi].map((m) => `<text x="${pad.l - 4}" y="${y(m) + 3}" text-anchor="end" font-size="10" fill="var(--sub)">${h(num(m, 1))}</text>`).join("");
  return `<svg class="level-chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="${h(t("Water level, last week"))}">
    ${ticks}<text x="4" y="${pad.t - 4}" font-size="10" fill="var(--sub)">m</text>
    ${rule(level.fullM, t("Full"), "var(--sub)")}${rule(level.drainedBelowM, t("Drained"), "var(--red)")}
    <path d="${line}" fill="none" stroke="#30b0c7" stroke-width="2" />
    <text x="${pad.l}" y="${H - 4}" font-size="10" fill="var(--sub)">${h(dayTime(history[0].time))}</text>
    <text x="${W - pad.r}" y="${H - 4}" text-anchor="end" font-size="10" fill="var(--sub)">${h(dayTime(history[history.length - 1].time))}</text>
  </svg>`;
}

/** Opened from the Water level tile: the level, its last week and the marks (WaterLevelDetailView). */
export function waterLevelBody(level) {
  const now = level.now;
  let main;
  if (now) {
    const warning = now.state === "drained"
      ? `<p class="red strong">${icon("octagon-alert")} ${h(t("Too little water at the club to row."))}</p>`
      : now.state === "lowered" ? `<p class="orange strong">${icon("triangle-alert")} ${h(t("Lowered: shallows, sandbanks and a long way to the water. Check the landing stage first."))}</p>` : "";
    main = `<p class="current-big"><strong>${h(stateTitle(now.state))}</strong>${now.light !== "green" ? dot(now.light, 14) : ""}</p>
      <p class="strong">${h([height(now.levelM), t("%@ below full", metres(now.belowFullM)), trendTitle(now.trend)].filter(Boolean).join(" · "))}</p>
      ${warning}
      ${now.history?.length > 1 ? `<h3 class="section">${h(t("Water level, last week"))}</h3>${levelChart(now.history, level)}` : ""}`;
  } else {
    main = `<p class="sub">${h(t("The gauge has sent no recent reading. Ask your club whether there is enough water to row."))}</p>`;
  }
  const notes = [
    t("Gauge %@", level.gauge),
    now?.time ? t("Reading %@", dayTime(now.time)) : null,
    t("Amber below %@, red below %@.", height(level.loweredBelowM), height(level.drainedBelowM)),
    t("Data: %@", level.attribution ?? "GKD Bayern"),
  ].filter(Boolean);
  return `${main}<p>${h(t("The lake is let down every winter, for flood protection and power: from mid-November, lowest in February, full again by about the end of May."))}</p>
    <div class="small sub current-notes">${notes.map((n) => `<p>${h(n)}</p>`).join("")}</div>`;
}
