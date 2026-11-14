// The lake view: the tile on a club page (LakeViewCard) and the full lake map
// with the hours, the layers, a tapped spot and route planning (LakeMapScreen).

import { baseMap } from "./basemap.js";
import { t, lang } from "./i18n.js";
import { icon } from "./icons.js";
import {
  store, getJSON, h, time, dayTime, duration, wind, windRange, waves, distance, temperature, lightTitle, reasonLabel, coldWaterText,
  dot, setTitle, openSheet, openMenu, loadLeaflet, testing, adviceOnly, mapBoat, mapLimits, boatInSentence, windUnit, dayLabel,
  CONDITION_ICONS, forecasts, conditionIcon, boatControl, loadCatalog, rain, wavesNumber, distanceNumber, unitSymbol,
} from "./shared.js";
import { riverSpeed } from "./river.js";
import { compass, matchesStandard, coldWaterKit, reasonCondition, key, sunDaysOf } from "./logic.js";
import {
  decodeView, hourIndex, viewStale, applyLakeLimits, stripes, stripesFall, coldShore, shares, zoneTitle, headline, windSummary, maxWave,
  waterKind, WATER_TEXTS, sectionEndTitle, openBounds,
  gridEdges, cellAt, cellColours, rasterPixels, fineLight, RGB, ramp, RouteEdit, routeLength, routePlanner, planRoute, bestStart, plansBetter,
  roughest, RELATION_WIND, RELATION_WAVES, pace as paceText, clubhouseOf, showsOars, shouldSplit, spotProbe, windAt, withDaylightNow,
  zoneNotes, zoneNoteText, zoneValues, arrowGlyph, fogginess, visibilityColour, hasVisibility,
} from "./lake.js";
import { readTrack, shareOnWater, routeFromTrack, plannedPace } from "./rowimport.js";
import { tip, wireTips, closeTip, bubbleTip } from "./tour.js";
import { routeDraft } from "./routedraft.js";
import { routeLink, readRouteLink, addSharedRoutes } from "./routelink.js";
import { downloadGpx } from "./routegpx.js";
import { loadLandWind, landWind } from "./weathermap.js";
import { SPACING, BLEND_M, arrowLength, arrowLines, windArrows, inside } from "./windarrows.js";

const views = new Map();
/** The route editor's statechart, the app's own file (ios/RowFrog/Charts, copied by scripts/build_web.py). */
let routeChart;
const loadRouteChart = () => (routeChart ??= fetch(new URL("charts/route-editor.json", import.meta.url)).then((r) => r.json()));

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

/** The sunrise and sunset of the club page that last showed each lake, for "now" on the lake (LakeViewStore.noteDaylight). */
const clubDays = new Map();
const noteDaylight = (lakeId, clubId) => {
  const days = sunDaysOf(forecasts.get(clubId)?.value);
  if (days.length) clubDays.set(lakeId, days);
};

/** The lake coloured for the map's boat, with the water the shore is drawn by; "now" by this minute's daylight. */
export async function viewForMap(lakeId) {
  const raw = withDaylightNow(await loadView(lakeId), clubDays.get(lakeId));
  const limits = mapLimits();
  const view = applyLakeLimits(raw, limits, matchesStandard(limits));
  return { ...view, clubs: await withClubhouses(lakeId, view.clubs), shoreWaterC: raw.waterC ?? clubWater.get(lakeId) ?? null };
}

/**
 * The lake view's clubs with the spot their pin moves to once zoomed in (`clubhouse`: the club's
 * place in OpenStreetMap or its hand-checked clubhouse, when apart from the launch point) and
 * whether oars then mark the launch point (`oars`), from the club list (ClubMarks.clubhouse).
 */
async function withClubhouses(lakeId, clubs) {
  const lakes = await loadCatalog().catch(() => []);
  const known = new Map(lakes.filter((l) => l.id === lakeId).flatMap((l) => l.clubs).map((c) => [c.id, c]));
  return clubs.map((c) => {
    const listed = { ...known.get(c.id), launchPoint: c.launchPoint };
    return { ...c, clubhouse: clubhouseOf(listed), oars: showsOars(listed) };
  });
}

/**
 * Splits and joins the clubs' pins on a Leaflet map as it zooms (ClubPinSplitter): each entry's
 * marker stands on the launch point until the clubhouse is `CLUB_SPLIT_AT` pixels away, then moves
 * there while oars in the club's colour mark the launch point, below the club's pin (only for a set
 * launch point: entries with `oars: false` move without them).
 */
export function splitClubPins(L, map, entries) {
  const pairs = entries.filter((e) => e.clubhouse).map((e) => ({
    ...e, split: false, withOars: e.oars,
    oars: L.marker([e.launch.lat, e.launch.lon], {
      icon: L.divIcon({ className: `club-pin oars ${e.own ? "own" : ""}`, iconSize: [26, 26], iconAnchor: [13, 13], html: `<span class="dot">${icon("oars")}</span>` }),
      title: e.own ? t("Launch point") : "", keyboard: false, zIndexOffset: -1000, interactive: false,
    }),
  }));
  const update = () => {
    for (const pair of pairs) {
      const a = map.latLngToContainerPoint([pair.launch.lat, pair.launch.lon]);
      const b = map.latLngToContainerPoint([pair.clubhouse.lat, pair.clubhouse.lon]);
      const now = shouldSplit(a.distanceTo(b), pair.split);
      if (now === pair.split) continue;
      pair.split = now;
      const at = now ? pair.clubhouse : pair.launch;
      pair.marker.setLatLng([at.lat, at.lon]);
      if (now && pair.withOars !== false) pair.oars.addTo(pair.layer ?? map);
      else pair.oars.remove();
    }
  };
  if (pairs.length) {
    map.on("zoomend", update);
    update();
  }
}

const rgb = (c, a = 1) => `rgba(${Math.round(c[0])}, ${Math.round(c[1])}, ${Math.round(c[2])}, ${a})`;
export const COLD_SHORE = { cool: "rgb(92, 168, 242)", cold: "rgb(20, 84, 194)" };

/**
 * The waves page's map (DetailLakeCard, owner 13 Nov 2026): the lake view's waves at an hour, in the place the
 * other value pages have their weather map; the link opens the lake view on its waves at that hour.
 * Returns a function that draws another hour, or null when the club has no lake view.
 */
export async function fillWavesMap(box, lakeId, clubId, at) {
  let view;
  try {
    view = await viewForMap(lakeId);
  } catch {
    return null;
  }
  if (!view.hours.length || !box.isConnected) return null;
  box.innerHTML = `<a class="wm-head lake-head" href="#"><span class="i-wrap">${icon("waves")}</span><strong class="when"></strong>
      <span class="wm-open">${icon("maximize-2")}</span></a><canvas class="mini wm-lake" role="img"></canvas>`;
  const link = box.querySelector("a"), canvas = box.querySelector("canvas");
  let shown = at;
  const draw = (date) => {
    shown = date;
    const hour = view.hours[hourIndex(view, date)];
    const first = view.hours[0].time, last = view.hours[view.hours.length - 1].time;
    const outside = date < new Date(first) || date >= new Date(new Date(last).getTime() + 3600e3);
    box.querySelector(".when").textContent = `${view.name} · ${dayTime(hour.time)}`;
    link.href = `#/lake/${encodeURIComponent(lakeId)}/${encodeURIComponent(clubId)}?at=${encodeURIComponent(hour.time)}&layer=waves`;
    canvas.setAttribute("aria-label", t("Opens the lake view"));
    canvas.classList.toggle("outside", outside);
    drawMiniMap(canvas, view, hour, clubId, "waves");
  };
  draw(at);
  draw.hours = view.hours.map((x) => x.time);
  canvas.addEventListener("click", () => link.click());
  new ResizeObserver(() => canvas.isConnected && draw(shown)).observe(canvas);
  return draw;
}

/**
 * The hour's lights (or waves, wind) as a small picture for smooth scaling: one pixel per cell, and for the
 * rowing light finer, judged per pixel from the blended values (LakeRaster.image, fineLight).
 */
export function rasterCanvas(view, hour, layer) {
  const limits = mapLimits();
  const { width, height, data } = (layer === "light" && fineLight(view, hour, limits)) || rasterPixels(view, cellColours(view, hour, layer, limits));
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  canvas.getContext("2d").putImageData(new ImageData(data, width, height), 0, 0);
  return canvas;
}

function strokeStripes(ctx, kind, w, hgt, scale = 1, fall = false) {
  const red = kind === "red";
  ctx.strokeStyle = red ? "rgba(255, 59, 48, .55)" : "rgba(255, 149, 0, .75)";
  ctx.lineWidth = (red ? 1.5 : 1.2) * scale;
  ctx.beginPath();
  const gap = (red ? 8 : 14) * scale;
  for (let x = -hgt; x < w; x += gap) {
    ctx.moveTo(x, fall ? 0 : hgt);
    ctx.lineTo(x + hgt, fall ? hgt : 0);
  }
  ctx.stroke();
}

/** On-screen size of the whole-lake stripes on the lake map, in CSS pixels (the mini map draws them at 1). */
const MAP_STRIPE_SCALE = 1.6;

/**
 * Stripes over a tile, continuing from tile to tile: lines placed in the map's global pixels
 * (`ox`, `oy` = the tile's top left), `gap` apart along x, rising or falling at 45°.
 */
function strokeTileStripes(ctx, kind, size, ox, oy, fall) {
  const red = kind === "red";
  // The pane is drawn at COLOUR_OPACITY as a whole, so the stripes are stronger here to look as before.
  ctx.strokeStyle = red ? `rgba(255, 59, 48, ${0.55 / COLOUR_OPACITY})` : "rgb(255, 149, 0)";
  ctx.lineWidth = (red ? 1.5 : 1.2) * MAP_STRIPE_SCALE;
  const gap = (red ? 8 : 14) * MAP_STRIPE_SCALE;
  ctx.beginPath();
  // Rising lines: x + y = k·gap (global); falling: x − y = k·gap.
  const base = fall ? ox - oy : ox + oy;
  const first = Math.floor((base - (fall ? size.y : 0) - gap) / gap);
  const last = Math.ceil((base + size.x + (fall ? 0 : size.y) + gap) / gap);
  for (let k = first; k <= last; k++) {
    const c = k * gap - base;
    if (fall) {
      ctx.moveTo(c, 0);
      ctx.lineTo(c + size.y, size.y);
    } else {
      ctx.moveTo(c, 0);
      ctx.lineTo(c - size.y, size.y);
    }
  }
  ctx.stroke();
}

/** The lake's colours as map tiles drawn at the screen's resolution from `page.colours` (see drawOverlay). */
/**
 * How strongly the colours cover the map. The pane is faded as a whole, not each tile: tiles overlap by a
 * pixel so no light seam shows between them at in-between zoom levels, and the overlap must not show darker.
 */
const COLOUR_OPACITY = 0.72;

function lakeColourLayer(L) {
  const Layer = L.GridLayer.extend({
    _initTile(tile) {
      L.GridLayer.prototype._initTile.call(this, tile);
      const size = this.getTileSize();
      tile.style.width = `${size.x + 1}px`;
      tile.style.height = `${size.y + 1}px`;
    },
    createTile(coords) {
      const tile = this.getTileSize();
      // One pixel more each way than the tile, over its neighbour (see COLOUR_OPACITY).
      const size = { x: tile.x + 1, y: tile.y + 1 };
      const ratio = window.devicePixelRatio || 1;
      const canvas = document.createElement("canvas");
      canvas.width = size.x * ratio;
      canvas.height = size.y * ratio;
      const map = this._map;
      const colours = page?.colours;
      if (!map || !colours) return canvas;
      const e = gridEdges(page.view.grid);
      const ox = coords.x * tile.x;
      const oy = coords.y * tile.y;
      const at = (lat, lon) => map.project([lat, lon], coords.z);
      const nw = at(e.north, e.west);
      const se = at(e.south, e.east);
      // Tiles outside the lake's box stay empty.
      if (se.x < ox || nw.x > ox + size.x || se.y < oy || nw.y > oy + size.y) return canvas;
      const ctx = canvas.getContext("2d");
      ctx.scale(ratio, ratio);
      const shore = new Path2D();
      for (const ring of page.view.outline) {
        if (ring.length < 3) continue;
        ring.forEach(([lon, lat], i) => {
          const p = at(lat, lon);
          if (i) shore.lineTo(p.x - ox, p.y - oy);
          else shore.moveTo(p.x - ox, p.y - oy);
        });
        shore.closePath();
      }
      ctx.clip(shore, "evenodd");
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = "high";
      ctx.drawImage(colours.raster, nw.x - ox, nw.y - oy, se.x - nw.x, se.y - nw.y);
      if (colours.stripes) strokeTileStripes(ctx, colours.stripes, size, ox, oy, colours.fall);
      return canvas;
    },
  });
  return new Layer({ pane: "lakeColours", interactive: false, updateWhenZooming: false, keepBuffer: 4 });
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
function drawMiniMap(canvas, view, hour, clubId, layer = "light") {
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
  ctx.drawImage(rasterCanvas(view, hour, layer), x0, y0, x1 - x0, y1 - y0);
  ctx.globalAlpha = 1;
  const kind = layer === "light" && stripes(hour.lakeWide);
  if (kind) strokeStripes(ctx, kind, w, hgt, 1, stripesFall(view.outline));
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
  // The page's club last, on top of clubs sharing its launch point.
  for (const club of [...view.clubs].sort((a, b) => (a.id === clubId) - (b.id === clubId))) {
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
  const [text, ...args] = headline(view, hour, mapLimits());
  return t(text, ...args.map((a) => t(a)));
}

function windText(hour) {
  const w = windSummary(hour);
  if (!w) return null;
  const speed = Math.round(w.min) === Math.round(w.max) ? wind(w.max) : `${windRange(w.min, w.max)} ${windUnit()}`;
  return `${speed}${w.fromDeg != null ? ` ${t("from %@", compass(w.fromDeg, lang()))}` : ""}, ${t("gusts up to %@", wind(w.gust))}`;
}

/** What holds for the whole lake (or river stretch) this hour, such as a DWD storm warning or darkness (LakeWideBanner). */
function lakeWideBanner(lakeWide, view, oneLine = false) {
  if (lakeWide.light === "green") return "";
  const first = lakeWide.reasons[0];
  return `<p class="lake-wide ${lakeWide.light === "red" ? "red" : "orange"}${oneLine ? " one-line" : ""}">${icon(first ? CONDITION_ICONS[reasonCondition(first.condition, first.topic)] : "triangle-alert")}
    <span>${h(t(waterKind(view) === "lake" ? key("Whole lake: %@") : key("Whole stretch: %@"), lakeWide.reasons.map(reasonLabel).join(", ")))}</span></p>`;
}

/** Which boat the lake is coloured for: the ticked one (MapBoatNote). */
export function mapBoatNote() {
  return `<p class="small sub">${icon("rower")} ${h(t("Coloured for %@", boatInSentence(mapBoat())))}</p>`;
}

export function kitBadge(view) {
  const kit = coldWaterKit(view.shoreWaterC, mapLimits());
  if (!kit) return "";
  const [title, advice] = coldWaterText(kit);
  return `<span class="kit" title="${h(advice)}">${icon("life-buoy")} <span class="kit-text">${h(title)}</span></span>`;
}

// ---- The tile on the club page ------------------------------------------------------

/** Fills the club page's lake view tile, or hides it when the lake has no view. */
export async function fillLakeCard(box, lakeId, clubId, waterC) {
  noteWater(lakeId, waterC);
  noteDaylight(lakeId, clubId);
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
  // A small table like the 48-hour one, wind with its direction, also for a lake or stretch in one part;
  // the old wind line under it went (owner's H1, 12 Nov 2026).
  const zones = view.zones.length ? zoneTable(view, hour, stale) : "";
  const water = WATER_TEXTS[waterKind(view)];
  // The whole tile opens the lake view: a › in the title row says so, as on the value tiles, instead of
  // an "Open lake view" link (owner, 13 Nov 2026; Card.opens in the app).
  const href = `#/lake/${encodeURIComponent(lakeId)}/${encodeURIComponent(clubId)}`;
  box.innerHTML = `<a class="card-title opens" href="${href}" tabindex="-1" aria-hidden="true">${icon("map")}<span>${h(`${t(water.view)} · ${view.name}`)}</span>${icon("chevron-right")}</a>
    <a class="lake-card ${aspect >= 1.3 ? "tall" : ""}" href="${href}" aria-label="${h(t(water.opens))}">
      <canvas class="mini" style="${aspect >= 1.3 ? `height:${Math.min(320, Math.max(170, 120 * aspect))}px` : ""}" role="img" aria-label="${h(t("Map of %@ coloured by the rowing light", view.name))}"></canvas>
      <div class="lake-summary">
        <small class="sub">${h(t("Now, %@", time(hour.time)))}</small>
        <strong class="headline">${h(headlineText(view, hour))}</strong>
        ${stale ? `<p class="small orange strong">${icon("clock-alert")} ${h(t("Forecast out of date: from %@. Check the conditions yourself.", dayTime(view.generatedAt)))}</p>` : ""}
        ${lakeWideBanner(hour.lakeWide, view)}
        ${mapBoatNote()}
        ${zones}
        ${view.sample ? `<p class="small orange strong">${icon("triangle-alert")} ${h(t("Sample wind"))}</p>` : ""}
      </div></a>`;
  box.hidden = false;
  const canvas = box.querySelector("canvas");
  drawMiniMap(canvas, view, hour, clubId);
  const zoneBox = box.querySelector(".zone-box");
  if (zoneBox) {
    fitZoneTable(zoneBox);
    new ResizeObserver(() => zoneBox.isConnected && fitZoneTable(zoneBox)).observe(zoneBox);
  }
  // Drawn again when it grows to fill its column (balanceCards in app.js).
  let size = `${canvas.clientWidth}x${canvas.clientHeight}`;
  new ResizeObserver(() => {
    const now = `${canvas.clientWidth}x${canvas.clientHeight}`;
    if (now !== size && canvas.isConnected) drawMiniMap(canvas, view, hour, clubId);
    size = now;
  }).observe(canvas);
}

/**
 * The parts of the lake as a small table styled like the 48-hour table (LakeZoneTable, owner's H1): a map symbol
 * over the parts, waves, wind with its direction under one wind symbol (arrow under a compass, speed under the
 * unit) and visibility, one line under the header. Values that set amber or red show in that colour. Another
 * reason and the "near the shore" note follow a part on their own line. When the table is too wide each part
 * falls back to its name over its values (fitZoneTable).
 */
function zoneTable(view, hour, stale) {
  const limits = mapLimits();
  const notes = zoneNotes(view, hour, limits);
  const rows = view.zones.map((z, i) => {
    if (!hour.zones[i]) return null;
    const values = zoneValues(view, hour, i, limits);
    if (!values) return null;
    const light = hour.zones[i].light;
    const noteKey = notes[i]?.light === light ? zoneNoteText(notes[i]) : null;
    const note = noteKey ? t(noteKey[0], t(noteKey[1])) : null;
    return { name: t(zoneTitle(z, waterKind(view))), light, values, note };
  }).filter(Boolean);
  if (!rows.length) return "";
  const raised = (light) => (light !== "green" ? ` strong ${light === "red" ? "red" : "orange"}` : "");
  const numCell = (text, light) => `<td class="num${raised(light)}">${h(text)}</td>`;
  const arrowCell = (v) => v.wind.speedMs != null && v.fromDeg != null
    ? `<td class="zt-arrow${v.wind.light !== "green" ? raised(v.wind.light) : " sub"}"><span class="arrow" style="transform:rotate(${Math.round(v.fromDeg + 180) % 360}deg)">${icon("arrow-up")}</span></td>`
    : "<td></td>";
  const extras = (r) => r.values.extra || r.note
    ? `<tr class="zt-extra"><td colspan="5">${r.values.extra ? `<small class="zone-values">${extraItem(r.values.extra)}</small>` : ""}${r.note ? `<small class="sub zone-note">${h(r.note)}</small>` : ""}</td></tr>`
    : "";
  const table = `<table class="zone-table" aria-hidden="true">
    <thead><tr class="zt-icons"><th rowspan="2" class="zt-map">${icon("map")}</th><th colspan="2" class="zt-wind">${icon(CONDITION_ICONS.wind)}</th><th>${icon(CONDITION_ICONS.waves)}</th><th>${icon(CONDITION_ICONS.visibility)}</th></tr>
    <tr class="zt-units"><th class="zt-arrow">${icon("compass")}</th><th>${h(windUnit())}</th><th>${h(unitSymbol("waves"))}</th><th>${h(unitSymbol("distance"))}</th></tr></thead>
    <tbody>${rows.map((r) => `<tr><td class="zt-name">${dot(r.light, 10, stale)}<strong>${h(r.name)}</strong></td>
      ${arrowCell(r.values)}${numCell(r.values.wind.speedMs != null ? windRange(r.values.wind.speedMs, r.values.wind.gustMs) : "–", r.values.wind.light)}
      ${numCell(wavesNumber(r.values.waves.m), r.values.waves.light)}
      ${numCell(distanceNumber(r.values.visibility?.m), r.values.visibility?.light ?? "green")}</tr>${extras(r)}`).join("")}</tbody></table>`;
  // The lines show the table's arrow as a character, short enough not to be cut at large text sizes.
  const lineValues = (v) => {
    const toward = v.fromDeg != null && v.wind.speedMs != null ? ` ${arrowGlyph(v.fromDeg + 180)}` : "";
    return [
      probeItem(icon("wind"), `${windRange(v.wind.speedMs, v.wind.gustMs)} ${windUnit()}${toward}`, v.wind.light),
      probeItem(icon("waves"), waves(v.waves.m), v.waves.light),
      ...(v.visibility ? [probeItem(icon(CONDITION_ICONS.visibility), distance(v.visibility.m), v.visibility.light)] : []),
    ].join("") + extraItem(v.extra);
  };
  const stacked = `<ul class="zones" aria-hidden="true">${rows.map((r) => `<li>${dot(r.light, 10, stale)}<span><strong>${h(r.name)}</strong>
    <small class="zone-values">${lineValues(r.values)}</small>${r.note ? `<small class="sub zone-note">${h(r.note)}</small>` : ""}</span></li>`).join("")}</ul>`;
  const spoken = rows.map((r) => {
    const v = r.values;
    const parts = [`${r.name}: ${lightTitle(r.light, stale)}`,
      `${t("Wind")} ${windRange(v.wind.speedMs, v.wind.gustMs)} ${windUnit()}${v.fromDeg != null && v.wind.speedMs != null ? ` ${t("from %@", compass(v.fromDeg))}` : ""}`,
      `${t("Waves")} ${waves(v.waves.m)}`];
    if (v.visibility) parts.push(`${t("Visibility")} ${distance(v.visibility.m)}`);
    if (r.note) parts.push(r.note);
    return `<li>${h(parts.join(", "))}</li>`;
  }).join("");
  return `<div class="zone-box" data-fit="table">${table}${stacked}<ul class="visually-hidden">${spoken}</ul></div>`;
}

/** The table when it fits the tile's width, otherwise each part's name over its values (ViewThatFits). */
function fitZoneTable(box) {
  const table = box.querySelector(".zone-table");
  if (!table) return;
  box.dataset.fit = "table";
  const fits = table.getBoundingClientRect().width <= box.getBoundingClientRect().width + 0.5;
  box.dataset.fit = fits ? "table" : "lines";
}

/**
 * A few stripes in a small square, running like the lake's stripes on the map: bottom left to top right, or top
 * left to bottom right where they fall (StripeSwatch).
 */
export function stripeSwatch(kind, fall = false) {
  const lines = [];
  for (let k = -18; k < 18; k += 6) lines.push(`M${k} ${fall ? 0 : 18}L${k + 18} ${fall ? 18 : 0}`);
  return `<svg class="stripes ${kind}${fall ? " fall" : ""}" width="18" height="18" viewBox="0 0 18 18" aria-hidden="true"><clipPath id="sw-${kind}-${fall ? "f" : "r"}"><rect width="18" height="18" rx="3"/></clipPath><path clip-path="url(#sw-${kind}-${fall ? "f" : "r"})" d="${lines.join("")}" fill="none" stroke-width="1.6"/></svg>`;
}

// ---- The full lake map ----------------------------------------------------------------

let page = null;

/** The lake map page: map on top, the panel with the hours and the details below. */
/** Counts the lake maps opened; a page that draws twice while loading builds only the newer one. */
let opened = 0;

/** `routeId`: a saved route to open, from Settings › Routes. */
export async function renderLakeMap(root, lakeId, clubId, back, at = null, routeId = null, layer = null) {
  const mine = ++opened;
  page?.map?.remove();
  if (clubId) noteDaylight(lakeId, clubId);
  // Over the map at the top left, a round close button and the lake's name, as the app's topBar; the layers,
  // the colour scale and the route tools sit by the map and in the panel (LakeMapScreen).
  root.innerHTML = `<div class="lake-screen">${testing()}
    <div class="lake-page"><div class="lake-map-box"><div class="lake-map" id="lake-map"></div>
      <header class="lake-top"><a class="glass round tool" href="${h(back)}" aria-label="${h(t("Close"))}">${icon("x")}</a><strong class="glass lake-name" id="lake-name"></strong>${clubId ? `<span class="lake-boat" id="lake-boat">${boatControl.html()}</span>` : ""}</header>
      <div class="lake-over" id="lake-over"></div></div>
      <section class="lake-panel" id="lake-panel"><p>${h(t("Loading the forecast…"))}</p></section></div></div>`;
  let view, chart;
  try {
    [view, chart] = await Promise.all([viewForMap(lakeId), loadRouteChart()]);
  } catch {
    routeChart = null;
    root.querySelector("#lake-panel").innerHTML = `<p><strong>${icon("cloud-off")} ${h(t("No forecast"))}</strong></p>`;
    return;
  }
  // Opened again while this one loaded: that one builds the map (Leaflet takes one map per box).
  if (mine !== opened) return;
  const water = WATER_TEXTS[waterKind(view)];
  setTitle(`${t(water.view)} · ${view.name}`);
  root.querySelector("#lake-name").textContent = view.name;
  const club = view.clubs.find((c) => c.id === clubId) ?? view.clubs[0];
  page = {
    root, view, club, lakeId, hour: hourIndex(view, at && !isNaN(at) ? at : new Date()),
    layer: LAYERS.some(([k]) => k === layer) && (layer !== "visibility" || hasVisibility(view)) ? layer : "light", spot: null,
    // The crew's own pace, remembered as in the app (2:30 at first, owner 14 Nov 2026).
    pace: store.routePace, followBoat: false, boatAt: 0, map: null, layers: {}, showTrack: true,
    // The route being planned, its saved route and its undo history, driven by the route editor's chart (RouteDraft).
    route: routeDraft(chart, { lakeId, launch: club?.launchPoint ?? null, points: club ? [club.launchPoint] : [] }),
    get routeMode() { return this.route.planning; },
    get points() { return this.route.points; },
    get outAndBack() { return this.route.outAndBack; },
    get selected() { return this.route.selected; },
    get savedId() { return this.route.saved?.id ?? null; },
    get rowed() { return this.route.rowed; },
    // On a phone the panel starts pushed down, as the app's (panelExpanded): the hour, one line and the hours.
    expanded: false,
    // On rivers: the current the club page shows (its gauge, mid-river), for the route planner (LakeView.currentMs).
    currentMs: view.section ? forecasts.get(clubId)?.value?.river?.now?.speedMs ?? null : null,
  };
  const asked = routeId && store.routes.find((r) => r.id === routeId && r.lakeId === lakeId);
  if (asked) page.route.send({ type: "OPEN_ROUTE", route: asked });
  wireLakeBoat();
  wirePanelDrag();
  await buildMap();
  if (mine !== opened) return;
  update();
  if (asked && page.map) fitView();
}

/**
 * The club page's boat button at the top, between the lake's name and the zoom buttons, also while
 * planning a route: the colours, the route's times and its light are for that boat (owner's pick B,
 * 5 Nov 2026). A boat picked here redraws the map in place, keeping the hour, the zoom and the route.
 */
function wireLakeBoat() {
  const box = page.root.querySelector("#lake-boat");
  box?.querySelector("[data-map-boat]")?.addEventListener("click", (e) => boatControl.open(e.currentTarget, () => {
    if (!box.isConnected) return;
    box.innerHTML = boatControl.html();
    wireLakeBoat();
    update();
  }));
}

async function buildMap() {
  const mine = page;
  const L = await loadLeaflet().catch(() => null);
  // Opened again while Leaflet loaded: that one builds the map in its own box (Leaflet takes one map per box).
  if (page !== mine) return;
  const box = page.root.querySelector("#lake-map");
  if (!L || !box) return;
  // The satellite button at the top right as in the app (RWLakeImagery), the zoom buttons under it on
  // computers; on touch screens pinching zooms, as in the app (owner's pick, 6 Nov 2026).
  const map = L.map(box, { zoomSnap: 0.25, attributionControl: true, zoomControl: false });
  page.map = map;
  await baseMap(L, map, { storeKey: "rf.lakeImagery", onChange: (on) => {
    page.satellite = on;
    box.classList.toggle("imagery", on);
    if (page.layers.arrows && page.map === map) drawArrows();
  } });
  if (page !== mine) return;
  L.control.zoom({ position: "topright" }).addTo(map);
  page.L = L;
  fitView();
  // As in Apple Maps: when the panel grows or shrinks, the map refits the route (or the lake) into the room left above it.
  let height = box.clientHeight;
  new ResizeObserver(() => {
    if (!box.isConnected || page?.map !== map) return;
    map.invalidateSize();
    if (Math.abs(box.clientHeight - height) > 24) {
      height = box.clientHeight;
      fitView();
    }
  }).observe(box);
  // The lake's colours sit over the base map and under the shore line, arrows and pins.
  const colourPane = map.createPane("lakeColours");
  colourPane.style.zIndex = 390;
  colourPane.style.opacity = String(COLOUR_OPACITY);
  const rings = page.view.outline.map((ring) => ring.map(([lon, lat]) => [lat, lon]));
  page.layers.shore = L.polygon(rings, { fill: false, weight: 1, color: "rgba(0, 122, 255, .45)", interactive: false }).addTo(map);
  page.layers.arrows = L.layerGroup().addTo(map);
  page.layers.route = L.layerGroup().addTo(map);
  page.layers.marks = L.layerGroup().addTo(map);
  const pins = [];
  for (const c of [...page.view.clubs].sort((a, b) => (a.id === page.club?.id) - (b.id === page.club?.id))) {
    const own = c.id === page.club?.id;
    // As the app's club pins: the page's club a blue house, the others grey with their name below (ClubMarks).
    const marker = L.marker([c.launchPoint.lat, c.launchPoint.lon], {
      icon: L.divIcon({ className: `club-pin ${own ? "own" : ""}`, iconSize: [30, 30], iconAnchor: [15, 15],
        html: `<span class="dot">${icon(own ? "house" : "rower")}</span>${own ? "" : `<span class="name">${h(c.shortName)}</span>`}` }),
      title: c.shortName, keyboard: false, zIndexOffset: own ? 1000 : 0,
    }).addTo(page.layers.marks);
    pins.push({ marker, launch: c.launchPoint, clubhouse: c.clubhouse, oars: c.oars, own, layer: page.layers.marks });
  }
  splitClubPins(L, map, pins);
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
  return { planner, plan: planRoute(planner, start, page.pace, page.currentMs) };
}

/** The route with its rowed track when it has more than the start, else the lake as it opens (LakeMapScreen.fit). */
function fitView() {
  const pts = page.points.length > 1 ? [...page.points, ...(page.rowed?.track && page.showTrack ? page.rowed.track : [])] : [];
  if (pts.length) {
    page.map.fitBounds(pts.map((p) => [p.lat, p.lon]), { ...mapRoom(), maxZoom: 16 });
    return;
  }
  const open = openBounds(page.view, page.club);
  page.map.fitBounds([[open.south, open.west], [open.north, open.east]], mapRoom());
}

/**
 * Room around the lake or route as the app's LakeMapScreen.fit: below the top buttons (the
 * north tip sat under them), 64 at the right for the layer buttons, 24 at the left, or
 * beside the card on wide screens (its right edge plus 24, LakePanelLayout.fitInsets).
 */
function mapRoom() {
  const mapBox = page.map.getContainer().getBoundingClientRect();
  const topBar = page.root.querySelector(".lake-top")?.getBoundingClientRect();
  const top = Math.max(24, (topBar?.bottom ?? mapBox.top) - mapBox.top + 16);
  const card = panelCard() ? page.root.querySelector("#lake-panel")?.getBoundingClientRect() : null;
  const left = card?.width ? card.right - mapBox.left + 24 : 24;
  // Never less than 150 px of map, as the app keeps.
  const fit = (a, b, room) => (a + b + 150 > room ? [Math.max(8, (room - 150) * (a / (a + b))), Math.max(8, (room - 150) * (b / (a + b)))] : [a, b]);
  const [l, r] = fit(left, 64, mapBox.width);
  const [t2, b] = fit(top, 40, mapBox.height);
  return { paddingTopLeft: [l, t2], paddingBottomRight: [r, b] };
}

function update() {
  const hour = shownHour();
  drawOverlay(hour);
  drawArrows();
  drawRoute();
  drawSpot();
  page.root.querySelector("#lake-over").innerHTML = mapControls();
  renderPanel(hour);
}

/** The panel alone, as after pulling it up or pushing it down. */
function renderPanel(hour = shownHour()) {
  // On a phone, under the grabber: the panel pulls up and pushes down (RoutePanelTip).
  const panelTip = panelWide() || page.routeMode ? "" : tip("routePanel");
  page.root.querySelector("#lake-panel").innerHTML = panelGrip() + panelTip + (page.routeMode ? planningPanel(hour) : viewingPanel(hour));
  wirePanel();
}

/**
 * The panel is pulled up or pushed down at every size: a sheet along the bottom on a phone held upright, a card
 * at the bottom left from 600 px wide (owner's pick B, 12 Nov 2026, docs/decisions/0026; LakePanelLayout in LakePanelCard.swift).
 * No size shows it as a column beside the map any more.
 */
const panelWide = () => false;
/** From this width the panel is a card at the bottom left over the map (style.css, the same number). */
const panelCard = () => matchMedia("(min-width: 600px)").matches;
const panelFull = () => page.expanded || panelWide();

/** The grabber at the top of the phone's panel: tap it, or pull the panel up or push it down (LakeMapScreen's grabber). */
const panelGrip = () => `<button class="panel-grip" id="panel-grip" aria-expanded="${page.expanded}" aria-label="${h(page.expanded ? t("Show less") : t("Show more"))}"></button>`;

function setExpanded(on) {
  if (!page || page.expanded === on || panelWide()) return;
  page.expanded = on;
  // Used what the tip points at.
  closeTip(page.root, "routePanel");
  renderPanel();
}

/** Pull up for everything, push down for the map: a vertical swipe of more than 30 px on the panel, as the app's drag
 * gesture. Pushing down only while the panel is scrolled to its top, so scrolling back up does not close it. */
function wirePanelDrag() {
  const panel = page.root.querySelector("#lake-panel");
  // Once per panel, though the page may be drawn twice in a row.
  if (panel.dataset.drag) return;
  panel.dataset.drag = "on";
  window.addEventListener("resize", () => panel.isConnected && fitProbe(panel));
  let start = null;
  panel.addEventListener("click", (e) => {
    if (e.target.closest("#panel-grip")) setExpanded(!page.expanded);
  });
  panel.addEventListener("touchstart", (e) => {
    const p = e.touches[0];
    start = e.touches.length === 1 && !e.target.closest("input[type=range], select") ? { x: p.clientX, y: p.clientY, top: panel.scrollTop } : null;
  }, { passive: true });
  panel.addEventListener("touchend", (e) => {
    const p = e.changedTouches[0];
    if (!start || !p) return;
    const dx = p.clientX - start.x, dy = p.clientY - start.y;
    const top = start.top;
    start = null;
    if (Math.abs(dy) <= 30 || Math.abs(dy) < Math.abs(dx)) return;
    if (dy < 0 && !page.expanded) setExpanded(true);
    else if (dy > 0 && page.expanded && top <= 0) setExpanded(false);
  }, { passive: true });
  panel.addEventListener("touchcancel", () => { start = null; }, { passive: true });
  // With a mouse, the grabber can be dragged as well as clicked.
  let drag = null;
  panel.addEventListener("pointerdown", (e) => {
    if (e.pointerType === "mouse" && e.target.closest("#panel-grip")) drag = e.clientY;
  });
  window.addEventListener("pointerup", (e) => {
    if (drag == null || !panel.isConnected) return;
    const dy = e.clientY - drag;
    drag = null;
    if (Math.abs(dy) > 30) {
      // The click that follows would toggle it back.
      panel.addEventListener("click", (c) => c.stopImmediatePropagation(), { capture: true, once: true });
      setExpanded(dy < 0);
    }
  });
}

/**
 * The cells smoothly scaled over the grid and clipped to the shore, with the whole-lake stripes.
 * Drawn tile by tile at the screen's own resolution (LakeColourLayer), so the shore edge and the
 * stripes stay sharp at every zoom, as the app's vector drawing; the stripes keep their on-screen
 * width and spacing instead of growing with the map (owner, 12 Nov 2026).
 */
function drawOverlay(hour) {
  const { L, map, view } = page;
  if (!map) return;
  page.colours = {
    raster: rasterCanvas(view, hour, page.layer),
    stripes: page.layer === "light" ? stripes(hour.lakeWide) : null,
    fall: stripesFall(view.outline),
  };
  if (page.layers.image) page.layers.image.redraw();
  else page.layers.image = lakeColourLayer(L).addTo(map);
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
  // On satellite pictures light arrows with a dark edge, as the app draws them over Apple's pictures.
  const [edge, core] = page.satellite ? ["rgba(0, 0, 0, .55)", "rgba(255, 255, 255, .9)"] : ["rgba(255, 255, 255, .7)", "rgba(26, 26, 26, .75)"];
  L.polyline(paths, { color: edge, weight: 4, interactive: false, lineCap: "round" }).addTo(page.layers.arrows);
  L.polyline(paths, { color: core, weight: 2, interactive: false, lineCap: "round" }).addTo(page.layers.arrows);
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
    page.route.send({ type: "ADD", point: at });
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
  if (layer === "visibility") {
    // By fogginess: 20 km, 1 km and 500 m at their places (LakeLegend).
    const amber = fogginess(1000), red = fogginess(500), top = red * 1.6;
    const stops = Array.from({ length: 11 }, (_, i) => rgb(visibilityColour(20000 / 10 ** ((top * i) / 10)))).join(", ");
    return `<div class="ramp"><span class="bar" style="background:linear-gradient(90deg, ${stops})"></span>
    <span class="labels"><small style="left:0">${h(distance(20000))}</small><small style="left:${(amber / top) * 100}%">${h(distance(1000))}</small><small style="left:${(red / top) * 100}%">${h(distance(500))}</small></span></div>`;
  }
  const [amber, red, fmt] = layer === "waves"
    ? [limits.value("waveAmber"), limits.value("waveRed"), waves]
    : [limits.value("windAmber"), limits.value("windRed"), wind];
  const top = red * 1.6;
  const stops = Array.from({ length: 11 }, (_, i) => rgb(ramp((top * i) / 10, amber, red))).join(", ");
  return `<div class="ramp"><span class="bar" style="background:linear-gradient(90deg, ${stops})"></span>
    <span class="labels"><small style="left:0">${h(fmt(0))}</small><small style="left:${(amber / top) * 100}%">${h(fmt(amber))}</small><small style="left:${(red / top) * 100}%">${h(fmt(red))}</small></span></div>`;
}

/** The rowing light first, then wind, waves and visibility, the order they have everywhere (owner, 13 Nov 2026). */
const LAYERS = [["light", key("Rowing light")], ["wind", key("Wind")], ["waves", key("Waves")], ["visibility", key("Visibility")]];
/** The layers this lake view can show: visibility only when the backend sends it per point. */
const shownLayers = () => LAYERS.filter(([k]) => k !== "visibility" || hasVisibility(page.view));

/** A layer button's picture: the three lights, the wind, the waves or visibility (LakeLayerIcon). */
const layerIcon = (layer) => (layer === "light" ? `<span class="lights">${["red", "amber", "green"].map((l) => `<i style="background:var(--${l})"></i>`).join("")}</span>`
  : icon(layer === "visibility" ? CONDITION_ICONS.visibility : layer));

/** The layer's colours in a slim strip (tap for the legend) at the lower left; one button per layer at the lower right (LakeScaleChip, layerButtons). */
function mapControls() {
  const limits = mapLimits();
  let scale;
  if (page.layer === "light") scale = ["green", "amber", "red"].map((l) => dot(l, 9)).join("");
  else if (page.layer === "visibility") {
    const top = fogginess(500);
    const stops = Array.from({ length: 6 }, (_, i) => rgb(visibilityColour(20000 / 10 ** ((top * i) / 5)))).join(", ");
    scale = `<small>${h(distance(20000))}</small><span class="bar" style="background:linear-gradient(90deg, ${stops})"></span><small>${h(distance(500))}</small>`;
  } else {
    const [top, fmt] = page.layer === "waves" ? [limits.value("waveRed"), waves] : [limits.value("windRed"), wind];
    const stops = Array.from({ length: 6 }, (_, i) => rgb(ramp((top * i) / 5, limits.value(page.layer === "waves" ? "waveAmber" : "windAmber"), top))).join(", ");
    scale = `<small>${h(fmt(0))}</small><span class="bar" style="background:linear-gradient(90deg, ${stops})"></span><small>${h(fmt(top))}</small>`;
  }
  return `<button class="glass lake-scale" id="scale" aria-label="${h(t("Legend"))}">${scale}</button>
    <div class="lake-layers-box">${page.layerNote ? `<span class="glass layer-note">${h(t(LAYERS.find(([k]) => k === page.layerNote)[1]))}</span>` : ""}
      <div class="glass lake-layers">${shownLayers().map(([k, label]) => `<button data-layer="${k}" class="${page.layer === k ? "on" : ""}" aria-label="${h(t(label))}" aria-pressed="${page.layer === k}">${layerIcon(k)}</button>`).join("")}</div></div>`;
}

/** The route button in the panel's first row: blue while planning (panelRouteButton). */
const routeButton = () => {
  const button = `<button class="tool route-button ${page.routeMode ? "on" : ""}" id="route-mode" aria-label="${h(page.routeMode ? t("End route planning") : t("Plan a route"))}"${!page.routeMode && lakeRoutes().length ? ' aria-haspopup="dialog"' : ""}>${icon("route")}</button>`;
  // RoutePlanningTip: a bubble on the button (placement rule R2), as the app's popoverTip.
  const bubble = page.routeMode ? "" : bubbleTip("routePlanning");
  return bubble ? `<span class="pop-anchor end">${button}${bubble}</span>` : button;
};
/** The saved routes on this lake, in their own order. */
const lakeRoutes = () => store.routes.filter((r) => r.lakeId === page.lakeId);

/** The route button's menu while not planning, when the lake has saved routes: a new route, a row to import or a saved one (LakeMapScreen.routeButton). */
function routeStartMenu() {
  return `<div class="menu routes-menu">
    <button id="new-route">${icon("plus")} <span>${h(t("New route"))}</span></button>
    ${importRowItem()}
  </div>
  ${savedRoutesList()}`;
}

const importRowItem = () => `<label id="import-row" title="${h(t("GPX, TCX or FIT files from CrewNerd, Garmin Connect, Strava and other apps."))}">${icon("import")} <span>${h(t("Import a row"))}</span>
      <input type="file" accept=".gpx,.tcx,.fit,application/gpx+xml,application/vnd.garmin.tcx+xml" hidden></label>`;

/** The menus' Saved routes section, each route opens on tap, then Manage routes… as in the app's menus. */
const savedRoutesList = () => {
  const saved = lakeRoutes();
  return saved.length ? `<h3 class="section">${h(t("Saved routes"))}</h3><div class="menu routes-menu">${saved.map((r) => `<button data-route="${h(r.id)}" class="${r.id === page.savedId ? "on" : ""}">${icon(routeSymbol(r))} <span>${h(r.name)}</span></button>`).join("")}
    <button id="manage-routes">${icon("list")} <span>${h(t("Manage routes…"))}</span></button></div>` : "";
};

/** The symbol for a route's shape, as in Manage routes (ManageRoutesView.row). */
const routeSymbol = (r) => (r.importedFrom ? "rower" : RouteEdit.isLoop(r.points) ? "repeat" : r.outAndBack ? "arrow-left-right" : "arrow-right");

/** At the end of the panel: the legend and what the map shows (moreRows). */
const moreRows = () => `<div class="more-rows"><button id="legend">${icon("list-rect")} <span>${h(t("Legend"))}</span>${icon("chevron-right")}</button>
  <button id="about">${icon("info")} <span>${h(t(WATER_TEXTS[waterKind(page.view)].about))}</span>${icon("chevron-right")}</button></div>`;

/** One value of a tapped spot: symbol and value, grey, or in the light's colour and semibold at amber or red (LakeProbeItemView). */
function probeItem(symbol, text, light = "green") {
  const raised = light !== "green";
  return `<span class="probe-item ${raised ? `strong ${light === "red" ? "red" : "orange"}` : "sub"}">${symbol} <span class="num">${h(text)}</span></span>`;
}

/** The spot's extra: hail, a thunderstorm or heavy rain (LakeWind.extra). */
function extraItem(extra) {
  if (!extra) return "";
  if (extra.kind === "hail") return probeItem(icon("cloud-hail"), t("Hail"), extra.light);
  if (extra.kind === "thunderstorm") return probeItem(icon(CONDITION_ICONS.thunderstorm), t("Thunderstorm"), extra.light);
  return probeItem(icon("cloud-rain"), rain(extra.mm), extra.light);
}

/** Wind, waves and visibility of a probe, as items. */
function probeValues(p) {
  return [
    probeItem(icon("wind"), `${windRange(p.wind.speedMs, p.wind.gustMs)} ${windUnit()}`, p.wind.light),
    probeItem(icon("waves"), waves(p.waves.m), p.waves.light),
    ...(p.visibility ? [probeItem(icon(CONDITION_ICONS.visibility), distance(p.visibility.m), p.visibility.light)] : []),
  ];
}

/**
 * The tapped spot in the pushed-down panel (LakeSpotProbe, owner's E2 and G): the verdict, then waves, wind and
 * visibility; the extra only when amber or red. On one line only where the longest verdict with wide values fits,
 * so the panel never jumps between spots or hours; otherwise the values go under the verdict, wrapping between
 * whole items (fitProbe).
 */
function spotProbeHtml(light, stale, p) {
  const verdict = `<span class="probe-verdict strong">${dot(light, 10, stale)} ${h(lightTitle(light, stale))}</span>`;
  const values = probeValues(p);
  const extra = extraItem(p.extra);
  return `<div class="probe" data-fit="two">${verdict}<span class="probe-values">${values.join("")}<span class="probe-extra">${extra}</span></span></div>`;
}

/** Whether the widest first line (longest verdict, 0.45 m, 12–18 m/s, 500 m) fits the panel: then one line. */
function fitProbe(panel) {
  const probe = panel.querySelector(".probe");
  if (!probe) return;
  const titles = ["green", "amber", "red"].map((l) => lightTitle(l)).concat(lightTitle("green", true));
  const longest = titles.reduce((a, b) => (b.length > a.length ? b : a), "");
  const test = document.createElement("div");
  test.className = "probe";
  test.dataset.fit = "one";
  test.style.cssText = "position:absolute;visibility:hidden;left:0;top:0;width:max-content";
  test.innerHTML = `<span class="probe-verdict strong">${dot("green", 10)} ${h(longest)}</span><span class="probe-values">${probeValues({
    waves: { m: 0.45, light: "green" }, wind: { speedMs: 12, gustMs: 18, light: "green" }, visibility: { m: 500, light: "green" } }).join("")}</span>`;
  probe.parentElement.append(test);
  const fits = test.getBoundingClientRect().width <= probe.parentElement.clientWidth;
  test.remove();
  probe.dataset.fit = fits ? "one" : "two";
}

function viewingPanel(hour) {
  const { view } = page;
  const stale = viewStale(view);
  if (!panelFull()) return collapsedViewing(hour, stale);
  let details;
  if (page.spot != null && page.spot.cell < hour.lights.length) {
    const i = page.spot.cell;
    // A lake-wide red (DWD warning, darkness) holds at every spot.
    const spotLight = hour.lakeWide.light === "red" ? "red" : hour.lights[i];
    // Blended at the exact spot the water was tapped (app #392).
    const w = windAt(view, hour, page.spot.at, i);
    const zone = view.grid.cellZone[i];
    details = `<div class="spot"><p class="spot-head">${dot(spotLight, 14, stale)} <strong>${h(lightTitle(spotLight, stale))}</strong>
        <button class="card-x" id="spot-close" aria-label="${h(t("Close"))}">${icon("x")}</button></p>
      ${view.zones.length > 1 && view.zones[zone] ? `<small class="sub">${h(t("Selected spot · %@", t(zoneTitle(view.zones[zone], waterKind(view)))))}</small>` : ""}
      <div class="now-metrics"><div><small class="label">${icon("wind")} ${h(t("Wind"))}</small><span>${h(windRange(w?.speedMs, w?.gustMs))} ${h(windUnit())}</span></div>
        ${w?.fromDeg != null ? `<div><small class="label">${icon("navigation")} ${h(t("From"))}</small><span>${h(compass(w.fromDeg, lang()))}</span></div>` : ""}
        <div><small class="label">${icon("waves")} ${h(t("Waves"))}</small><span>${h(waves(hour.wavesCm[i] / 100))}</span></div>
        ${w?.visM != null ? `<div><small class="label">${icon(CONDITION_ICONS.visibility)} ${h(t("Visibility"))}</small><span>${h(distance(w.visM))}</span></div>` : ""}</div>
      ${(() => { const x = extraItem(spotProbe(view, hour, i, mapLimits(), page.spot.at).extra); return x ? `<p class="spot-extra">${x}</p>` : ""; })()}</div>`;
  } else {
    const windLine = windText(hour);
    const top = maxWave(hour);
    details = `<p class="strong">${h(headlineText(view, hour))}</p>
      ${windLine ? `<p class="small sub">${icon("wind")} ${h(windLine)}</p>` : ""}
      ${top != null ? `<p class="small sub">${icon("waves")} ${h(t("Waves up to %@", waves(top)))}</p>` : ""}
      <p class="small sub">${h(t("Tap the water to see the conditions there."))}</p>`;
  }
  return `<p class="panel-head"><strong>${h(dayTime(hour.time))}</strong>${view.sample ? `<span class="small orange strong">${icon("triangle-alert")} ${h(t("Sample wind"))}</span>` : ""}${routeButton()}</p>
    ${stale ? `<p class="small orange strong">${icon("clock-alert")} ${h(t("Forecast out of date: from %@. Check the conditions yourself.", dayTime(view.generatedAt)))}</p>` : ""}
    ${lakeWideBanner(hour.lakeWide, view)}
    ${kitBadge(view)}
    ${details}
    ${legendLine()}
    ${mapBoatNote()}
    ${hourStrip()}
    ${moreRows()}`;
}

/** The panel pushed down: the hour, the whole-lake line, one line on the conditions or the tapped spot, and the hours (collapsedSummary). */
function collapsedViewing(hour, stale) {
  const { view } = page;
  let line;
  if (page.spot != null && page.spot.cell < hour.lights.length) {
    const i = page.spot.cell;
    const spotLight = hour.lakeWide.light === "red" ? "red" : hour.lights[i];
    line = spotProbeHtml(spotLight, stale, spotProbe(view, hour, i, mapLimits(), page.spot.at));
  } else {
    line = `<p class="one-line strong">${h(headlineText(view, hour))}</p>`;
  }
  return `<p class="panel-head"><strong>${h(dayTime(hour.time))}</strong>${view.sample ? `<span class="small orange strong">${icon("triangle-alert")} ${h(t("Sample wind"))}</span>` : ""}${routeButton()}</p>
    ${stale ? `<p class="small orange strong one-line">${icon("clock-alert")} ${h(t("Forecast out of date: from %@. Check the conditions yourself.", dayTime(view.generatedAt)))}</p>` : ""}
    ${lakeWideBanner(hour.lakeWide, view, true)}
    ${kitBadge(view)}
    ${line}
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
    const better = bestStart(found.planner, page.pace, new Date(), page.currentMs);
    const betterIndex = better && plansBetter(better, plan) ? view.hours.reduce((n, x, i) => (new Date(x.time) <= better.start ? i : n), 0) : null;
    summary = `<p class="small sub">${h(t("Waves up to %@", waves(plan.maxWaveM)))}</p>
      ${roughText ? `<p class="small sub">${h(roughText)}</p>` : ""}
      ${plan.currentMs >= 0.05 ? `<p class="small sub">${conditionIcon("current")} ${h(t("Times count with the current of ≈ %@: faster downstream, slower upstream.", riverSpeed(plan.currentMs)))}</p>` : ""}
      ${plan.noHeadway ? `<p class="small orange">${icon("triangle-alert")} ${h(t("Against this current your boat hardly makes headway on part of the route."))}</p>` : ""}
      ${plan.beyondForecast ? `<p class="small orange">${icon("clock-alert")} ${h(t("The forecast ends before you are back."))}</p>` : ""}
      ${viewStale(view) ? `<p class="small orange strong">${icon("clock-alert")} ${h(t("Forecast out of date: from %@. Check the conditions yourself.", dayTime(view.generatedAt)))}</p>` : ""}
      ${adviceOnly()}
      ${page.followBoat ? "" : tip("boatTime")}
      <p class="boat-follow"><label class="tick inline"><input type="checkbox" id="follow" ${page.followBoat ? "checked" : ""}> ${icon("rower")} ${h(t("Lake at the boat's time"))}</label>
        ${page.followBoat ? `<input type="range" id="boat-at" min="0" max="1" step="0.01" value="${page.boatAt}" aria-label="${h(t("Where the boat is"))}">` : ""}</p>
      ${stop ? `<p class="small sub">${h(t("The boat at %@ after %@: %@, waves %@", time(stop.time), distance(stop.distanceM), lightTitle(stop.light), waves(stop.waveM) + (stop.relation ? ` ${t(RELATION_WAVES[stop.relation])}` : "")))}</p>` : ""}
      ${betterIndex != null ? `<button class="link" id="better" data-hour="${betterIndex}">${icon("history")} ${h(t("Better start: %@ · %@", dayTime(better.start), lightTitle(better.worstLight)))}</button>` : ""}`;
  } else {
    summary = `<p class="small">${h(t("It starts at your club and goes one way; pick Out and back or Loop under the way back to row back to it. Tap or pull a stretch to add a point there. Tap a point to delete it, or drag it to move it. A point within 50 m of the start closes the loop."))}</p>`;
  }
  // The route's light and times, or what to do first, with the route button (planningPanel's first row).
  const head = plan ? `<p class="route-line">${dot(plan.worstLight, 10)} <strong>${h(lightTitle(plan.worstLight))}</strong>
      <span class="sub">${h(t("%@ · %@ · back %@", distance(plan.distanceM), duration(plan.start, plan.end), time(plan.end)))}</span>${routeButton()}</p>`
    : `<p class="route-line"><strong>${h(t("Tap the water to add the turning points of your route."))}</strong>${routeButton()}</p>`;
  // One choice instead of the loop button and the out-and-back switch, which switched each other off (returnPicker).
  const back = isLoop ? "loop" : page.outAndBack ? "outAndBack" : "oneWay";
  const picker = `<div class="segmented way-back" role="group" aria-label="${h(t("Way back"))}">${[
    // Short, for the three parts of the switch: the app keys them apart from the longer texts (RouteReturn.title).
    ["oneWay", lang() === "de" ? t("Way back one way") : "One way"], ["outAndBack", lang() === "de" ? t("Way back out and back") : "Out and back"], ["loop", t("Loop")]]
    .map(([k, label]) => `<button data-way-back="${k}" class="${back === k ? "on" : ""}" ${k === "loop" && page.points.length < 3 && !isLoop ? "disabled" : ""}>${h(label)}</button>`).join("")}</div>`;
  // A tapped turning point swaps the tools for deleting it (planningTools).
  const tools = page.selected != null ? `<p class="point-bar"><strong>${h(t("Turning point %d").replace("%d", page.selected))}</strong>
      <button class="pill red" id="delete-point">${icon("trash-2")} ${h(t("Delete point"))}</button><button class="card-x" id="point-done" aria-label="${h(t("Close"))}">${icon("x")}</button></p>
    <p class="small sub">${h(t("Drag the point to move it. The magnifier shows where it lands."))}</p>`
    : `<div class="route-tools">
      <button class="pill" id="undo" ${page.route.canUndo ? "" : "disabled"}>${icon("undo-2")} ${h(t("Undo"))}</button>
      <button class="pill" id="clear" ${page.points.length > 1 ? "" : "disabled"} aria-label="${h(t("Clear route"))}" title="${h(t("Clear route"))}">${icon("trash-2")}</button>
      <button class="pill routes-button" id="routes" aria-haspopup="dialog">${icon(page.route.status === "saved" ? "bookmark-fill" : "bookmark")} ${h(t("Routes"))}</button>
    </div>`;
  return `${head}${plan ? routeBar(plan) : ""}
    ${lakeWideBanner(hour.lakeWide, view)}
    ${kitBadge(view)}
    <div class="route-controls">
      <span class="start"><button class="tool" id="earlier" aria-label="${h(t("An hour earlier"))}" ${page.hour <= 0 ? "disabled" : ""}>${icon("chevron-left")}</button>
        <label><small class="sub">${h(t("Start"))}</small><select id="start">${view.hours.map((x, i) => `<option value="${i}" ${i === page.hour ? "selected" : ""}>${h(dayTime(x.time))}</option>`).join("")}</select></label>
        <button class="tool" id="later" aria-label="${h(t("An hour later"))}" ${page.hour >= view.hours.length - 1 ? "disabled" : ""}>${icon("chevron-right")}</button></span>
      <span class="pace"><small class="sub">${h(t("Pace /500 m"))}</small><strong class="num">${h(paceText(page.pace))}</strong>
        <span class="stepper"><button id="pace-down" aria-label="−">−</button><button id="pace-up" aria-label="+">+</button></span></span>
    </div>
    ${picker}
    ${tools}
    ${panelFull() ? `${routeTip(isLoop)}${summary}${moreRows()}` : ""}`;
}

/** The Routes menu of the route panel: save, import a row, the rowed track, the lake's saved routes and Manage routes… (LakeMapScreen.routesMenu). */
function routesMenu() {
  return `<div class="menu routes-menu">
    <button id="save-route" ${page.points.length > 1 ? "" : "disabled"}>${icon("download")} <span>${h(t("Save route"))}</span></button>
    ${page.route.saved ? `<button id="save-new-route" ${page.points.length > 1 ? "" : "disabled"}>${icon("copy-plus")} <span>${h(t("Save as new route"))}</span></button>` : ""}
    ${importRowItem()}
    ${page.rowed?.track ? `<button id="show-track" aria-pressed="${page.showTrack}">${icon("spline")} <span>${h(t("Show rowed track"))}</span>${page.showTrack ? icon("check", "end") : ""}</button>` : ""}
  </div>
  ${savedRoutesList()}
  ${page.savedId && lakeRoutes().some((r) => r.id === page.savedId) ? `<div class="menu routes-menu"><button id="export-gpx">${icon("file-up")} <span>${h(t("Export GPX"))}</span></button><button id="delete-open-route" class="red">${icon("trash-2")} <span>${h(t("Delete this route"))}</span></button></div>` : ""}
`;
}

/** One saved route's row with its tools, in Manage routes and in Settings › Routes (ManageRoutesView.row). */
function routeRow(r, i, count, current) {
  return `<div class="row-setting">
        <button class="route-open" data-open="${h(r.id)}">${icon(routeSymbol(r))}<span class="stack"><span>${h(r.name)}</span><small class="sub">${h(routeDetails(r))}</small></span>
          ${r.id === current ? `<small class="sub strong">${h(t("Open"))}</small>` : ""}</button>
        <span class="route-actions">
          <button class="tool" data-up="${h(r.id)}" aria-label="${h(t("Move up"))}" ${i === 0 ? "disabled" : ""}>${icon("arrow-up")}</button>
          <button class="tool" data-down="${h(r.id)}" aria-label="${h(t("Move down"))}" ${i === count - 1 ? "disabled" : ""}>${icon("arrow-down")}</button>
          <button class="tool" data-rename="${h(r.id)}" aria-label="${h(t("Rename"))}" title="${h(t("Rename"))}">${icon("pencil")}</button>
          <button class="tool" data-copy="${h(r.id)}" aria-label="${h(t("Duplicate"))}" title="${h(t("Duplicate"))}">${icon("copy-plus")}</button>
          <button class="tool" data-share-one="${h(r.id)}" aria-label="${h(t("Share"))}" title="${h(t("Share"))}" aria-expanded="false">${icon("share")}</button>
          <button class="tool red" data-delete="${h(r.id)}" aria-label="${h(t("Delete"))}" title="${h(t("Delete"))}">${icon("trash-2")}</button></span>
        <span class="route-share" hidden><button class="pill" data-link="${h(r.id)}">${icon("share")} ${h(t("Share link"))}</button>
          <button class="pill" data-gpx="${h(r.id)}">${icon("file-up")} ${h(t("Export GPX"))}</button>
          <button class="tool" data-share-done aria-label="${h(t("Close"))}">${icon("x")}</button></span></div>`;
}

/**
 * The rows' tools: open, move within the route's own water, rename, duplicate, delete. `redraw` draws the
 * list again; `renamed` and `deleted` tell an open lake map.
 */
function wireRouteRows(box, { open, redraw, renamed = () => {}, deleted = () => {} }) {
  const find = (id) => store.routes.find((x) => x.id === id);
  const move = (id, by) => {
    const all = [...store.routes];
    const lakeId = find(id)?.lakeId;
    const mine = all.filter((r) => r.lakeId === lakeId);
    const i = mine.findIndex((r) => r.id === id);
    const other = mine[i + by];
    if (!other) return;
    const a = all.findIndex((r) => r.id === id);
    const b = all.findIndex((r) => r.id === other.id);
    [all[a], all[b]] = [all[b], all[a]];
    store.routes = all;
    redraw();
  };
  // Share link or GPX file per route (ManageRoutesView / AllRoutesView: Share link, Export GPX); the row's tools
  // make way for the two choices, so a sheet that lists the routes stays open.
  const sharing = (row, on) => {
    row.querySelector(".route-actions").hidden = on;
    row.querySelector(".route-share").hidden = !on;
    row.querySelector("[data-share-one]").setAttribute("aria-expanded", String(on));
    (on ? row.querySelector("[data-link]") : row.querySelector("[data-share-one]"))?.focus();
  };
  box.querySelectorAll("[data-share-one]").forEach((b) => b.addEventListener("click", () => sharing(b.closest(".row-setting"), true)));
  box.querySelectorAll("[data-share-done]").forEach((b) => b.addEventListener("click", () => sharing(b.closest(".row-setting"), false)));
  box.querySelectorAll("[data-link]").forEach((b) => b.addEventListener("click", () => {
    const r = find(b.dataset.link);
    if (r) shareRoutes([r]);
    sharing(b.closest(".row-setting"), false);
  }));
  box.querySelectorAll("[data-gpx]").forEach((b) => b.addEventListener("click", () => {
    const r = find(b.dataset.gpx);
    if (r) downloadGpx(r);
    sharing(b.closest(".row-setting"), false);
  }));
  box.querySelectorAll("[data-open]").forEach((b) => b.addEventListener("click", () => {
    const r = find(b.dataset.open);
    if (r) open(r);
  }));
  box.querySelectorAll("[data-up]").forEach((b) => b.addEventListener("click", () => move(b.dataset.up, -1)));
  box.querySelectorAll("[data-down]").forEach((b) => b.addEventListener("click", () => move(b.dataset.down, 1)));
  box.querySelectorAll("[data-rename]").forEach((b) => b.addEventListener("click", () => {
    const r = find(b.dataset.rename);
    const name = r && prompt(t("Rename route"), r.name);
    if (!name?.trim()) return;
    store.routes = store.routes.map((x) => (x.id === r.id ? { ...x, name: name.trim() } : x));
    renamed(find(r.id));
    redraw();
  }));
  box.querySelectorAll("[data-copy]").forEach((b) => b.addEventListener("click", () => {
    const r = find(b.dataset.copy);
    if (!r) return;
    const copy = { ...r, id: crypto.randomUUID?.() ?? `r${Date.now()}`, name: t("%@ (copy)", r.name) };
    const all = [...store.routes];
    all.splice(all.indexOf(r) + 1, 0, copy);
    store.routes = all;
    redraw();
  }));
  box.querySelectorAll("[data-delete]").forEach((b) => b.addEventListener("click", () => {
    const r = find(b.dataset.delete);
    if (!r || !confirm(t("Delete “%@”?", r.name))) return;
    store.routes = store.routes.filter((x) => x.id !== r.id);
    deleted(r);
    redraw();
  }));
}

/** Manage routes: the lake's saved routes with their length and shape; open, rename, duplicate, delete, move (ManageRoutesView). */
function openManageRoutes() {
  const body = () => {
    const saved = lakeRoutes();
    return saved.length
      ? `<section class="card group manage-routes">${saved.map((r, i) => routeRow(r, i, saved.length, page.savedId)).join("")}</section>`
      : `<div class="empty-state">${icon("route")}<strong>${h(t("No saved routes"))}</strong><p class="sub">${h(t("Plan a route on the map and save it from the bookmark menu."))}</p></div>`;
  };
  openSheet(t("Manage routes"), body(), (sheet) => {
    const box = sheet.querySelector(".sheet-body");
    const wire = () => wireRouteRows(box, {
      open: (r) => {
        sheet.close();
        openRoute(r);
      },
      redraw: () => {
        box.innerHTML = body();
        wire();
        update();
      },
      // The open route keeps its new name for the next Save.
      renamed: (r) => page.route.send({ type: "ROUTE_CHANGED", id: r.id, route: r }),
      deleted: (r) => {
        if (page.savedId === r.id) page.route.send({ type: "DELETE_ROUTE" });
      },
    });
    wire();
  });
}

/**
 * Settings › Routes: every saved route, grouped by its water, with the same tools as Manage routes; a route
 * opens on its lake map (owner's pick, 12 Nov 2026; the app's AllRoutesView).
 */
export async function renderAllRoutes(root) {
  setTitle(t("Routes"));
  const lakes = await loadCatalog().catch(() => []);
  const draw = () => {
    const byLake = new Map();
    for (const r of store.routes) byLake.set(r.lakeId, [...(byLake.get(r.lakeId) ?? []), r]);
    const lakeOf = (id) => lakes.find((l) => l.id === id);
    const groups = [...byLake.entries()].sort(([a], [b]) => (lakeOf(a)?.name ?? a).localeCompare(lakeOf(b)?.name ?? b));
    root.innerHTML = `<header class="nav"><a class="link back" href="#/settings" aria-label="${h(t("Settings"))}">${icon("chevron-left")}</a><strong class="nav-title">${h(t("Routes"))}</strong><span class="nav-side">${store.routes.length ? `<button class="link" data-share-routes aria-label="${h(t("Share all routes"))}" title="${h(t("Share all routes"))}">${icon("share")}</button>` : ""}</span></header>
    ${testing()}
    <main class="page settings-topic all-routes">
      <section class="card group"><div class="row-setting pace-setting"><span>${h(t("Standard pace /500 m"))}</span>
        <span class="pace"><strong class="num" id="std-pace">${h(paceText(store.routePace))}</strong>
        <span class="stepper"><button id="std-pace-down" aria-label="−">−</button><button id="std-pace-up" aria-label="+">+</button></span></span></div></section>
      <p class="footer">${h(t("Route times on the lake maps start from this pace; the map's own stepper changes it too."))}</p>
      ${groups.length ? groups.map(([lakeId, list]) => `<h3 class="section">${h(lakeOf(lakeId)?.name ?? lakeId)}</h3>
      <section class="card group manage-routes" data-lake="${h(lakeId)}">${list.map((r, i) => routeRow(r, i, list.length, null)).join("")}</section>`).join("")
      + `<p class="footer">${h(t("Every saved route, by water. Tap one to open it on its lake map."))}</p>`
    : `<div class="empty-state">${icon("route")}<strong>${h(t("No saved routes"))}</strong><p class="sub">${h(t("Plan a route on the map and save it from the bookmark menu."))}</p></div>`}
    </main>`;
    wireRouteRows(root, {
      // On the lake map from the page of a saved club on that lake, else its first club.
      open: (r) => {
        const lake = lakeOf(r.lakeId);
        const club = store.clubs.find((c) => lake?.clubs.some((x) => x.id === c.id)) ?? lake?.clubs[0];
        location.hash = `#/lake/${encodeURIComponent(r.lakeId)}${club ? `/${encodeURIComponent(club.id)}` : ""}?route=${encodeURIComponent(r.id)}`;
      },
      redraw: draw,
    });
    root.querySelector("[data-share-routes]")?.addEventListener("click", () => shareRoutes(store.routes));
    for (const [sel, by] of [["#std-pace-down", -5], ["#std-pace-up", 5]]) root.querySelector(sel).addEventListener("click", () => {
      store.routePace = Math.min(240, Math.max(90, store.routePace + by));
      root.querySelector("#std-pace").textContent = paceText(store.routePace);
    });
  };
  draw();
}

/** Shares a link with the routes (the share sheet where the browser has one, else the link is copied). */
async function shareRoutes(routes) {
  const url = routeLink(routes);
  const title = routes.length === 1 ? routes[0].name : t("%@ routes", String(routes.length));
  if (navigator.share) {
    try {
      await navigator.share({ title, url });
    } catch { /* closed */ }
    return;
  }
  try {
    await navigator.clipboard.writeText(url);
    alert(t("Link copied. Open it in another browser to save the routes there."));
  } catch {
    prompt(t("Copy this link"), url);
  }
}

/**
 * A route link (#/routes/add?r=…, from the app's Share link or another browser): saves its routes in this
 * browser, skipping any already saved, then opens a single route on its lake map, several in Settings › Routes.
 */
export async function openSharedRoutes(value) {
  const shared = readRouteLink(value);
  if (!shared?.length) {
    alert(t("This link has no route Row Frog can read."));
    return location.replace("#/settings/routes");
  }
  const named = shared.map((r) => (r.name === "Route" ? { ...r, name: t("Route %@", distance(routeLength(r.points, r.outAndBack))) } : r));
  const { list, routes } = addSharedRoutes(store.routes, named);
  store.routes = list;
  if (routes.length > 1) return location.replace("#/settings/routes");
  const [r] = routes;
  const lake = (await loadCatalog().catch(() => [])).find((l) => l.id === r.lakeId);
  if (!lake) return location.replace("#/settings/routes");
  const club = store.clubs.find((c) => lake.clubs.some((x) => x.id === c.id)) ?? lake.clubs[0];
  location.replace(`#/lake/${encodeURIComponent(r.lakeId)}${club ? `/${encodeURIComponent(club.id)}` : ""}?route=${encodeURIComponent(r.id)}`);
}

/** "6.2 km · Loop · rowed 3 Nov" (ManageRoutesView.details). */
function routeDetails(r) {
  const shape = RouteEdit.isLoop(r.points) ? t("Loop") : r.outAndBack ? t("Out and back") : t("One way");
  let text = `${distance(routeLength(r.points, r.outAndBack))} · ${shape}`;
  if (r.importedFrom) text += ` · ${r.rowedAt ? t("rowed %@", dayLabel(new Date(r.rowedAt))) : t("rowed")}`;
  return text;
}

/** A saved route on the map, for planning (RouteStore.load). */
function openRoute(r) {
  page.route.send({ type: "OPEN_ROUTE", route: r });
  page.spot = null;
  update();
  if (page.map) fitView();
}

function deleteRoute(r) {
  store.routes = store.routes.filter((x) => x.id !== r.id);
  if (page.savedId === r.id) page.route.send({ type: "DELETE_ROUTE" });
}

/** The one tip that fits the route drawn so far, in the app's order (LakeMapScreen.routeHint). */
function routeTip(isLoop) {
  const n = page.points.length;
  if (page.selected != null) return tip("turningPoint");
  // After the first turning point: one way, out and back, or a loop (WayBackTip).
  if (n >= 2 && !page.outAndBack && !isLoop && tip("wayBack")) return tip("wayBack");
  if (n >= 3) return tip("stretchPoint");
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
    // Thin and dashed in the text colour, as the app's (label colour at 80 %, 1.5 pt, 3-3 dashes).
    const theme = document.documentElement.dataset.theme;
    const dark = theme ? theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
    L.polyline(page.rowed.track.map((p) => [p.lat, p.lon]), { color: dark ? "#fff" : "#000", weight: 1.5, opacity: 0.8, dashArray: "3 3", interactive: false }).addTo(group);
  }
  // A thin line to tap: a tap on a stretch adds a turning point there.
  page.points.forEach((p, i) => {
    if (i === 0) return;
    const a = page.points[i - 1];
    L.polyline([[a.lat, a.lon], [p.lat, p.lon]], { color: "transparent", weight: 18 })
      .on("click", (ev) => {
        L.DomEvent.stop(ev);
        page.route.send({ type: "INSERT", index: i, point: { lat: ev.latlng.lat, lon: ev.latlng.lng } });
        update();
      }).addTo(group);
  });
  const isLoop = RouteEdit.isLoop(page.points);
  const turns = [];
  page.points.forEach((p, i) => {
    if (i === 0 || (isLoop && i === page.points.length - 1)) return;
    const marker = L.marker([p.lat, p.lon], {
      draggable: true,
      icon: L.divIcon({ className: `turn ${page.selected === i ? "on" : ""}`, html: `<span>${i}</span>`, iconSize: [24, 24], iconAnchor: [12, 12] }),
    }).addTo(group);
    marker.on("click", (ev) => {
      L.DomEvent.stop(ev);
      page.route.send({ type: "SELECT", index: i });
      update();
    });
    marker.on("dragend", () => {
      const ll = marker.getLatLng();
      page.route.send({ type: "MOVE", index: i, point: { lat: ll.lat, lon: ll.lng } });
      update();
    });
    turns.push({ marker, i });
  });
  hideOverlappingTurns(turns);
}

/**
 * As the app (MapKit's collision rule, owner 14 Nov 2026): a turning point that would overlap an earlier one at
 * this zoom is hidden, so they never pile up into a chain; the selected one always shows. Again after each zoom.
 */
function hideOverlappingTurns(turns) {
  const map = page.map;
  const place = () => {
    const shown = [];
    for (const { marker, i } of turns) {
      const at = map.latLngToContainerPoint(marker.getLatLng());
      const hide = page.selected !== i && shown.some((q) => q.distanceTo(at) < 22);
      marker.getElement()?.style.setProperty("visibility", hide ? "hidden" : "");
      if (!hide) shown.push(at);
    }
  };
  place();
  if (page.placeTurns) map.off("zoomend", page.placeTurns);
  page.placeTurns = place;
  map.on("zoomend", place);
}

function wirePanel() {
  const panel = page.root.querySelector("#lake-panel");
  fitProbe(panel);
  const on = (sel, event, fn) => panel.querySelector(sel)?.addEventListener(event, fn);
  panel.querySelectorAll("#hour-strip [data-hour]").forEach((b) => b.addEventListener("click", () => {
    page.hour = Number(b.dataset.hour);
    update();
  }));
  // Only the strip scrolls sideways to the hour; scrollIntoView would also scroll the panel down to the strip,
  // and a panel not at its top cannot be pushed down.
  const strip = panel.querySelector("#hour-strip");
  const chosen = strip?.querySelector(".on");
  if (chosen) {
    const [a, b] = [chosen.getBoundingClientRect(), strip.getBoundingClientRect()];
    strip.scrollLeft += a.left - b.left - (strip.clientWidth - a.width) / 2;
  }
  // The map's own controls: a layer's name shows for a moment beside the buttons after a switch.
  const over = page.root.querySelector("#lake-over");
  over.querySelectorAll("[data-layer]").forEach((b) => b.addEventListener("click", () => {
    page.layer = b.dataset.layer;
    page.layerNote = page.layer;
    clearTimeout(page.noteTimer);
    page.noteTimer = setTimeout(() => {
      page.layerNote = null;
      if (page.root.isConnected) page.root.querySelector(".layer-note")?.remove();
    }, 1200);
    update();
  }));
  over.querySelector("#scale").addEventListener("click", () => openSheet(t("Legend"), legendSheet()));
  on("#route-mode", "click", (e) => (closeTip(panel, "routePlanning"), !page.routeMode && lakeRoutes().length ? openMenu(e.currentTarget, routeStartMenu(), wireRoutes) : toggleRouteMode()));
  on("#legend", "click", () => openSheet(t("Legend"), legendSheet()));
  on("#about", "click", () => openSheet(t(WATER_TEXTS[waterKind(page.view)].about), aboutSheet()));
  panel.querySelectorAll("[data-way-back]").forEach((b) => b.addEventListener("click", () => {
    closeTip(panel, "wayBack");
    page.route.send({ type: "WAY_BACK", way: b.dataset.wayBack });
    update();
  }));
  on("#spot-close", "click", () => {
    page.spot = null;
    update();
  });
  // The route tools: each sends its event to the route editor (routedraft.js), then the panel redraws.
  const send = (type) => () => {
    page.route.send({ type });
    update();
  };
  on("#undo", "click", send("UNDO"));
  on("#clear", "click", send("CLEAR"));
  on("#delete-point", "click", send("DELETE_POINT"));
  on("#point-done", "click", send("DONE"));
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
    page.pace = store.routePace = Math.max(90, page.pace - 5);
    update();
  });
  on("#pace-up", "click", () => {
    page.pace = store.routePace = Math.min(240, page.pace + 5);
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
  on("#routes", "click", (e) => openMenu(e.currentTarget, routesMenu(), wireRoutes));
  wireTips(panel);
}

/** The route menus' buttons; each closes the menu before the panel redraws. */
function wireRoutes(menu) {
  menu.querySelector("#save-route")?.addEventListener("click", () => {
    menu.close();
    saveRoute();
  });
  menu.querySelector("#save-new-route")?.addEventListener("click", () => {
    menu.close();
    saveRoute(true);
  });
  menu.querySelector("#import-row input")?.addEventListener("change", (e) => {
    const file = e.target.files?.[0];
    menu.close();
    importRow(file);
  });
  menu.querySelector("#new-route")?.addEventListener("click", () => {
    menu.close();
    page.route.send({ type: "NEW_ROUTE" });
    page.spot = null;
    update();
  });
  menu.querySelector("#show-track")?.addEventListener("click", () => {
    page.showTrack = !page.showTrack;
    menu.close();
    update();
  });
  menu.querySelectorAll("[data-route]").forEach((b) => b.addEventListener("click", () => {
    const r = store.routes.find((x) => x.id === b.dataset.route);
    menu.close();
    if (r) openRoute(r);
  }));
  menu.querySelector("#manage-routes")?.addEventListener("click", () => {
    menu.close();
    openManageRoutes();
  });
  // The open saved route as a GPX file (RouteGPX in the app).
  menu.querySelector("#export-gpx")?.addEventListener("click", () => {
    const r = store.routes.find((x) => x.id === page.savedId);
    menu.close();
    if (r) downloadGpx(r);
  });
  menu.querySelector("#delete-open-route")?.addEventListener("click", () => {
    const r = store.routes.find((x) => x.id === page.savedId);
    menu.close();
    if (!r) return;
    deleteRoute(r);
    update();
  });
}

/** Save updates the open saved route; Save as new route keeps it and saves a copy (owner decision 12 Nov 2026). */
function saveRoute(asNew = false) {
  const { saved } = page.route;
  const fallback = t("Route %@", distance(routeLength(page.points, page.outAndBack)));
  const name = prompt(t(asNew ? "Save as new route" : "Save route"), asNew ? t("%@ (copy)", saved.name) : saved?.name ?? fallback);
  if (name == null || !page.route.send({ type: asNew ? "SAVE_AS_NEW" : "SAVE", name: name.trim() || fallback })) return;
  const route = page.route.saved;
  const list = store.routes;
  const i = list.findIndex((r) => r.id === route.id);
  if (i >= 0) list[i] = route;
  else list.push(route);
  store.routes = list;
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
  if (row.pace) page.pace = store.routePace = plannedPace(row.pace);
  page.route.send({ type: "OPEN_ROUTE", route });
  page.showTrack = true;
  update();
}

function toggleRouteMode() {
  page.route.send({ type: "TOGGLE_PLANNING" });
  page.spot = null;
  update();
}

function legendSheet() {
  const row = (sym, text) => `<li>${sym}<span>${h(text)}</span></li>`;
  const cold = coldShore(page.view.shoreWaterC, mapLimits());
  // Only what the map shows now, as the app's LakeMapLegend: the layer's colours, the stripes of this
  // hour, the wind and the tapped spot when there are any, the route rows while planning.
  const hour = shownHour();
  const kind = page.layer === "light" && hour ? stripes(hour.lakeWide) : null;
  const fall = stripesFall(page.view.outline);
  const found = currentPlan();
  const layerTitle = t(LAYERS.find(([k]) => k === page.layer)[1]);
  const colours = page.layer === "light"
    ? ["green", "amber", "red"].map((l) => row(dot(l, 14), lightTitle(l))).join("")
    : `<li class="ramp-row">${layerLegend(page.layer)}</li>`;
  return `<h3>${h(layerTitle)}</h3><ul class="legend">
      ${colours}
      ${kind === "red" ? row(stripeSwatch("red", fall), t("Grey squares with red stripes: the whole lake is red (official warning or darkness), see the panel.")) : ""}
      ${kind === "amber" ? row(stripeSwatch("amber", fall), t("Amber stripes: the whole lake is amber (the last hour before sunset, official warning), see the panel. The squares keep their own colours.")) : ""}</ul>
    <h3>${h(t("On the map"))}</h3><ul class="legend">
      ${row(`<span class="club-mark own"></span>`, t("The club of this page"))}
      ${row(`<span class="club-mark"></span>`, t("Other clubs on the lake"))}
      ${row(`<span class="club-mark own oars">${icon("oars")}</span>`, t("Zoomed in: the club's pin moves to the club's own place in the map app, and oars mark the launch point the forecast is for"))}
      ${cold ? row(`<span class="shore-mark" style="background:${COLD_SHORE[cold]}"></span>`, t("Blue shore: the water is cold. Bring a life jacket; light blue below %@, deeper blue below %@.", temperature(mapLimits().value("lifeJacket")), temperature(10))) : ""}
      ${hour?.wind?.length ? row(icon("arrow-up-right"), t("Wind: points where the wind blows to; longer arrows mean stronger wind. Between the forecast points the wind is estimated from the nearest ones. On land the arrows show the weather map's wind forecast for each place.")) : ""}
      ${page.spot != null && !page.routeMode ? row(icon("crosshair"), t("The spot you tapped")) : ""}</ul>
    ${page.routeMode ? `<h3>${h(t("Route"))}</h3><ul class="legend">
      ${row(`<span class="club-mark own"></span>`, t("Start at your club"))}
      ${row(`<span class="turn-mark">1</span>`, t("Turning point: tap to select, hold and drag to move"))}
      ${found?.plan.segments.length ? row(`<span class="route-bar small"><span style="width:34%;background:var(--green)"></span><span style="width:33%;background:var(--amber)"></span><span style="width:33%;background:var(--red)"></span></span>`, t("The route in the light the boat meets there; out and back run side by side")) : ""}
      ${boatStop(found?.plan) ? row(`<span class="club-mark boat"></span>`, t("Where the boat is at the time shown")) : ""}
      ${page.rowed?.track && page.showTrack ? row(`<span class="track-mark"></span>`, t("Dashed: the track as you rowed it (imported row)")) : ""}</ul>` : ""}`;
}

function aboutSheet() {
  const river = waterKind(page.view) !== "lake"
    ? `<p>${h(t("The view shows your club's stretch of the river: to the next weir or lock each way, or where a bigger river joins, else about 12 km upstream and 8 km downstream (10 km each way on canals). Markers show where it ends. It opens on the 10 km around your club."))}</p>`
    : "";
  return `${river}<p>${h(t("The lake is divided into small squares. For each square and hour, the app takes the wind from the nearest forecast point and works out the waves from how much open water the wind has crossed to get there."))}</p>
    <p>${h(t("Each square gets the same rowing light as a club page, from wind, gusts, waves, fog and thunderstorm risk at that square. Official warnings, darkness and cold water apply to the whole lake and are shown in the panel below the map. While they make the whole lake red, the squares turn grey with red stripes; in the last hour before sunset and under an amber official warning, fainter amber stripes are drawn over the squares. Cold water draws the shore blue and adds the life-jacket badge to the panel."))}</p>
    <p>${h(t("Waves are an estimate: there are no wave measurements on these lakes, and shelter from steep shores or currents is not taken into account."))}</p>
    <h3>${h(t("Data"))}</h3>
    ${(page.view.attribution ?? []).map((a) => `<p class="sub small">${h(t(a))}</p>`).join("")}`;
}
