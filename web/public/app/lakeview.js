// The lake view: the tile on a club page (LakeViewCard) and the full lake map
// with the hours, the layers, a tapped spot and route planning (LakeMapScreen).

import { t } from "./i18n.js";
import { icon } from "./icons.js";
import {
  store, getJSON, h, time, dayTime, duration, wind, windRange, waves, distance, temperature, lightTitle, reasonLabel, coldWaterText,
  dot, setTitle, openSheet, loadLeaflet, testing, adviceOnly, mapBoat, mapLimits, selectedBoat, boatLimits, boatInSentence, windUnit,
  CONDITION_ICONS,
} from "./shared.js";
import { compass, matchesStandard, allowsMore, coldWaterKit, reasonCondition, key } from "./logic.js";
import {
  decodeView, hourIndex, viewStale, applyLakeLimits, stripes, coldShore, shares, zoneTitle, headline, windSummary, maxWave,
  waterKind, WATER_TEXTS, sectionEndTitle, openBounds,
  gridEdges, cellAt, cellColours, rasterPixels, RGB, ramp, RouteEdit, routeLength, routePlanner, planRoute, bestStart, plansBetter,
  roughest, RELATION_WIND, RELATION_WAVES, pace as paceText,
} from "./lake.js";
import { readTrack, shareOnWater, routeFromTrack, plannedPace } from "./rowimport.js";
import { tip, wireTips } from "./tour.js";
import { loadLandWind, landWind } from "./weathermap.js";
import { SPACING, BLEND_M, arrowLength, arrowLines, windArrows, inside } from "./windarrows.js";

const views = new Map();

/** The lake as the backend sent it, kept for half an hour. */
async function loadView(lakeId) {
  const kept = views.get(lakeId);
  if (kept && Date.now() - kept.at < 30 * 60 * 1000) return kept.view;
  // The lake card and the satellite card ask at once: one download for both.
  const view = getJSON(`lakes/${encodeURIComponent(lakeId)}/view`).then(decodeView);
  views.set(lakeId, { at: Date.now(), view });
  view.catch(() => views.get(lakeId)?.view === view && views.delete(lakeId));
  return view;
}

/** Pull to refresh and coming back renew the lake view (LocationPageView.refreshLakeView). */
export const forgetView = (lakeId) => views.delete(lakeId);

/** The water of the club page that last showed each lake, for lakes without a station. */
const clubWater = new Map();
export const noteWater = (lakeId, celsius) => celsius != null && clubWater.set(lakeId, celsius);

/** The lake coloured for the map's boat, with the water the shore is drawn by. */
export async function viewForMap(lakeId) {
  const raw = await loadView(lakeId);
  const limits = mapLimits();
  const view = applyLakeLimits(raw, limits, matchesStandard(limits));
  return { ...view, shoreWaterC: raw.waterC ?? clubWater.get(lakeId) ?? null };
}

const rgb = (c, a = 1) => `rgba(${Math.round(c[0])}, ${Math.round(c[1])}, ${Math.round(c[2])}, ${a})`;
export const COLD_SHORE = { cool: "rgb(92, 168, 242)", cold: "rgb(20, 84, 194)" };

/** The hour's lights (or waves, wind) as a small picture, one pixel per cell, for smooth scaling. */
export function rasterCanvas(view, hour, layer) {
  const { width, height, data } = rasterPixels(view, cellColours(view, hour, layer, mapLimits()));
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  canvas.getContext("2d").putImageData(new ImageData(data, width, height), 0, 0);
  return canvas;
}

function strokeStripes(ctx, kind, w, hgt, scale = 1) {
  const red = kind === "red";
  ctx.strokeStyle = red ? "rgba(255, 59, 48, .55)" : "rgba(255, 149, 0, .75)";
  ctx.lineWidth = (red ? 1.5 : 1.2) * scale;
  ctx.beginPath();
  const gap = (red ? 8 : 14) * scale;
  for (let x = -hgt; x < w; x += gap) {
    ctx.moveTo(x, hgt);
    ctx.lineTo(x + hgt, 0);
  }
  ctx.stroke();
}

function arrowPath(ctx, x, y, towardDeg, length) {
  const r = (towardDeg * Math.PI) / 180;
  const dx = Math.sin(r);
  const dy = -Math.cos(r);
  const tip = [x + (dx * length) / 2, y + (dy * length) / 2];
  ctx.moveTo(x - (dx * length) / 2, y - (dy * length) / 2);
  ctx.lineTo(...tip);
  for (const side of [-1, 1]) {
    const a = r + Math.PI + side * 0.5;
    ctx.moveTo(...tip);
    ctx.lineTo(tip[0] + Math.sin(a) * length * 0.35, tip[1] - Math.cos(a) * length * 0.35);
  }
}

/** The lake by itself, north up, coloured by the light of each part, with wind arrows and the clubs (LakeMiniMap). */
function drawMiniMap(canvas, view, hour, clubId) {
  const ratio = window.devicePixelRatio || 1;
  const w = canvas.clientWidth;
  const hgt = canvas.clientHeight;
  canvas.width = w * ratio;
  canvas.height = hgt * ratio;
  const ctx = canvas.getContext("2d");
  ctx.scale(ratio, ratio);
  const e = gridEdges(view.grid);
  const k = Math.cos((((e.north + e.south) / 2) * Math.PI) / 180);
  const pad = 6;
  const scale = Math.min((w - 2 * pad) / ((e.east - e.west) * k), (hgt - 2 * pad) / (e.north - e.south));
  const ox = (w - (e.east - e.west) * k * scale) / 2;
  const oy = (hgt - (e.north - e.south) * scale) / 2;
  const pt = (lon, lat) => [ox + (lon - e.west) * k * scale, oy + (e.north - lat) * scale];
  const shore = new Path2D();
  for (const ring of view.outline) {
    if (ring.length < 3) continue;
    shore.moveTo(...pt(ring[0][0], ring[0][1]));
    for (const p of ring.slice(1)) shore.lineTo(...pt(p[0], p[1]));
    shore.closePath();
  }
  ctx.fillStyle = "rgba(0, 122, 255, .2)";
  ctx.fill(shore, "evenodd");
  ctx.save();
  ctx.clip(shore, "evenodd");
  ctx.globalAlpha = 0.85;
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = "high";
  const [x0, y0] = pt(e.west, e.north);
  const [x1, y1] = pt(e.east, e.south);
  ctx.drawImage(rasterCanvas(view, hour, "light"), x0, y0, x1 - x0, y1 - y0);
  ctx.globalAlpha = 1;
  const kind = stripes(hour.lakeWide);
  if (kind) strokeStripes(ctx, kind, w, hgt);
  ctx.restore();
  const cold = coldShore(view.shoreWaterC, mapLimits());
  ctx.strokeStyle = cold ? COLD_SHORE[cold] : "rgba(0, 122, 255, .4)";
  ctx.lineWidth = cold ? (cold === "cool" ? 1.6 : 2.2) : 0.7;
  ctx.stroke(shore);
  ctx.strokeStyle = getComputedStyle(canvas).color;
  ctx.globalAlpha = 0.55;
  ctx.lineWidth = 1.2;
  ctx.beginPath();
  view.points.forEach((p, i) => {
    const from = hour.wind[i]?.fromDeg;
    if (from != null) arrowPath(ctx, ...pt(p.lon, p.lat), from + 180, 12);
  });
  ctx.stroke();
  ctx.globalAlpha = 1;
  for (const club of view.clubs) {
    const [x, y] = pt(club.launchPoint.lon, club.launchPoint.lat);
    const own = club.id === clubId;
    ctx.beginPath();
    ctx.arc(x, y, own ? 4.5 : 3, 0, 2 * Math.PI);
    ctx.fillStyle = own ? "#007aff" : "#fff";
    ctx.fill();
    ctx.strokeStyle = own ? "#fff" : "#007aff";
    ctx.lineWidth = 1.5;
    ctx.stroke();
  }
}

function headlineText(view, hour) {
  const [text, ...args] = headline(view, hour);
  return t(text, ...args.map((a) => t(a)));
}

function windText(hour) {
  const w = windSummary(hour);
  if (!w) return null;
  const speed = Math.round(w.min) === Math.round(w.max) ? wind(w.max) : `${windRange(w.min, w.max)} ${windUnit()}`;
  return `${speed}${w.fromDeg != null ? ` ${t("from %@", compass(w.fromDeg))}` : ""}, ${t("gusts up to %@", wind(w.gust))}`;
}

/** What holds for the whole lake (or river stretch) this hour, such as a DWD storm warning or darkness (LakeWideBanner). */
function lakeWideBanner(lakeWide, view) {
  if (lakeWide.light === "green") return "";
  const first = lakeWide.reasons[0];
  return `<p class="lake-wide ${lakeWide.light === "red" ? "red" : "orange"}">${icon(first ? CONDITION_ICONS[reasonCondition(first.condition)] : "triangle-alert")}
    <span>${h(t(waterKind(view) === "lake" ? key("Whole lake: %@") : key("Whole stretch: %@"), lakeWide.reasons.map(reasonLabel).join(", ")))}</span></p>`;
}

/** Which boat the lake is coloured for, with a warning when it takes more wind or waves than the ticked one (MapBoatNote). */
export function mapBoatNote() {
  const boat = mapBoat();
  if (allowsMore(mapLimits(), boatLimits(selectedBoat()))) {
    return `<p class="small orange strong">${icon("triangle-alert")} ${h(t("Coloured for %@, not for %@: the lake may look calmer than it is for you.", boatInSentence(boat), boatInSentence(selectedBoat())))}</p>`;
  }
  return `<p class="small sub">${icon("sailboat")} ${h(t("Coloured for %@", boatInSentence(boat)))}</p>`;
}

export function kitBadge(view) {
  const kit = coldWaterKit(view.shoreWaterC, mapLimits());
  if (!kit) return "";
  const [title, advice] = coldWaterText(kit);
  return `<span class="kit" title="${h(advice)}">${icon("life-buoy")} ${h(title)}</span>`;
}

// ---- The tile on the club page ------------------------------------------------------

/** Fills the club page's lake view tile, or hides it when the lake has no view. */
export async function fillLakeCard(box, lakeId, clubId, waterC) {
  noteWater(lakeId, waterC);
  let view;
  try {
    view = await viewForMap(lakeId);
  } catch {
    box.remove();
    return;
  }
  const hour = view.hours[hourIndex(view)];
  if (!hour) return;
  const e = gridEdges(view.grid);
  const aspect = (e.north - e.south) / ((e.east - e.west) * Math.cos((((e.north + e.south) / 2) * Math.PI) / 180));
  const stale = viewStale(view);
  const zones = view.zones.length > 1 ? view.zones.map((z, i) => hour.zones[i] ? `<li>${dot(hour.zones[i].light, 10, stale)}<span><strong>${h(t(zoneTitle(z, waterKind(view))))}</strong>
    <small class="sub">${h(t("Waves up to %@", waves(hour.zones[i].maxWaveM)))}</small></span></li>` : "").join("") : "";
  const windLine = windText(hour);
  const water = WATER_TEXTS[waterKind(view)];
  box.innerHTML = `<header class="card-title">${icon("map")}<span>${h(`${t(water.view)} · ${view.name}`)}</span></header>
    <a class="lake-card ${aspect >= 1.3 ? "tall" : ""}" href="#/lake/${encodeURIComponent(lakeId)}/${encodeURIComponent(clubId)}" aria-label="${h(t(water.opens))}">
      <canvas class="mini" style="${aspect >= 1.3 ? `height:${Math.min(320, Math.max(170, 120 * aspect))}px` : ""}" role="img" aria-label="${h(t("Map of %@ coloured by the rowing light", view.name))}"></canvas>
      <div class="lake-summary">
        <small class="sub">${h(t("Now, %@", time(hour.time)))}</small>
        <strong class="headline">${h(headlineText(view, hour))}</strong>
        ${stale ? `<p class="small orange strong">${icon("clock")} ${h(t("Forecast out of date: from %@. Check the conditions yourself.", dayTime(view.generatedAt)))}</p>` : ""}
        ${lakeWideBanner(hour.lakeWide, view)}
        ${mapBoatNote()}
        ${zones ? `<ul class="zones">${zones}</ul>` : ""}
        ${windLine ? `<p class="small sub">${icon("wind")} ${h(windLine)}</p>` : ""}
        ${view.sample ? `<p class="small orange strong">${icon("triangle-alert")} ${h(t("Sample wind"))}</p>` : ""}
        <span class="tint">${h(t("Open lake view"))} ${icon("chevron-right")}</span>
      </div></a>`;
  box.hidden = false;
  const canvas = box.querySelector("canvas");
  drawMiniMap(canvas, view, hour, clubId);
  // Drawn again when it grows to fill its column (balanceCards in app.js).
  let size = `${canvas.clientWidth}x${canvas.clientHeight}`;
  new ResizeObserver(() => {
    const now = `${canvas.clientWidth}x${canvas.clientHeight}`;
    if (now !== size && canvas.isConnected) drawMiniMap(canvas, view, hour, clubId);
    size = now;
  }).observe(canvas);
}

// ---- The full lake map ----------------------------------------------------------------

let page = null;

/** The lake map page: map on top, the panel with the hours and the details below. */
export async function renderLakeMap(root, lakeId, clubId, back, at = null) {
  page?.map?.remove();
  root.innerHTML = `<div class="lake-screen"><header class="nav lake-nav"><a class="link" href="${h(back)}">${icon("chevron-left")} ${h(t("Back"))}</a>
      <span class="spacer"></span>
      <button class="tool" id="route-mode" aria-label="${h(t("Plan a route"))}">${icon("route")}</button>
      <button class="tool" id="legend" aria-label="${h(t("Legend"))}">${icon("layers")}</button>
      <button class="tool" id="about" aria-label="${h(t("About the lake view"))}">${icon("info")}</button></header>
    ${testing()}
    <div class="lake-page"><div class="lake-map" id="lake-map"></div><section class="lake-panel" id="lake-panel"><p>${h(t("Loading the forecast…"))}</p></section></div></div>`;
  let view;
  try {
    view = await viewForMap(lakeId);
  } catch {
    root.querySelector("#lake-panel").innerHTML = `<p><strong>${icon("wifi-off")} ${h(t("No forecast"))}</strong></p>`;
    return;
  }
  const water = WATER_TEXTS[waterKind(view)];
  setTitle(`${t(water.view)} · ${view.name}`);
  root.querySelector("#about").setAttribute("aria-label", t(water.about));
  const club = view.clubs.find((c) => c.id === clubId) ?? view.clubs[0];
  page = {
    root, view, club, lakeId, hour: hourIndex(view, at && !isNaN(at) ? at : new Date()), layer: "light", spot: null,
    routeMode: false, points: club ? [club.launchPoint] : [], undo: [], outAndBack: false, pace: 135,
    selected: null, followBoat: false, boatAt: 0, savedId: null, map: null, layers: {}, rowed: null, showTrack: true,
  };
  root.querySelector("#route-mode").addEventListener("click", toggleRouteMode);
  root.querySelector("#legend").addEventListener("click", () => openSheet(t("Legend"), legendSheet()));
  root.querySelector("#about").addEventListener("click", () => openSheet(t(water.about), aboutSheet()));
  await buildMap();
  update();
}

async function buildMap() {
  const L = await loadLeaflet().catch(() => null);
  const box = page.root.querySelector("#lake-map");
  if (!L || !box) return;
  const map = L.map(box, { zoomSnap: 0.25, attributionControl: true });
  page.map = map;
  page.L = L;
  const open = openBounds(page.view, page.club);
  map.fitBounds([[open.south, open.west], [open.north, open.east]], { padding: [12, 12] });
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19, referrerPolicy: "strict-origin", attribution: '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>',
  }).addTo(map);
  const rings = page.view.outline.map((ring) => ring.map(([lon, lat]) => [lat, lon]));
  page.layers.shore = L.polygon(rings, { fill: false, weight: 1, color: "rgba(0, 122, 255, .45)", interactive: false }).addTo(map);
  page.layers.arrows = L.layerGroup().addTo(map);
  page.layers.route = L.layerGroup().addTo(map);
  page.layers.marks = L.layerGroup().addTo(map);
  for (const c of page.view.clubs) {
    const own = c.id === page.club?.id;
    L.circleMarker([c.launchPoint.lat, c.launchPoint.lon], { radius: own ? 7 : 5, color: own ? "#fff" : "#007aff", weight: 2, fillColor: own ? "#007aff" : "#fff", fillOpacity: 1 })
      .bindTooltip(c.shortName).addTo(page.layers.marks);
  }
  // Where the club's stretch of the river ends: a weir or lock, or where rowers turn (SectionEndPin).
  for (const end of [page.view.section?.up, page.view.section?.down].filter(Boolean)) {
    const barrier = end.end === "weir/lock";
    const [text, ...args] = sectionEndTitle(end);
    L.marker([end.at.lat, end.at.lon], {
      icon: L.divIcon({ className: `pin end-pin ${barrier ? "barrier" : ""}`, html: icon(barrier ? "x" : "flag"), iconSize: [26, 26], iconAnchor: [13, 13] }),
      keyboard: false,
    }).bindTooltip(barrier ? t(text) + args[0] : t(text, ...args)).addTo(page.layers.marks);
  }
  map.on("click", (ev) => tapped({ lat: ev.latlng.lat, lon: ev.latlng.lng }));
  map.on("zoomend moveend", drawArrows);
  // The weather map's wind, for the arrows on land.
  loadLandWind(gridCentre(page.view)).then(() => map === page.map && drawArrows()).catch(() => {});
}

function shownHour() {
  const stop = boatStop(currentPlan()?.plan);
  if (stop) {
    let i = 0;
    page.view.hours.forEach((x, j) => {
      if (new Date(x.time) <= stop.time) i = j;
    });
    return page.view.hours[i];
  }
  return page.view.hours[page.hour];
}

function boatStop(plan) {
  if (!plan || !page.followBoat || !plan.stops.length) return null;
  return plan.stops[Math.min(plan.stops.length - 1, Math.floor(page.boatAt * plan.stops.length))];
}

function currentPlan() {
  if (!page.routeMode || page.points.length < 2) return null;
  const planner = routePlanner(page.view, page.points, page.outAndBack && !RouteEdit.isLoop(page.points));
  if (!planner) return null;
  const hour = page.view.hours[page.hour];
  const start = new Date(Math.max(new Date(hour.time).getTime(), Math.min(Date.now(), new Date(hour.time).getTime() + 3599000)));
  return { planner, plan: planRoute(planner, start, page.pace) };
}

function update() {
  const hour = shownHour();
  drawOverlay(hour);
  drawArrows();
  drawRoute();
  drawSpot();
  page.root.querySelector("#route-mode").classList.toggle("on", page.routeMode);
  page.root.querySelector("#lake-panel").innerHTML = page.routeMode ? planningPanel(hour) : viewingPanel(hour);
  wirePanel();
}

/** The cells smoothly scaled over the grid and clipped to the shore, drawn in the map's projection. */
function drawOverlay(hour) {
  const { L, map, view } = page;
  if (!map) return;
  const e = gridEdges(view.grid);
  const merc = (lat) => Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360));
  const k = Math.cos((((e.north + e.south) / 2) * Math.PI) / 180);
  const longest = 1800;
  const wDeg = (e.east - e.west) * k;
  const hDeg = e.north - e.south;
  const width = Math.round(wDeg >= hDeg ? longest : (longest * wDeg) / hDeg);
  const height = Math.round(wDeg >= hDeg ? (longest * hDeg) / wDeg : longest);
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  const x = (lon) => ((lon - e.west) / (e.east - e.west)) * width;
  const y = (lat) => ((merc(e.north) - merc(lat)) / (merc(e.north) - merc(e.south))) * height;
  const shore = new Path2D();
  for (const ring of view.outline) {
    if (ring.length < 3) continue;
    shore.moveTo(x(ring[0][0]), y(ring[0][1]));
    for (const p of ring.slice(1)) shore.lineTo(x(p[0]), y(p[1]));
    shore.closePath();
  }
  ctx.save();
  ctx.clip(shore, "evenodd");
  ctx.globalAlpha = 0.72;
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(rasterCanvas(view, hour, page.layer), 0, 0, width, height);
  ctx.globalAlpha = 1;
  const kind = page.layer === "light" ? stripes(hour.lakeWide) : null;
  if (kind) strokeStripes(ctx, kind, width, height, width / 500);
  ctx.restore();
  const url = canvas.toDataURL();
  if (page.layers.image) page.layers.image.setUrl(url);
  else page.layers.image = L.imageOverlay(url, [[e.south, e.west], [e.north, e.east]], { interactive: false }).addTo(map);
  const cold = coldShore(view.shoreWaterC, mapLimits());
  page.layers.shore.setStyle(cold ? { color: COLD_SHORE[cold], weight: cold === "cool" ? 2.5 : 3.5 } : { color: "rgba(0, 122, 255, .45)", weight: 1 });
  page.layers.shore.bringToFront();
}

/**
 * Arrows on an even grid over the whole map, finer as the map zooms in, fixed
 * to the map so they stay put while it moves; where the wind blows to, longer
 * in stronger wind. On land the wind is the weather map's own forecast, faded
 * in from the lake's over the first kilometre.
 */
function drawArrows() {
  const { L, map, view } = page;
  if (!map) return;
  const hour = shownHour();
  page.layers.arrows.clearLayers();
  const zoom = map.getZoom();
  const project = (lat, lon) => {
    const p = map.project([lat, lon], zoom);
    return [p.x, p.y];
  };
  const back = ([x, y]) => map.unproject([x, y], zoom);
  const bounds = map.getPixelBounds();
  const margin = arrowLength(15);
  const samples = view.points.flatMap((p, i) => {
    const w = hour.wind[i];
    if (w?.fromDeg == null) return [];
    const [x, y] = project(p.lat, p.lon);
    return [{ x, y, towardDeg: (w.fromDeg + 180) % 360, speedMs: w.speedMs ?? 0 }];
  });
  const rings = view.outline.filter((r) => r.length > 2).map((r) => r.map(([lon, lat]) => project(lat, lon)));
  const centre = map.getCenter();
  const fromLand = landWind(gridCentre(view), hour.time);
  const metresPerPixel = (40075016.686 * Math.cos((centre.lat * Math.PI) / 180)) / (256 * 2 ** zoom);
  const arrows = windArrows({
    area: [bounds.min.x - margin, bounds.min.y - margin, bounds.max.x + margin, bounds.max.y + margin],
    spacing: SPACING, rings, samples, blend: BLEND_M / metresPerPixel,
    land: fromLand && ((p) => {
      const ll = back(p);
      return fromLand({ lat: ll.lat, lon: ll.lng });
    }),
  });
  // On land as on the water, at full strength.
  const paths = arrows.flatMap((a) => arrowLines(a.x, a.y, a.towardDeg, arrowLength(a.speedMs)).map((line) => line.map(back)));
  if (!paths.length) return;
  L.polyline(paths, { color: "rgba(255, 255, 255, .7)", weight: 4, interactive: false, lineCap: "round" }).addTo(page.layers.arrows);
  L.polyline(paths, { color: "rgba(26, 26, 26, .75)", weight: 2, interactive: false, lineCap: "round" }).addTo(page.layers.arrows);
}

/** Even-odd test against the shore and islands. */
const onWater = (lat, lon) => inside(page.view.outline, [lon, lat]);

/** The middle of the lake's grid. */
function gridCentre(view) {
  const e = gridEdges(view.grid);
  return { lat: (e.north + e.south) / 2, lon: (e.west + e.east) / 2 };
}

function drawSpot() {
  const { L, map } = page;
  if (!map) return;
  page.layers.spot?.remove();
  page.layers.spot = null;
  if (page.spot == null || page.routeMode) return;
  page.layers.spot = L.circleMarker([page.spot.at.lat, page.spot.at.lon], { radius: 9, color: "#007aff", weight: 3, fill: false, interactive: false }).addTo(map);
}

function tapped(at) {
  const cell = cellAt(page.view.grid, at);
  if (page.routeMode) {
    if (cell == null && !onWater(at.lat, at.lon)) return;
    page.undo.push(page.points);
    page.points = RouteEdit.add(at, page.points);
    page.selected = null;
  } else {
    page.spot = cell == null ? null : { cell, at };
  }
  update();
}

// ---- Panels ---------------------------------------------------------------------------

function hourStrip() {
  return `<div class="hour-strip" id="hour-strip">${page.view.hours.map((x, i) => {
    const s = shares(x);
    const bar = ["green", "amber", "red"].filter((l) => s[l]).map((l) => {
      const shown = x.lakeWide.light === "red" ? "red" : x.lakeWide.light === "amber" && l === "green" ? "amber" : l;
      return `<span style="width:${s[l] * 100}%;background:var(--${shown})"></span>`;
    }).join("");
    return `<button data-hour="${i}" class="${i === page.hour ? "on" : ""}" aria-label="${h(dayTime(x.time))}"><small>${h(time(x.time))}</small><span class="share">${bar}</span></button>`;
  }).join("")}</div>`;
}

const legendLine = () => layerLegend(page.layer);

/** The colours of a layer: the three lights, or the ramp for waves or wind up to the map boat's limits. */
export function layerLegend(layer) {
  const limits = mapLimits();
  if (layer === "light") {
    return `<p class="legend-line">${["green", "amber", "red"].map((l) => `<span>${dot(l, 9)} ${h(lightTitle(l))}</span>`).join("")}</p>`;
  }
  const [amber, red, fmt] = layer === "waves"
    ? [limits.value("waveAmber"), limits.value("waveRed"), waves]
    : [limits.value("windAmber"), limits.value("windRed"), wind];
  const top = red * 1.6;
  const stops = Array.from({ length: 11 }, (_, i) => rgb(ramp((top * i) / 10, amber, red))).join(", ");
  return `<div class="ramp"><span class="bar" style="background:linear-gradient(90deg, ${stops})"></span>
    <span class="labels"><small style="left:0">${h(fmt(0))}</small><small style="left:${(amber / top) * 100}%">${h(fmt(amber))}</small><small style="left:${(red / top) * 100}%">${h(fmt(red))}</small></span></div>`;
}

function viewingPanel(hour) {
  const { view } = page;
  const stale = viewStale(view);
  const layers = [["light", t("Rowing light")], ["waves", t("Waves")], ["wind", t("Wind")]];
  let details;
  if (page.spot != null && page.spot.cell < hour.lights.length) {
    const i = page.spot.cell;
    // A lake-wide red (DWD warning, darkness) holds at every spot.
    const spotLight = hour.lakeWide.light === "red" ? "red" : hour.lights[i];
    const w = hour.wind[view.grid.cellPoint[i]];
    const zone = view.grid.cellZone[i];
    details = `<div class="spot"><p class="spot-head">${dot(spotLight, 14, stale)} <strong>${h(lightTitle(spotLight, stale))}</strong>
        <button class="tool" id="spot-close" aria-label="${h(t("Close"))}">${icon("x")}</button></p>
      ${view.zones.length > 1 && view.zones[zone] ? `<small class="sub">${h(t("Selected spot · %@", t(zoneTitle(view.zones[zone], waterKind(view)))))}</small>` : ""}
      <div class="now-metrics"><div><small class="label">${icon("waves")} ${h(t("Waves"))}</small><span>${h(waves(hour.wavesCm[i] / 100))}</span></div>
        <div><small class="label">${icon("wind")} ${h(t("Wind"))}</small><span>${h(windRange(w?.speedMs, w?.gustMs))} ${h(windUnit())}</span></div>
        ${w?.fromDeg != null ? `<div><small class="label">${icon("navigation")} ${h(t("From"))}</small><span>${h(compass(w.fromDeg))}</span></div>` : ""}</div></div>`;
  } else {
    const windLine = windText(hour);
    const top = maxWave(hour);
    details = `<p class="strong">${h(headlineText(view, hour))}</p>
      ${windLine ? `<p class="small sub">${icon("wind")} ${h(windLine)}</p>` : ""}
      ${top != null ? `<p class="small sub">${icon("waves")} ${h(t("Waves up to %@", waves(top)))}</p>` : ""}
      <p class="small sub">${h(t("Tap the water to see the conditions there."))}</p>`;
  }
  return `<div class="segmented" id="layers">${layers.map(([k, label]) => `<button data-layer="${k}" class="${page.layer === k ? "on" : ""}">${h(label)}</button>`).join("")}</div>
    <p class="panel-head"><strong>${h(dayTime(hour.time))}</strong>${view.sample ? `<span class="small orange strong">${icon("triangle-alert")} ${h(t("Sample wind"))}</span>` : ""}</p>
    ${stale ? `<p class="small orange strong">${icon("clock")} ${h(t("Forecast out of date: from %@. Check the conditions yourself.", dayTime(view.generatedAt)))}</p>` : ""}
    ${lakeWideBanner(hour.lakeWide, view)}
    ${kitBadge(view)}
    ${details}
    ${legendLine()}
    ${mapBoatNote()}
    ${hourStrip()}`;
}

function planningPanel(hour) {
  const { view } = page;
  const found = currentPlan();
  const plan = found?.plan;
  const stop = boatStop(plan);
  const isLoop = RouteEdit.isLoop(page.points);
  const saved = store.routes.filter((r) => r.lakeId === page.lakeId);
  let summary;
  if (plan) {
    const rough = roughest(plan);
    const roughText = rough && plan.worstLight !== "green" ? (() => {
      const parts = [waves(rough.waveM) + (rough.relation ? ` ${t(RELATION_WAVES[rough.relation])}` : "")];
      if (rough.windMs != null) parts.push(`${windRange(rough.windMs, rough.gustMs)} ${windUnit()}${rough.relation ? ` ${t(RELATION_WIND[rough.relation])}` : ""}`);
      const zone = view.grid.cellZone[rough.cell] ?? 0;
      const place = view.zones.length > 1 && view.zones[zone] ? `, ${t(zoneTitle(view.zones[zone], waterKind(view)))}` : "";
      return `${t("Roughest at %@", time(rough.time))}${place}: ${parts.join(", ")}`;
    })() : null;
    const better = bestStart(found.planner, page.pace);
    const betterIndex = better && plansBetter(better, plan) ? view.hours.reduce((n, x, i) => (new Date(x.time) <= better.start ? i : n), 0) : null;
    summary = `<p class="route-line">${dot(plan.worstLight, 10)} <strong>${h(lightTitle(plan.worstLight))}</strong>
        <span class="sub">${h(t("%@ · %@ · back %@", distance(plan.distanceM), duration(plan.start, plan.end), time(plan.end)))}</span></p>
      ${routeBar(plan)}
      <p class="small sub">${h(t("Waves up to %@", waves(plan.maxWaveM)))}</p>
      ${roughText ? `<p class="small sub">${h(roughText)}</p>` : ""}
      ${plan.beyondForecast ? `<p class="small orange">${icon("clock")} ${h(t("The forecast ends before you are back."))}</p>` : ""}
      ${viewStale(view) ? `<p class="small orange strong">${icon("clock")} ${h(t("Forecast out of date: from %@. Check the conditions yourself.", dayTime(view.generatedAt)))}</p>` : ""}
      ${adviceOnly()}
      ${page.followBoat ? "" : tip("boatTime")}
      <p class="boat-follow"><label class="tick inline"><input type="checkbox" id="follow" ${page.followBoat ? "checked" : ""}> ${icon("sailboat")} ${h(t("Lake at the boat's time"))}</label>
        ${page.followBoat ? `<input type="range" id="boat-at" min="0" max="1" step="0.01" value="${page.boatAt}" aria-label="${h(t("Where the boat is"))}">` : ""}</p>
      ${stop ? `<p class="small sub">${h(t("The boat at %@ after %@: %@, waves %@", time(stop.time), distance(stop.distanceM), lightTitle(stop.light), waves(stop.waveM) + (stop.relation ? ` ${t(RELATION_WAVES[stop.relation])}` : "")))}</p>` : ""}
      ${betterIndex != null ? `<button class="link" id="better" data-hour="${betterIndex}">${icon("clock")} ${h(t("Better start: %@ · %@", dayTime(better.start), lightTitle(better.worstLight)))}</button>` : ""}`;
  } else {
    summary = `<p class="small">${h(t("Tap the water to add the turning points of your route. It starts at your club and goes one way; turn on Out and back to row the same way back. Tap or pull a stretch to add a point there. Tap a point to delete it, or drag it to move it. A point within 50 m of the start closes the loop."))}</p>`;
  }
  const selected = page.selected != null ? `<p class="point-bar"><strong>${h(t("Turning point %d", page.selected))}</strong>
      <button class="link red" id="delete-point">${icon("trash-2")} ${h(t("Delete point"))}</button><button class="link" id="point-done">${h(t("Done"))}</button></p>` : "";
  return `${selected}
    <div class="route-tools">
      <button class="pill" id="undo" ${page.undo.length ? "" : "disabled"}>${icon("undo-2")} ${h(t("Undo"))}</button>
      <button class="pill" id="close-loop" ${page.points.length >= 3 && !isLoop ? "" : "disabled"}>${icon("rotate-ccw")} ${h(t("Close loop"))}</button>
      <button class="pill" id="clear" ${page.points.length > 1 ? "" : "disabled"}>${icon("trash-2")} ${h(t("Clear route"))}</button>
      <button class="pill" id="save-route" ${page.points.length > 1 ? "" : "disabled"}>${icon("check")} ${h(t("Save route"))}</button>
      <label class="pill" id="import-row" title="${h(t("GPX, TCX or FIT files from CrewNerd, Garmin Connect, Strava and other apps."))}">${icon("upload")} ${h(t("Import a row"))}
        <input type="file" accept=".gpx,.tcx,.fit,application/gpx+xml,application/vnd.garmin.tcx+xml" hidden></label>
      ${page.rowed?.track ? `<label class="tick inline"><input type="checkbox" id="show-track" ${page.showTrack ? "checked" : ""}> ${icon("spline")} ${h(t("Show rowed track"))}</label>` : ""}
    </div>
    ${routeTip(isLoop)}
    ${lakeWideBanner(hour.lakeWide, view)}
    ${kitBadge(view)}
    <div class="route-controls">
      <span class="start"><button class="tool" id="earlier" aria-label="${h(t("An hour earlier"))}" ${page.hour <= 0 ? "disabled" : ""}>${icon("chevron-left")}</button>
        <label><small class="sub">${h(t("Start"))}</small><select id="start">${view.hours.map((x, i) => `<option value="${i}" ${i === page.hour ? "selected" : ""}>${h(dayTime(x.time))}</option>`).join("")}</select></label>
        <button class="tool" id="later" aria-label="${h(t("An hour later"))}" ${page.hour >= view.hours.length - 1 ? "disabled" : ""}>${icon("chevron-right")}</button></span>
      <span class="pace"><small class="sub">${h(t("Pace /500 m"))}</small><strong class="num">${h(paceText(page.pace))}</strong>
        <span class="stepper"><button id="pace-down" aria-label="−">−</button><button id="pace-up" aria-label="+">+</button></span></span>
      <label class="tick inline" title="${h(t("Out and back"))}"><input type="checkbox" id="out-back" ${page.outAndBack && !isLoop ? "checked" : ""} ${isLoop ? "disabled" : ""}> ${icon("arrow-up-down")} ${h(t("Out and back"))}</label>
    </div>
    ${summary}
    ${saved.length ? `<h3 class="section">${icon("list")} ${h(t("Saved routes"))}</h3><ul class="saved-routes">${saved.map((r) => `<li class="${r.id === page.savedId ? "on" : ""}">
        <button data-route="${h(r.id)}">${icon("route")} <span>${h(r.name)}</span><small class="sub">${h(distance(routeLength(r.points, r.outAndBack)))}</small></button>
        <button class="tool" data-rename-route="${h(r.id)}" aria-label="${h(t("Rename"))}" title="${h(t("Rename"))}">${icon("signature")}</button>
        <button class="tool" data-copy-route="${h(r.id)}" aria-label="${h(t("Duplicate"))}" title="${h(t("Duplicate"))}">${icon("copy")}</button>
        <button class="tool" data-delete-route="${h(r.id)}" aria-label="${h(t("Delete this route"))}">${icon("trash-2")}</button></li>`).join("")}</ul>` : ""}`;
}

/** The one tip that fits the route drawn so far, in the app's order (LakeMapScreen.routeHint). */
function routeTip(isLoop) {
  const n = page.points.length;
  if (page.selected != null) return tip("turningPoint");
  if (n >= 3 && !isLoop && tip("closeLoop")) return tip("closeLoop");
  if (n >= 3) return tip("stretchPoint");
  if (n === 2 && !page.outAndBack) return tip("oneWay");
  return n < 2 ? tip("rowImport") : "";
}

/** The route from start to finish as a bar, coloured by the light at each stretch (RouteBar). */
function routeBar(plan) {
  let from = 0;
  const parts = plan.stops.map((s, i) => {
    const to = i + 1 < plan.stops.length ? (s.distanceM + plan.stops[i + 1].distanceM) / 2 : plan.distanceM;
    const part = `<span style="width:${((to - from) / plan.distanceM) * 100}%;background:var(--${s.light})"></span>`;
    from = to;
    return part;
  });
  return `<span class="route-bar">${parts.join("")}</span>`;
}

function drawRoute() {
  const { L, map } = page;
  if (!map) return;
  const group = page.layers.route;
  group.clearLayers();
  if (!page.routeMode) return;
  const found = currentPlan();
  if (found) {
    for (const seg of found.plan.segments) {
      L.polyline(seg.points.map((p) => [p.lat, p.lon]), { color: "#fff", weight: 8, opacity: 0.9, interactive: false }).addTo(group);
      L.polyline(seg.points.map((p) => [p.lat, p.lon]), { color: `rgb(${RGB[seg.light].join(",")})`, weight: 5, interactive: false }).addTo(group);
    }
    const stop = boatStop(found.plan);
    if (stop) L.circleMarker([stop.coordinate.lat, stop.coordinate.lon], { radius: 8, color: "#fff", weight: 2, fillColor: "#5856d6", fillOpacity: 1 }).addTo(group);
  }
  // The imported row as it was rowed, thin over the route (RowedTrackLine).
  if (page.rowed?.track && page.showTrack) {
    L.polyline(page.rowed.track.map((p) => [p.lat, p.lon]), { color: "#fff", weight: 3.5, opacity: 0.8, interactive: false }).addTo(group);
    L.polyline(page.rowed.track.map((p) => [p.lat, p.lon]), { color: "#5856d6", weight: 2, interactive: false }).addTo(group);
  }
  // A thin line to tap: a tap on a stretch adds a turning point there.
  page.points.forEach((p, i) => {
    if (i === 0) return;
    const a = page.points[i - 1];
    L.polyline([[a.lat, a.lon], [p.lat, p.lon]], { color: "transparent", weight: 18 })
      .on("click", (ev) => {
        L.DomEvent.stop(ev);
        page.undo.push(page.points);
        page.points = RouteEdit.insert({ lat: ev.latlng.lat, lon: ev.latlng.lng }, i, page.points);
        update();
      }).addTo(group);
  });
  const isLoop = RouteEdit.isLoop(page.points);
  page.points.forEach((p, i) => {
    if (i === 0 || (isLoop && i === page.points.length - 1)) return;
    const marker = L.marker([p.lat, p.lon], {
      draggable: true,
      icon: L.divIcon({ className: `turn ${page.selected === i ? "on" : ""}`, html: `<span>${i}</span>`, iconSize: [24, 24], iconAnchor: [12, 12] }),
    }).addTo(group);
    marker.on("click", (ev) => {
      L.DomEvent.stop(ev);
      page.selected = i;
      update();
    });
    marker.on("dragend", () => {
      const ll = marker.getLatLng();
      page.undo.push(page.points);
      page.points = RouteEdit.move(i, { lat: ll.lat, lon: ll.lng }, page.points);
      update();
    });
  });
}

function wirePanel() {
  const panel = page.root.querySelector("#lake-panel");
  const on = (sel, event, fn) => panel.querySelector(sel)?.addEventListener(event, fn);
  panel.querySelectorAll("#hour-strip [data-hour]").forEach((b) => b.addEventListener("click", () => {
    page.hour = Number(b.dataset.hour);
    update();
  }));
  panel.querySelector("#hour-strip .on")?.scrollIntoView({ inline: "center", block: "nearest" });
  panel.querySelectorAll("[data-layer]").forEach((b) => b.addEventListener("click", () => {
    page.layer = b.dataset.layer;
    update();
  }));
  on("#spot-close", "click", () => {
    page.spot = null;
    update();
  });
  const edit = (fn) => () => {
    page.undo.push(page.points);
    page.points = fn(page.points);
    page.selected = null;
    update();
  };
  on("#undo", "click", () => {
    page.points = page.undo.pop() ?? page.points;
    page.selected = null;
    update();
  });
  on("#close-loop", "click", edit((p) => RouteEdit.close(p)));
  on("#clear", "click", edit((p) => {
    page.rowed = null;
    return p.slice(0, 1);
  }));
  on("#delete-point", "click", edit((p) => RouteEdit.remove(page.selected, p)));
  on("#point-done", "click", () => {
    page.selected = null;
    update();
  });
  on("#earlier", "click", () => {
    page.hour = Math.max(0, page.hour - 1);
    update();
  });
  on("#later", "click", () => {
    page.hour = Math.min(page.view.hours.length - 1, page.hour + 1);
    update();
  });
  on("#start", "change", (e) => {
    page.hour = Number(e.target.value);
    update();
  });
  on("#better", "click", (e) => {
    page.hour = Number(e.currentTarget.dataset.hour);
    update();
  });
  on("#pace-down", "click", () => {
    page.pace = Math.max(90, page.pace - 5);
    update();
  });
  on("#pace-up", "click", () => {
    page.pace = Math.min(240, page.pace + 5);
    update();
  });
  on("#out-back", "change", (e) => {
    page.outAndBack = e.target.checked;
    update();
  });
  on("#follow", "change", (e) => {
    page.followBoat = e.target.checked;
    update();
  });
  on("#boat-at", "input", (e) => {
    page.boatAt = Number(e.target.value);
    const hour = shownHour();
    drawOverlay(hour);
    drawArrows();
    drawRoute();
  });
  on("#boat-at", "change", () => update());
  on("#save-route", "click", saveRoute);
  on("#import-row input", "change", (e) => importRow(e.target.files?.[0]));
  on("#show-track", "change", (e) => {
    page.showTrack = e.target.checked;
    drawRoute();
  });
  wireTips(panel);
  panel.querySelectorAll("[data-route]").forEach((b) => b.addEventListener("click", () => {
    const r = store.routes.find((x) => x.id === b.dataset.route);
    if (!r) return;
    page.undo.push(page.points);
    page.points = r.points;
    page.outAndBack = r.outAndBack;
    page.savedId = r.id;
    page.rowed = r.track ? r : null;
    update();
  }));
  // Rename and duplicate, as under Manage routes in the app (ManageRoutesView).
  panel.querySelectorAll("[data-rename-route]").forEach((b) => b.addEventListener("click", () => {
    const r = store.routes.find((x) => x.id === b.dataset.renameRoute);
    const name = r && prompt(t("Rename route"), r.name);
    if (!name?.trim()) return;
    store.routes = store.routes.map((x) => (x.id === r.id ? { ...x, name: name.trim() } : x));
    update();
  }));
  panel.querySelectorAll("[data-copy-route]").forEach((b) => b.addEventListener("click", () => {
    const r = store.routes.find((x) => x.id === b.dataset.copyRoute);
    if (!r) return;
    const copy = { ...r, id: crypto.randomUUID?.() ?? `r${Date.now()}`, name: t("%@ (copy)", r.name) };
    const all = [...store.routes];
    all.splice(all.indexOf(r) + 1, 0, copy);
    store.routes = all;
    update();
  }));
  panel.querySelectorAll("[data-delete-route]").forEach((b) => b.addEventListener("click", () => {
    const r = store.routes.find((x) => x.id === b.dataset.deleteRoute);
    if (!r || !confirm(t("Delete “%@”?", r.name))) return;
    store.routes = store.routes.filter((x) => x.id !== r.id);
    if (page.savedId === r.id) page.savedId = null;
    update();
  }));
}

function saveRoute() {
  const existing = store.routes.find((r) => r.id === page.savedId);
  const fallback = t("Route %@", distance(routeLength(page.points, page.outAndBack)));
  const name = prompt(t("Save route"), existing?.name ?? fallback);
  if (name == null) return;
  const route = { id: existing?.id ?? crypto.randomUUID?.() ?? `r${Date.now()}`, name: name.trim() || fallback, lakeId: page.lakeId, points: page.points, outAndBack: page.outAndBack };
  // A changed imported route keeps the row's track.
  if (page.rowed) Object.assign(route, { track: page.rowed.track, rowedAt: page.rowed.rowedAt, importedFrom: page.rowed.importedFrom });
  const list = store.routes;
  const i = list.findIndex((r) => r.id === route.id);
  if (i >= 0) list[i] = route;
  else list.push(route);
  store.routes = list;
  page.savedId = route.id;
  update();
}

/** A GPX, TCX or FIT file becomes a saved route on this lake, planned at the pace it was rowed (LakeMapScreen.importRow). */
async function importRow(file) {
  if (!file) return;
  let points;
  try {
    points = readTrack(await file.arrayBuffer());
  } catch {
    alert(t("Row Frog could not read a GPS track in this file."));
    return;
  }
  const { view } = page;
  if (shareOnWater(points, view.grid) < 0.5) {
    alert(t("This row was not on %@.", view.name));
    return;
  }
  const row = routeFromTrack(points, view.clubs.map((c) => c.launchPoint));
  if (!row) {
    alert(t("This row is too short to make a route of."));
    return;
  }
  const date = new Intl.DateTimeFormat(document.documentElement.lang || "en", { day: "numeric", month: "short" }).format(row.rowedAt ? new Date(row.rowedAt) : new Date());
  const route = {
    id: crypto.randomUUID?.() ?? `r${Date.now()}`, name: t("Rowed %@, %@", date, distance(row.distanceM)), lakeId: page.lakeId,
    points: row.points, outAndBack: row.outAndBack, track: row.track, rowedAt: row.rowedAt, importedFrom: "file",
  };
  store.routes = [...store.routes, route];
  if (row.pace) page.pace = plannedPace(row.pace);
  page.undo.push(page.points);
  page.points = route.points;
  page.outAndBack = route.outAndBack;
  page.savedId = route.id;
  page.rowed = route;
  page.showTrack = true;
  update();
}

function toggleRouteMode() {
  page.routeMode = !page.routeMode;
  page.spot = null;
  page.selected = null;
  update();
}

function legendSheet() {
  const row = (sym, text) => `<li>${sym}<span>${h(text)}</span></li>`;
  const cold = coldShore(page.view.shoreWaterC, mapLimits());
  return `<h3>${h(t("Rowing light"))}</h3><ul class="legend">
      ${["green", "amber", "red"].map((l) => row(dot(l, 14), lightTitle(l))).join("")}
      ${row(`<span class="stripes red"></span>`, t("Grey squares with red stripes: the whole lake is red (official warning or darkness), see the panel."))}
      ${row(`<span class="stripes amber"></span>`, t("Amber stripes: the whole lake is amber (sunrise or sunset, official warning), see the panel. The squares keep their own colours."))}</ul>
    <h3>${h(t("On the map"))}</h3><ul class="legend">
      ${row(`<span class="club-mark own"></span>`, t("The club of this page"))}
      ${row(`<span class="club-mark"></span>`, t("Other clubs on the lake"))}
      ${cold ? row(`<span class="shore-mark" style="background:${COLD_SHORE[cold]}"></span>`, t("Blue shore: the water is cold. Bring a life jacket; light blue below %@, deeper blue below %@.", temperature(mapLimits().value("lifeJacket")), temperature(10))) : ""}
      ${row(icon("arrow-up"), t("Wind: points where the wind blows to; longer arrows mean stronger wind. Between the forecast points the wind is estimated from the nearest ones. On land the arrows show the weather map's wind forecast for each place."))}</ul>
    <h3>${h(t("Route"))}</h3><ul class="legend">
      ${row(`<span class="club-mark own"></span>`, t("Start at your club"))}
      ${row(`<span class="turn-mark">1</span>`, t("Turning point: tap to select, hold and drag to move"))}
      ${row(`<span class="route-bar small"><span style="width:50%;background:var(--green)"></span><span style="width:50%;background:var(--amber)"></span></span>`, t("The route in the light the boat meets there; out and back run side by side"))}
      ${row(`<span class="club-mark boat"></span>`, t("Where the boat is at the time shown"))}</ul>`;
}

function aboutSheet() {
  const river = waterKind(page.view) !== "lake"
    ? `<p>${h(t("The view shows your club's stretch of the river: to the next weir or lock each way, or where a bigger river joins, else about 12 km upstream and 8 km downstream (10 km each way on canals). Markers show where it ends. It opens on the 10 km around your club."))}</p>`
    : "";
  return `${river}<p>${h(t("The lake is divided into small squares. For each square and hour, the app takes the wind from the nearest forecast point and works out the waves from how much open water the wind has crossed to get there."))}</p>
    <p>${h(t("Each square gets the same rowing light as a club page, from wind, gusts, waves, fog and thunderstorm risk at that square. Official warnings, darkness and cold water apply to the whole lake and are shown in the panel below the map. While they make the whole lake red, the squares turn grey with red stripes; at sunrise or sunset and under an amber official warning, fainter amber stripes are drawn over the squares. Cold water draws the shore blue and adds the life-jacket badge to the panel."))}</p>
    <p>${h(t("Waves are an estimate: there are no wave measurements on these lakes, and shelter from steep shores or currents is not taken into account."))}</p>
    <h3>${h(t("Data"))}</h3>
    ${(page.view.attribution ?? []).map((a) => `<p class="sub small">${h(t(a))}</p>`).join("")}`;
}
