// DWD's rain radar (RainRadar.swift): the reading at the launch point that the
// rain tile, the top tile and the rain view share (the radar for two hours,
// the forecast after them), the rain radar card (off by default) and the
// radar map from an hour ago to DWD's nowcast two hours ahead.

import { t, num } from "./i18n.js";
import { icon } from "./icons.js";
import { key, sky, precipitationKind } from "./logic.js";
import { store, h, time, rain, savingData, loadLeaflet, openSheet } from "./shared.js";

export const DWD_WMS = "https://maps.dwd.de/geoserver/dwd/wms";
const LAYER = "dwd:Niederschlagsradar";
const MIN = 60000;
/** mm/h; less is noise or drizzle that does not count. */
export const RAIN_FROM = 0.1;
export const RADAR_CREDIT = key("Radar: Deutscher Wetterdienst (DWD), CC BY 4.0");

// ---- Reading the radar at a point (RadarClient) -----------------------------------------

const iso = (ms) => new Date(ms).toISOString().replace(".000", "");

async function reading(point, at) {
  const d = 0.01;
  const query = new URLSearchParams({
    SERVICE: "WMS", VERSION: "1.3.0", REQUEST: "GetFeatureInfo", LAYERS: LAYER, QUERY_LAYERS: LAYER, CRS: "EPSG:4326",
    // WMS 1.3.0 with EPSG:4326 takes latitude first.
    BBOX: `${point.lat - d},${point.lon - d},${point.lat + d},${point.lon + d}`, WIDTH: "101", HEIGHT: "101", I: "50", J: "50",
    INFO_FORMAT: "application/json",
  });
  if (at != null) query.set("TIME", iso(at));
  const response = await fetch(`${DWD_WMS}?${query}`);
  if (!response.ok) throw new Error(`radar ${response.status}`);
  const props = (await response.json()).features?.[0]?.properties;
  const at2 = Date.parse(props?.TIME);
  const reference = Date.parse(props?.REFERENCE_TIME);
  if (!props || Number.isNaN(at2) || Number.isNaN(reference)) throw new Error("radar");
  return { time: at2, mm: Math.max(0, props.RV_ANALYSIS ?? 0), reference };
}

/** Now and every 15 minutes up to two hours ahead: { reference, steps: [{ time, mm }] } (times in ms). */
async function loadRadar(point) {
  const now = await reading(point, null);
  const steps = await Promise.all(Array.from({ length: 9 }, (_, i) => reading(point, now.reference + i * 15 * MIN)));
  return { reference: now.reference, steps: steps.map(({ time: at, mm }) => ({ time: at, mm })).sort((a, b) => a.time - b.time) };
}

const testSwitch = (name) => {
  try {
    return localStorage.getItem(name) === "true";
  } catch {
    return false;
  }
};

/** Handbook: `localStorage["rf.radarFailed"] = "true"` acts as if DWD did not answer (-RWRadarFailed). */
const radarDown = () => testSwitch("rf.radarFailed");

/** Handbook: `localStorage["rf.sampleRadar"] = "true"` puts made-up rain on the radar from 30 minutes on (-RWSampleRadar). */
function sampleRadar() {
  if (!testSwitch("rf.sampleRadar")) return null;
  const now = Math.floor(Date.now() / (5 * MIN)) * 5 * MIN;
  return { reference: now, steps: [0, 0, 0.6, 1.8, 3.2, 1.1, 0, 0, 0].map((mm, i) => ({ time: now + i * 15 * MIN, mm })) };
}

// ---- One reading per launch point, kept fresh while its page is open (RadarStore) ------------

const readings = new Map();
const loading = new Map();
const failed = new Set();
/** Failed reads in a row per launch point, for the quicker retries. */
const failures = new Map();
/** When each launch point was last asked, so a page drawn again does not ask before the retry is due. */
const tried = new Map();
const keyOf = (p) => `${p.lat},${p.lon}`;

/** DWD's 5 minutes; 15 when saving data. */
export const refreshMs = () => (savingData() ? 15 : 5) * MIN;

/** After a failed read: again after 30 seconds, 1 minute and 2 minutes, then at the usual pace (RadarStore.retries). */
const RETRIES = [0.5 * MIN, MIN, 2 * MIN];
export const retryDelay = (count) => (count >= 1 && count <= RETRIES.length ? Math.min(RETRIES[count - 1], refreshMs()) : refreshMs());
/** Refresh skips the radar when it was read this recently (RadarStore.pullGap). */
const PULL_GAP = MIN;

/** The last reading at a launch point, however old. */
export function radarAt(point) {
  if (!point) return null;
  return sampleRadar() ?? readings.get(keyOf(point))?.radar ?? null;
}

/** Whether the radar could not be read (not just still loading) and there is no reading still worth showing. */
export const radarFailed = (point) => point != null && failed.has(keyOf(point));

/** The reading at a point, asking DWD only when the last one is older than the refresh time (or `force`). */
export async function readRadar(point, force = false) {
  if (!point) return null;
  const sample = sampleRadar();
  if (sample) return sample;
  const k = keyOf(point);
  if (radarDown()) {
    readings.delete(k);
    failed.add(k);
    return null;
  }
  const kept = readings.get(k);
  if (!force && kept && Date.now() - kept.at < refreshMs()) return kept.radar;
  if (!force && failures.has(k) && Date.now() - tried.get(k) < retryDelay(failures.get(k)) - 1000) return kept?.radar ?? null;
  if (!loading.has(k)) {
    tried.set(k, Date.now());
    loading.set(k, loadRadar(point)
      .then((radar) => {
        readings.set(k, { radar, at: Date.now() });
        failed.delete(k);
        failures.delete(k);
        return radar;
      })
      .catch(() => {
        failures.set(k, (failures.get(k) ?? 0) + 1);
        // No reading, or one too old to show: the rain tile says the radar is missing.
        if (!ahead(readings.get(k)?.radar, Date.now())) failed.add(k);
        return readings.get(k)?.radar ?? null;
      })
      .finally(() => loading.delete(k)));
  }
  return loading.get(k);
}

/** Reads the radar now and again every refresh while `alive()`; `changed` gets each new reading. */
export function followRadar(point, alive, changed) {
  if (!point) return;
  const tick = async () => {
    if (!alive()) return;
    const before = radarAt(point);
    const radar = await readRadar(point);
    if (!alive()) return;
    if (radar !== before || (!radar && radarFailed(point))) changed(radar);
    setTimeout(tick, failures.has(keyOf(point)) ? retryDelay(failures.get(keyOf(point))) : refreshMs());
  };
  tick();
}

/** Refresh on a club page: reads the radar again unless it was read less than a minute ago and that read worked (RadarStore.reload). */
export async function reloadRadar(point) {
  if (!point || sampleRadar() || radarDown()) return;
  const k = keyOf(point);
  const fresh = () => !failures.has(k) && Date.now() - (readings.get(k)?.at ?? 0) < PULL_GAP;
  if (fresh()) return;
  await loading.get(k);
  if (fresh()) return;
  await readRadar(point, true);
}

// ---- What the radar says (RainRadar, RainOutlook) -------------------------------------

export const rainingNow = (r) => (r.steps[0]?.mm ?? 0) >= RAIN_FROM;
export const firstRain = (r) => r.steps.find((s) => s.mm >= RAIN_FROM) ?? null;
export const dryAgain = (r) => (rainingNow(r) ? r.steps.find((s) => s.mm < RAIN_FROM) ?? null : null);
export const peak = (r) => Math.max(0, ...r.steps.map((s) => s.mm));
/** Where the nowcast ends, two hours ahead. */
export const radarEnd = (r) => r.steps[r.steps.length - 1]?.time ?? r.reference;

/** The steps from `at` on; none once fewer than 30 minutes of the nowcast are left. */
export function ahead(r, at) {
  if (!r) return null;
  const left = r.steps.filter((s) => s.time > at - 7.5 * MIN);
  return left.length >= 3 ? { reference: r.reference, steps: left } : null;
}

export const intensity = (mm) => t(mm < 2.5 ? "Light rain" : mm < 10 ? "Rain" : "Heavy rain");
const level = (mm) => (mm < RAIN_FROM ? -1 : mm < 2.5 ? 0 : mm < 10 ? 1 : 2);

/** The radar card's line, e.g. "Light rain from 21:30" (RainRadar.summary). */
export function radarSummary(r) {
  const first = firstRain(r);
  if (!first) return t("No rain in the next 2 hours");
  if (rainingNow(r)) {
    const dry = dryAgain(r);
    return dry ? t("%@ now, dry from %@", intensity(peak(r)), time(dry.time)) : t("%@ for the next 2 hours", intensity(peak(r)));
  }
  return t("%@ from %@", intensity(peak(r)), time(first.time));
}

const kindOf = (hour) => precipitationKind(sky(hour.weatherCode));

/**
 * Rain from a moment on in the words the rain tile, the top tile and the rain
 * view share. The radar measures how much falls, not what, so snow, hail and
 * drizzle are named from the forecast's weather code for that hour.
 */
export function rainOutlook(r, hours) {
  const kind = (at) => {
    const hour = hours.filter((x) => Date.parse(x.time) <= at).pop() ?? hours[0];
    const k = hour && kindOf(hour);
    return k ? t(k) : t("Rain");
  };
  const first = r.steps[0];
  const now = first && rainingNow(r) ? (kind(first.time) === t("Rain") ? intensity(first.mm) : kind(first.time)) : null;
  const dry = dryAgain(r);
  const wet = firstRain(r);
  let next = null;
  if (now) {
    // Raining: it ends, or gets heavier, whichever comes first; else the forecast's end.
    const heavier = r.steps.find((s) => level(s.mm) > level(first.mm));
    if (dry && (!heavier || dry.time < heavier.time)) next = { text: t("Dry from %@", time(dry.time)), fromRadar: true };
    else if (heavier) next = { text: t("Heavier from %@", time(heavier.time)), fromRadar: true };
    else {
      const end = radarEnd(r);
      const after = hours.find((x) => Date.parse(x.time) >= end && (x.precipitationMm ?? 0) < 0.1);
      next = { text: after ? t("Until about %@", time(after.time)) : t("No end in sight"), fromRadar: false };
    }
  } else if (wet) {
    next = { text: t("%@ from %@", kind(wet.time), time(wet.time)), fromRadar: true };
  }
  const summary = now ? (dry ? t("%@ now, dry from %@", now, time(dry.time)) : t("%@ for the next 2 hours", now))
    : wet ? t("%@ from %@", kind(wet.time), time(wet.time)) : t("No rain in the next 2 hours");
  return { now, next, summary };
}

/** The radar from the shown moment on, while it still reaches half an hour ahead. */
export const radarAhead = (d) => ahead(d.radar, d.moment.getTime());

/**
 * The sky word and symbol for the shown moment, matched to the rain tile
 * (ConditionData.sky): while the radar covers the moment it decides whether
 * anything falls, so the headline never says "Rain" over a "Dry" rain tile, or
 * the other way round. The forecast still names how cloudy it is and what falls.
 */
export function skyNow(d) {
  const hour = d.now;
  const model = sky(hour.weatherCode, hour.cloudCoverPct, hour.precipitationMm);
  const a = radarAhead(d);
  if (!a) return model;
  const wet = precipitationKind(model) != null;
  if (rainingNow(a)) {
    if (wet) return model;
    if ((hour.temperatureC ?? 10) <= 0) return "snow";
    return (a.steps[0]?.mm ?? 0) >= 10 ? "heavyRain" : "rain";
  }
  return wet ? sky(null, hour.cloudCoverPct, 0) : model;
}

/** The first forecast hour with rain after the radar's two hours (or from the shown hour without radar). */
export function forecastRain(d) {
  const a = radarAhead(d);
  const after = a ? radarEnd(a) : -Infinity;
  return d.next24.find((x) => (x.precipitationMm ?? 0) >= 0.1 && Date.parse(x.time) >= after) ?? null;
}

/** The rain tile's and the top tile's two lines: the radar for two hours, then the forecast (ConditionData.rainLines). */
export function rainLines(d) {
  const later = () => {
    const wet = forecastRain(d);
    return wet ? t("%@ from %@", t(kindOf(wet) ?? "Rain"), time(wet.time)) : t("Dry next 24 h");
  };
  const a = radarAhead(d);
  if (a) {
    const outlook = rainOutlook(a, d.timeline);
    if (outlook.next) return { value: outlook.now ?? t("Dry"), detail: outlook.next.text, fromRadar: outlook.next.fromRadar };
    return { value: outlook.now ?? t("Dry"), detail: later(), fromRadar: false };
  }
  if ((d.now.precipitationMm ?? 0) >= 0.1) return { value: rain(d.now.precipitationMm), detail: kindOf(d.now) ? t(kindOf(d.now)) : "", fromRadar: false };
  return { value: t("Dry"), detail: later(), fromRadar: false };
}

/**
 * The rain tile's graphic while the radar is read: thin bars for the radar's
 * quarter hours, a line, then wider, paler bars for the forecast's next hours,
 * on one scale (RadarSparkBars). Null without the radar.
 */
export function radarGraphic(d) {
  const a = radarAhead(d);
  if (!a) return null;
  const end = radarEnd(a);
  const radar = a.steps.map((s) => s.mm);
  const forecast = d.future.filter((x) => Date.parse(x.time) >= end).slice(0, 4).map((x) => x.precipitationMm ?? 0);
  const top = Math.max(0.1, ...radar, ...forecast);
  const bar = (v, wet, cls = "") => `<span class="${wet ? "wet" : ""} ${cls}" style="height:${Math.max(2, (28 * Math.min(v, top)) / top)}px"></span>`;
  return `<span class="spark radar" aria-hidden="true">${radar.map((v) => bar(v, v >= RAIN_FROM)).join("")}<i></i>${forecast.map((v) => bar(v, v >= 0.1, "later")).join("")}</span>`;
}

/** The small radar symbol in front of a line read from the radar. */
/**
 * The small radar symbol in the rain tile's title line: the bars come from the
 * radar, or (struck through) the radar could not be read and the bars are the
 * forecast's only (RadarMark).
 */
export const radarTitleMark = (missing) => `<span class="radar-mark head${missing ? " missing" : ""}" role="img" aria-label="${h(missing ? t("Radar not available right now") : t("Radar"))}">${icon("radar")}</span>`;

export const radarMark = () => `<span class="radar-mark" title="${h(t("Rain radar"))}">${icon("radar")}</span>`;

// ---- The rain radar card (RainRadarCard), off by default -------------------------------

export function radarCard(point) {
  return `<section class="card radar-card" id="radar">${radarCardBody(point)}</section>`;
}

export function radarCardBody(point) {
  const r = radarAt(point);
  const title = `<header class="card-title">${icon("umbrella")}<span>${h(t("Rain radar"))}</span></header>`;
  if (!r) return `${title}<p class="sub">${h(radarFailed(point) ? t("Radar not available right now") : t("Loading…"))}</p>`;
  const bars = r.steps.map((s) => `<span class="${s.mm >= RAIN_FROM ? "wet" : ""}" style="height:${4 + 36 * Math.min(s.mm / 10, 1)}px"
    title="${h(`${time(s.time)}: ${rain(s.mm)}`)}"></span>`).join("");
  return `${title}<button class="radar-open" aria-label="${h(t("Opens the rain radar map"))}">
      <span class="radar-line"><strong>${h(radarSummary(r))}</strong><span class="tint small">${h(t("Map"))} ${icon("chevron-right")}</span></span>
      <span class="radar-bars">${bars}</span>
      <span class="radar-axis sub"><small>${h(t("Now"))}</small><small>+1 h</small><small>+2 h</small></span></button>
    <p class="sub small">${h(t(RADAR_CREDIT))}</p>`;
}

/** Opens the radar map from the card. */
export function wireRadarCard(box, point) {
  box?.querySelector(".radar-open")?.addEventListener("click", () => openRadarMap(point, radarAt(point)?.reference));
}

// ---- The radar map (RadarMapScreen, RadarRegion, RadarFrames) -------------------------------

/** DWD's colours for dwd:Niederschlagsradar and the rain each stands for, in mm/h (RadarColours). */
export const RADAR_COLOURS = [
  ["#33ffff", 0.1, 0.2], ["#1acc9a", 0.2, 0.4], ["#019934", 0.4, 1], ["#4db31b", 1, 2], ["#99cc01", 2, 3], ["#cce601", 3, 5],
  ["#ffff01", 5, 7.5], ["#ffc401", 7.5, 10], ["#ff8901", 10, 15], ["#ff4501", 15, 30], ["#fe0000", 30, 45], ["#e5004c", 45, 75],
  ["#cc0098", 75, 100], ["#6600cb", 100, 150], ["#0000fe", 150, null],
];

const number = (v) => num(v, Math.round(v) === v ? 0 : 1);
const range = ([, from, to]) => (to == null ? `≥ ${number(from)} mm/h` : `${number(from)}–${number(to)} mm/h`);

/** Minutes between the map's pictures; 30 when saving data (7 pictures instead of 13). */
export const radarStep = () => (savingData() ? 30 : 15);

/** The latest radar picture's time; now to 5 minutes when not known yet. */
const base = (reference) => reference ?? Math.floor(Date.now() / (5 * MIN)) * 5 * MIN;

/** From an hour ago to DWD's nowcast two hours ahead (RadarWindow.frames). */
export function radarFrames(reference, step = radarStep()) {
  const b = base(reference);
  const out = [];
  for (let m = -60; m <= 120; m += step) out.push(b + m * MIN);
  return out;
}

/** Whether the radar has a picture for a time: an hour back to two ahead. */
export const radarCovers = (at, now = Date.now()) => at - now >= -3600000 && at - now <= 7200000;

/** The frame nearest a time, while the radar covers it. */
export function nearestFrame(at, frames) {
  if (!radarCovers(at)) return null;
  return frames.reduce((a, b) => (Math.abs(b - at) < Math.abs(a - at) ? b : a));
}

const R = 6378137;
/** The square around the club the pictures cover: 300 km of web-mercator map each way, one 1024 px picture. */
export function radarRegion(point) {
  const x = (point.lon * Math.PI * R) / 180;
  const y = Math.log(Math.tan(Math.PI / 4 + (point.lat * Math.PI) / 360)) * R;
  const half = 300000;
  const lat = (yy) => ((2 * Math.atan(Math.exp(yy / R)) - Math.PI / 2) * 180) / Math.PI;
  const lon = (xx) => (xx / R) * 180 / Math.PI;
  return {
    bbox: [x - half, y - half, x + half, y + half],
    bounds: [[lat(y - half), lon(x - half)], [lat(y + half), lon(x + half)]],
  };
}

export function radarUrl(region, at) {
  const query = new URLSearchParams({
    SERVICE: "WMS", VERSION: "1.3.0", REQUEST: "GetMap", LAYERS: LAYER, STYLES: "", CRS: "EPSG:3857", BBOX: region.bbox.join(","),
    WIDTH: "1024", HEIGHT: "1024", FORMAT: "image/png8", TRANSPARENT: "TRUE", TIME: iso(at),
  });
  return `${DWD_WMS}?${query}`;
}

/** Pictures loaded in this visit, by URL; a frame shown again needs nothing new. */
const pictures = new Map();

function picture(url) {
  if (!pictures.has(url)) {
    pictures.set(url, new Promise((resolve) => {
      const img = new Image();
      let tries = 0;
      img.onload = () => resolve(true);
      img.onerror = () => {
        if (++tries < 3) setTimeout(() => (img.src = `${url}&retry=${tries}`), tries * 1000);
        else {
          pictures.delete(url);
          resolve(false);
        }
      };
      img.src = url;
    }));
  }
  return pictures.get(url);
}

/**
 * The radar picture over a Leaflet map (the rain view's map card). `show`
 * keeps the last picture until the next one has loaded, so nothing flashes.
 */
export function radarOverlay(L, map, point) {
  const region = radarRegion(point);
  let overlay = null;
  let wanted = null;
  return {
    async show(at) {
      const url = radarUrl(region, at);
      wanted = url;
      if (!(await picture(url)) || wanted !== url) return;
      if (overlay) overlay.setUrl(url);
      else overlay = L.imageOverlay(url, region.bounds, { opacity: 0.75, interactive: false }).addTo(map);
    },
    remove() {
      wanted = null;
      overlay?.remove();
      overlay = null;
    },
  };
}

/** A thin colour bar from light to heavy rain with a few numbers under it. */
export function radarColourBar() {
  const step = 100 / RADAR_COLOURS.length;
  return `<div class="radar-colours" aria-label="${h(t("Colours from light blue for light rain over green and yellow to red and purple for heavy rain"))}">
    <span class="bar">${RADAR_COLOURS.map(([c]) => `<i style="background:${c}"></i>`).join("")}</span>
    <span class="labels">${[0, 4, 8, 11].map((i) => `<small style="left:${i * step}%">${h(number(RADAR_COLOURS[i][1]))}</small>`).join("")}<small class="unit">mm/h</small></span></div>`;
}

function legendBody() {
  return `<ul class="radar-legend">${RADAR_COLOURS.map((c) => `<li><i style="background:${c[0]}"></i><span>${h(range(c))}</span><span class="sub">${h(intensity(c[1]))}</span></li>`).join("")}</ul>
    <p class="sub small">${h(t("Rain as measured by DWD's radar (past and latest picture) and as DWD expects it to move (forecast). Snow and hail show as rain. Radar: Deutscher Wetterdienst (DWD), CC BY 4.0"))}</p>`;
}

/**
 * The rain radar full screen around the club: every picture from an hour ago
 * to two hours ahead is loaded first (the latest first, then outwards), then
 * it plays, with a slider and the repeat switch the weather maps share.
 */
export async function openRadarMap(point, reference) {
  if (!point) return;
  const step = radarStep();
  const frames = radarFrames(reference, step);
  const nowIndex = 60 / step;
  const region = radarRegion(point);
  const panel = document.createElement("div");
  panel.className = "wm-full radar-full";
  panel.innerHTML = `<header class="nav"><span></span><strong class="nav-title">${h(t("Rain radar"))}</strong><button class="link strong" id="rm-done">${h(t("Done"))}</button></header>
    <div class="wm" id="rm-map"></div><section class="wm-panel" id="rm-panel"></section>`;
  document.body.append(panel);
  document.body.classList.add("locked");
  const L = await loadLeaflet();
  if (!panel.isConnected) return;
  const map = L.map(panel.querySelector("#rm-map"), { zoomControl: true, zoomSnap: 0.25 });
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19, referrerPolicy: "strict-origin", attribution: '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>',
  }).addTo(map);
  map.fitBounds([[point.lat - 0.6, point.lon - 0.8], [point.lat + 0.6, point.lon + 0.8]], { animate: false });
  L.circleMarker([point.lat, point.lon], { radius: 6, color: "#fff", weight: 2, fillColor: "#007aff", fillOpacity: 1, interactive: false }).addTo(map);
  const overlay = L.imageOverlay(radarUrl(region, frames[nowIndex]), region.bounds, { opacity: 0.75, interactive: false }).addTo(map);
  let index = nowIndex;
  let playing = false;
  let timer = null;
  let rounds = 0;
  const loaded = new Set();
  let failedCount = 0;
  let done = false;

  const close = () => {
    clearTimeout(timer);
    map.remove();
    panel.remove();
    document.body.classList.remove("locked");
    document.removeEventListener("keydown", keys);
  };
  const keys = (e) => e.key === "Escape" && !document.querySelector("dialog.sheet") && close();
  document.addEventListener("keydown", keys);
  panel.querySelector("#rm-done").addEventListener("click", close);

  const show = () => {
    const url = radarUrl(region, frames[index]);
    // A picture still loading keeps the last one rather than an empty map.
    if (loaded.has(frames[index])) overlay.setUrl(url);
  };
  const tick = () => {
    if (!playing || !panel.isConnected) return;
    if (index < frames.length - 1) index++;
    else if (store.mapLoop && rounds < 2) {
      rounds++;
      index = 0;
    } else {
      playing = false;
      index = nowIndex;
    }
    show();
    render();
    // A little longer on the latest picture and at the end, so they can be read.
    if (playing) timer = setTimeout(tick, index === nowIndex || index === frames.length - 1 ? 1400 : 600);
  };
  const play = (on) => {
    clearTimeout(timer);
    playing = on;
    if (on) {
      rounds = 0;
      if (index === frames.length - 1) index = 0;
      show();
      timer = setTimeout(tick, 600);
    }
    render();
  };

  function render() {
    const p = panel.querySelector("#rm-panel");
    const label = index < nowIndex ? t("radar") : index === nowIndex ? t("latest radar picture") : t("forecast");
    p.innerHTML = `<p class="wm-line"><strong>${h(time(frames[index]))}</strong><span class="sub">${h(label)}</span><span class="spacer"></span>
        ${loaded.size < frames.length && !done ? `<progress max="${frames.length}" value="${loaded.size}" aria-label="${h(t("Loading the radar pictures"))}"></progress>` : ""}
        <button class="tool" id="rm-legend" aria-label="${h(t("What the colours mean"))}">${icon("info")}</button></p>
      ${radarColourBar()}
      <div class="map-controls"><button class="tool" id="rm-play" aria-label="${h(playing ? t("Pause") : t("Play"))}">${icon(playing ? "pause" : "play")}</button>
        <input type="range" id="rm-slider" min="0" max="${frames.length - 1}" step="1" value="${index}" aria-label="${h(t("Time"))}">
        <button class="tool ${store.mapLoop ? "on" : ""}" id="rm-loop" aria-label="${h(t("Play 3 times"))}">${icon("repeat")}</button></div>
      <p class="radar-axis sub"><small>−1 h</small><small>${h(t("Now"))}</small><small>+1 h</small><small>+2 h</small></p>
      ${failedCount && done ? `<p class="small orange">${h(t("%@ of %@ pictures could not be loaded.", String(failedCount), String(frames.length)))}</p>` : ""}
      <p class="small sub">${h(t(RADAR_CREDIT))}</p>`;
    p.querySelector("#rm-play").addEventListener("click", () => play(!playing));
    p.querySelector("#rm-slider").addEventListener("input", (e) => {
      clearTimeout(timer);
      playing = false;
      index = Number(e.target.value);
      show();
      render();
    });
    p.querySelector("#rm-loop").addEventListener("click", () => {
      store.mapLoop = !store.mapLoop;
      render();
    });
    p.querySelector("#rm-legend").addEventListener("click", () => openSheet(t("What the colours mean"), legendBody()));
  }
  render();

  // The latest picture first, then outwards, three at a time: DWD's server is slow with many at once.
  const order = frames.map((_, i) => i).sort((a, b) => Math.abs(a - nowIndex) - Math.abs(b - nowIndex));
  let next = 0;
  const worker = async () => {
    while (next < order.length && panel.isConnected) {
      const i = order[next++];
      if (await picture(radarUrl(region, frames[i]))) loaded.add(frames[i]);
      else failedCount++;
      if (!panel.isConnected) return;
      if (i === index) show();
      if (!playing) render();
    }
  };
  await Promise.all([worker(), worker(), worker()]);
  done = true;
  if (!panel.isConnected) return;
  // Starts playing on its own once every picture is there.
  if (loaded.size === frames.length) play(true);
  else render();
}
