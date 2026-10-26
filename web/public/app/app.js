// Row Frog in the browser, laid out like the iPhone app: a page per club with
// the rowing light on top, the DWD warnings, the current conditions tiles, the
// next 48 hours, the launch point and the satellite picture, and the list of
// clubs with search. It reads the same published files as the app
// (api.rowfrog.com/v1). No account and no cookies: the chosen clubs, units,
// boat, language and the accepted safety notice stay in this browser.

import { t, num, locale, setLanguage, savedLanguage, lang } from "./i18n.js";
import { icon } from "./icons.js";
import {
  API, ZONE, isStale, shownLight, currentHour, nextHours, windValue, WIND_UNITS, compass, searchClubs, town,
  overlayBox, localDay, sky, SKY_TITLES, skyIcon, precipitationKind, REASONS, lightFor, reasonCondition, feelsLikeNote,
  pressureChange, pressureTrend, estimatedWater, iceOff, ICE_TITLES, iceValue, sunState, BOATS, applyBoat,
} from "./logic.js";

const SAFETY_VERSION = 1;
const root = document.getElementById("root");

// ---- Stored in the browser -------------------------------------------------

function load(name, fallback) {
  try {
    const raw = localStorage.getItem(name);
    return raw == null ? fallback : JSON.parse(raw);
  } catch {
    return fallback;
  }
}

function save(name, value) {
  try {
    localStorage.setItem(name, JSON.stringify(value));
  } catch {}
}

const store = {
  get clubs() { return load("rf.clubs", []); },
  set clubs(list) { save("rf.clubs", list); },
  // m/s and small boats, as the app starts.
  get wind() { return WIND_UNITS[load("rf.wind", "ms")] ? load("rf.wind", "ms") : "ms"; },
  set wind(unit) { save("rf.wind", unit); },
  get boat() { return BOATS[load("rf.boat", "small")] ? load("rf.boat", "small") : "small"; },
  set boat(id) { save("rf.boat", id); },
  get safety() { return load("rf.safety", null); },
  set safety(value) { save("rf.safety", value); },
};

function savedClub(club, lake) {
  return {
    id: club.id, name: club.name, shortName: club.shortName, address: club.address, lakeId: lake.id, lakeName: lake.name,
    country: club.country ?? lake.country, launchPoint: club.launchPoint, launchPointVerified: club.launchPointVerified, source: club.source,
  };
}

// ---- Loading ---------------------------------------------------------------

async function getJSON(path) {
  const response = await fetch(`${API}/${path}`, { cache: "no-cache" });
  if (!response.ok) throw new Error(`${response.status} ${path}`);
  return response.json();
}

let catalog = null;

/** Every water with its clubs, in all countries the search covers. */
async function loadCatalog() {
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
async function findClub(id) {
  const lakes = await loadCatalog().catch(() => []);
  for (const lake of lakes) {
    const club = lake.clubs.find((c) => c.id === id);
    if (club) return savedClub(club, lake);
  }
  return null;
}

const forecasts = new Map();

async function loadForecast(id, fresh = false) {
  const kept = forecasts.get(id);
  if (kept && !fresh && Date.now() - kept.at < 5 * 60 * 1000) return kept.forecast;
  const forecast = await getJSON(`clubs/${encodeURIComponent(id)}/forecast`);
  forecasts.set(id, { at: Date.now(), forecast });
  return forecast;
}

// ---- Formatting, as Format in the app ---------------------------------------------

function h(text) {
  return String(text ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

function time(value) {
  return new Intl.DateTimeFormat(locale(), { timeZone: ZONE, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(value));
}

/** "Today", "Tomorrow" or "Tuesday, 27 Oct". */
function dayLabel(value) {
  const day = typeof value === "string" && value.length === 10 ? value : localDay(value);
  if (day === localDay(new Date())) return t("Today");
  if (day === localDay(new Date(Date.now() + 86400000))) return t("Tomorrow");
  return new Intl.DateTimeFormat(locale(), { timeZone: "UTC", weekday: "long", day: "numeric", month: "short" }).format(new Date(`${day}T12:00:00Z`));
}

function dayTime(value) {
  return new Intl.DateTimeFormat(locale(), { timeZone: ZONE, weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(value));
}

function duration(from, to) {
  const minutes = Math.max(0, Math.floor((to - from) / 60000));
  return minutes >= 60 ? `${Math.floor(minutes / 60)} h ${minutes % 60} min` : `${minutes} min`;
}

const degrees = (c, digits = 0) => (c == null ? "–" : `${num(c, digits)}°`);
const temperature = (c, digits = 0) => (c == null ? "–" : `${num(c, digits)} °C`);
const windUnit = () => WIND_UNITS[store.wind].label;
const windNumber = (ms) => (ms == null ? "–" : num(windValue(ms, store.wind)));
const wind = (ms) => (ms == null ? "–" : `${windNumber(ms)} ${windUnit()}`);
const windRange = (ms, gust) => (ms == null ? "–" : `${windNumber(ms)}–${windNumber(gust)}`);
const wavesNumber = (m) => (m == null ? "–" : num(m, 2));
const waves = (m) => (m == null ? "–" : `${wavesNumber(m)} m`);
const rainNumber = (mm) => (mm == null ? "–" : num(mm, 1));
const rain = (mm) => (mm == null ? "–" : `${rainNumber(mm)} mm`);
const distanceNumber = (m) => (m == null ? "–" : num(m / 1000, m < 10000 ? 1 : 0));
const distance = (m) => (m == null ? "–" : `${distanceNumber(m)} km`);

/** "Rain 3.1 mm", or null when nothing falls. */
function precipitationText(hour) {
  const kind = precipitationKind(sky(hour.weatherCode));
  if (hour.precipitationMm == null) return kind ? t(kind) : "–";
  if (hour.precipitationMm < 0.05 && !kind) return null;
  return `${t(kind ?? "Rain")} ${rain(hour.precipitationMm)}`;
}

function lightTitle(light, stale = false) {
  if (stale && light === "green") return t("Forecast out of date");
  return { green: t("Good to row"), amber: t("Row with care"), red: t("Stay ashore"), grey: t("Forecast out of date") }[light];
}

function reasonLabel(condition) {
  return {
    lake_warning: t("DWD storm warning"), lake_strong_wind: t("DWD strong-wind warning"), single_cold: t("Single in cold water"),
    freezing_water: t("Near-freezing water"), weather_warning: t("DWD weather warning"), wind: t("Wind"), gusts: t("Gusts"),
    waves: t("Waves"), fog: t("Fog"), heavy_rain: t("Heavy rain"), hail: t("Hail"), thunderstorm: t("Thunderstorm risk"),
    ice: t("Ice"), daylight: t("Sun down"), twilight: t("Sunrise / sunset"), cold_water: t("Very cold water"),
    cool_water: t("Cold-water shock possible"),
  }[condition] ?? condition;
}

function reasonExplanation(condition, light) {
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

const flag = (code) => String.fromCodePoint(...[...(code ?? "de").toUpperCase()].map((c) => 0x1f1a5 + c.charCodeAt(0)));

function setTitle(text) {
  document.title = text ? `${text} · Row Frog` : "Row Frog";
}

// ---- Small pieces, as in the app ---------------------------------------------------

/** The rowing light as a dot; green turns grey on an old forecast. */
function dot(light, size = 14, stale = false) {
  return `<span class="dot ${h(shownLight(light, stale))}" style="--s:${size}px" aria-hidden="true"></span>`;
}

/** The weather symbol for an hour, coloured like the app's multicolour symbols. */
function skySymbol(hour, cls = "") {
  const [name, colour] = skyIcon(sky(hour.weatherCode), hour.sunUp === false);
  return `<span class="sky ${colour} ${cls}" title="${h(t(SKY_TITLES[sky(hour.weatherCode)]))}">${icon(name)}</span>`;
}

const CONDITION_ICONS = {
  temperature: "thermometer", feelsLike: "person-standing", humidity: "droplets", pressure: "gauge", wind: "wind", waves: "waves",
  waterTemperature: "thermometer-snowflake", precipitation: "cloud-rain", visibility: "binoculars", cloudCover: "cloud",
  thunderstorm: "cloud-lightning", uvIndex: "sun", ice: "snowflake", daylight: "sunrise", warning: "triangle-alert",
};

function conditionIcon(condition) {
  return `<span class="cond ${condition}">${icon(CONDITION_ICONS[condition] ?? "info")}</span>`;
}

/** A card with an uppercase caption and an icon, like Card in the app. */
function card(title, iconName, body, { legend = null, id = "", cls = "" } = {}) {
  return `<section class="card ${cls}" ${id ? `id="${id}"` : ""}>
    <header class="card-title">${icon(iconName)}<span>${h(title)}</span>
      ${legend ? `<button class="info" data-legend="${legend}" aria-label="${h(t("What the symbols mean"))}">${icon("info")}</button>` : ""}</header>
    ${body}</section>`;
}

/** A coloured bar with a dot where the value sits (ScaleBar). */
function scaleBar(fraction, colours) {
  const f = Math.min(1, Math.max(0, fraction ?? 0));
  return `<span class="scale" style="--bar:linear-gradient(90deg, ${colours.join(", ")})"><span class="knob" style="left:${f * 100}%"></span></span>`;
}

/** Colour zones from a list of [start, colour] (ScaleBar with zones). */
function zoneBar(fraction, zones) {
  const stops = zones.map(([start, colour], i) => {
    const end = i + 1 < zones.length ? zones[i + 1][0] : 1;
    return `${colour} ${start * 100}% ${end * 100}%`;
  });
  return scaleBar(fraction, stops);
}

const C = { blue: "var(--blue)", teal: "var(--teal)", green: "var(--green)", orange: "var(--orange)", red: "var(--red)", yellow: "var(--yellow)", purple: "var(--purple)" };

function windDial(hour) {
  if (hour.windFromDeg == null) return "";
  return `<span class="dial"><span class="needle" style="transform:rotate(${hour.windFromDeg + 180}deg)"></span><span class="hub">${h(windNumber(hour.windSpeedMs))}</span></span>`;
}

function sparkBars(values) {
  const top = Math.max(1, ...values);
  return `<span class="spark">${values.map((v) => `<span style="height:${Math.max(6, (v / top) * 100)}%" class="${v >= 0.1 ? "wet" : ""}"></span>`).join("")}</span>`;
}

function levelSegments(level) {
  const colours = [C.green, C.orange, C.red];
  return `<span class="levels">${colours.map((c, i) => `<span style="height:${40 + i * 30}%;background:${i < level ? c : "var(--fill)"}"></span>`).join("")}</span>`;
}

function cloudLayers(hour) {
  if (hour.cloudCoverHighPct == null) return "";
  const rows = [[t("H"), hour.cloudCoverHighPct], [t("M"), hour.cloudCoverMidPct], [t("L"), hour.cloudCoverLowPct]];
  return `<span class="layers">${rows.map(([name, pct]) => `<span><small>${h(name)}</small><span class="track"><span style="width:${pct ?? 0}%"></span></span></span>`).join("")}</span>`;
}

function pressureGauge(hpa, trend) {
  // 960 hPa at the left end of the arc, 1060 hPa at the right.
  const angle = -120 + Math.min(1, Math.max(0, ((hpa ?? 1013) - 960) / 100)) * 240;
  const arrow = trend === "Rising" ? "arrow-up" : trend === "Falling" ? "arrow-up" : null;
  return `<span class="gauge"><span class="needle" style="transform:rotate(${angle}deg)"></span>
    ${arrow ? `<span class="trend ${trend === "Falling" ? "down" : ""}">${icon(arrow)}</span>` : `<span class="trend">=</span>`}</span>`;
}

/** The sun's path over the day with the sun at `at` (SunPath). */
function sunPath(sunrise, sunset, at, width = 64, height = 32) {
  const f = Math.min(1, Math.max(0, (at - sunrise) / (sunset - sunrise)));
  const x = 4 + f * (width - 8);
  const y = height - 4 - Math.sin(f * Math.PI) * (height - 10);
  const up = at >= sunrise && at < sunset;
  return `<svg class="sunpath" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" aria-hidden="true">
    <line x1="0" y1="${height - 4}" x2="${width}" y2="${height - 4}" />
    <path d="M4 ${height - 4} Q ${width / 2} ${-height + 14} ${width - 4} ${height - 4}" />
    ${up ? `<circle cx="${x}" cy="${y}" r="4" />` : ""}</svg>`;
}

// ---- Safety notice -----------------------------------------------------------

function safetyPoints() {
  return [
    [t("Row Frog gives information and advice, not decisions."), t("Forecasts, rowing lights, limits and maps are calculated from weather models and measurements by third parties. They can be wrong, late or missing, and conditions on the water can change faster than any forecast.")],
    [t("Green does not mean safe, and red does not cover every danger."), t("The app does not know your skills, your fitness, your boat and equipment, or what you see on the water.")],
    [t("You decide."), t("Whether you go out and when you turn back is always your own decision, and that of your crew, cox or coach, whatever the app shows.")],
    [t("When in doubt, ask or stay ashore."), t("Ask experienced rowers, your coach or your club's boat warden, or stay ashore.")],
    [t("Under 18?"), t("Decide together with your coach or your parents, and follow your club's rules for young rowers.")],
    [t("Always follow the rules."), t("Your club's rowing rules, local regulations, official warnings such as storm warning lights, and instructions from authorities and the water police come first.")],
    [t("Use at your own risk."), t("To the extent permitted by law, we accept no liability for decisions made on the basis of the app's data and advice.")],
  ];
}

function safetyList() {
  return `<ol class="safety">${safetyPoints().map(([title, text]) => `<li><strong>${h(title)}</strong><p>${h(text)}</p></li>`).join("")}</ol>`;
}

function renderSafetyGate() {
  setTitle(t("Before you row"));
  const changed = store.safety && store.safety.version < SAFETY_VERSION;
  root.innerHTML = `
    <main class="page">
      <h1 class="large">${h(t("Before you row"))}</h1>
      <section class="card">${languagePicker()}</section>
      ${changed ? `<p class="banner amber">${h(t("This notice has changed. Please read it again."))}</p>` : ""}
      <section class="card">${safetyList()}</section>
      <div id="end"></div>
      <label class="tick"><input type="checkbox" id="agree" disabled>
        <span>${h(t("I have read this and understand that Row Frog only gives advice. I alone decide whether and when I go on the water."))}</span></label>
      <p class="hint" id="scroll-hint">${h(t("Scroll to the end to continue."))}</p>
      <button class="primary" id="continue" disabled>${h(t("Agree and continue"))}</button>
    </main>`;
  wireLanguage(renderSafetyGate);
  const agree = root.querySelector("#agree");
  const button = root.querySelector("#continue");
  new IntersectionObserver((entries, observer) => {
    if (entries.some((e) => e.isIntersecting)) {
      agree.disabled = false;
      root.querySelector("#scroll-hint").hidden = true;
      observer.disconnect();
    }
  }).observe(root.querySelector("#end"));
  agree.addEventListener("change", () => (button.disabled = !agree.checked));
  button.addEventListener("click", () => {
    store.safety = { version: SAFETY_VERSION, at: new Date().toISOString() };
    route();
  });
}

function languagePicker() {
  const choice = savedLanguage();
  const option = (value, label) => `<option value="${value}" ${choice === value ? "selected" : ""}>${h(label)}</option>`;
  return `<label class="row-setting"><span>${icon("languages")} ${h(t("Language"))}</span>
    <select id="language">${option("auto", t("Device"))}${option("en", "English")}${option("de", "Deutsch")}</select></label>`;
}

function wireLanguage(again) {
  root.querySelector("#language")?.addEventListener("change", async (e) => {
    await setLanguage(e.target.value);
    again();
  });
}

const testing = () => `<p class="testing">${h(t("Test version: only for you, hidden from search engines."))}</p>`;

// ---- Dialogs (the app's sheets) -------------------------------------------------------

function openSheet(title, body, wire) {
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

function legendBody(part) {
  if (part === "lights") {
    return `<ul class="legend">${["green", "amber", "red"].map((l) => `<li>${dot(l, 18)}<span>${h(lightTitle(l))}</span></li>`).join("")}
      <li>${dot("green", 18, true)}<span>${h(t("Forecast out of date: more than 3 hours old. Amber and red still show."))}</span></li></ul>
      ${adviceOnly()}`;
  }
  const symbols = `<h3>${h(t("Weather symbols"))}</h3><ul class="legend grid">${Object.keys(SKY_TITLES).map((k) => {
    const [name, colour] = skyIcon(k);
    return `<li><span class="sky ${colour}">${icon(name)}</span><span>${h(t(SKY_TITLES[k]))}</span></li>`;
  }).join("")}</ul><p class="sub">${h(t("At night the sun becomes a moon and the row is dimmed."))}</p>`;
  const explain = (list) => `<ul class="legend">${list.map(([c, title, unit, text]) => `<li>${conditionIcon(c)}<span><strong>${h(unit ? `${title} (${unit})` : title)}</strong><small>${h(text)}</small></span></li>`).join("")}</ul>`;
  const rows = conditionTexts();
  if (part === "hourly") {
    return `<ul class="legend">
      <li><span class="cond">${icon("clock")}</span><span>${h(t("Time; the hour starts here."))}</span></li>
      <li>${dot("green", 12)}<span>${h(t("Rowing light for your boat in that hour."))}</span></li>
      <li><span class="cond">${icon("cloud-sun")}</span><span>${h(t("Weather symbol; it also shows how cloudy it is."))}</span></li></ul>
      ${explain(["temperature", "feelsLike", "wind", "waves", "precipitation", "visibility"].map((c) => rows[c]))}
      <p class="sub">${h(t("Hours after sunset are dimmed. Tap an hour to see all its values."))}</p>`;
  }
  return symbols + explain(TILE_ORDER.map((c) => rows[c]));
}

function conditionTexts() {
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

const adviceOnly = () => `<p class="advice">${icon("user-round-search")}<span>${h(t("Advice only. You decide whether to go out. When in doubt, ask experienced rowers or stay ashore."))}</span></p>`;

/** Picks the boat for the rowing light, with the light each boat gets now (BoatMenu). */
function openBoatMenu(raw) {
  const now = raw ? new Date() : null;
  const body = `<ul class="boats">${Object.entries(BOATS).map(([id, boat]) => {
    const light = raw ? currentHour(applyBoat(raw, id).hours, now).light : null;
    return `<li><button data-boat="${id}" class="${store.boat === id ? "on" : ""}">
      ${light ? dot(light, 16, isStale(raw)) : icon("sailboat")}
      <span><strong>${h(t(boat.title))}</strong><small>${h(t(boat.detail))}</small></span>
      ${store.boat === id ? icon("check") : ""}</button></li>`;
  }).join("")}</ul><p class="sub">${h(t("Picks another boat for the rowing light."))}</p>`;
  openSheet(t("Boat"), body, (dialog) => {
    dialog.querySelectorAll("[data-boat]").forEach((b) => b.addEventListener("click", () => {
      store.boat = b.dataset.boat;
      dialog.close();
      route(false);
    }));
  });
}

// ---- Bottom bar ----------------------------------------------------------------------------

/** Settings and boat on the left, a dot per club page, the list on the right (RootView). */
function bottomBar(currentId, raw) {
  const clubs = store.clubs;
  return `<nav class="bottom">
    <a href="#/settings" class="tool" aria-label="${h(t("Settings"))}">${icon("settings")}</a>
    <button class="tool boat" id="boat-button" aria-label="${h(t("For %@", t(BOATS[store.boat].inSentence)))}">${icon("sailboat")}<small>${h(store.boat === "big" ? t("Big") : t("Small"))}</small></button>
    <span class="dots">${clubs.map((c, i) => `<a href="#/club/${encodeURIComponent(c.id)}" class="${c.id === currentId ? "on" : ""}" aria-label="${h(c.shortName || c.name)}">${i === 0 ? icon("house") : "<span></span>"}</a>`).join("")}</span>
    <a href="#/list" class="tool" aria-label="${h(t("Locations"))}">${icon("list")}</a>
  </nav>`;
}

function wireBottomBar(raw) {
  root.querySelector("#boat-button")?.addEventListener("click", () => openBoatMenu(raw));
}

// ---- List and search (LocationListView) -----------------------------------------------------

let editing = false;

async function renderList() {
  setTitle(t("Locations"));
  const clubs = store.clubs;
  root.innerHTML = `
    <header class="nav">
      <a href="#/settings" class="tool" aria-label="${h(t("Settings"))}">${icon("settings")}</a>
      ${clubs.length ? `<button class="link" id="edit">${h(editing ? t("Done") : t("Edit"))}</button>` : ""}
      <span class="spacer"></span>
      ${clubs.length ? `<a class="link strong" href="#/club/${encodeURIComponent(clubs[0].id)}">${h(t("Done"))}</a>` : ""}
    </header>
    ${testing()}
    <main class="page">
      <h1 class="large">${h(t("Locations"))}</h1>
      <label class="search">${icon("search")}
        <input id="query" type="search" autocomplete="off" placeholder="${h(t("Search clubs, lakes or towns"))}" aria-label="${h(t("Search clubs, lakes or towns"))}"></label>
      <ul id="results" class="results" hidden></ul>
      <div id="saved">
        ${clubs.length ? "" : `<p class="empty">${h(t("Pick your home club first, then any others you row at."))}</p>`}
        <ul class="rows">${clubs.map((c, i) => `
          <li class="${editing ? "editing" : ""}">
            ${editing ? `<button class="round red" data-remove="${h(c.id)}" aria-label="${h(t("Remove"))}">${icon("trash-2")}</button>` : ""}
            <a class="row" href="#/club/${encodeURIComponent(c.id)}" data-id="${h(c.id)}">${rowSkeleton(c, i === 0)}</a>
            ${editing && i > 0 ? `<button class="round" data-home="${h(c.id)}" aria-label="${h(t("Home base"))}">${icon("house")}</button>` : ""}
          </li>`).join("")}</ul>
        <p class="footnote" id="updated"></p>
      </div>
      ${footerLinks()}
    </main>`;
  root.querySelector("#edit")?.addEventListener("click", () => {
    editing = !editing;
    renderList();
  });
  root.querySelectorAll("[data-remove]").forEach((b) => b.addEventListener("click", () => {
    store.clubs = store.clubs.filter((c) => c.id !== b.dataset.remove);
    renderList();
  }));
  root.querySelectorAll("[data-home]").forEach((b) => b.addEventListener("click", () => {
    const list = store.clubs;
    store.clubs = [list.find((c) => c.id === b.dataset.home), ...list.filter((c) => c.id !== b.dataset.home)];
    renderList();
  }));
  wireSearch();
  const updated = [];
  await Promise.all([...root.querySelectorAll(".row")].map(async (row) => {
    const at = await fillRow(row);
    if (at) updated.push(at);
  }));
  if (updated.length) {
    root.querySelector("#updated").textContent = t("Updated %@", time(Math.min(...updated.map((d) => new Date(d)))));
  }
}

function rowSkeleton(club, isHome) {
  return `<div class="row-top">
      <div class="row-name">
        <strong>${isHome ? icon("house") : ""}${h(club.shortName || club.name)}</strong>
        <small>${h([club.lakeName, town(club.address)].filter(Boolean).join(" · "))}</small>
      </div>
      <div class="row-now"><span class="spinner"></span></div>
    </div>
    <div class="row-bottom"></div>`;
}

async function fillRow(row) {
  let raw;
  try {
    raw = await loadForecast(row.dataset.id);
  } catch {
    row.querySelector(".row-now").innerHTML = `<span class="sub">${h(t("No forecast"))}</span>`;
    return null;
  }
  const forecast = applyBoat(raw, store.boat);
  const stale = isStale(forecast);
  const hour = currentHour(forecast.hours);
  const water = forecast.waterTemperature?.celsius;
  const estimate = estimatedWater(forecast);
  row.style.setProperty("--tint", `var(--${shownLight(hour.light, stale)})`);
  row.classList.add("tinted");
  row.querySelector(".row-now").innerHTML = `<div class="now-line">${dot(hour.light, 18, stale)}${skySymbol(hour)}${conditionIcon("temperature")}<span class="big-temp">${h(degrees(hour.temperatureC))}</span></div>
    ${hour.apparentTemperatureC != null ? `<small class="sub">${icon("person-standing")} ${h(t("Feels like %@", degrees(hour.apparentTemperatureC)))}</small>` : ""}`;
  const warning = forecast.warnings?.items?.[0];
  const sun = sunState(forecast);
  const ice = forecast.ice;
  const iceText = iceOff(ice) ? t("Off season") : ice && ice.status !== "unavailable" ? t(ICE_TITLES[ice.status] ?? "No data") : "–";
  row.querySelector(".row-bottom").innerHTML = `
    <div class="row-why">
      <strong>${h(lightTitle(hour.light, stale))}</strong>
      ${stale ? `<small class="orange">${icon("clock")} ${h(t("As of %@", dayTime(forecast.generatedAt)))}</small>` : ""}
      <small class="why">${h(hour.reasons.length ? t("Why: %@", hour.reasons.map((r) => reasonLabel(r.condition)).join(", ")) : t("All conditions within the limits"))}</small>
      ${warning ? `<small class="warn ${warning.severity === "minor" ? "orange" : "red"}">${icon("triangle-alert")} ${h(shortWarning(warning))}</small>` : ""}
      ${sun ? `<small class="sub">${icon(sun.up ? "sunset" : "sunrise")} ${h(sun.up ? t("Sunset %@", time(sun.sunset)) : t("Sunrise %@", time(sun.sunrise)))}</small>` : ""}
    </div>
    <div class="metrics">
      <span class="${water == null && estimate != null ? "sub" : ""}">${conditionIcon("waterTemperature")}${h(water == null && estimate != null ? `≈ ${degrees(estimate, 1)}` : degrees(water, 1))}</span>
      <span>${conditionIcon("visibility")}${h(distance(hour.visibilityM))}</span>
      <span>${conditionIcon("wind")}${h(`${windRange(hour.windSpeedMs, hour.windGustMs)} ${windUnit()}`)}</span>
      <span>${conditionIcon("precipitation")}${h(precipitationText(hour) ?? t("Dry"))}</span>
      <span>${conditionIcon("waves")}${h(waves(hour.waveHeightM))}</span>
      <span class="${iceOff(ice) || iceText === "–" ? "sub" : ""}">${conditionIcon("ice")}${h(iceText)}</span>
    </div>`;
  return forecast.generatedAt;
}

function shortWarning(w) {
  if (w.kind === "lake") return t("DWD lake warning");
  const event = lang() === "en" && w.english ? w.english.event : w.event;
  return t("DWD warning: %@", event ? event[0].toUpperCase() + event.slice(1).toLowerCase() : "");
}

function wireSearch() {
  const input = root.querySelector("#query");
  const results = root.querySelector("#results");
  const saved = root.querySelector("#saved");
  let lakes = null;
  input.addEventListener("focus", async () => {
    try {
      lakes = await loadCatalog();
    } catch {
      results.hidden = false;
      results.innerHTML = `<li class="hint">${h(t("Could not load the club list."))}</li>`;
    }
  }, { once: true });
  input.addEventListener("input", async () => {
    lakes ??= await loadCatalog().catch(() => null);
    if (!lakes) return;
    const searching = input.value.trim() !== "";
    results.hidden = !searching;
    saved.hidden = searching;
    const found = searchClubs(lakes, input.value);
    const ids = new Set(store.clubs.map((c) => c.id));
    results.innerHTML = found.map(({ club, lake }) => `
      <li><button class="result" data-club="${h(club.id)}" data-lake="${h(lake.id)}">
        <span class="flag">${flag(club.country ?? lake.country)}</span>
        <span class="result-text"><strong>${h(club.name)}</strong>
        <small>${h([lake.name, town(club.address)].filter(Boolean).join(" · "))}</small>
        ${club.launchPointVerified ? "" : `<small class="orange">${h(t("Launch point not yet confirmed"))}</small>`}</span>
        <span class="add ${ids.has(club.id) ? "in" : ""}">${icon(ids.has(club.id) ? "circle-check" : "plus")}</span>
      </button></li>`).join("") || (searching ? `<li class="hint">${h(t("No clubs found."))}</li>` : "");
  });
  results.addEventListener("click", (e) => {
    const button = e.target.closest(".result");
    if (!button) return;
    const lake = lakes.find((l) => l.id === button.dataset.lake);
    const club = lake.clubs.find((c) => c.id === button.dataset.club);
    const list = store.clubs;
    if (!list.some((c) => c.id === club.id)) store.clubs = [...list, savedClub(club, lake)];
    location.hash = `#/club/${encodeURIComponent(club.id)}`;
  });
}

// ---- Club page (LocationPageView) ------------------------------------------------------------

const TILE_ORDER = ["temperature", "feelsLike", "wind", "waves", "waterTemperature", "ice", "precipitation", "thunderstorm", "visibility", "cloudCover", "humidity", "pressure", "uvIndex", "daylight"];

async function renderClub(id) {
  let club = store.clubs.find((c) => c.id === id);
  if (!club?.launchPoint) club = (await findClub(id)) ?? club;
  const saved = store.clubs.some((c) => c.id === id);
  const name = club ? club.shortName || club.name : id;
  setTitle(name);
  const isHome = store.clubs[0]?.id === id;
  root.innerHTML = `${testing()}<main class="page club">
      ${clubHeader(club, name, isHome, null)}
      <section class="card loading"><p>${h(t("Loading the forecast…"))}</p></section>
    </main>${bottomBar(id, null)}`;
  wireBottomBar(null);
  wireSwipe(id);
  let raw;
  try {
    raw = await loadForecast(id, true);
  } catch {
    root.querySelector(".loading").innerHTML = `<p><strong>${icon("wifi-off")} ${h(t("No forecast"))}</strong></p><button class="primary" id="retry">${h(t("Try again"))}</button>`;
    root.querySelector("#retry").addEventListener("click", () => renderClub(id));
    return;
  }
  const forecast = applyBoat(raw, store.boat);
  const now = new Date();
  const stale = isStale(forecast, now);
  const hour = currentHour(forecast.hours, now);
  const warnings = forecast.warnings;
  const showWarnings = warnings && (warnings.status !== "ok" || warnings.items?.length);
  root.querySelector("main").innerHTML = `
    ${clubHeader(club, name, isHome, forecast, stale)}
    ${saved ? "" : `<button class="primary wide" id="add">${icon("plus")} ${h(t("Add to my clubs"))}</button>`}
    ${nowCard(forecast, hour, { stale, club })}
    ${showWarnings ? warningsCard(warnings, club, forecast.generatedAt) : ""}
    ${conditionsCard(forecast, hour)}
    ${hourlyCard(forecast, now, stale)}
    ${club?.launchPoint ? launchPointCard(club) : ""}
    <section class="card" id="satellite" hidden></section>
    ${sourceLine(forecast)}
    ${credits(forecast, club)}
    ${footerLinks()}`;
  root.querySelector("nav.bottom").outerHTML = bottomBar(id, raw);
  wireBottomBar(raw);
  wireClubPage(id, club, raw, forecast, hour);
  if (club?.launchPoint) showLaunchMap(club);
  satelliteCard(forecast.lakeId);
}

function clubHeader(club, name, isHome, forecast, stale = false) {
  const slow = forecast?.refresh && forecast.refresh.used === false;
  return `<header class="club-head">
    ${isHome ? `<p class="home">${icon("house")} ${h(t("Home base"))}</p>` : ""}
    <h1>${h(name)}</h1>
    <p class="sub">${h([club?.lakeName, town(club?.address)].filter(Boolean).join(" · "))}</p>
    ${club && club.launchPointVerified === false ? `<p class="orange small">${icon("map-pin-off")} ${h(t("Launch point not yet confirmed"))}</p>` : ""}
    ${forecast ? (stale
      ? `<p class="orange small">${icon("clock")} ${h(t("Forecast out of date: from %@. Check the conditions yourself.", dayTime(forecast.generatedAt)))}</p>`
      : `<p class="sub small">${h(t("Updated %@", time(forecast.generatedAt)))} · <button class="link" id="refresh">${h(t("Refresh"))}</button></p>`) : ""}
    ${slow ? `<p class="sub small">${icon("hourglass")} ${h(t("Nobody opened this club lately, so it updates less often. From the next server update, within about 30 minutes, it updates every half hour."))}</p>` : ""}
  </header>`;
}

function wireClubPage(id, club, raw, forecast, hour) {
  root.querySelector("#refresh")?.addEventListener("click", () => renderClub(id));
  root.querySelector("#add")?.addEventListener("click", () => {
    store.clubs = [...store.clubs, club];
    renderClub(id);
  });
  root.querySelectorAll("[data-legend]").forEach((b) => b.addEventListener("click", () => {
    const part = b.dataset.legend;
    openSheet({ lights: t("Rowing light"), conditions: t("Weather symbols"), hourly: t("The columns") }[part], legendBody(part));
  }));
  root.querySelector("#boat-line")?.addEventListener("click", () => openBoatMenu(raw));
  root.querySelector("#no-warning")?.addEventListener("click", () => {
    openSheet(t("DWD warnings"), warningsBody(forecast.warnings, club, forecast.generatedAt, true));
  });
  root.querySelectorAll("[data-tile]").forEach((b) => b.addEventListener("click", () => {
    const [c, title, unit, text] = conditionTexts()[b.dataset.tile];
    openSheet(title, `<p>${conditionIcon(c)} ${h(text)}</p>${unit ? `<p class="sub">${h(unit)}</p>` : ""}`);
  }));
  root.querySelectorAll("[data-hour]").forEach((b) => b.addEventListener("click", () => {
    const at = forecast.hours.find((x) => x.time === b.dataset.hour);
    openSheet(dayTime(at.time), nowCard(forecast, at, { at: new Date(at.time), stale: isStale(forecast) }) + conditionsCard(forecast, at));
  }));
}

/** Left and right swipes, and the arrow keys, move between the club pages like the app's paging. */
let swipeOff = null;
function wireSwipe(id) {
  swipeOff?.();
  const ids = store.clubs.map((c) => c.id);
  const i = ids.indexOf(id);
  if (i < 0 || ids.length < 2) return;
  const go = (step) => {
    const next = ids[i + step];
    if (next) location.hash = `#/club/${encodeURIComponent(next)}`;
  };
  let start = null;
  const down = (e) => (start = e.touches?.[0] ? [e.touches[0].clientX, e.touches[0].clientY] : null);
  const up = (e) => {
    if (!start || !e.changedTouches?.[0]) return;
    const dx = e.changedTouches[0].clientX - start[0];
    const dy = e.changedTouches[0].clientY - start[1];
    if (Math.abs(dx) > 70 && Math.abs(dx) > 2 * Math.abs(dy) && !e.target.closest(".hourly, .map")) go(dx < 0 ? 1 : -1);
    start = null;
  };
  const key = (e) => {
    if (document.querySelector("dialog[open]") || e.target.closest?.("input, select")) return;
    if (e.key === "ArrowRight") go(1);
    if (e.key === "ArrowLeft") go(-1);
  };
  document.addEventListener("touchstart", down, { passive: true });
  document.addEventListener("touchend", up);
  document.addEventListener("keydown", key);
  swipeOff = () => {
    document.removeEventListener("touchstart", down);
    document.removeEventListener("touchend", up);
    document.removeEventListener("keydown", key);
    swipeOff = null;
  };
}

/** The top tile: the rowing light, why, the main values and the daylight (NowCard). */
function nowCard(forecast, hour, { stale = false, at = null } = {}) {
  const water = forecast.waterTemperature;
  const estimate = estimatedWater(forecast);
  const kind = sky(hour.weatherCode);
  const boat = t("For %@", t(BOATS[store.boat].inSentence));
  const reasons = hour.reasons ?? [];
  const ice = iceValue(forecast);
  const warnings = forecast.warnings;
  const sun = sunState(forecast, at ?? new Date());
  const waterReasons = REASONS.waterTemperature;
  return `<section class="card now">
    <div class="now-head">
      ${dot(hour.light, 36, stale)}
      <div class="now-title">
        <h2>${h(lightTitle(hour.light, stale))} ${at ? "" : `<button class="info" data-legend="lights" aria-label="${h(t("What the symbols mean"))}">${icon("info")}</button>`}</h2>
        ${at ? `<small class="sub">${h(boat)}</small>` : `<button class="boat-line" id="boat-line">${h(boat)} ${icon("chevrons-up-down")}</button>`}
      </div>
      <div class="now-sky">${skySymbol(hour, "large")}<small class="sub">${h(t(SKY_TITLES[kind]))}</small></div>
    </div>
    <ul class="reasons">
      ${stale && !at ? `<li class="orange">${icon("clock")}<span>${h(t("The forecast is more than 3 hours old. Check the conditions yourself before you go out."))}</span></li>` : ""}
      ${reasons.length ? reasons.map((r) => {
        const text = water == null && waterReasons.includes(r.condition) ? t("Estimated: %@", reasonExplanation(r.condition, r.light)) : reasonExplanation(r.condition, r.light);
        return `<li class="${r.light === "red" ? "red" : "orange"}">${icon(CONDITION_ICONS[reasonCondition(r.condition)])}<span>${h(text)}</span></li>`;
      }).join("") : `<li>${icon("circle-check")}<span>${h(t("All conditions are within the limits."))}</span></li>`}
      ${!at && warnings?.status === "ok" && !warnings.items?.length ? `<li><button class="no-warning" id="no-warning"><span class="green">${icon("shield-check")} ${h(t("No DWD warning"))}</span>
        <span class="sub">· ${h(t("checked %@", time(forecast.generatedAt)))}</span> <span class="tint">${icon("info")}</span></button></li>` : ""}
    </ul>
    ${adviceOnly()}
    <hr>
    <div class="now-values">
      <div class="air">
        <small class="label">${conditionIcon("temperature")} ${h(t("Air"))}</small>
        <span class="v44">${h(degrees(hour.temperatureC))}</span>
        ${hour.apparentTemperatureC != null ? `<small class="sub">${icon("person-standing")} ${h(t("Feels like %@", degrees(hour.apparentTemperatureC)))}</small>` : ""}
      </div>
      <div class="${water == null && estimate != null ? "secondary" : ""}">
        <small class="label">${conditionIcon("waterTemperature")} ${h(t("Water"))}</small>
        <span class="v28">${h(water == null && estimate != null ? degrees(estimate) : degrees(water?.celsius, 1))}</span>
        <small class="sub">${h(water ? t("Measured %@", time(water.measuredAt)) : estimate != null ? t("Estimated") : " ")}</small>
      </div>
      <div>
        <small class="label">${conditionIcon("wind")} ${h(t("Wind"))}</small>
        <span class="v28">${h(windRange(hour.windSpeedMs, hour.windGustMs))}${hour.windFromDeg != null ? `<span class="arrow" style="transform:rotate(${hour.windFromDeg + 180}deg)">${icon("arrow-up")}</span>` : ""}</span>
        <small class="sub">${h(windUnit() + (hour.windFromDeg != null ? ` · ${t("from %@", compass(hour.windFromDeg))}` : ""))}</small>
      </div>
    </div>
    <div class="now-metrics">
      <div><small class="label">${conditionIcon("waves")} ${h(t("Waves"))}</small><span>${h(waves(hour.waveHeightM))}</span></div>
      <div><small class="label">${conditionIcon("precipitation")} ${h(t("Rain, hail"))}</small><span>${h(precipitationText(hour) ?? t("None"))}</span></div>
      <div><small class="label">${conditionIcon("visibility")} ${h(t("Visibility"))}</small><span>${h(distance(hour.visibilityM))}</span></div>
      ${ice ? `<div><small class="label">${conditionIcon("ice")} ${h(t("Ice"))}</small><span>${h(t(ice))}</span></div>` : ""}
    </div>
    ${sun ? `<p class="daylight">${sun.up
      ? `${sunPath(sun.sunrise, sun.sunset, at ?? new Date(), 44, 22)}<span>${h(t("Sunset %@ · %@ of daylight left", time(sun.sunset), duration(at ?? new Date(), sun.sunset)))}</span>`
      : `<span class="moon">${icon("moon-star")}</span><span>${h(t("Sun is down · rowing advised again from %@", time(sun.sunrise)))}</span>`}</p>` : ""}
  </section>`;
}

/** The DWD warnings card, shown while a warning is out or DWD could not be checked (WarningsCard). */
function warningsCard(warnings, club, checkedAt) {
  return card(t("DWD warnings"), "triangle-alert", warningsBody(warnings, club, checkedAt, false), { cls: "warnings" });
}

function warningsBody(warnings, club, checkedAt, guideOpen) {
  if (warnings.status !== "ok") {
    return `<p class="orange">${icon("wifi-off")} ${h(t("Warnings could not be loaded. Check dwd.de or the shore lights before going out."))}</p>`;
  }
  const place = town(club?.address);
  const placeText = place ? t("weather warnings for %@", place) : t("weather warnings for this place");
  const coverage = warnings.lakeArea
    ? t("Covers the DWD lake warning for %@ and %@.", warnings.lakeArea, placeText)
    : t("DWD has no lake warning service %@. Covers %@.", club?.lakeName ? t("for %@", club.lakeName) : t("for this water"), placeText);
  const items = warnings.items ?? [];
  const guide = warnings.lakeArea ? shoreLights(guideOpen) : "";
  if (!items.length) {
    return `<p class="green strong">${icon("shield-check")} ${h(t("No warning right now"))}</p>
      <p class="sub small">${h(`${coverage} ${t("Checked %@.", time(checkedAt))}`)}</p>${guide}`;
  }
  const lake = items.filter((w) => w.kind === "lake");
  const other = items.filter((w) => w.kind !== "lake");
  return `${lake.map(warningRow).join("")}${guide}${other.map(warningRow).join("")}<p class="sub small">${h(coverage)}</p>`;
}

const SEVERITY = { extreme: "var(--extreme)", severe: "var(--red)", moderate: "var(--orange)" };

function warningRow(w) {
  const colour = SEVERITY[w.severity] ?? "var(--yellow)";
  const english = lang() === "en" && w.english;
  const period = w.onset && w.expires ? t("%@ until %@", dayTime(w.onset), dayTime(w.expires))
    : w.onset ? t("From %@", dayTime(w.onset)) : w.expires ? t("Until %@", dayTime(w.expires)) : "";
  const text = (headline, description, instruction) => `<p class="headline">${h(headline)}</p>
    ${period ? `<p class="small">${icon("clock")} ${h(period)}</p>` : ""}
    <p>${h(description)}</p>${instruction ? `<p class="sub small">${h(instruction)}</p>` : ""}`;
  return `<div class="warning" style="--w:${colour}">
    <p class="sub small strong"><span style="color:${colour}">${icon(w.kind === "lake" ? "siren" : "triangle-alert")}</span>
      ${h(`${w.kind === "lake" ? t("Lake warning") : t("Weather warning")} · ${w.area ?? ""}`)}
      ${w.sample ? `<span class="tag">${h(t("SAMPLE"))}</span>` : ""}</p>
    ${english ? text(w.english.headline, w.english.description ?? t("DWD publishes the details of this warning in German only; see the original below."), w.english.instruction)
      + `<div class="original" lang="de"><p class="strong">${h(t("Original from DWD (German)"))}</p><p class="strong">${h(w.headline)}</p><p>${h(w.description)}</p>${w.instruction ? `<p>${h(w.instruction)}</p>` : ""}</div>`
      : text(w.headline, w.description, w.instruction)}
  </div>`;
}

function shoreLights(open) {
  const row = (flashes, colour, title, text) => `<li><span style="color:var(--${colour})">${icon("siren")}</span>
    <span><strong>${h(t("%@ flashes a minute: %@", flashes, title))}</strong><small>${h(text)}</small></span></li>`;
  return `<details class="shore" ${open ? "open" : ""}><summary>${icon("siren")} ${h(t("What the shore warning lights mean"))}</summary>
    <ul class="legend">
      ${row(40, "orange", t("Strong-wind warning"), t("Wind or gusts of Beaufort 6 to 7 (39 to 61 km/h) are expected. Boats on the water head for the shore; small boats stay ashore. The rowing light is red for small racing and training boats and amber for the others."))}
      ${row(90, "red", t("Storm warning"), t("Beaufort 8 or more (62 km/h and above). Go ashore at once and do not launch. The rowing light is red for every boat."))}
    </ul>
    <p class="sub small">${h(t("The lights run from 1 April to 31 October, usually from 7:00 to 22:00; times may vary by lake. Outside these times there is no light, so check the forecast yourself."))}</p>
  </details>`;
}

/** The current conditions: the sky, then two tiles a row in the app's order (ConditionsCard). */
function conditionsCard(forecast, hour) {
  const kind = sky(hour.weatherCode);
  const head = `<div class="cc-head">${skySymbol(hour, "large")}<div><strong>${h(t(SKY_TITLES[kind]))}</strong>
    <small class="sub">${h(t("%@ · feels like %@", degrees(hour.temperatureC), degrees(hour.apparentTemperatureC)))}</small></div></div>`;
  const tiles = TILE_ORDER.map((c) => conditionTile(c, forecast, hour)).join("");
  return card(t("Current conditions"), "gauge", `${head}<div class="tiles">${tiles}</div>`, { legend: "conditions" });
}

function conditionTile(condition, forecast, hour) {
  const i = forecast.hours.indexOf(hour);
  const next24 = forecast.hours.slice(Math.max(0, i), Math.max(0, i) + 24);
  const titles = conditionTexts();
  const light = REASONS[condition] ? lightFor(hour, REASONS[condition]) : null;
  const header = (title) => `<span class="tile-head">${conditionIcon(condition)}<span>${h(title)}</span>${light && light !== "green" ? dot(light, 8) : ""}${icon("chevron-right")}</span>`;
  const tile = (value, detail, graphic = "", off = false) => `<button class="tile ${off ? "off" : ""}" data-tile="${condition}">
    ${header(titles[condition][1])}
    <span class="tile-body"><span><strong>${h(value)}</strong><small>${h(detail)}</small></span><span class="graphic">${graphic}</span></span></button>`;
  const water = forecast.waterTemperature;
  const estimate = estimatedWater(forecast);
  const temps = next24.map((x) => x.temperatureC).filter((v) => v != null);
  switch (condition) {
    case "temperature":
      return tile(degrees(hour.temperatureC), temps.length ? t("High %@ · low %@", degrees(Math.max(...temps)), degrees(Math.min(...temps))) : "",
        scaleBar(((hour.temperatureC ?? 0) + 10) / 45, [C.blue, C.teal, C.green, C.orange, C.red]));
    case "feelsLike":
      return tile(degrees(hour.apparentTemperatureC), feelsLikeNote(hour) ? t(feelsLikeNote(hour)) : "",
        scaleBar(((hour.apparentTemperatureC ?? 0) + 10) / 45, [C.blue, C.teal, C.green, C.orange, C.red]));
    case "wind": {
      const gust = t("Gusts %@", windNumber(hour.windGustMs));
      return tile(wind(hour.windSpeedMs), hour.windFromDeg != null ? `${gust} · ${t("from %@", compass(hour.windFromDeg))}` : gust, windDial(hour));
    }
    case "waves": {
      // The app's limits for the boat: amber and red zones up to a third past red.
      const [amber, red] = store.boat === "big" ? [0.25, 0.4] : [0.15, 0.25];
      const top = (red * 4) / 3;
      const fetch = hour.fetchM;
      return tile(waves(hour.waveHeightM), fetch == null ? "" : fetch < 50 ? t("Wind blows off the shore") : t("%@ open water upwind", distance(fetch)),
        zoneBar((hour.waveHeightM ?? 0) / top, [[0, C.green], [amber / top, C.orange], [red / top, C.red]]));
    }
    case "waterTemperature": {
      const value = water == null && estimate != null ? `≈ ${degrees(estimate)}` : degrees(water?.celsius, 1);
      const detail = water == null && estimate != null ? (forecast.waterEstimate ? t("Satellite estimate") : t("Estimated, not measured"))
        : water ? t("Measured %@", time(water.measuredAt)) : t("No lake station");
      return tile(value, detail, water ? zoneBar(water.celsius / 25, [[0, C.red], [0.4, C.orange], [0.6, C.green]]) : "");
    }
    case "ice": {
      const ice = forecast.ice;
      const off = iceOff(ice);
      let value, detail;
      if (off) [value, detail] = [t("Off season"), t("Nov–Apr")];
      else if (ice && ice.status !== "unavailable") [value, detail] = [t(ICE_TITLES[ice.status] ?? "No data"), iceDetail(ice)];
      else if (water?.celsius >= 8) [value, detail] = [t("No ice"), t("Water too warm")];
      else [value, detail] = [t("No data yet"), t("Check the lake yourself")];
      return tile(value, detail, "", off);
    }
    case "precipitation": {
      let detail;
      if ((hour.precipitationMm ?? 0) >= 0.1) detail = t(precipitationKind(sky(hour.weatherCode)) ?? "Rain");
      else {
        const wet = next24.find((x) => (x.precipitationMm ?? 0) >= 0.1);
        detail = wet ? t("%@ from %@", t(precipitationKind(sky(wet.weatherCode)) ?? "Rain"), time(wet.time)) : t("Dry next 24 h");
      }
      return tile((hour.precipitationMm ?? 0) >= 0.1 ? rain(hour.precipitationMm) : t("Dry"), detail,
        sparkBars(forecast.hours.slice(Math.max(0, i), Math.max(0, i) + 8).map((x) => x.precipitationMm ?? 0)));
    }
    case "thunderstorm": {
      const level = light === "red" ? 3 : light === "amber" ? 2 : 1;
      const storm = (forecast.warnings?.items ?? []).some((w) => /GEWITTER/i.test(w.event ?? ""));
      return tile({ 3: t("High"), 2: t("Possible"), 1: t("Low") }[level], storm ? t("DWD warning") : t("No DWD warning"), levelSegments(level));
    }
    case "visibility": {
      let detail;
      if ((hour.visibilityM ?? Infinity) < 1000) detail = t("Fog");
      else {
        const fog = next24.find((x) => (x.visibilityM ?? Infinity) < 1000);
        detail = fog ? t("Fog from %@", time(fog.time)) : t("No fog");
      }
      const f = Math.log10(Math.max(hour.visibilityM ?? 40000, 100) / 100) / Math.log10(400);
      return tile(distance(hour.visibilityM), detail, zoneBar(f, [[0, C.red], [0.27, C.orange], [0.384, C.green]]));
    }
    case "cloudCover":
      return tile(`${num(hour.cloudCoverPct)} %`, hour.cloudCoverLowPct != null ? t("Low cloud %@ %%", num(hour.cloudCoverLowPct)) : "", cloudLayers(hour));
    case "humidity":
      return tile(hour.humidityPct == null ? "–" : `${num(hour.humidityPct)} %`, hour.dewPointC != null ? t("Dew point %@", degrees(hour.dewPointC)) : "",
        `<span class="drop" style="--f:${hour.humidityPct ?? 0}%">${icon("droplet")}</span>`);
    case "pressure": {
      const change = pressureChange(forecast.hours, hour);
      const trend = change == null ? null : pressureTrend(change);
      return tile(hour.pressureHpa == null ? "–" : num(hour.pressureHpa), trend ? `hPa · ${t(trend).toLowerCase()}` : "hPa", pressureGauge(hour.pressureHpa, trend));
    }
    case "uvIndex": {
      const withUv = next24.filter((x) => x.uvIndex != null);
      const top = withUv.length ? withUv.reduce((a, b) => (b.uvIndex > a.uvIndex ? b : a)) : null;
      return tile(num(hour.uvIndex), top ? t("Max %@ · %@", num(top.uvIndex), dayLabel(top.time)) : "",
        scaleBar((hour.uvIndex ?? 0) / 11, [C.green, C.yellow, C.orange, C.red, C.purple]));
    }
    case "daylight": {
      const at = new Date(hour.time) > new Date() ? new Date(hour.time) : new Date();
      const sun = sunState(forecast, at);
      if (!sun) return tile("–", "");
      const graphic = sunPath(sun.sunrise, sun.sunset, at);
      return sun.up
        ? `<button class="tile" data-tile="daylight">${header(t("Sunset"))}<span class="tile-body"><span><strong>${h(time(sun.sunset))}</strong><small>${h(t("Sunrise %@", time(sun.sunrise)))}</small></span><span class="graphic">${graphic}</span></span></button>`
        : `<button class="tile" data-tile="daylight">${header(t("Sunrise"))}<span class="tile-body"><span><strong>${h(time(sun.sunrise))}</strong><small>${h(t("Sunset %@", time(sun.sunset)))}</small></span><span class="graphic">${graphic}</span></span></button>`;
    }
    default:
      return "";
  }
}

function iceDetail(ice) {
  if (ice.thicknessCm > 0) return t("About %@ cm, estimated", num(ice.thicknessCm));
  if (ice.basis === "season") return t("No ice this time of year");
  if (ice.basis === "measured") return t("Water %@, too warm for ice", temperature(ice.waterTemperatureC, 1));
  if (ice.basis === "model") return ice.status === "edges" ? t("Bays and harbours first") : t("Estimated from frost");
  return t("Check the lake yourself");
}

/** The next 48 hours, a row an hour under a day header with sunrise and sunset (HourlyCard). */
function hourlyCard(forecast, now, stale) {
  const list = nextHours(forecast.hours, now, 48);
  const head = `<div class="hrow hhead">
    <span>${icon("clock")}</span><span>${dot("grey", 8)}</span><span>${icon("cloud-sun")}</span>
    ${[["temperature", "°C"], ["feelsLike", "°C"], ["wind", windUnit()], ["waves", "m"], ["precipitation", "mm"], ["visibility", "km"]]
      .map(([c, unit]) => `<span class="num">${icon(CONDITION_ICONS[c])}<small>${h(unit)}</small></span>`).join("")}</div>`;
  let lastDay = null;
  const rows = list.map((x) => {
    const day = localDay(x.time);
    let header = "";
    if (day !== lastDay) {
      const sun = forecast.daylight?.find((d) => d.date === day);
      header = `<div class="dayhead"><strong>${h(dayLabel(day))}</strong>${sun ? `<span>${icon("sunrise")} ${h(time(sun.sunrise))} ${icon("sunset")} ${h(time(sun.sunset))}</span>` : ""}</div>`;
      lastDay = day;
    }
    const fog = lightFor(x, ["fog"]);
    return `${header}<button class="hrow ${x.sunUp === false ? "night" : ""}" data-hour="${h(x.time)}">
      <span>${h(time(x.time))}</span><span>${dot(x.light, 12, stale)}</span><span>${skySymbol(x)}</span>
      <span class="num">${h(num(x.temperatureC))}</span>
      <span class="num sub">${h(num(x.apparentTemperatureC))}</span>
      <span class="num">${h(windRange(x.windSpeedMs, x.windGustMs))}</span>
      <span class="num">${h(wavesNumber(x.waveHeightM))}</span>
      <span class="num ${(x.precipitationMm ?? 0) >= 0.1 ? "blue" : ""}">${h(rainNumber(x.precipitationMm))}</span>
      <span class="num ${fog && fog !== "green" ? (fog === "red" ? "red" : "orange") : ""}">${h(distanceNumber(x.visibilityM))}</span>
    </button>`;
  }).join("");
  return card(t("Next 48 hours"), "clock", `<div class="hourly">${head}${rows}</div>`, { legend: "hourly", cls: "hourly-card" });
}

/** The launch point on a map, with what it stands for (LaunchPointMapCard). */
function launchPointCard(club) {
  const { lat, lon } = club.launchPoint;
  const unconfirmed = club.source === "drv" ? t("Not yet confirmed by the club; taken from the club's address.") : t("Not yet confirmed by the club; taken from OpenStreetMap.");
  return card(t("Launch point"), "map-pin", `
    <div class="map" id="launch-map" role="img" aria-label="${h(t("Map of the launch point of %@", club.shortName || club.name))}"></div>
    <p>${h(t("The forecast, waves and warnings are for this point."))}</p>
    ${club.launchPointVerified ? "" : `<p class="orange small">${icon("map-pin-off")} ${h(unconfirmed)}</p>`}
    <div class="map-foot"><small class="sub">${h(`${lat.toFixed(5)}° N, ${lon.toFixed(5)}° E`)}</small>
      <a class="pill" href="https://www.openstreetmap.org/?mlat=${lat}&amp;mlon=${lon}#map=16/${lat}/${lon}" target="_blank" rel="noopener noreferrer">${icon("map")} ${h(t("Launch point on the map"))}</a>
      <a class="pill" href="https://www.openstreetmap.org/directions?to=${lat}%2C${lon}" target="_blank" rel="noopener noreferrer">${icon("map-pinned")} ${h(t("Directions to the club"))}</a></div>`);
}

let leaflet = null;

/** Leaflet (in vendor/) with OpenStreetMap's tiles, loaded only when a launch point is shown. */
function loadLeaflet() {
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

async function showLaunchMap(club) {
  const L = await loadLeaflet().catch(() => null);
  const box = root.querySelector("#launch-map");
  if (!L || !box) return;
  const { lat, lon } = club.launchPoint;
  const map = L.map(box, { scrollWheelZoom: false, attributionControl: true }).setView([lat, lon], 14);
  // OpenStreetMap asks for the site in the Referer; the page itself sends none.
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19, referrerPolicy: "strict-origin", attribution: '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>',
  }).addTo(map);
  L.marker([lat, lon], {
    icon: L.divIcon({ className: "pin", html: icon(store.clubs[0]?.id === club.id ? "house" : "map-pin"), iconSize: [30, 30], iconAnchor: [15, 15] }),
    keyboard: false,
  }).addTo(map);
}

/** The Sentinel-2 pictures of the lake: latest, mostly clear and clearest (SatellitePictureCard). */
async function satelliteCard(lakeId) {
  const box = root.querySelector("#satellite");
  let meta;
  try {
    meta = await getJSON(`lakes/${encodeURIComponent(lakeId)}/satellite`);
  } catch {
    return;
  }
  const kinds = [["latest", t("Latest")], ["mostlyClear", t("Mostly clear")], ["clearest", t("Clearest")]].filter(([k]) => meta[k]?.image);
  if (!kinds.length || !box) return;
  const ice = meta.ice?.image && meta.ice.bbox ? overlayBox(meta.bbox, meta.ice.bbox) : null;
  const show = (kind) => {
    const pick = meta[kind];
    const cloud = (pick.lakeCloud ?? 0) * 100;
    box.innerHTML = `<header class="card-title">${icon("globe")}<span>${h(t("Satellite picture"))}</span></header>
      <div class="segmented">${kinds.map(([k, label]) => `<button data-kind="${k}" class="${k === kind ? "on" : ""}">${h(label)}</button>`).join("")}</div>
      <div class="picture" style="aspect-ratio:${meta.width}/${meta.height};width:min(100%, calc(60vh * ${meta.width / meta.height}))">
        <img src="${API}/lakes/${encodeURIComponent(lakeId)}/${h(pick.image)}" alt="${h(t("Satellite picture of the lake"))}" loading="lazy">
        ${ice ? `<img class="overlay" src="${API}/lakes/${encodeURIComponent(lakeId)}/${h(meta.ice.image)}" alt="" style="left:${ice.left}%;top:${ice.top}%;width:${ice.width}%;height:${ice.height}%">` : ""}
      </div>
      <p class="sub small">${h(cloud < 1 ? t("Sentinel-2 · %@ · no cloud over the lake", dayLabel(pick.date)) : t("Sentinel-2 · %@ · %@ %% of the lake under cloud", dayLabel(pick.date), num(cloud)))}</p>
      ${ice ? `<p class="sub small">${h(t("Satellite ice map, %@", dayLabel(meta.ice.date)))}</p>` : ""}
      <p class="sub small">${h(meta.attribution)}${meta.ice ? ` · ${h(meta.ice.attribution)}` : ""}</p>`;
    box.querySelectorAll(".segmented button").forEach((b) => b.addEventListener("click", () => show(b.dataset.kind)));
  };
  box.hidden = false;
  show(kinds[0][0]);
}

/** Which weather model the forecast comes from (ForecastSourceLine). */
function sourceLine(forecast) {
  const part = forecast.forecastSource?.parts?.[0];
  if (!part) return "";
  const short = part.provider.match(/\(([^)]+)\)\s*$/)?.[1] ?? part.provider;
  return `<p class="source">${icon("info")} ${h(t("Forecast: %@", `${short} ${part.model}, ${t("%@ km grid", num(part.resolutionKm, part.resolutionKm % 1 ? 1 : 0))}`))}</p>`;
}

function credits(forecast, club) {
  let clubData = "";
  if (club && !club.launchPointVerified) {
    clubData = {
      drv: t("Club data: Deutscher Ruderverband e.V. (rudern.de). Launch point geocoded with © OpenStreetMap contributors, ODbL"),
      oerv: t("Club data: Österreichischer Ruderverband (rudern.at). Launch point geocoded with © OpenStreetMap contributors, ODbL"),
      swissrowing: t("Club data: Swiss Rowing (swissrowing.ch). Launch point geocoded with © OpenStreetMap contributors, ODbL"),
    }[club.source] ?? t("Launch point from © OpenStreetMap contributors, ODbL");
  }
  return `<div class="credits">${(forecast.attribution ?? []).map((a) => `<p>${h(t(a))}</p>`).join("")}${clubData ? `<p>${h(clubData)}</p>` : ""}</div>`;
}

// ---- Settings ----------------------------------------------------------------------

function renderSettings() {
  setTitle(t("Settings"));
  const unit = store.wind;
  const accepted = store.safety?.at ? new Intl.DateTimeFormat(locale(), { dateStyle: "long" }).format(new Date(store.safety.at)) : null;
  const back = store.clubs[0] ? `#/club/${encodeURIComponent(store.clubs[0].id)}` : "#/list";
  root.innerHTML = `
    <header class="nav"><span class="spacer"></span><a class="link strong" href="${back}">${h(t("Done"))}</a></header>
    ${testing()}
    <main class="page">
      <h1 class="large">${h(t("Settings"))}</h1>
      <section class="card group">
        ${languagePicker()}
        <label class="row-setting"><span>${icon("wind")} ${h(t("Wind"))}</span>
          <select id="wind">${Object.entries(WIND_UNITS).map(([k, u]) => `<option value="${k}" ${k === unit ? "selected" : ""}>${h(u.label)}</option>`).join("")}</select></label>
        <label class="row-setting"><span>${icon("sailboat")} ${h(t("Boat"))}</span>
          <select id="boat">${Object.entries(BOATS).map(([k, b]) => `<option value="${k}" ${k === store.boat ? "selected" : ""}>${h(t(b.title))}</option>`).join("")}</select></label>
      </section>
      ${card(t("Safety notice"), "shield-check", `${safetyList()}${accepted ? `<p class="sub">${h(t("You accepted this notice on %@.", accepted))}</p>` : ""}`)}
      ${card(t("Stored in this browser"), "info", `<p>${h(t("Your clubs, settings and your acceptance of the safety notice stay in this browser. Nothing is sent anywhere."))}</p>
        <button id="reset" class="quiet">${h(t("Delete everything stored here"))}</button>`)}
      ${footerLinks()}
    </main>`;
  wireLanguage(renderSettings);
  root.querySelector("#wind").addEventListener("change", (e) => (store.wind = e.target.value));
  root.querySelector("#boat").addEventListener("change", (e) => (store.boat = e.target.value));
  root.querySelector("#reset").addEventListener("click", () => {
    if (!confirm(t("Delete your clubs, settings and the accepted safety notice from this browser?"))) return;
    try {
      for (const name of Object.keys(localStorage)) if (name.startsWith("rf.")) localStorage.removeItem(name);
    } catch {}
    location.hash = "#/";
    route();
  });
}

function footerLinks() {
  return `<footer class="links">
    <a href="/impressum/">${h(t("Legal notice"))}</a> · <a href="/privacy/">${h(t("Privacy"))}</a> · <a href="/credits/">${h(t("Data sources"))}</a>
  </footer>`;
}

// ---- Routing -------------------------------------------------------------------------

/** As the app opens: the home base's page, or the list while there is no club yet. */
function route(scroll = true) {
  swipeOff?.();
  document.querySelector("dialog.sheet")?.remove();
  if (scroll) window.scrollTo(0, 0);
  if (!store.safety || store.safety.version < SAFETY_VERSION) return renderSafetyGate();
  const hash = location.hash.replace(/^#/, "");
  const club = hash.match(/^\/club\/(.+)$/);
  if (club) return renderClub(decodeURIComponent(club[1]));
  if (hash === "/settings") return renderSettings();
  if (hash === "/list" || !store.clubs.length) return renderList();
  return renderClub(store.clubs[0].id);
}

window.addEventListener("hashchange", () => route());
// Back on the page after a while: show fresh numbers.
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") forecasts.clear();
});

await setLanguage(savedLanguage());
route();
