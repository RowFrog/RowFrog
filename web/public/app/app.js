// Row Frog in the browser: the club list, search and club page, reading the
// same published files as the iPhone app (api.rowfrog.com/v1). No account and
// no cookies: the chosen clubs, units, language and the accepted safety notice
// stay in this browser (localStorage).

import { t, num, lang, locale, setLanguage, savedLanguage } from "./i18n.js";
import {
  API, ZONE, isStale, shownLight, currentHour, nextHours, days, weatherSymbol, windValue, WIND_UNITS,
  compass, searchClubs, waterTemperature, town, overlayBox, localDay,
} from "./logic.js";

const SAFETY_VERSION = 1;
const root = document.getElementById("root");

// ---- Stored in the browser -------------------------------------------------

function load(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw == null ? fallback : JSON.parse(raw);
  } catch {
    return fallback;
  }
}

function save(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {}
}

const store = {
  get clubs() { return load("rf.clubs", []); },
  set clubs(list) { save("rf.clubs", list); },
  get wind() { return load("rf.wind", "kmh"); },
  set wind(unit) { save("rf.wind", unit); },
  get safety() { return load("rf.safety", null); },
  set safety(value) { save("rf.safety", value); },
};

function savedClub(club, lake) {
  return { id: club.id, name: club.name, shortName: club.shortName, address: club.address, lakeId: lake.id, lakeName: lake.name, country: club.country ?? lake.country };
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

const forecasts = new Map();

async function loadForecast(id, fresh = false) {
  const kept = forecasts.get(id);
  if (kept && !fresh && Date.now() - kept.at < 5 * 60 * 1000) return kept.forecast;
  const forecast = await getJSON(`clubs/${encodeURIComponent(id)}/forecast`);
  forecasts.set(id, { at: Date.now(), forecast });
  return forecast;
}

// ---- Small helpers ---------------------------------------------------------

function h(text) {
  return String(text ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

function time(value) {
  return new Intl.DateTimeFormat(locale(), { timeZone: ZONE, hour: "2-digit", minute: "2-digit" }).format(new Date(value));
}

function hourLabel(value) {
  return new Intl.DateTimeFormat(locale(), { timeZone: ZONE, hour: "2-digit" }).format(new Date(value));
}

function dayLabel(day, long = false) {
  const date = new Date(`${day}T12:00:00Z`);
  const today = localDay(new Date());
  const tomorrow = localDay(new Date(Date.now() + 86400000));
  if (day === today) return t("Today");
  if (day === tomorrow) return t("Tomorrow");
  return new Intl.DateTimeFormat(locale(), { timeZone: "UTC", weekday: long ? "long" : "short", day: "numeric", month: long ? "long" : "numeric" }).format(date);
}

function dayTime(value) {
  return new Intl.DateTimeFormat(locale(), { timeZone: ZONE, weekday: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(value));
}

const temp = (c, digits = 0) => (c == null ? "–" : `${num(c, digits)} °C`);
const wind = (ms) => (ms == null ? "–" : `${windValue(ms, store.wind)} ${WIND_UNITS[store.wind].label}`);

function lightTitle(light) {
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
    case "freezing_water": return t("The water is below %@. You are strongly advised not to go out, at least not in a small boat.", temp(4));
    case "weather_warning": return t("DWD has issued a weather warning for this place.");
    case "wind": return t("Mean wind is above the limit.");
    case "gusts": return t("Gusts are above the limit.");
    case "waves": return t("Waves at the launch point are too high.");
    case "fog": return t("Visibility is poor (fog or mist).");
    case "heavy_rain": return t("Heavy rain of %@ or more in the hour.", `${num(4)} mm`);
    case "hail": return t("Hail is forecast with a thunderstorm.");
    case "thunderstorm": return t("Thunderstorms are possible.");
    case "ice": return light === "red" ? t("Ice on the lake is likely (estimate).") : t("Thin ice at the shore or drift ice is possible (estimate).");
    case "daylight": return t("The sun is down. Rowing is only advised in daylight.");
    case "twilight": return t("Sunrise or sunset falls in this hour.");
    case "cold_water": return t("Very cold water, below %@: wear a life jacket, stay near the shore and don't row alone.", temp(10));
    case "cool_water": return t("Water is below %@: a capsize can cause cold-water shock. We advise a life jacket.", temp(15));
    default: return "";
  }
}

function iceLabel(status) {
  return { open: t("No ice"), edges: t("Shore ice possible"), forming: t("Ice forming"), frozen: t("Ice cover likely"), drift_ice: t("Drift ice possible"), unavailable: t("Not available") }[status] ?? status;
}

function iceBasis(ice) {
  if (ice.basis === "season") return t("No ice this time of year");
  if (ice.basis === "measured") return t("Water %@, too warm for ice", temp(ice.waterTemperatureC, 1));
  if (ice.basis === "model") return ice.status === "edges" ? t("Bays and harbours first") : t("Estimated from frost");
  return "";
}

const flag = (code) => String.fromCodePoint(...[...(code ?? "de").toUpperCase()].map((c) => 0x1f1a5 + c.charCodeAt(0)));

function dot(light, size = "") {
  return `<span class="dot ${h(light)} ${size}" aria-hidden="true"></span>`;
}

function setTitle(text) {
  document.title = text ? `${text} · Row Frog` : "Row Frog";
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
    <main class="page narrow">
      <h1>${h(t("Before you row"))}</h1>
      ${languagePicker()}
      ${changed ? `<p class="banner amber">${h(t("This notice has changed. Please read it again."))}</p>` : ""}
      ${safetyList()}
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

// ---- Top bar and language ------------------------------------------------------

function bar(title, back = false) {
  return `<header class="bar">
      ${back ? `<a href="#/" class="icon" aria-label="${h(t("Back"))}">‹</a>` : `<a href="/" class="brand">Row Frog</a>`}
      <span class="bar-title">${h(title ?? "")}</span>
      <a href="#/settings" class="icon" aria-label="${h(t("Settings"))}">⚙︎</a>
    </header>
    <p class="testing">${h(t("Test version: only for you, hidden from search engines."))}</p>`;
}

function languagePicker() {
  const choice = savedLanguage();
  const option = (value, label) => `<option value="${value}" ${choice === value ? "selected" : ""}>${h(label)}</option>`;
  return `<label class="inline">${h(t("Language"))}
    <select id="language">${option("auto", t("Device"))}${option("en", "English")}${option("de", "Deutsch")}</select></label>`;
}

function wireLanguage(again) {
  root.querySelector("#language")?.addEventListener("change", async (e) => {
    await setLanguage(e.target.value);
    again();
  });
}

// ---- List and search -------------------------------------------------------------

async function renderList() {
  setTitle("");
  const clubs = store.clubs;
  root.innerHTML = `
    ${bar(t("Your clubs"))}
    <main class="page">
      <div class="search">
        <input id="query" type="search" autocomplete="off" placeholder="${h(t("Search for a club, town or lake"))}" aria-label="${h(t("Search"))}">
        <ul id="results" class="results"></ul>
      </div>
      ${clubs.length ? "" : `<p class="empty">${h(t("Pick your home club first, then any others you row at."))}</p>`}
      <ul class="clubs">${clubs.map((c, i) => `
        <li><a class="club-row" href="#/club/${encodeURIComponent(c.id)}" data-id="${h(c.id)}">
          <span class="light-slot">${dot("loading", "big")}</span>
          <span class="club-text"><strong>${i === 0 ? "🏠 " : ""}${h(c.shortName || c.name)}</strong>
            <small>${h(c.lakeName)}${town(c.address) ? ` · ${h(town(c.address))}` : ""}</small>
            <small class="status"></small></span>
          <span class="club-now"></span>
        </a></li>`).join("")}
      </ul>
      ${footerLinks()}
    </main>`;
  wireSearch();
  for (const row of root.querySelectorAll(".club-row")) fillRow(row);
}

async function fillRow(row) {
  try {
    const forecast = await loadForecast(row.dataset.id);
    const stale = isStale(forecast);
    const hour = currentHour(forecast.hours);
    const light = shownLight(hour.light, stale);
    row.querySelector(".light-slot").innerHTML = dot(light, "big");
    row.querySelector(".status").textContent = lightTitle(light);
    row.querySelector(".club-now").innerHTML = `<span class="sym">${weatherSymbol(hour.weatherCode, hour.sunUp)}</span>
      <strong>${h(temp(hour.temperatureC))}</strong><small>${h(wind(hour.windSpeedMs))}</small>`;
  } catch {
    row.querySelector(".light-slot").innerHTML = dot("grey", "big");
    row.querySelector(".status").textContent = t("Could not load the forecast.");
  }
}

function wireSearch() {
  const input = root.querySelector("#query");
  const results = root.querySelector("#results");
  let lakes = null;
  input.addEventListener("focus", async () => {
    try {
      lakes = await loadCatalog();
    } catch {
      results.innerHTML = `<li class="hint">${h(t("Could not load the club list."))}</li>`;
    }
  }, { once: true });
  input.addEventListener("input", async () => {
    lakes ??= await loadCatalog().catch(() => null);
    if (!lakes) return;
    const found = searchClubs(lakes, input.value);
    const saved = new Set(store.clubs.map((c) => c.id));
    results.innerHTML = found.map(({ club, lake }) => `
      <li><button class="result" data-club="${h(club.id)}" data-lake="${h(lake.id)}">
        <span>${flag(club.country ?? lake.country)}</span>
        <span class="club-text"><strong>${h(club.shortName || club.name)}</strong>
        <small>${h(club.shortName ? club.name : "")}</small>
        <small>${h(lake.name)}${town(club.address) ? ` · ${h(town(club.address))}` : ""}</small></span>
        <span class="add">${saved.has(club.id) ? "✓" : "+"}</span>
      </button></li>`).join("") || (input.value.trim() ? `<li class="hint">${h(t("No clubs found."))}</li>` : "");
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

// ---- Club page -------------------------------------------------------------------

async function renderClub(id) {
  const saved = store.clubs.find((c) => c.id === id);
  let club = saved;
  if (!club) {
    const lakes = await loadCatalog().catch(() => []);
    for (const lake of lakes) {
      const found = lake.clubs.find((c) => c.id === id);
      if (found) club = savedClub(found, lake);
    }
  }
  const name = club ? club.shortName || club.name : id;
  setTitle(name);
  root.innerHTML = `${bar(name, true)}<main class="page"><p class="hint">${h(t("Loading…"))}</p></main>`;
  let forecast;
  try {
    forecast = await loadForecast(id, true);
  } catch {
    root.querySelector("main").innerHTML = `<p class="banner red">${h(t("Could not load the forecast."))}</p>`;
    return;
  }
  const now = new Date();
  const stale = isStale(forecast, now);
  const hour = currentHour(forecast.hours, now);
  const light = shownLight(hour.light, stale);
  const isHome = store.clubs[0]?.id === id;
  root.querySelector("main").innerHTML = `
    <section class="head">
      <h1>${h(club?.name ?? name)}</h1>
      <p class="sub">${h(club?.lakeName ?? "")}${town(club?.address) ? ` · ${h(town(club.address))}` : ""}</p>
      <p class="sub">${h(t("Updated %@", dayTime(forecast.generatedAt)))}</p>
      <div class="actions">
        ${saved ? (isHome ? `<span class="tag">🏠 ${h(t("Home base"))}</span>` : `<button id="make-home">${h(t("Make home base"))}</button>`) : `<button id="add">${h(t("Add to my clubs"))}</button>`}
        ${saved ? `<button id="remove" class="quiet">${h(t("Remove"))}</button>` : ""}
      </div>
    </section>
    ${stale ? `<p class="banner amber">${h(t("Forecast out of date: from %@. Check the conditions yourself.", dayTime(forecast.generatedAt)))}</p>` : ""}
    ${forecast.refresh && forecast.refresh.used === false ? `<p class="banner info">${h(t("Nobody opened this club lately, so its forecast is renewed less often. It speeds up within the next half hour."))}</p>` : ""}
    ${lightCard(hour, light)}
    ${warningsCard(forecast.warnings)}
    ${nowCard(forecast, hour)}
    ${hoursCard(forecast, now, stale)}
    ${daysCard(forecast, now)}
    ${waterCard(forecast)}
    ${iceCard(forecast.ice)}
    <section class="card" id="satellite" hidden></section>
    ${creditsCard(forecast)}
    ${footerLinks()}`;
  wireClubActions(id, club);
  satelliteCard(forecast.lakeId);
}

function wireClubActions(id, club) {
  root.querySelector("#add")?.addEventListener("click", () => {
    store.clubs = [...store.clubs, club];
    renderClub(id);
  });
  root.querySelector("#make-home")?.addEventListener("click", () => {
    const list = store.clubs;
    store.clubs = [list.find((c) => c.id === id), ...list.filter((c) => c.id !== id)];
    renderClub(id);
  });
  root.querySelector("#remove")?.addEventListener("click", () => {
    store.clubs = store.clubs.filter((c) => c.id !== id);
    location.hash = "#/";
  });
}

function lightCard(hour, light) {
  const reasons = hour.reasons ?? [];
  return `<section class="card light-card ${h(light)}">
    <div class="light-top">${dot(light, "huge")}<div><h2>${h(lightTitle(light))}</h2>
      <p class="sub">${h(t("Now, for small racing boats (1x, 2x, 2-)"))}</p></div></div>
    ${reasons.length ? `<ul class="reasons">${reasons.map((r) => `<li>${dot(r.light)}<div><strong>${h(reasonLabel(r.condition))}</strong><p>${h(reasonExplanation(r.condition, r.light))}</p></div></li>`).join("")}</ul>` : ""}
    <p class="advice">${h(t("Advice only. You decide whether to go out. When in doubt, ask experienced rowers or stay ashore."))}</p>
  </section>`;
}

function warningsCard(warnings) {
  if (!warnings) return "";
  if (warnings.status !== "ok") {
    return `<section class="card"><h2>${h(t("Warnings"))}</h2><p class="banner amber">${h(t("DWD warnings could not be checked. Look at the storm warning lights and dwd.de."))}</p></section>`;
  }
  const items = warnings.items ?? [];
  return `<section class="card"><h2>${h(t("Warnings"))}</h2>
    ${items.length ? items.map((w) => {
      const english = lang() === "en" && w.english;
      const event = english ? w.english.event : w.event;
      const headline = english ? w.english.headline : w.headline;
      const description = english ? w.english.description : w.description;
      const span = [w.onset && dayTime(w.onset), w.expires && dayTime(w.expires)].filter(Boolean).join(" – ");
      return `<div class="warning ${w.kind === "lake" ? "lake" : ""}">
        <strong>⚠️ ${h(event)}</strong>${w.sample ? ` <span class="tag">${h(t("Sample"))}</span>` : ""}
        <p>${h(headline)}</p>${span ? `<p class="sub">${h(span)}</p>` : ""}
        ${description ? `<details><summary>${h(t("Details"))}</summary><p>${h(description)}</p>${w.instruction ? `<p>${h(english ? w.english.instruction : w.instruction)}</p>` : ""}</details>` : ""}
      </div>`;
    }).join("") : `<p>✓ ${h(t("No DWD warnings right now"))}${warnings.lakeArea ? ` · ${h(warnings.lakeArea)}` : ""}</p>`}
    <p class="credit">${h(t("Source: Deutscher Wetterdienst"))}</p>
  </section>`;
}

function tile(label, value, detail = "") {
  return `<div class="tile"><small>${h(label)}</small><strong>${value}</strong>${detail ? `<small>${detail}</small>` : ""}</div>`;
}

function nowCard(forecast, hour) {
  const water = waterTemperature(forecast);
  const basis = { measured: t("Measured"), satellite: t("Satellite estimate"), air: t("Estimated from the air") };
  const sun = forecast.daylight?.find((d) => d.date === localDay(new Date()));
  const arrow = hour.windFromDeg == null ? "" : `<span class="arrow" style="transform:rotate(${hour.windFromDeg}deg)">↓</span> `;
  return `<section class="card"><h2>${h(t("Conditions now"))}</h2><div class="tiles">
    ${tile(t("Air"), `${weatherSymbol(hour.weatherCode, hour.sunUp)} ${h(temp(hour.temperatureC))}`, h(t("Feels like %@", temp(hour.apparentTemperatureC))))}
    ${tile(t("Water"), `💧 ${h(temp(water?.celsius, 1))}`, h(water ? basis[water.basis] : ""))}
    ${tile(t("Wind"), `${arrow}${h(wind(hour.windSpeedMs))}`, h(`${compass(hour.windFromDeg)} · ${t("Gusts")} ${wind(hour.windGustMs)}`))}
    ${tile(t("Waves"), h(hour.waveHeightM == null ? "–" : `${num(hour.waveHeightM * 100)} cm`), h(t("At the launch point")))}
    ${tile(t("Cloud cover"), h(`${num(hour.cloudCoverPct)} %`), h(t("Low %@", `${num(hour.cloudCoverLowPct)} %`)))}
    ${tile(t("Visibility"), h(hour.visibilityM == null ? "–" : hour.visibilityM >= 10000 ? `${num(hour.visibilityM / 1000)} km` : `${num(hour.visibilityM / 1000, 1)} km`))}
    ${tile(t("Rain"), h(`${num(hour.precipitationMm, 1)} mm`), h(t("This hour")))}
    ${tile(t("Humidity"), h(`${num(hour.humidityPct)} %`), h(t("Dew point %@", temp(hour.dewPointC))))}
    ${tile(t("Pressure"), h(`${num(hour.pressureHpa)} hPa`))}
    ${hour.uvIndex != null ? tile(t("UV index"), h(num(hour.uvIndex))) : ""}
    ${sun ? tile(t("Daylight"), h(`🌅 ${time(sun.sunrise)}`), h(`🌇 ${time(sun.sunset)}`)) : ""}
  </div></section>`;
}

function hoursCard(forecast, now, stale) {
  const list = nextHours(forecast.hours, now, 48);
  let lastDay = null;
  const cells = list.map((x) => {
    const day = localDay(x.time);
    const divider = day !== lastDay && lastDay !== null ? `<div class="divider"><span>${h(dayLabel(day))}</span></div>` : "";
    lastDay = day;
    const light = shownLight(x.light, stale);
    const arrow = x.windFromDeg == null ? "" : `<span class="arrow" style="transform:rotate(${x.windFromDeg}deg)">↓</span>`;
    return `${divider}<div class="hour ${x.sunUp ? "" : "night"}" title="${h(x.reasons.map((r) => reasonLabel(r.condition)).join(", "))}">
      <small>${h(hourLabel(x.time))}</small>
      <span class="bar-light ${h(light)}"></span>
      <span class="sym">${weatherSymbol(x.weatherCode, x.sunUp)}</span>
      <strong>${h(num(x.temperatureC))}°</strong>
      <small>${arrow}${h(windValue(x.windSpeedMs, store.wind) ?? "–")}</small>
      <small class="gust">${h(windValue(x.windGustMs, store.wind) ?? "–")}</small>
    </div>`;
  }).join("");
  return `<section class="card"><h2>${h(t("Next 48 hours"))}</h2>
    <p class="sub">${h(t("Light, weather, temperature, wind and gusts in %@", WIND_UNITS[store.wind].label))}</p>
    <div class="hours">${cells}</div></section>`;
}

function daysCard(forecast, now) {
  const list = days(forecast, now);
  if (!list.length) return "";
  return `<section class="card"><h2>${h(t("Next days"))}</h2>
    <p class="sub">${h(t("Rowing light for each daylight hour"))}</p>
    <ul class="days">${list.map((d) => `<li>
      <span class="day-name">${h(dayLabel(d.day))}</span>
      <span class="sym">${weatherSymbol(d.weatherCode)}</span>
      <span class="strip">${d.lights.map((x) => `<span class="${h(x.light)}" title="${h(hourLabel(x.time))}"></span>`).join("")}</span>
      <span class="range">${h(num(d.minC))}° / <strong>${h(num(d.maxC))}°</strong></span>
      <small>${h(t("Gusts"))} ${h(wind(d.maxGustMs))}${d.rainMm >= 0.1 ? ` · ${h(num(d.rainMm, 1))} mm` : ""}</small>
    </li>`).join("")}</ul></section>`;
}

function waterCard(forecast) {
  const measured = forecast.waterTemperature;
  const water = waterTemperature(forecast);
  if (!water) return "";
  const station = measured?.station;
  let source = "";
  if (measured) {
    source = t("Measured %@", dayTime(measured.measuredAt));
    if (station?.name) source += ` · ${station.name}`;
  } else if (forecast.waterEstimate) {
    source = t("Estimated from a satellite reading of %@", dayLabel(forecast.waterEstimate.reading.date, true));
  } else {
    source = t("Estimated from the air temperatures of the last weeks");
  }
  return `<section class="card"><h2>${h(t("Water temperature"))}</h2>
    <p class="big">💧 ${h(temp(water.celsius, 1))}</p>
    <p class="sub">${station?.url ? `<a href="${h(station.url)}" target="_blank" rel="noopener noreferrer">${h(source)}</a>` : h(source)}</p>
    ${forecast.waterForecast?.length ? `<ul class="water-days">${forecast.waterForecast.map((d) => `<li><small>${h(dayLabel(d.date))}</small><strong>${h(temp(d.celsius, 1))}</strong></li>`).join("")}</ul>
    <p class="sub">${h(t("Expected in the next days, worked out from the air temperature forecast."))}</p>` : ""}
  </section>`;
}

function iceCard(ice) {
  if (!ice) return "";
  return `<section class="card"><h2>${h(t("Ice"))}</h2>
    <p>${ice.light ? dot(ice.light) : ""} <strong>${h(iceLabel(ice.status))}</strong>${ice.thicknessCm ? ` · ${h(num(ice.thicknessCm))} cm` : ""}</p>
    <p class="sub">${h(iceBasis(ice))}</p>
    ${ice.days?.length ? `<ul class="water-days">${ice.days.map((d) => `<li><small>${h(dayLabel(d.date))}</small><strong>${h(iceLabel(d.status))}</strong></li>`).join("")}</ul>` : ""}
  </section>`;
}

async function satelliteCard(lakeId) {
  const card = root.querySelector("#satellite");
  let meta;
  try {
    meta = await getJSON(`lakes/${encodeURIComponent(lakeId)}/satellite`);
  } catch {
    return;
  }
  const kinds = [["latest", t("Latest")], ["mostlyClear", t("Mostly clear")], ["clearest", t("Clearest")]].filter(([k]) => meta[k]?.image);
  if (!kinds.length || !card) return;
  const ice = meta.ice?.image && meta.ice.bbox ? overlayBox(meta.bbox, meta.ice.bbox) : null;
  const show = (kind) => {
    const pick = meta[kind];
    card.innerHTML = `<h2>${h(t("Satellite picture"))}</h2>
      <div class="tabs">${kinds.map(([k, label]) => `<button data-kind="${k}" class="${k === kind ? "on" : ""}">${h(label)}</button>`).join("")}</div>
      <div class="picture" style="aspect-ratio:${meta.width}/${meta.height};width:min(100%, calc(60vh * ${meta.width / meta.height}))">
        <img src="${API}/lakes/${encodeURIComponent(lakeId)}/${h(pick.image)}" alt="${h(t("Satellite picture"))}" loading="lazy">
        ${ice ? `<img class="overlay" src="${API}/lakes/${encodeURIComponent(lakeId)}/${h(meta.ice.image)}" alt="" style="left:${ice.left}%;top:${ice.top}%;width:${ice.width}%;height:${ice.height}%">` : ""}
      </div>
      <p class="sub">${h(dayLabel(pick.date, true))} · ${h(t("Cloud over the lake: %@", `${num(pick.lakeCloud * 100)} %`))}</p>
      ${ice ? `<p class="sub">${h(t("Ice map from %@", dayLabel(meta.ice.date, true)))}</p>` : ""}
      <p class="credit">${h(meta.attribution)}${meta.ice ? ` · ${h(meta.ice.attribution)}` : ""}</p>`;
    card.querySelectorAll(".tabs button").forEach((b) => b.addEventListener("click", () => show(b.dataset.kind)));
  };
  card.hidden = false;
  show(kinds[0][0]);
}

function creditsCard(forecast) {
  const models = forecast.forecastSource?.parts?.map((p) => `${p.model} (${p.provider}, ${num(p.resolutionKm, 1)} km)`).join(", ");
  return `<section class="card credits"><h2>${h(t("Data sources"))}</h2>
    <ul>${(forecast.attribution ?? []).map((a) => `<li>${h(t(a))}</li>`).join("")}
    <li>${h(t("Weather data by Open-Meteo.com"))}</li>
    ${models ? `<li>${h(t("Forecast model: %@", models))}</li>` : ""}</ul>
  </section>`;
}

// ---- Settings ----------------------------------------------------------------------

function renderSettings() {
  setTitle(t("Settings"));
  const unit = store.wind;
  const accepted = store.safety?.at ? new Intl.DateTimeFormat(locale(), { dateStyle: "long" }).format(new Date(store.safety.at)) : null;
  root.innerHTML = `${bar(t("Settings"), true)}
    <main class="page narrow">
      <section class="card">
        ${languagePicker()}
        <label class="inline">${h(t("Wind"))}
          <select id="wind">${Object.entries(WIND_UNITS).map(([k, u]) => `<option value="${k}" ${k === unit ? "selected" : ""}>${h(u.label)}</option>`).join("")}</select></label>
      </section>
      <section class="card"><h2>${h(t("Safety notice"))}</h2>
        ${safetyList()}
        ${accepted ? `<p class="sub">${h(t("You accepted this notice on %@.", accepted))}</p>` : ""}
      </section>
      <section class="card"><h2>${h(t("Stored in this browser"))}</h2>
        <p>${h(t("Your clubs, settings and your acceptance of the safety notice stay in this browser. Nothing is sent anywhere."))}</p>
        <button id="reset" class="quiet">${h(t("Delete everything stored here"))}</button>
      </section>
      ${footerLinks()}
    </main>`;
  wireLanguage(renderSettings);
  root.querySelector("#wind").addEventListener("change", (e) => (store.wind = e.target.value));
  root.querySelector("#reset").addEventListener("click", () => {
    if (!confirm(t("Delete your clubs, settings and the accepted safety notice from this browser?"))) return;
    try {
      for (const key of Object.keys(localStorage)) if (key.startsWith("rf.")) localStorage.removeItem(key);
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

function route() {
  window.scrollTo(0, 0);
  if (!store.safety || store.safety.version < SAFETY_VERSION) return renderSafetyGate();
  const hash = location.hash.replace(/^#/, "");
  const club = hash.match(/^\/club\/(.+)$/);
  if (club) return renderClub(decodeURIComponent(club[1]));
  if (hash === "/settings") return renderSettings();
  return renderList();
}

window.addEventListener("hashchange", route);
// Back on the page after a while: show fresh numbers.
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") forecasts.clear();
});

await setLanguage(savedLanguage());
route();
