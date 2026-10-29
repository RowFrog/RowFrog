// What every page of the web app shares: what stays in the browser, the boats,
// loading the published files, the formatting (Format in the app) and the
// small pieces such as the rowing light's dot and the sheets.

import { t, num, locale } from "./i18n.js";
import { icon, iconShape } from "./icons.js";
import {
  API, ZONE, shownLight, UNITS, unitStep, localDay, sky, SKY_TITLES, skyIcon, precipitationKind, BOATS, twilight, GROUPS, BOAT_TYPES, LIMITS, isGroup, limitsFor, applyLimits, beaufort, COLD, REASONS, lightFor, pressureChange, pressureTrend,
} from "./logic.js";
import { isOwn, loadOwnForecast } from "./ownplace.js";

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
  get wind() { return unitId("wind"); },
  set wind(unit) { save("rf.wind", unit); },
  /** "device", "h24" or "h12" (TimeFormat). */
  get timeFormat() { return TIME_FORMATS.includes(load("rf.timeFormat")) ? load("rf.timeFormat") : "device"; },
  set timeFormat(value) { save("rf.timeFormat", value); },
  /** "device", "long", "short", "dmy", "mdy" or "iso" (DateFormat). */
  get dateFormat() { return DATE_FORMATS.includes(load("rf.dateFormat")) ? load("rf.dateFormat") : "device"; },
  set dateFormat(value) { save("rf.dateFormat", value); },
  /** On mobile data, satellite pictures load only when tapped (AppSettings.saveMobileData). */
  get saveData() { return load("rf.saveData", false) === true; },
  set saveData(on) { save("rf.saveData", on); },
  /** "device", "light" or "dark". */
  get appearance() { return ["light", "dark"].includes(load("rf.appearance")) ? load("rf.appearance") : "device"; },
  set appearance(value) { save("rf.appearance", value); },
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
  if (condition === "current") return `${num(value, 1)} m/s`;
  if (store.wind === "bft") return `${beaufort(value)} Bft`;
  const v = inUnit("wind", value);
  return `${num(v, Math.abs(v - Math.round(v)) < 0.05 ? 0 : 1)} ${windUnit()}`;
}

/** The forecast for the ticked boat. */
export const forBoat = (raw) => applyLimits(raw, currentLimits());

// ---- Loading ---------------------------------------------------------------

export async function getJSON(path) {
  const response = await fetch(`${API}/${path}`, { cache: "no-cache", signal: AbortSignal.timeout?.(30000) });
  if (!response.ok) throw Object.assign(new Error(`${response.status} ${path}`), { status: response.status });
  return response.json();
}

/** Why a forecast could not be loaded: a few words and what happened, on whose side, what helps (RefreshFailure). */
export function refreshFailure(error, ownPlace = false) {
  const kind = error?.name === "TimeoutError" ? "timeout"
    : error instanceof SyntaxError ? "unreadable"
      : ownPlace ? "placeService"
        : error?.status === 404 ? "notFound"
          : error?.status ? "server"
            : error instanceof TypeError ? "offline" : "other";
  const code = String(error?.status ?? "");
  return {
    offline: [t("no internet connection"), t("Your browser could not reach the internet, or the connection dropped during the download. Check your connection, then try again.")],
    timeout: [t("the server did not answer in time"), t("The forecast server (api.rowfrog.com) did not answer in time. That is usually a slow connection or a short hiccup at the server. Try again in a minute.")],
    notFound: [t("no forecast for this club on the server"), t("The server has no forecast file for this club. A newly added club gets one with the next forecast run, every 30 minutes. Nothing to fix on your side.")],
    server: [t("server error %@", code), t("The forecast server (api.rowfrog.com) answered with error %@. That is on our side, not yours, and usually fixes itself. Try again later.", code)],
    unreadable: [t("the forecast could not be read"), t("The forecast arrived, but this version of the website could not read it. Reload the page; if that doesn't help, tell us.")],
    placeService: [t("the weather service did not answer"), t("Your own places get their forecast straight from Open-Meteo, which did not answer properly. That is on their side and usually passes quickly. Try again later.")],
    other: [t("unexpected error"), t("Loading the forecast failed in your browser for an unexpected reason (%@). The forecast shown stays. Try again; if it keeps failing, please tell us.", error?.message ?? "")],
  }[kind];
}

/** The forecast loaded earlier in this visit, if any. */
export const keptForecast = (id) => forecasts.get(id)?.forecast ?? null;

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

/**
 * The saved clubs brought up to date with the catalog, as the app looks each
 * one up by id (LocationStore.lake(of:)): a club moved to the water it rows
 * on, or renamed, shows its new water and name. True when something changed.
 */
export async function refreshSavedClubs() {
  const lakes = await loadCatalog().catch(() => null);
  if (!lakes) return false;
  const fresh = new Map();
  for (const lake of lakes) for (const club of lake.clubs) fresh.set(club.id, savedClub(club, lake));
  let changed = false;
  const clubs = store.clubs.map((club) => {
    const now = fresh.get(club.id);
    if (!now || Object.keys(now).every((k) => JSON.stringify(now[k]) === JSON.stringify(club[k]))) return club;
    changed = true;
    return { ...club, ...now };
  });
  if (changed) store.clubs = clubs;
  return changed;
}

export const forecasts = new Map();

export async function loadForecast(id, fresh = false) {
  const kept = forecasts.get(id);
  if (kept && !fresh && Date.now() - kept.at < 5 * 60 * 1000) return kept.forecast;
  const own = isOwn(id) ? store.clubs.find((c) => c.id === id) : null;
  const forecast = own ? await loadOwnForecast(own) : await getJSON(`clubs/${encodeURIComponent(id)}/forecast`);
  forecasts.set(id, { at: Date.now(), forecast });
  return forecast;
}

// ---- Units, as AppSettings in the app ----------------------------------------------

/** Where each unit is kept (rf.temperature, rf.wind, rf.waves, rf.rain, rf.distance, rf.pressure). */
const unitKey = (kind) => `rf.${kind}`;

/** The id of the unit picked for a kind of value, else the standard one. */
export function unitId(kind) {
  const id = load(unitKey(kind), UNITS[kind].standard);
  return UNITS[kind].options[id] ? id : UNITS[kind].standard;
}

export const setUnit = (kind, id) => save(unitKey(kind), id);

/** The picked unit: { label, title, from, digits }. */
export const unit = (kind) => UNITS[kind].options[unitId(kind)];

/** The unit's symbol as shown ("°C", "km/h", "NM" in English, "sm" in German). */
export const unitSymbol = (kind) => t(unit(kind).label);

/** A metric value in the picked unit, for charts and limits. */
export const inUnit = (kind, value) => (value == null ? null : unit(kind).from(value));

/** A metric change (a difference, a trend step) in the picked unit. */
export const unitChange = (kind, value) => unitStep(unit(kind), value);

export const TIME_FORMATS = ["device", "h24", "h12"];
export const DATE_FORMATS = ["device", "long", "short", "dmy", "mdy", "iso"];

/** Sets the colours: the browser's light or dark, or the one picked. */
export function applyAppearance() {
  const root = document.documentElement;
  if (store.appearance === "device") delete root.dataset.theme;
  else root.dataset.theme = store.appearance;
}

/**
 * Why the website is saving data now (DataSaver): "browser" when the browser
 * or phone asks to save data, "mobile" on mobile data with Save mobile data on,
 * else null. Only some browsers tell the website either.
 */
export function dataSaving() {
  const connection = navigator.connection;
  if (connection?.saveData) return "browser";
  if (store.saveData && connection?.type === "cellular") return "mobile";
  return null;
}

export const savingData = () => dataSaving() != null;

// ---- Formatting, as Format in the app ---------------------------------------------

export function h(text) {
  return String(text ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

/**
 * A club's name for a title on one line (ClubTitle in the app): the long name
 * with the short one in brackets where it fits, else the short name alone.
 * fitNames (app.js) picks which of the two shows.
 */
export function clubNameHtml(club, fallback = "") {
  const name = club?.name?.trim();
  const short = club?.shortName?.trim();
  if (!name || !short || name === short) return `<span class="fit-one">${h(short || name || fallback)}</span>`;
  return `<span class="fit-name"><span class="fit-long">${h(`${name} (${short})`)}</span><span class="fit-short">${h(short)}</span></span>`;
}

/** A clock time in the picked format: the browser's own, "18:05" or "6:05 PM" (TimeFormat). */
export function time(value, format = store.timeFormat) {
  if (format === "h12") return new Intl.DateTimeFormat("en-US", { timeZone: ZONE, hour: "numeric", minute: "2-digit", hour12: true }).format(new Date(value));
  if (format === "h24") return new Intl.DateTimeFormat("en-GB", { timeZone: ZONE, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(value));
  return new Intl.DateTimeFormat(navigator.language || locale(), { timeZone: ZONE, hour: "numeric", minute: "2-digit" }).format(new Date(value));
}

/** Whether times carry AM or PM, so take more room. */
export const usesAMPM = () => /[AP]M/i.test(time(Date.UTC(2026, 0, 1, 18)));

/** A day in the picked format (DateFormat), without "Today" or "Tomorrow". */
export function dateText(day, format = store.dateFormat) {
  const date = new Date(`${day}T12:00:00Z`);
  const f = (options) => new Intl.DateTimeFormat(locale(), { timeZone: "UTC", ...options }).format(date);
  const [y, m, d] = day.split("-");
  switch (format) {
    case "long": return f({ weekday: "long", day: "numeric", month: "long" });
    case "short": return f({ weekday: "short", day: "numeric", month: "short" });
    case "dmy": return `${f({ weekday: "short" })} ${d}.${m}.${y}`;
    case "mdy": return `${f({ weekday: "short" })} ${m}/${d}/${y}`;
    case "iso": return `${f({ weekday: "short" })} ${day}`;
    default: return f({ weekday: "long", day: "numeric", month: "short" });
  }
}

/** "Today", "Tomorrow" or the day in the picked format, e.g. "Tuesday, 27 Oct". */
export function dayLabel(value) {
  const day = typeof value === "string" && value.length === 10 ? value : localDay(value);
  if (day === localDay(new Date())) return t("Today");
  if (day === localDay(new Date(Date.now() + 86400000))) return t("Tomorrow");
  return dateText(day);
}

/** "Today 21:00", "Tomorrow 03:00" or "Mon 21:00". */
export function dayTime(value) {
  const day = localDay(value);
  let label;
  if (day === localDay(new Date())) label = t("Today");
  else if (day === localDay(new Date(Date.now() + 86400000))) label = t("Tomorrow");
  else label = new Intl.DateTimeFormat(locale(), { timeZone: ZONE, weekday: "short" }).format(new Date(value));
  return `${label} ${time(value)}`;
}

export function duration(from, to) {
  const minutes = Math.max(0, Math.floor((to - from) / 60000));
  return minutes >= 60 ? `${Math.floor(minutes / 60)} h ${minutes % 60} min` : `${minutes} min`;
}

export const degrees = (c, digits = 0) => (c == null ? "–" : `${num(inUnit("temperature", c), digits)}°`);
export const temperature = (c, digits = 0) => (c == null ? "–" : `${num(inUnit("temperature", c), digits)} ${unitSymbol("temperature")}`);
export const windUnit = () => unitSymbol("wind");
export const windNumber = (ms) => (ms == null ? "–" : num(Math.round(inUnit("wind", ms))));
export const wind = (ms) => (ms == null ? "–" : `${windNumber(ms)} ${windUnit()}`);
export const windRange = (ms, gust) => (ms == null ? "–" : `${windNumber(ms)}–${windNumber(gust)}`);
export const wavesNumber = (m) => (m == null ? "–" : num(inUnit("waves", m), unit("waves").digits));
export const waves = (m) => (m == null ? "–" : `${wavesNumber(m)} ${unitSymbol("waves")}`);
export const rainNumber = (mm) => (mm == null ? "–" : num(inUnit("rain", mm), unit("rain").digits));
export const rain = (mm) => (mm == null ? "–" : `${rainNumber(mm)} ${unitSymbol("rain")}`);
/** One decimal below 10, e.g. "2.4 km", "12 km". */
export function distanceNumber(m) {
  if (m == null) return "–";
  const value = inUnit("distance", m);
  return num(value, value < 10 ? 1 : 0);
}
export const distance = (m) => (m == null ? "–" : `${distanceNumber(m)} ${unitSymbol("distance")}`);
export const pressureNumber = (hpa) => (hpa == null ? "–" : num(inUnit("pressure", hpa), unit("pressure").digits));
/** "1013 hPa", "1.013 bar", "29.92 inHg". */
export const pressure = (hpa) => (hpa == null ? "–" : `${pressureNumber(hpa)} ${unitSymbol("pressure")}`);
/** A change over some hours: "2.5 hPa", "0.07 inHg". */
export const pressureChangeText = (hpa) => `${num(unitChange("pressure", hpa), unit("pressure").changeDigits)} ${unitSymbol("pressure")}`;

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
    freezing_water: t("Near-freezing water"), weather_warning: t("Weather warning"), wind: t("Wind"), gusts: t("Gusts"),
    waves: t("Waves"), fog: t("Fog"), heavy_rain: t("Heavy rain"), hail: t("Hail"), thunderstorm: t("Thunderstorm risk"),
    ice: t("Ice"), daylight: t("Sun down"), twilight: t("Sunrise / sunset"), cold_water: t("Very cold water"),
    cool_water: t("Cold-water shock possible"), shipping_stopped: t("Shipping stopped"), high_water: t("High water"),
    current: t("Strong current"), lake_lowered: t("Lake lowered"), lake_drained: t("Lake drained"),
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
    case "weather_warning": return t("An official weather warning is out for this place.");
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
    case "shipping_stopped": return t("The river is above the gauge's shipping mark: even motor ships stay in.");
    case "high_water": return t("The river is at or above mean high water: strong current, flotsam and flooded banks.");
    case "current": return t("The current is strong (from the nearest gauge).");
    case "lake_lowered": return t("The lake is let down for the winter: shallows, and a long way to the water.");
    case "lake_drained": return t("The lake is let down for the winter: too little water at the club to row.");
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
export function skySymbol(hour, cls = "", kind = sky(hour.weatherCode)) {
  const [name, colour] = skyIcon(kind, hour.sunUp === false);
  return `<span class="sky ${colour} ${cls}" title="${h(t(SKY_TITLES[kind]))}">${icon(name)}</span>`;
}

export const CONDITION_ICONS = {
  temperature: "thermometer", feelsLike: "person-standing", humidity: "droplets", pressure: "gauge", wind: "wind", waves: "waves",
  waterTemperature: "thermometer-snowflake", precipitation: "cloud-rain", visibility: "binoculars", cloudCover: "cloud",
  thunderstorm: "cloud-lightning", uvIndex: "sun", ice: "snowflake", daylight: "sunrise", warning: "triangle-alert",
  current: "circle-arrow-right", waterLevel: "arrow-down-to-line",
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

/**
 * A condition's graphic, the same on its tile and at the top of its own page
 * (the app's tile graphics). Daylight draws its sun path where it is shown; ice has none.
 */
export function conditionGraphic(condition, forecast, hour) {
  const warm = [C.blue, C.teal, C.green, C.orange, C.red];
  switch (condition) {
    case "temperature": return scaleBar(((hour.temperatureC ?? 0) + 10) / 45, warm);
    case "feelsLike": return scaleBar(((hour.apparentTemperatureC ?? 0) + 10) / 45, warm);
    case "wind": return windDial(hour);
    case "waves": {
      // The limits for the boat: amber and red zones up to a third past red.
      const limits = currentLimits();
      const [amber, red] = [limits.value("waveAmber"), limits.value("waveRed")];
      const top = (red * 4) / 3;
      return zoneBar((hour.waveHeightM ?? 0) / top, [[0, C.green], [amber / top, C.orange], [red / top, C.red]]);
    }
    case "waterTemperature": {
      const water = forecast.waterTemperature;
      // Blues for cold water: it calls for a life jacket, not a warning colour.
      return water ? zoneBar(water.celsius / 25, [[0, "var(--deep-water)"], [0.16, "var(--kit)"], [0.4, "var(--kit-light)"], [0.6, C.green]]) : "";
    }
    case "precipitation": {
      const i = Math.max(0, forecast.hours.findIndex((x) => x.time === hour.time));
      return sparkBars(forecast.hours.slice(i, i + 8).map((x) => x.precipitationMm ?? 0));
    }
    case "thunderstorm": {
      const light = lightFor(hour, REASONS.thunderstorm);
      return levelSegments(light === "red" ? 3 : light === "amber" ? 2 : 1);
    }
    case "visibility": {
      const f = Math.log10(Math.max(hour.visibilityM ?? 40000, 100) / 100) / Math.log10(400);
      return zoneBar(f, [[0, C.red], [0.27, C.orange], [0.384, C.green]]);
    }
    case "cloudCover": return cloudBig(hour);
    case "humidity":
      return `<span class="humid">${filledIcon("droplet", hour.humidityPct, 2.5, 22, "drop")}${hour.temperatureC != null && hour.dewPointC != null ? dewGap(hour.temperatureC, hour.dewPointC) : ""}</span>`;
    case "pressure": {
      const change = pressureChange(forecast.hours, hour);
      return pressureGauge(hour.pressureHpa, change == null ? null : pressureTrend(change));
    }
    case "uvIndex": return scaleBar((hour.uvIndex ?? 0) / 11, [C.green, C.yellow, C.orange, C.red, C.purple]);
    default: return "";
  }
}

/** Air temperature and dew point as two dots with the gap between them (DewGap): mist when they touch. */
export function dewGap(air, dewPoint) {
  const gap = air - dewPoint;
  // 0–8 degrees of gap across the bar.
  const offset = (Math.min(Math.max(gap, 0), 8) / 8) * 34;
  return `<span class="dewgap"><small>${num(Math.round(unitChange("temperature", gap)))}°</small>
    <span class="track"><i class="dew"></i><i class="air" style="left:${offset}px"></i></span></span>`;
}

export function cloudLayers(hour) {
  if (hour.cloudCoverHighPct == null) return "";
  const rows = [[t("H"), hour.cloudCoverHighPct], [t("M"), hour.cloudCoverMidPct], [t("L"), hour.cloudCoverLowPct]];
  return `<span class="layers">${rows.map(([name, pct]) => `<span><small>${h(name)}</small><span class="track"><span style="width:${pct ?? 0}%"></span></span></span>`).join("")}</span>`;
}

/**
 * An outlined icon filled from the bottom to `pct` (the humidity drop, the
 * cloud cover); `top` and `bottom` are where the shape starts and ends in its 24-unit box.
 */
export function filledIcon(name, pct, top, bottom, cls) {
  const shape = iconShape(name);
  const level = bottom - ((bottom - top) * Math.min(100, Math.max(0, pct ?? 0))) / 100;
  const id = `fill-${name}`;
  return `<svg class="filled ${cls}" viewBox="0 0 24 24" aria-hidden="true"><defs><clipPath id="${id}"><rect x="0" y="${level.toFixed(2)}" width="24" height="24" /></clipPath></defs>
    <g class="fill" clip-path="url(#${id})">${shape}</g><g class="outline">${shape}</g></svg>`;
}

/** The cloud filling with the cover and the three layers beside it. */
export const cloudBig = (hour) => `<span class="cloud-big">${filledIcon("cloud", hour.cloudCoverPct, 3, 19, "cloudy")}${cloudLayers(hour)}</span>`;

export function pressureGauge(hpa, trend) {
  // 960 hPa at the left end of the arc, 1060 hPa at the right.
  const angle = -120 + Math.min(1, Math.max(0, ((hpa ?? 1013) - 960) / 100)) * 240;
  const arrow = trend === "Rising" ? "arrow-up" : trend === "Falling" ? "arrow-up" : null;
  return `<span class="gauge"><span class="needle" style="transform:rotate(${angle}deg)"></span>
    ${arrow ? `<span class="trend ${trend === "Falling" ? "down" : ""}">${icon(arrow)}</span>` : `<span class="trend">=</span>`}</span>`;
}

/** The sun's path over the day with the sun at `at` (SunPath). */
/** Hours of the day (0–24) of a time on the lakes' clock. */
function clockHours(value) {
  const parts = new Intl.DateTimeFormat("en-GB", { timeZone: ZONE, hour: "numeric", minute: "numeric", hourCycle: "h23" }).formatToParts(new Date(value));
  const part = (type) => Number(parts.find((x) => x.type === type)?.value ?? 0);
  return part("hour") + part("minute") / 60;
}

let sunPaths = 0;

/**
 * The day's sun path as in the Weather app (SunPath / SunPathGraph): the
 * whole 24 hours, bright above the horizon and faint below it, with the sun
 * where it is at `at`, by day or by night.
 */
export function sunPath(sunrise, sunset, at, width = 64, height = 32) {
  const rise = clockHours(sunrise);
  const down = clockHours(sunset);
  const noon = (rise + down) / 2;
  const lineWidth = height >= 48 ? 3 : 2;
  // Sun height through the day, 0 at sunrise and sunset; noon touches the top, midnight the bottom.
  const sunHeight = (h) => Math.cos((2 * Math.PI * (h - noon)) / 24) - Math.cos((2 * Math.PI * (down - noon)) / 24);
  const top = sunHeight(noon);
  const bottom = sunHeight(noon + 12);
  const inset = lineWidth * 2 + 2;
  const y = (h) => ((top - sunHeight(h)) / (top - bottom)) * (height - 2 * inset) + inset;
  const x = (h) => (h / 24) * width;
  const points = Array.from({ length: 97 }, (_, i) => `${x(i / 4).toFixed(1)},${y(i / 4).toFixed(1)}`).join(" ");
  const horizon = y(rise);
  const now = clockHours(at);
  const r = lineWidth * 2 + 1;
  const id = `sun${++sunPaths}`;
  return `<svg class="sunpath" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" aria-hidden="true">
    <defs><clipPath id="${id}-day"><rect width="${width}" height="${horizon}" /></clipPath>
      <clipPath id="${id}-night"><rect y="${horizon}" width="${width}" height="${height - horizon}" /></clipPath></defs>
    <polyline class="day" points="${points}" clip-path="url(#${id}-day)" stroke-width="${lineWidth}" />
    <polyline class="night" points="${points}" clip-path="url(#${id}-night)" stroke-width="${Math.max(1, lineWidth - 1)}" />
    <line x1="0" y1="${horizon}" x2="${width}" y2="${horizon}" />
    <circle cx="${x(now).toFixed(1)}" cy="${y(now).toFixed(1)}" r="${r}" /></svg>`;
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
    temperature: r("temperature", t("Air temperature"), unitSymbol("temperature"), t("Air temperature at 2 m.")),
    feelsLike: r("feelsLike", t("Feels like"), unitSymbol("temperature"), t("How warm or cold it feels on the water. Wind makes it feel colder (wind chill); humid air and sun make it feel warmer (heat index).")),
    humidity: r("humidity", t("Humidity"), "%", t("Relative humidity. The dew point is the temperature at which the air turns to mist or dew.")),
    pressure: r("pressure", t("Air pressure"), unitSymbol("pressure"), t("Air pressure at sea level and where it goes in the next 3 hours. Falling fast often means wind and rain ahead.")),
    wind: r("wind", t("Wind and gusts"), windUnit(), t("Mean wind – strongest gust, in %@. The arrow points where the wind blows to.", windUnit())),
    waves: r("waves", t("Waves"), unitSymbol("waves"), t("Estimated wave height at the launch point, from wind and open water upwind.")),
    waterTemperature: r("waterTemperature", t("Water temperature"), unitSymbol("temperature"), t("Latest lake measurement. Below %@, extra care; below %@, cold water.", temperature(15), temperature(10))),
    precipitation: r("precipitation", t("Precipitation"), unitSymbol("rain"), t("What falls in the hour (rain, drizzle, snow, hail) and how much, in %@. Hail comes with thunderstorms.", unitSymbol("rain"))),
    visibility: r("visibility", t("Visibility (fog)"), unitSymbol("distance"), t("How far you can see. Fog below %@ is amber, below %@ red.", distance(1000), distance(500))),
    cloudCover: r("cloudCover", t("Cloud cover"), "%", t("Share of the sky covered by cloud.")),
    thunderstorm: r("thunderstorm", t("Thunderstorm risk"), "", t("Estimated from the forecast. Official thunderstorm warnings for the place appear under the warnings.")),
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
