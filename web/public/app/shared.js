// What every page of the web app shares: what stays in the browser, the boats,
// loading the published files, the formatting (Format in the app) and the
// small pieces such as the rowing light's dot and the sheets.

import { t, num, locale } from "./i18n.js";
import { icon } from "./icons.js";
import {
  API, ZONE, shownLight, windValue, WIND_UNITS, localDay, sky, SKY_TITLES, skyIcon, precipitationKind, BOATS, twilight, GROUPS, BOAT_TYPES, LIMITS, isGroup, limitsFor, applyLimits, beaufort, COLD,
} from "./logic.js";

// ---- Stored in the browser -------------------------------------------------

export function load(name, fallback) {
  try {
    const raw = localStorage.getItem(name);
    return raw == null ? fallback : JSON.parse(raw);
  } catch {
    return fallback;
  }
}

export function save(name, value) {
  try {
    localStorage.setItem(name, JSON.stringify(value));
  } catch {}
}

export const store = {
  get clubs() { return load("rf.clubs", []); },
  set clubs(list) { save("rf.clubs", list); },
  // m/s and small boats, as the app starts.
  get wind() { return WIND_UNITS[load("rf.wind", "ms")] ? load("rf.wind", "ms") : "ms"; },
  set wind(unit) { save("rf.wind", unit); },
  // The boat the rowing light is for: a group or one of the user's own boats.
  get boat() { const id = load("rf.boat", "small"); return allBoats().some((b) => b.id === id) ? id : "small"; },
  set boat(id) { save("rf.boat", id); },
  /** The user's own boats, besides the small and big boat groups: { id, name, type, class }. */
  get boats() { return load("rf.boats", []); },
  set boats(list) { save("rf.boats", list); },
  /** Limits the user changed, per boat id; a missing entry means the app's limit for the boat's type. */
  get limits() { return load("rf.limits", {}); },
  set limits(value) { save("rf.limits", value); },
  /** The boat the lake map is coloured for, or "follow" for the ticked one. */
  get mapBoat() { return load("rf.mapBoat", "small"); },
  set mapBoat(id) { save("rf.mapBoat", id); },
  /** Saved routes: { id, name, lakeId, points: [{ lat, lon }], outAndBack }. */
  get routes() { return load("rf.routes", []); },
  set routes(list) { save("rf.routes", list); },
  /** Whether a value page's map follows its chart (DetailTime.linked). */
  get mapLinked() { return load("rf.mapLinked", true); },
  set mapLinked(on) { save("rf.mapLinked", on); },
  /** How much map the weather maps open with: "close", "normal" or "wide". */
  get mapZoom() { return load("rf.mapZoom", "normal"); },
  set mapZoom(zoom) { save("rf.mapZoom", zoom); },
  /** The full-screen map plays 3 times round. */
  get mapLoop() { return load("rf.mapLoop", true); },
  set mapLoop(on) { save("rf.mapLoop", on); },
  /** "About the limits" open on value pages. */
  get limitInfo() { return load("rf.limitInfo", false); },
  set limitInfo(on) { save("rf.limitInfo", on); },
  /** The layers drawn over the satellite picture (SatelliteLayers). */
  get satLayers() { const on = load("rf.satLayers", []); return Array.isArray(on) ? on : []; },
  set satLayers(list) { save("rf.satLayers", list); },
  get safety() { return load("rf.safety", null); },
  set safety(value) { save("rf.safety", value); },
};

export function savedClub(club, lake) {
  return {
    id: club.id, name: club.name, shortName: club.shortName, address: club.address, lakeId: lake.id, lakeName: lake.name,
    country: club.country ?? lake.country, launchPoint: club.launchPoint, launchPointVerified: club.launchPointVerified, source: club.source,
  };
}

// ---- Boats (AppSettings.boats) ------------------------------------------------

/** Small boats, big boats, then the user's own. */
export function allBoats() {
  return [...GROUPS, ...store.boats];
}

export const boatById = (id) => allBoats().find((b) => b.id === id) ?? GROUPS[0];
export const selectedBoat = () => boatById(store.boat);
export const boatLimits = (boat) => limitsFor(boat, store.limits[boat.id] ?? {});
/** The limits the rowing light uses. */
export const currentLimits = () => boatLimits(selectedBoat());

export function boatTitle(boat) {
  if (isGroup(boat)) return t(BOATS[boat.id].title);
  return boat.name?.trim() || `${t(BOAT_TYPES[boat.type].title)} ${boat.class}`;
}

/** The boat inside a sentence: "for small boats", "for Anna". */
export const boatInSentence = (boat) => (isGroup(boat) ? t(BOATS[boat.id].inSentence) : boatTitle(boat));
export const boatDetail = (boat) => (isGroup(boat) ? t(BOATS[boat.id].detail) : t("%@ · %@", t(BOAT_TYPES[boat.type].title), boat.class));
/** For the bottom bar: "Small", "Big", its own name, or its class. */
export const boatShort = (boat) => (isGroup(boat) ? t(BOATS[boat.id].short) : boat.name?.trim() || boat.class);

/** The boat whose limits colour the lake view and route planning. */
export const mapBoat = () => (store.mapBoat === "follow" ? selectedBoat() : boatById(store.mapBoat));
export const mapLimits = () => boatLimits(mapBoat());

/** A limit's value in the user's units; wind keeps its decimal so 5.5 m/s does not read as 6. */
export function limitText(limit, value) {
  const { condition } = LIMITS[limit];
  if (condition === "waves") return waves(value);
  if (condition === "waterTemperature") return temperature(value);
  if (store.wind === "bft") return `${beaufort(value)} Bft`;
  const v = WIND_UNITS[store.wind].from(value);
  return `${num(v, Math.abs(v - Math.round(v)) < 0.05 ? 0 : 1)} ${windUnit()}`;
}

/** The forecast for the ticked boat. */
export const forBoat = (raw) => applyLimits(raw, currentLimits());

// ---- Loading ---------------------------------------------------------------

export async function getJSON(path) {
  const response = await fetch(`${API}/${path}`, { cache: "no-cache" });
  if (!response.ok) throw new Error(`${response.status} ${path}`);
  return response.json();
}

export let catalog = null;

/** Every water with its clubs, in all countries the search covers. */
export async function loadCatalog() {
  if (catalog) return catalog;
  const kept = load("rf.catalog", null);
  if (kept && Date.now() - kept.at < 24 * 3600 * 1000) return (catalog = kept.lakes);
  const countries = await getJSON("countries/index");
  const lists = await Promise.all(countries.map((c) => getJSON(`countries/${c.code}/lakes`)));
  catalog = lists.flat();
  save("rf.catalog", { at: Date.now(), lakes: catalog });
  return catalog;
}

/** The club with its lake from the catalog, for clubs saved before the launch point was kept. */
export async function findClub(id) {
  const lakes = await loadCatalog().catch(() => []);
  for (const lake of lakes) {
    const club = lake.clubs.find((c) => c.id === id);
    if (club) return savedClub(club, lake);
  }
  return null;
}

export const forecasts = new Map();

export async function loadForecast(id, fresh = false) {
  const kept = forecasts.get(id);
  if (kept && !fresh && Date.now() - kept.at < 5 * 60 * 1000) return kept.forecast;
  const forecast = await getJSON(`clubs/${encodeURIComponent(id)}/forecast`);
  forecasts.set(id, { at: Date.now(), forecast });
  return forecast;
}

// ---- Formatting, as Format in the app ---------------------------------------------

export function h(text) {
  return String(text ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

export function time(value) {
  return new Intl.DateTimeFormat(locale(), { timeZone: ZONE, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(value));
}

/** "Today", "Tomorrow" or "Tuesday, 27 Oct". */
export function dayLabel(value) {
  const day = typeof value === "string" && value.length === 10 ? value : localDay(value);
  if (day === localDay(new Date())) return t("Today");
  if (day === localDay(new Date(Date.now() + 86400000))) return t("Tomorrow");
  return new Intl.DateTimeFormat(locale(), { timeZone: "UTC", weekday: "long", day: "numeric", month: "short" }).format(new Date(`${day}T12:00:00Z`));
}

export function dayTime(value) {
  return new Intl.DateTimeFormat(locale(), { timeZone: ZONE, weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(value));
}

export function duration(from, to) {
  const minutes = Math.max(0, Math.floor((to - from) / 60000));
  return minutes >= 60 ? `${Math.floor(minutes / 60)} h ${minutes % 60} min` : `${minutes} min`;
}

export const degrees = (c, digits = 0) => (c == null ? "–" : `${num(c, digits)}°`);
export const temperature = (c, digits = 0) => (c == null ? "–" : `${num(c, digits)} °C`);
export const windUnit = () => WIND_UNITS[store.wind].label;
export const windNumber = (ms) => (ms == null ? "–" : num(windValue(ms, store.wind)));
export const wind = (ms) => (ms == null ? "–" : `${windNumber(ms)} ${windUnit()}`);
export const windRange = (ms, gust) => (ms == null ? "–" : `${windNumber(ms)}–${windNumber(gust)}`);
export const wavesNumber = (m) => (m == null ? "–" : num(m, 2));
export const waves = (m) => (m == null ? "–" : `${wavesNumber(m)} m`);
export const rainNumber = (mm) => (mm == null ? "–" : num(mm, 1));
export const rain = (mm) => (mm == null ? "–" : `${rainNumber(mm)} mm`);
export const distanceNumber = (m) => (m == null ? "–" : num(m / 1000, m < 10000 ? 1 : 0));
export const distance = (m) => (m == null ? "–" : `${distanceNumber(m)} km`);

/** "Rain 3.1 mm", or null when nothing falls. */
export function precipitationText(hour) {
  const kind = precipitationKind(sky(hour.weatherCode));
  if (hour.precipitationMm == null) return kind ? t(kind) : "–";
  if (hour.precipitationMm < 0.05 && !kind) return null;
  return `${t(kind ?? "Rain")} ${rain(hour.precipitationMm)}`;
}

export function lightTitle(light, stale = false) {
  if (stale && light === "green") return t("Forecast out of date");
  return { green: t("Good to row"), amber: t("Row with care"), red: t("Stay ashore"), grey: t("Forecast out of date") }[light];
}

/** A reason's short label; "(your limit)" when the user's own limit decided it. */
export function reasonLabel(reason) {
  const base = baseLabel(reason.condition ?? reason);
  return reason.mine ? t("%@ (your limit)", base) : base;
}

export function baseLabel(condition) {
  return {
    lake_warning: t("DWD storm warning"), lake_strong_wind: t("DWD strong-wind warning"), single_cold: t("Single in cold water"),
    freezing_water: t("Near-freezing water"), weather_warning: t("DWD weather warning"), wind: t("Wind"), gusts: t("Gusts"),
    waves: t("Waves"), fog: t("Fog"), heavy_rain: t("Heavy rain"), hail: t("Hail"), thunderstorm: t("Thunderstorm risk"),
    ice: t("Ice"), daylight: t("Sun down"), twilight: t("Sunrise / sunset"), cold_water: t("Very cold water"),
    cool_water: t("Cold-water shock possible"),
  }[condition] ?? condition;
}

/** "Water near Aken" in the page's language (Lake.title). */
export const lakeTitle = (name) => (name?.startsWith("Water near ") ? t("Water near %@", name.slice("Water near ".length)) : name);

/** A reason's sentence for an hour; "sunrise or sunset in this hour" says which, and when. */
export function hourExplanation(forecast, reason, hour) {
  if (reason.condition === "twilight") {
    const sun = twilight(forecast, hour);
    if (sun) return sun.kind === "sunrise" ? t("Sunrise at %@ in this hour.", time(sun.time)) : t("Sunset at %@ in this hour.", time(sun.time));
  }
  const text = reasonExplanation(reason.condition, reason.light);
  return reason.mine ? `${text} ${t("You set this limit yourself.")}` : text;
}

/** A note under the reasons: a value within the user's own limit but above the app's (Reason.noteText). */
export function noteText(note) {
  if (note.condition === "cold_margin") {
    return t("Cold water: the app lowers its wind and gust limits by %@ below %@. Your own limits stay as you set them, so take extra care.", wind(COLD.marginMs), temperature(COLD.waterC));
  }
  return t("%@: above the app's usual limit for %@, within yours. Take extra care.", baseLabel(note.condition), boatInSentence(selectedBoat()));
}

export function reasonExplanation(condition, light) {
  switch (condition) {
    case "lake_warning": return t("DWD has issued a storm warning for the lake; its warning lights flash 90 times a minute.");
    case "lake_strong_wind": return t("DWD has issued a strong-wind warning for the lake; its warning lights flash 40 times a minute.");
    case "single_cold": return t("In a single, row with a coach boat or a partner boat while the water is this cold.");
    case "freezing_water": return t("The water is below %@. You are strongly advised not to go out, at least not in a small boat.", temperature(4));
    case "weather_warning": return t("DWD has issued a weather warning for this place.");
    case "wind": return t("Mean wind is above the limit.");
    case "gusts": return t("Gusts are above the limit.");
    case "waves": return t("Waves at the launch point are too high.");
    case "fog": return t("Visibility is poor (fog or mist).");
    case "heavy_rain": return t("Heavy rain of %@ or more in the hour.", rain(4));
    case "hail": return t("Hail is forecast with a thunderstorm.");
    case "thunderstorm": return t("Thunderstorms are possible.");
    case "ice": return light === "red" ? t("Ice on the lake is likely (estimate).") : t("Thin ice at the shore or drift ice is possible (estimate).");
    case "daylight": return t("The sun is down. Rowing is only advised in daylight.");
    case "twilight": return t("Sunrise or sunset falls in this hour.");
    case "cold_water": return t("Very cold water, below %@: wear a life jacket, stay near the shore and don't row alone.", temperature(10));
    case "cool_water": return t("Water is below %@: a capsize can cause cold-water shock. We advise a life jacket.", temperature(15));
    default: return condition;
  }
}

/** The badge's short text and full advice for what cold water calls for (ColdWaterKit). */
export function coldWaterText(kit) {
  return {
    lifeJacket: [t("Life jacket"), t("Cold water: a capsize can cause cold-water shock. Wear a life jacket and clothes that keep you warm when wet.")],
    partnerBoat: [t("Life jacket · partner boat"), t("Very cold water, below %@: wear a life jacket, stay near the shore and row a single only with a coach boat or a partner boat.", temperature(10))],
    nearShore: [t("Life jacket · near the shore"), t("Very cold water, below %@: wear a life jacket, stay near the shore and don't row alone.", temperature(10))],
  }[kit];
}

/** The blue badge under the rowing light: what to bring, not a warning (ColdWaterBadge). */
export function coldWaterBadge(kit, estimated) {
  const [title, advice] = coldWaterText(kit);
  return `<button class="kit" data-tile="waterTemperature" title="${h(estimated ? t("Estimated: %@", advice) : advice)}">${icon("life-buoy")} ${h(estimated ? `≈ ${title}` : title)}</button>`;
}

export const flag = (code) => String.fromCodePoint(...[...(code ?? "de").toUpperCase()].map((c) => 0x1f1a5 + c.charCodeAt(0)));

export function setTitle(text) {
  document.title = text ? `${text} · Row Frog` : "Row Frog";
}

// ---- Small pieces, as in the app ---------------------------------------------------

/** The rowing light as a dot; green turns grey on an old forecast. */
export function dot(light, size = 14, stale = false) {
  return `<span class="dot ${h(shownLight(light, stale))}" style="--s:${size}px" aria-hidden="true"></span>`;
}

/** The weather symbol for an hour, coloured like the app's multicolour symbols. */
export function skySymbol(hour, cls = "") {
  const [name, colour] = skyIcon(sky(hour.weatherCode), hour.sunUp === false);
  return `<span class="sky ${colour} ${cls}" title="${h(t(SKY_TITLES[sky(hour.weatherCode)]))}">${icon(name)}</span>`;
}

export const CONDITION_ICONS = {
  temperature: "thermometer", feelsLike: "person-standing", humidity: "droplets", pressure: "gauge", wind: "wind", waves: "waves",
  waterTemperature: "thermometer-snowflake", precipitation: "cloud-rain", visibility: "binoculars", cloudCover: "cloud",
  thunderstorm: "cloud-lightning", uvIndex: "sun", ice: "snowflake", daylight: "sunrise", warning: "triangle-alert",
};

export function conditionIcon(condition) {
  return `<span class="cond ${condition}">${icon(CONDITION_ICONS[condition] ?? "info")}</span>`;
}

/** A card with an uppercase caption and an icon, like Card in the app. */
export function card(title, iconName, body, { legend = null, id = "", cls = "" } = {}) {
  return `<section class="card ${cls}" ${id ? `id="${id}"` : ""}>
    <header class="card-title">${icon(iconName)}<span>${h(title)}</span>
      ${legend ? `<button class="info" data-legend="${legend}" aria-label="${h(t("What the symbols mean"))}">${icon("info")}</button>` : ""}</header>
    ${body}</section>`;
}

/** A coloured bar with a dot where the value sits (ScaleBar). */
export function scaleBar(fraction, colours) {
  const f = Math.min(1, Math.max(0, fraction ?? 0));
  return `<span class="scale" style="--bar:linear-gradient(90deg, ${colours.join(", ")})"><span class="knob" style="left:${f * 100}%"></span></span>`;
}

/** Colour zones from a list of [start, colour] (ScaleBar with zones). */
export function zoneBar(fraction, zones) {
  const stops = zones.map(([start, colour], i) => {
    const end = i + 1 < zones.length ? zones[i + 1][0] : 1;
    return `${colour} ${start * 100}% ${end * 100}%`;
  });
  return scaleBar(fraction, stops);
}

export const C = { blue: "var(--blue)", teal: "var(--teal)", green: "var(--green)", orange: "var(--orange)", red: "var(--red)", yellow: "var(--yellow)", purple: "var(--purple)" };

export function windDial(hour) {
  if (hour.windFromDeg == null) return "";
  return `<span class="dial"><span class="needle" style="transform:rotate(${hour.windFromDeg + 180}deg)"></span><span class="hub">${h(windNumber(hour.windSpeedMs))}</span></span>`;
}

export function sparkBars(values) {
  const top = Math.max(1, ...values);
  return `<span class="spark">${values.map((v) => `<span style="height:${Math.max(6, (v / top) * 100)}%" class="${v >= 0.1 ? "wet" : ""}"></span>`).join("")}</span>`;
}

export function levelSegments(level) {
  const colours = [C.green, C.orange, C.red];
  return `<span class="levels">${colours.map((c, i) => `<span style="height:${40 + i * 30}%;background:${i < level ? c : "var(--fill)"}"></span>`).join("")}</span>`;
}

export function cloudLayers(hour) {
  if (hour.cloudCoverHighPct == null) return "";
  const rows = [[t("H"), hour.cloudCoverHighPct], [t("M"), hour.cloudCoverMidPct], [t("L"), hour.cloudCoverLowPct]];
  return `<span class="layers">${rows.map(([name, pct]) => `<span><small>${h(name)}</small><span class="track"><span style="width:${pct ?? 0}%"></span></span></span>`).join("")}</span>`;
}

export function pressureGauge(hpa, trend) {
  // 960 hPa at the left end of the arc, 1060 hPa at the right.
  const angle = -120 + Math.min(1, Math.max(0, ((hpa ?? 1013) - 960) / 100)) * 240;
  const arrow = trend === "Rising" ? "arrow-up" : trend === "Falling" ? "arrow-up" : null;
  return `<span class="gauge"><span class="needle" style="transform:rotate(${angle}deg)"></span>
    ${arrow ? `<span class="trend ${trend === "Falling" ? "down" : ""}">${icon(arrow)}</span>` : `<span class="trend">=</span>`}</span>`;
}

/** The sun's path over the day with the sun at `at` (SunPath). */
export function sunPath(sunrise, sunset, at, width = 64, height = 32) {
  const f = Math.min(1, Math.max(0, (at - sunrise) / (sunset - sunrise)));
  const x = 4 + f * (width - 8);
  const y = height - 4 - Math.sin(f * Math.PI) * (height - 10);
  const up = at >= sunrise && at < sunset;
  return `<svg class="sunpath" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" aria-hidden="true">
    <line x1="0" y1="${height - 4}" x2="${width}" y2="${height - 4}" />
    <path d="M4 ${height - 4} Q ${width / 2} ${-height + 14} ${width - 4} ${height - 4}" />
    ${up ? `<circle cx="${x}" cy="${y}" r="4" />` : ""}</svg>`;
}


// ---- Maps ----------------------------------------------------------------------------

let leaflet = null;

/** Leaflet (in vendor/) with OpenStreetMap's tiles, loaded only when a launch point is shown. */
export function loadLeaflet() {
  leaflet ??= new Promise((resolve, reject) => {
    const css = document.createElement("link");
    css.rel = "stylesheet";
    css.href = new URL("vendor/leaflet/leaflet.css", import.meta.url).href;
    document.head.append(css);
    const script = document.createElement("script");
    script.src = new URL("vendor/leaflet/leaflet.js", import.meta.url).href;
    script.onload = () => resolve(window.L);
    script.onerror = reject;
    document.head.append(script);
  });
  return leaflet;
}

// ---- Sheets ------------------------------------------------------------------------

export function openSheet(title, body, wire) {
  document.querySelector("dialog.sheet")?.remove();
  const dialog = document.createElement("dialog");
  dialog.className = "sheet";
  dialog.innerHTML = `<header><strong>${h(title)}</strong><button class="done">${h(t("Done"))}</button></header><div class="sheet-body">${body}</div>`;
  document.body.append(dialog);
  dialog.querySelector(".done").addEventListener("click", () => dialog.close());
  dialog.addEventListener("click", (e) => e.target === dialog && dialog.close());
  dialog.addEventListener("close", () => dialog.remove());
  wire?.(dialog);
  dialog.showModal();
}

// ---- Notes every page shows --------------------------------------------------------

export const testing = () => `<p class="testing">${h(t("Test version: only for you, hidden from search engines."))}</p>`;

export const adviceOnly = () => `<p class="advice">${icon("user-round-search")}<span>${h(t("Advice only. You decide whether to go out. When in doubt, ask experienced rowers or stay ashore."))}</span></p>`;

export function footerLinks() {
  return `<footer class="links">
    <a href="/impressum/">${h(t("Legal notice"))}</a> · <a href="/privacy/">${h(t("Privacy"))}</a> · <a href="/credits/">${h(t("Data sources"))}</a>
  </footer>`;
}


// ---- Conditions (Condition in the app) --------------------------------------------

/** The tiles of Current conditions, in order (Condition.tileOrder). */
export const TILE_ORDER = ["temperature", "feelsLike", "wind", "waves", "waterTemperature", "ice", "precipitation", "thunderstorm", "visibility", "cloudCover", "humidity", "pressure", "uvIndex", "daylight"];

/** Each condition's icon key, title, unit and explanation. */
export function conditionTexts() {
  const r = (c, title, unit, text) => [c, title, unit, text];
  return {
    temperature: r("temperature", t("Air temperature"), "°C", t("Air temperature at 2 m.")),
    feelsLike: r("feelsLike", t("Feels like"), "°C", t("How warm or cold it feels on the water. Wind makes it feel colder (wind chill); humid air and sun make it feel warmer (heat index).")),
    humidity: r("humidity", t("Humidity"), "%", t("Relative humidity. The dew point is the temperature at which the air turns to mist or dew.")),
    pressure: r("pressure", t("Air pressure"), "hPa", t("Air pressure at sea level and where it goes in the next 3 hours. Falling fast often means wind and rain ahead.")),
    wind: r("wind", t("Wind and gusts"), windUnit(), t("Mean wind – strongest gust, in %@. The arrow points where the wind blows to.", windUnit())),
    waves: r("waves", t("Waves"), "m", t("Estimated wave height at the launch point, from wind and open water upwind.")),
    waterTemperature: r("waterTemperature", t("Water temperature"), "°C", t("Latest lake measurement. Below %@, extra care; below %@, cold water.", temperature(15), temperature(10))),
    precipitation: r("precipitation", t("Rain, hail, snow"), "mm", t("What falls in the hour (rain, drizzle, snow, hail) and how much, in %@. Hail comes with thunderstorms.", "mm")),
    visibility: r("visibility", t("Visibility (fog)"), "km", t("How far you can see. Fog below %@ is amber, below %@ red.", distance(1000), distance(500))),
    cloudCover: r("cloudCover", t("Cloud cover"), "%", t("Share of the sky covered by cloud.")),
    thunderstorm: r("thunderstorm", t("Thunderstorm risk"), "", t("Estimated from the forecast. DWD thunderstorm warnings for the place appear under DWD warnings.")),
    uvIndex: r("uvIndex", t("UV index"), "", t("How strong the sun's UV light is (WHO scale). From 3, protect your skin and eyes; the water reflects extra UV.")),
    ice: r("ice", t("Ice cover"), "", t("Estimated from the last weeks' frost and the water temperature, and on larger lakes checked against the Copernicus satellite ice map when clouds allow. Likely ice turns the light red, possible ice at the shore or drift ice amber. Never go onto the ice because of this app.")),
    daylight: r("daylight", t("Daylight"), "", t("Rowing is only advised while the sun is up. Hours with sunrise or sunset are amber, dark hours red.")),
  };
}

/** The ice tile's second line. */
export function iceDetail(ice) {
  if (ice.thicknessCm > 0) return t("About %@ cm, estimated", num(ice.thicknessCm));
  if (ice.basis === "season") return t("No ice this time of year");
  if (ice.basis === "measured") return t("Water %@, too warm for ice", temperature(ice.waterTemperatureC, 1));
  if (ice.basis === "model") return ice.status === "edges" ? t("Bays and harbours first") : t("Estimated from frost");
  return t("Check the lake yourself");
}
