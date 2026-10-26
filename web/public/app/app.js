// Row Frog in the browser, laid out like the iPhone app: a page per club with
// the rowing light on top, the DWD warnings, the current conditions tiles, the
// next 48 hours, the launch point and the satellite picture, and the list of
// clubs with search. It reads the same published files as the app
// (api.rowfrog.com/v1). No account and no cookies: the chosen clubs, units,
// boat, language and the accepted safety notice stay in this browser.

import { t, num, locale, setLanguage, savedLanguage, lang } from "./i18n.js";
import { icon } from "./icons.js";
import {
  store, TILE_ORDER, conditionTexts, iceDetail, allBoats, selectedBoat, boatLimits, currentLimits, boatTitle, boatInSentence,
  boatDetail, boatShort, limitText, forBoat, loadCatalog, findClub, forecasts, loadForecast, h, time, dayLabel, dayTime, duration,
  degrees, temperature, windUnit, windNumber, wind, windRange, wavesNumber, waves, rainNumber, distanceNumber, distance,
  precipitationText, lightTitle, reasonLabel, lakeTitle, hourExplanation, noteText, reasonExplanation, coldWaterText,
  coldWaterBadge, setTitle, dot, skySymbol, CONDITION_ICONS, conditionIcon, conditionGraphic, card, sunPath, openSheet,
  loadLeaflet, testing, adviceOnly, footerLinks, mapBoat, mapLimits, unitSymbol, inUnit, pressureNumber, usesAMPM,
  applyAppearance, unitId, setUnit, TIME_FORMATS, DATE_FORMATS, dateText, dataSaving,
} from "./shared.js";
import {
  isStale, shownLight, currentHour, nextHours, UNITS, compass, searchClubs, town, localDay, sky, SKY_TITLES, skyIcon, REASONS,
  lightFor, reasonCondition, feelsLikeNote, pressureChange, pressureTrend, estimatedWater, iceOff, ICE_TITLES, iceValue, sunState,
  coldWaterKit, place, GROUPS, BOAT_TYPES, BOAT_CLASSES, LIMITS, isGroup, standardLimit, applyLimits, steadierBoat, COLD,
  waterForHour, allowsMore, key,
} from "./logic.js";
import { fillLakeCard, renderLakeMap } from "./lakeview.js";
import { satelliteCard } from "./satellite.js";
import { renderAddPlace } from "./addplace.js";
import { isOwn } from "./ownplace.js";
import { loadCountries, inCountry, countryChips, resultRow, wireResults, renderCountries, renderCountry, renderWater } from "./countries.js";
import { renderValuePage } from "./valuepage.js";
import { layoutFor, visibleCards, openArrange } from "./arrange.js";
import { showBackground, renderBackgrounds, backgroundSummary } from "./backgrounds.js";
import { renderTour, tourSeen, tip, withTip, wireTips, replayTips } from "./tour.js";
import { MAP_ZOOMS } from "./weathermap.js";
import { conditionData } from "./values.js";
import { radarAt, followRadar, rainLines, radarGraphic, radarMark, radarCard, radarCardBody, wireRadarCard } from "./radar.js";

const SAFETY_VERSION = 1;
const root = document.getElementById("root");

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


// ---- Dialogs (the app's sheets) -------------------------------------------------------

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



/** Picks the boat for the rowing light, with the light each boat gets now (BoatMenu). */
function openBoatMenu(raw) {
  const now = raw ? new Date() : null;
  const row = (boat) => {
    let light = null;
    if (raw) {
      const hour = currentHour(applyLimits(raw, boatLimits(boat)).hours, now);
      light = hour.light;
    }
    const on = store.boat === boat.id;
    return `<li><button data-boat="${h(boat.id)}" class="${on ? "on" : ""}">
      ${light ? dot(light, 16, isStale(raw)) : icon("sailboat")}
      <span><strong>${h(boatTitle(boat))}</strong><small>${h(light ? lightTitle(light, isStale(raw)) : boatDetail(boat))}</small></span>
      ${on ? icon("check") : ""}</button></li>`;
  };
  const mine = store.boats;
  const body = `<h3>${h(t("Rowing light for"))}</h3><ul class="boats">${GROUPS.map(row).join("")}</ul>
    ${mine.length ? `<h3>${h(t("My boats"))}</h3><ul class="boats">${mine.map(row).join("")}</ul>` : ""}
    <a class="pill" href="#/settings/boats">${icon("sliders-horizontal")} ${h(t("Boats and limits…"))}</a>`;
  openSheet(t("Boat"), body, (dialog) => {
    dialog.querySelectorAll("[data-boat]").forEach((b) => b.addEventListener("click", () => {
      store.boat = b.dataset.boat;
      dialog.close();
      route(false);
    }));
    dialog.querySelector("a.pill").addEventListener("click", () => dialog.close());
  });
}

// ---- Bottom bar ----------------------------------------------------------------------------

/** Settings and boat on the left, a dot per club page, the list on the right (RootView). */
function bottomBar(currentId, raw) {
  const clubs = store.clubs;
  return `<nav class="bottom">
    <a href="#/settings" class="tool" aria-label="${h(t("Settings"))}">${icon("settings")}</a>
    <button class="tool boat" id="boat-button" aria-label="${h(t("For %@", boatInSentence(selectedBoat())))}">${icon("sailboat")}<small>${h(boatShort(selectedBoat()))}</small></button>
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
      <div id="chips" hidden></div>
      <ul id="results" class="results" hidden></ul>
      <p class="add-own" id="add-own" hidden><a class="link" href="#/add-place">${icon("map-pin")} ${h(t("Not in the list? Add a place"))}</a>
        <small class="sub">${h(t("Put your club, boathouse or spot on the map yourself."))}</small></p>
      <div id="saved">
        ${clubs.length ? "" : `<p class="empty">${h(t("Pick your home club first, then any others you row at."))}</p>`}
        <ul class="rows">${clubs.map((c, i) => `
          <li class="${editing ? "editing" : ""}">
            ${editing ? `<button class="round red" data-remove="${h(c.id)}" aria-label="${h(t("Remove"))}">${icon("trash-2")}</button>` : ""}
            <a class="row" href="#/club/${encodeURIComponent(c.id)}" data-id="${h(c.id)}">${rowSkeleton(c, i === 0)}</a>
            ${editing && i > 0 ? `<button class="round" data-home="${h(c.id)}" aria-label="${h(t("Home base"))}">${icon("house")}</button>` : ""}
          </li>`).join("")}</ul>
        <p class="footnote" id="updated"></p>
        <p class="list-links"><a class="link" id="browse" href="#/countries" hidden>${icon("globe")} ${h(t("Browse clubs by country"))}</a>
          <a class="link" href="#/add-place">${icon("map-pin")} ${h(t("Add a place yourself"))}</a></p>
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
        <small>${h(place(club.lakeName, town(club.address), lakeTitle))}</small>
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
  const forecast = forBoat(raw);
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
  const kit = coldWaterKit(water ?? estimate, currentLimits());
  const iceText = iceOff(ice) ? t("Off season") : ice && ice.status !== "unavailable" ? t(ICE_TITLES[ice.status] ?? "No data") : "–";
  row.querySelector(".row-bottom").innerHTML = `
    <div class="row-why">
      <strong>${h(lightTitle(hour.light, stale))}</strong>
      ${stale ? `<small class="orange">${icon("clock")} ${h(t("As of %@", dayTime(forecast.generatedAt)))}</small>` : ""}
      <small class="why">${h(hour.reasons.length ? t("Why: %@", hour.reasons.map(reasonLabel).join(", ")) : t("All conditions within the limits"))}</small>
      ${kit ? `<small class="kit-line" title="${h(coldWaterText(kit)[1])}">${icon("life-buoy")} ${h(coldWaterText(kit)[0])}</small>` : ""}
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
  const name = event ? event[0].toUpperCase() + event.slice(1).toLowerCase() : "";
  return isDWD(w) ? t("DWD warning: %@", name) : t("%@ warning: %@", serviceShort(w.source), name);
}

function wireSearch() {
  const input = root.querySelector("#query");
  const results = root.querySelector("#results");
  const chips = root.querySelector("#chips");
  const saved = root.querySelector("#saved");
  let lakes = null;
  let countries = [];
  let country = null;
  // The country list and chips only when the search covers more than one country.
  loadCountries().then((list) => {
    countries = list;
    root.querySelector("#browse")?.toggleAttribute("hidden", list.length < 2);
  }).catch(() => {});
  input.addEventListener("focus", async () => {
    try {
      lakes = await loadCatalog();
    } catch {
      results.hidden = false;
      results.innerHTML = `<li class="hint">${h(t("Could not load the club list."))}</li>`;
    }
  }, { once: true });
  const show = async () => {
    lakes ??= await loadCatalog().catch(() => null);
    if (!lakes) return;
    const searching = input.value.trim() !== "";
    results.hidden = !searching;
    chips.hidden = !searching || countries.length < 2;
    saved.hidden = searching;
    const addOwn = root.querySelector("#add-own");
    addOwn.hidden = !searching;
    addOwn.querySelector("a").href = `#/add-place?name=${encodeURIComponent(input.value.trim())}`;
    chips.innerHTML = countryChips(countries, country);
    const shown = country ? inCountry(lakes, country) : lakes;
    results.innerHTML = searchClubs(shown, input.value).map(({ club, lake }) => resultRow(club, lake, { showFlag: !country })).join("")
      || (searching ? `<li class="hint">${h(t("No clubs found."))}</li>` : "");
  };
  input.addEventListener("input", show);
  chips.addEventListener("click", (e) => {
    const chip = e.target.closest("[data-country]");
    if (!chip) return;
    country = chip.dataset.country || null;
    show();
  });
  wireResults(results, { find: (f) => lakes?.find(f) });
}

// ---- Club page (LocationPageView) ------------------------------------------------------------


/** Counts club page renders, so the radar of a page left behind stops refreshing. */
let clubRenders = 0;

async function renderClub(id) {
  const shown = ++clubRenders;
  let club = store.clubs.find((c) => c.id === id);
  if (!club?.launchPoint) club = (await findClub(id)) ?? club;
  const saved = store.clubs.some((c) => c.id === id);
  const name = club ? club.shortName || club.name : id;
  setTitle(name);
  const isHome = store.clubs[0]?.id === id;
  const side = sideList.matches;
  root.innerHTML = `${testing()}<div class="split">
      ${side ? `<aside class="side">${sideRows(id)}</aside>` : ""}
      <main class="page club">
        ${clubHeader(club, name, isHome, null)}
        <section class="card loading"><p>${h(t("Loading the forecast…"))}</p></section>
      </main>
    </div>${bottomBar(id, null)}`;
  if (side) root.querySelectorAll(".side .row").forEach(fillRow);
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
  const forecast = forBoat(raw);
  const now = new Date();
  const stale = isStale(forecast, now);
  const hour = currentHour(forecast.hours, now);
  const warnings = forecast.warnings;
  const showWarnings = warnings && (warnings.status !== "ok" || !localChecked(warnings) || warnings.items?.length);
  // The cards in the order chosen under "Arrange this page".
  const cards = {
    conditions: () => withTip(conditionsCard(forecast, hour, radarAt(club?.launchPoint)), "conditionsExtras"),
    // Off by default: the rain tile shows the radar; "Arrange this page" switches the card on.
    radar: () => (club?.launchPoint ? radarCard(club.launchPoint) : ""),
    lakeView: () => (forecast.lakeId ? `<section class="card" id="lake-view" hidden></section>` : ""),
    hourly: () => withTip(hourlyCard(forecast, now, stale), "hourly"),
    launchPoint: () => (club?.launchPoint ? withTip(launchPointCard(club), "launchPoint") : ""),
    satellite: () => `<section class="card" id="satellite" hidden></section>`,
  };
  root.querySelector("main").innerHTML = `
    ${clubHeader(club, name, isHome, forecast, stale)}
    ${saved ? "" : `<button class="primary wide" id="add">${icon("plus")} ${h(t("Add to my clubs"))}</button>`}
    ${nowCard(forecast, hour, { stale, radar: radarAt(club?.launchPoint) })}
    ${tip("topTile")}
    ${(waterForHour(raw, hour) ?? 99) < COLD.waterC ? tip("coldWater") : ""}
    ${showWarnings ? warningsCard(warnings, club, forecast.generatedAt) : ""}
    <div class="cards">${visibleCards(layoutFor(id)).map((c) => cards[c]?.() ?? "").join("")}</div>
    ${tip("source")}
    ${sourceLine(forecast)}
    <button class="pill" id="arrange">${icon("arrow-up-down")} ${h(t("Arrange this page"))}</button>
    ${credits(forecast, club)}
    ${footerLinks()}`;
  root.querySelector("nav.bottom").outerHTML = bottomBar(id, raw);
  wireBottomBar(raw);
  wireClubPage(id, club, raw, forecast, hour);
  wireTips(root.querySelector("main"));
  balanceCards();
  if (root.querySelector("#launch-map")) showLaunchMap(club);
  wireRadarCard(root.querySelector("#radar"), club?.launchPoint);
  followRadar(club?.launchPoint, () => shown === clubRenders && root.querySelector("main.club") != null, () => showRadar(club, forecast, hour));
  const satelliteBox = root.querySelector("#satellite");
  if (forecast.lakeId && satelliteBox) satelliteCard(satelliteBox, forecast.lakeId, id, balanceCards);
  const lakeBox = root.querySelector("#lake-view");
  if (lakeBox) {
    fillLakeCard(lakeBox, forecast.lakeId, id, waterForHour(raw, hour)).then(() => {
      if (!lakeBox.hidden) lakeBox.querySelector(".card-title")?.insertAdjacentHTML("afterend", tip("lakeView"));
      balanceCards();
    });
  }
}

/** A new radar reading: the rain tile, the top tile's rain value and the radar card follow it (RadarStore). */
function showRadar(club, forecast, hour) {
  const radar = radarAt(club?.launchPoint);
  const replace = (el, html) => {
    if (!el) return;
    const fresh = document.createElement("div");
    fresh.innerHTML = html;
    el.innerHTML = fresh.firstElementChild.innerHTML;
  };
  replace(root.querySelector('.card:not(.now) [data-tile="precipitation"]'), conditionTile("precipitation", forecast, hour, radar));
  const cell = root.querySelector(".card.now .now-rain");
  if (cell) cell.innerHTML = rainCell(conditionData(forecast, hour, radar));
  const box = root.querySelector("#radar");
  if (box && club?.launchPoint) {
    box.innerHTML = radarCardBody(club.launchPoint);
    wireRadarCard(box, club.launchPoint);
  }
  balanceCards();
}

// ---- Wide screens (iPad, Mac, PC), as in the app on iPad ------------------------------------

/** The list beside the club page from this size on (RootView's side list). */
const sideList = matchMedia("(min-width: 860px) and (min-height: 560px)");
sideList.addEventListener("change", () => location.hash.startsWith("#/club/") && route(false));

/** From this width the page's cards go into two columns (LocationPageView.twoColumnWidth). */
const TWO_COLUMNS = 600;

/** The saved clubs as rows beside the page, the shown one marked. */
function sideRows(currentId) {
  return `<header class="side-head"><h2>${h(t("Locations"))}</h2><a class="link" href="#/list">${h(t("Edit"))}</a></header>
    <ul class="rows">${store.clubs.map((c, i) => `<li><a class="row ${c.id === currentId ? "current" : ""}" href="#/club/${encodeURIComponent(c.id)}" data-id="${h(c.id)}">${rowSkeleton(c, i === 0)}</a></li>`).join("")}</ul>`;
}

/**
 * The cards in two columns on a wide page, each going to the shorter column
 * in turn (BalancedColumns in the app); one column on a narrow one.
 */
function balanceCards() {
  const box = root.querySelector(".cards");
  if (!box) return;
  // Always in page order, never in the columns' order from the last sorting.
  const cards = [...box.querySelectorAll(".card")];
  cards.forEach((card, i) => (card.dataset.order ??= i));
  cards.sort((a, b) => a.dataset.order - b.dataset.order);
  // Keep the page's height while the cards move: emptied, it would be shorter
  // than the window and Safari, which has no scroll anchoring, jumps to the top.
  const scroller = document.scrollingElement;
  const y = scroller.scrollTop;
  box.style.minHeight = `${box.offsetHeight}px`;
  requestAnimationFrame(() => {
    box.style.minHeight = "";
    if (scroller.scrollTop !== y) scroller.scrollTop = y;
  });
  box.replaceChildren();
  box.classList.toggle("two", box.clientWidth >= TWO_COLUMNS);
  if (!box.classList.contains("two")) {
    cardWatch?.disconnect();
    box.append(...cards);
    return fitSatellite();
  }
  const columns = [document.createElement("div"), document.createElement("div")];
  columns.forEach((c) => (c.className = "col"));
  box.append(...columns);
  for (const card of cards) {
    const shorter = columns[1].offsetHeight < columns[0].offsetHeight ? columns[1] : columns[0];
    shorter.append(card);
  }
  // The columns set the card's width, and with it the caption's lines.
  fitSatellite();
  watchCards(cards);
}

let cardWatch = null;
let rebalance = 0;

/**
 * Sorts the cards again whenever one changes height (a picture or the lake
 * view finishing loading), so the columns always follow the cards' final
 * heights in page order, as the app's layout does, and never the order in
 * which their data happened to arrive.
 */
function watchCards(cards) {
  cardWatch?.disconnect();
  // The heights the columns were sorted by.
  const heights = new Map(cards.map((card) => [card, card.offsetHeight]));
  cardWatch = new ResizeObserver((entries) => {
    if (!entries.some(({ target }) => heights.get(target) !== target.offsetHeight)) return;
    if (!cards[0]?.isConnected) return cardWatch.disconnect();
    cancelAnimationFrame(rebalance);
    rebalance = requestAnimationFrame(balanceCards);
  });
  cards.forEach((card) => cardWatch.observe(card));
}

let resizeTimer = null;
window.addEventListener("resize", () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => {
    fitSatellite();
    const box = root.querySelector(".cards");
    if (box && box.classList.contains("two") !== box.clientWidth >= TWO_COLUMNS) balanceCards();
  }, 150);
});

function clubHeader(club, name, isHome, forecast, stale = false) {
  const slow = forecast?.refresh && forecast.refresh.used === false;
  return `<header class="club-head">
    ${isHome ? `<p class="home">${icon("house")} ${h(t("Home base"))}</p>` : ""}
    <h1>${h(name)}</h1>
    <p class="sub">${h(place(club?.lakeName, town(club?.address), lakeTitle))}</p>
    ${club && club.launchPointVerified === false ? `<p class="orange small">${icon("map-pin-off")} ${h(t("Launch point not yet confirmed"))}</p>` : ""}
    ${isOwn(club?.id) ? `<p class="sub small own-note">${icon("map-pin")} ${h(t("Your own place, kept in this browser. No waves, water temperature or warnings here."))}</p>` : ""}
    ${forecast ? (stale
      ? `<p class="orange small">${icon("clock")} ${h(t("Forecast out of date: from %@. Check the conditions yourself.", dayTime(forecast.generatedAt)))}</p>`
      : `<p class="sub small">${h(t("Updated %@", time(forecast.generatedAt)))} · <button class="link" id="refresh">${h(t("Refresh"))}</button></p>`) : ""}
    ${slow ? `<p class="sub small">${icon("hourglass")} ${h(t("Nobody opened this club lately, so it updates less often. From the next server update, within about 30 minutes, it updates every half hour."))}</p>` : ""}
  </header>`;
}

function wireClubPage(id, club, raw, forecast, hour) {
  root.querySelector("#refresh")?.addEventListener("click", () => renderClub(id));
  root.querySelector("#arrange").addEventListener("click", () => openArrange(club ?? { id }, () => renderClub(id)));
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
    openSheet(warningsIsDWD(forecast.warnings) ? t("DWD warnings") : t("Official warnings"), warningsBody(forecast.warnings, club, forecast.generatedAt, true));
  });
  root.querySelectorAll("[data-tile]").forEach((b) => b.addEventListener("click", () => {
    location.hash = `#/club/${encodeURIComponent(id)}/value/${b.dataset.tile}`;
  }));
  root.querySelectorAll("[data-hour]").forEach((b) => b.addEventListener("click", () => {
    const at = forecast.hours.find((x) => x.time === b.dataset.hour);
    // Within the radar's 2 hours the rain values come from the radar, later from the forecast.
    const radar = radarAt(club?.launchPoint);
    openSheet(dayTime(at.time), nowCard(forecast, at, { at: new Date(at.time), stale: isStale(forecast), radar }) + conditionsCard(forecast, at, radar), (sheet) => {
      // A value from a later hour opens its page at that hour.
      sheet.querySelectorAll("[data-tile]").forEach((t2) => t2.addEventListener("click", () => {
        location.hash = `#/club/${encodeURIComponent(id)}/value/${t2.dataset.tile}/${encodeURIComponent(at.time)}`;
      }));
    });
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
    if (Math.abs(dx) > 70 && Math.abs(dx) > 2 * Math.abs(dy) && !e.target.closest(".hourly, .map, .side")) go(dx < 0 ? 1 : -1);
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
function nowCard(forecast, hour, { stale = false, at = null, radar = null } = {}) {
  const water = forecast.waterTemperature;
  const estimate = estimatedWater(forecast);
  const kind = sky(hour.weatherCode);
  const boat = t("For %@", boatInSentence(selectedBoat()));
  const reasons = hour.reasons ?? [];
  const ice = iceValue(forecast);
  const warnings = forecast.warnings;
  const sun = sunState(forecast, at ?? new Date());
  const waterReasons = REASONS.waterTemperature;
  // The water at the shown hour: now the reading or estimate, later the water forecast.
  const latest = water?.celsius ?? estimate;
  const hourWater = at ? forecast.waterForecast?.find((d) => d.date === localDay(hour.time))?.celsius ?? latest : latest;
  const kit = coldWaterKit(hourWater, currentLimits());
  const steadier = steadierBoat(hour, hourWater, store.boats, store.boat, boatLimits);
  const d = conditionData(forecast, hour, radar);
  // The waves line in fewer words than the tile's, so it fits under the value in German too.
  const fetch = hour.fetchM;
  const wavesCaption = fetch == null ? "" : fetch < 50 ? t("Offshore wind") : t("%@ open water", distance(fetch));
  const fogNow = (hour.visibilityM ?? Infinity) < 1000;
  const fog = d.next24.find((x) => (x.visibilityM ?? Infinity) < 1000);
  const visibilityCaption = fogNow ? t("Fog") : fog ? t("Fog from %@", time(fog.time)) : t("No fog");
  const iceLine = forecast.ice ? iceDetail(forecast.ice) : t("Check the lake yourself");
  // As wide as its longest direction ("from NW"), so the column keeps one width whatever the wind does.
  const unitLine = (deg) => windUnit() + (deg != null ? ` · ${t("from %@", compass(deg))}` : "");
  return `<section class="card now">
    <div class="now-head">
      ${dot(hour.light, 36, stale)}
      <div class="now-title">
        <h2>${h(lightTitle(hour.light, stale))} ${at ? "" : `<button class="info" data-legend="lights" aria-label="${h(t("What the symbols mean"))}">${icon("info")}</button>`}</h2>
        ${at ? `<small class="sub">${h(boat)}</small>` : `<button class="boat-line" id="boat-line">${h(boat)} ${icon("chevrons-up-down")}</button>`}
      </div>
      <div class="now-sky">${skySymbol(hour, "large")}<small class="sub">${h(t(SKY_TITLES[kind]))}</small></div>
    </div>
    ${kit ? coldWaterBadge(kit, water == null) : ""}
    <ul class="reasons">
      ${stale && !at ? `<li class="orange">${icon("clock")}<span>${h(t("The forecast is more than 3 hours old. Check the conditions yourself before you go out."))}</span></li>` : ""}
      ${reasons.length ? reasons.map((r) => {
        const text = water == null && waterReasons.includes(r.condition) ? t("Estimated: %@", reasonExplanation(r.condition, r.light)) : hourExplanation(forecast, r, hour);
        return `<li class="${r.light === "red" ? "red" : "orange"}">${icon(CONDITION_ICONS[reasonCondition(r.condition)])}<span>${h(text)}</span></li>`;
      }).join("") : `<li>${icon("circle-check")}<span>${h(t("All conditions are within the limits."))}</span></li>`}
      ${(hour.notes ?? []).map((n) => `<li class="sub">${icon("info")}<span>${h(noteText(n))}</span></li>`).join("")}
      ${steadier ? `<li class="tint">${icon("sailboat")}<span>${h(steadier.light === "green"
        ? t("A steadier boat helps: %@ would be green now.", boatTitle(steadier.boat))
        : t("A steadier boat helps: %@ would only need care now.", boatTitle(steadier.boat)))}</span></li>` : ""}
      ${!at && warnings?.status === "ok" && localChecked(warnings) && !warnings.items?.length ? `<li><button class="no-warning" id="no-warning"><span class="green">${icon("shield-check")} ${h(warningsIsDWD(warnings) ? t("No DWD warning") : t("No official warning"))}</span>
        <span class="sub">· ${h(t("checked %@", time(forecast.generatedAt)))}</span> <span class="tint">${icon("info")}</span></button></li>` : ""}
    </ul>
    ${adviceOnly()}
    <hr>
    <div class="now-grid">
      <div class="air">
        <small class="label">${conditionIcon("temperature")} ${h(t("Air"))}</small>
        <span class="v44">${h(degrees(hour.temperatureC))}</span>
        ${hour.apparentTemperatureC != null ? `<small class="sub grey">${icon("person-standing")} ${h(t("Feels like %@", degrees(hour.apparentTemperatureC)))}</small>` : ""}
      </div>
      <div class="${water == null && estimate != null ? "secondary" : ""}">
        <small class="label">${conditionIcon("waterTemperature")} ${h(t("Water"))}</small>
        <span class="v28">${h(water == null && estimate != null ? degrees(estimate) : degrees(water?.celsius, 1))}</span>
        <small class="sub grey">${h(water ? t("Measured %@", time(water.measuredAt)) : estimate != null ? t("Estimated") : " ")}</small>
      </div>
      <div>
        <small class="label">${conditionIcon("wind")} ${h(t("Wind"))}</small>
        <span class="v28">${h(windRange(hour.windSpeedMs, hour.windGustMs))}${hour.windFromDeg != null ? `<span class="arrow" style="transform:rotate(${hour.windFromDeg + 180}deg)">${icon("arrow-up")}</span>` : ""}</span>
        <small class="sub stack">${[0, 45, 90, 135, 180, 225, 270, 315].map((deg) => `<span aria-hidden="true">${h(unitLine(deg))}</span>`).join("")}<span>${h(unitLine(hour.windFromDeg))}</span></small>
      </div>
      <div>
        <small class="label">${conditionIcon("waves")} ${h(t("Waves"))}</small><span class="v17">${h(waves(hour.waveHeightM))}</span>
        ${wavesCaption ? `<small class="sub grey">${h(wavesCaption)}</small>` : ""}
      </div>
      <div class="now-rain">${rainCell(d)}</div>
      <div>
        <small class="label">${conditionIcon("visibility")} ${h(t("Visibility"))}</small><span class="v17">${h(distance(hour.visibilityM))}</span>
        <small class="sub grey">${h(visibilityCaption)}</small>
      </div>
    </div>
    ${ice ? `<p class="ice-line"><small class="label">${conditionIcon("ice")} ${h(t("Ice"))}</small><span class="v17">${h(t(ice))}</span>
      <small class="sub">${h(iceLine === t("Bays and harbours first") ? t("Bays first") : iceLine)}</small></p>` : ""}
    ${sun ? `<p class="daylight">${sun.up
      ? `${sunPath(sun.sunrise, sun.sunset, at ?? new Date(), 44, 22)}<span>${h(t("Sunset %@ · %@ of daylight left", time(sun.sunset), duration(at ?? new Date(), sun.sunset)))}</span>`
      : `<span class="moon">${icon("moon-star")}</span><span>${h(t("Sun is down · rowing advised again from %@", time(sun.sunrise)))}</span>`}</p>` : ""}
  </section>`;
}

/** The top tile's rain value with the rain tile's line under it, so both always say the same. */
function rainCell(d) {
  const lines = rainLines(d);
  const caption = lines.detail === t("Dry next 24 h") ? t("Dry for 24 h") : lines.detail;
  return `<small class="label">${conditionIcon("precipitation")} ${h(t("Rain, hail"))}</small><span class="v17">${h(lines.value)}</span>
    ${caption ? `<small class="sub grey">${lines.fromRadar ? radarMark() : ""}${h(caption)}</small>` : ""}`;
}

/** The DWD warnings card, shown while a warning is out or DWD could not be checked (WarningsCard). */
function warningsCard(warnings, club, checkedAt) {
  const title = localChecked(warnings) && warningsIsDWD(warnings) ? t("DWD warnings") : t("Official warnings");
  return card(title, "triangle-alert", warningsBody(warnings, club, checkedAt, false), { cls: "warnings" });
}

/** False outside Germany, where DWD does not warn: then "no warning" must not be said. Older files lack `local`. */
function localChecked(warnings) {
  return warnings?.local?.checked !== false;
}

/** True while the place's warnings are DWD's (Germany, and older files); else labels say "official". */
function warningsIsDWD(warnings) {
  return (warnings?.local?.source ?? "dwd") === "dwd";
}

function isDWD(w) {
  return (w.source ?? "dwd") === "dwd";
}

/** "DWD", "GeoSphere" or "MeteoSwiss", for labels such as "GeoSphere warning: Wind". */
function serviceShort(source) {
  return { geosphere: "GeoSphere", meteoswiss: "MeteoSwiss" }[source] ?? "DWD";
}

/** Outside Germany: the place's own weather service warns, and Row Frog does not read it yet. */
function notCheckedNote(local) {
  const service = local?.service ?? t("the national weather service");
  return `<p class="orange">${icon("circle-alert")} ${h(t("Row Frog cannot check the weather warnings for this place yet. Check %@ before going out.", service))}</p>
    ${local?.url ? `<p><a class="strong" href="${h(local.url)}" target="_blank" rel="noopener">${icon("globe")} ${h(t("Open the warnings of %@", service))}</a></p>` : ""}`;
}

function warningsBody(warnings, club, checkedAt, guideOpen) {
  if (warnings.status !== "ok") {
    return `<p class="orange">${icon("wifi-off")} ${h(warningsIsDWD(warnings)
      ? t("Warnings could not be loaded. Check dwd.de or the shore lights before going out.")
      : t("Warnings could not be loaded. Check %@ or the shore lights before going out.", warnings.local?.service ?? "DWD"))}</p>`;
  }
  const place = town(club?.address);
  if (!localChecked(warnings)) {
    const lakeRows = (warnings.items ?? []).filter((w) => w.kind === "lake").map(warningRow).join("");
    const where = place ?? t("this place");
    const note = warnings.lakeArea
      ? t("Covers the DWD lake warning for %@. Weather warnings for %@ are not checked yet.", warnings.lakeArea, where)
      : t("Lake and weather warnings for %@ are not checked yet.", where);
    return `${lakeRows}${notCheckedNote(warnings.local)}<p class="sub small">${h(note)}</p>${warnings.lakeArea ? shoreLights(guideOpen) : ""}`;
  }
  const placeText = place ? t("weather warnings for %@", place) : t("weather warnings for this place");
  const service = warnings.local?.service ?? "";
  const coverage = !warningsIsDWD(warnings)
    ? warnings.lakeArea
      ? t("Covers the DWD lake warning for %@ and the warnings of %@ for %@.", warnings.lakeArea, service, place ?? t("this place"))
      : t("Covers the warnings of %@ for %@. Lake warnings for this water are not published for apps.", service, place ?? t("this place"))
    : warnings.lakeArea
      ? t("Covers the DWD lake warning for %@ and %@.", warnings.lakeArea, placeText)
      : t("DWD has no lake warning service %@. Covers %@.", club?.lakeName ? t("for %@", lakeTitle(club.lakeName)) : t("for this water"), placeText);
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
    ${english ? text(w.english.headline, w.english.description ?? (isDWD(w)
        ? t("DWD publishes the details of this warning in German only; see the original below.")
        : t("The details of this warning are in German only; see the original below.")), w.english.instruction)
      + `<div class="original" lang="de"><p class="strong">${h(isDWD(w) ? t("Original from DWD (German)") : t("Original from %@ (German)", serviceShort(w.source)))}</p><p class="strong">${h(w.headline)}</p><p>${h(w.description)}</p>${w.instruction ? `<p>${h(w.instruction)}</p>` : ""}</div>`
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
function conditionsCard(forecast, hour, radar = null) {
  const kind = sky(hour.weatherCode);
  const head = `<div class="cc-head">${skySymbol(hour, "large")}<div><strong>${h(t(SKY_TITLES[kind]))}</strong>
    <small class="sub">${h(t("%@ · feels like %@", degrees(hour.temperatureC), degrees(hour.apparentTemperatureC)))}</small></div></div>`;
  const tiles = TILE_ORDER.map((c) => conditionTile(c, forecast, hour, radar)).join("");
  return card(t("Current conditions"), "gauge", `${head}<div class="tiles">${tiles}</div>`, { legend: "conditions" });
}

function conditionTile(condition, forecast, hour, radar = null) {
  const i = forecast.hours.indexOf(hour);
  const next24 = forecast.hours.slice(Math.max(0, i), Math.max(0, i) + 24);
  const titles = conditionTexts();
  const graphic = conditionGraphic(condition, forecast, hour);
  const light = REASONS[condition] ? lightFor(hour, REASONS[condition]) : null;
  const header = (title) => `<span class="tile-head">${conditionIcon(condition)}<span>${h(title)}</span>${light && light !== "green" ? dot(light, 8) : ""}${icon("chevron-right")}</span>`;
  // `mark`: rain read from the radar starts its line with the radar's symbol.
  const tile = (value, detail, graphic = "", off = false, mark = "") => `<button class="tile ${off ? "off" : ""}" data-tile="${condition}">
    ${header(titles[condition][1])}
    <span class="tile-body"><span><strong>${h(value)}</strong><small>${mark}${h(detail)}</small></span><span class="graphic">${graphic}</span></span></button>`;
  const water = forecast.waterTemperature;
  const estimate = estimatedWater(forecast);
  const temps = next24.map((x) => x.temperatureC).filter((v) => v != null);
  switch (condition) {
    case "temperature":
      return tile(degrees(hour.temperatureC), temps.length ? t("High %@ · low %@", degrees(Math.max(...temps)), degrees(Math.min(...temps))) : "", graphic);
    case "feelsLike":
      return tile(degrees(hour.apparentTemperatureC), feelsLikeNote(hour) ? t(feelsLikeNote(hour)) : "", graphic);
    case "wind": {
      const gust = t("Gusts %@", windNumber(hour.windGustMs));
      return tile(wind(hour.windSpeedMs), hour.windFromDeg != null ? `${gust} · ${t("from %@", compass(hour.windFromDeg))}` : gust, graphic);
    }
    case "waves": {
      const fetch = hour.fetchM;
      return tile(waves(hour.waveHeightM), fetch == null ? "" : fetch < 50 ? t("Wind blows off the shore") : t("%@ open water upwind", distance(fetch)), graphic);
    }
    case "waterTemperature": {
      const value = water == null && estimate != null ? `≈ ${degrees(estimate)}` : degrees(water?.celsius, 1);
      const detail = water == null && estimate != null ? (forecast.waterEstimate ? t("Satellite estimate") : t("Estimated, not measured"))
        : water ? t("Measured %@", time(water.measuredAt)) : t("No lake station");
      return tile(value, detail, graphic);
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
      // DWD's radar for the next two hours, then the forecast.
      const d = conditionData(forecast, hour, radar);
      const lines = rainLines(d);
      return tile(lines.value, lines.detail, radarGraphic(d) ?? graphic, false, lines.fromRadar ? radarMark() : "");
    }
    case "thunderstorm": {
      const level = light === "red" ? 3 : light === "amber" ? 2 : 1;
      const storm = (forecast.warnings?.items ?? []).some((w) => /GEWITTER/i.test(w.event ?? ""));
      const note = !localChecked(forecast.warnings) ? t("Warnings not checked")
        : !warningsIsDWD(forecast.warnings) ? (storm ? t("Official warning") : t("No warning"))
        : storm ? t("DWD warning") : t("No DWD warning");
      return tile({ 3: t("High"), 2: t("Possible"), 1: t("Low") }[level], note, graphic);
    }
    case "visibility": {
      let detail;
      if ((hour.visibilityM ?? Infinity) < 1000) detail = t("Fog");
      else {
        const fog = next24.find((x) => (x.visibilityM ?? Infinity) < 1000);
        detail = fog ? t("Fog from %@", time(fog.time)) : t("No fog");
      }
      return tile(distance(hour.visibilityM), detail, graphic);
    }
    case "cloudCover":
      return tile(`${num(hour.cloudCoverPct)} %`, hour.cloudCoverLowPct != null ? t("Low cloud %@ %%", num(hour.cloudCoverLowPct)) : "", graphic);
    case "humidity":
      return tile(hour.humidityPct == null ? "–" : `${num(hour.humidityPct)} %`, hour.dewPointC != null ? t("Dew point %@", degrees(hour.dewPointC)) : "", graphic);
    case "pressure": {
      const change = pressureChange(forecast.hours, hour);
      const trend = change == null ? null : pressureTrend(change);
      return tile(pressureNumber(hour.pressureHpa), trend ? `${unitSymbol("pressure")} · ${t(trend).toLowerCase()}` : unitSymbol("pressure"), graphic);
    }
    case "uvIndex": {
      const withUv = next24.filter((x) => x.uvIndex != null);
      const top = withUv.length ? withUv.reduce((a, b) => (b.uvIndex > a.uvIndex ? b : a)) : null;
      return tile(num(hour.uvIndex), top ? t("Max %@ · %@", num(top.uvIndex), dayLabel(top.time)) : "", graphic);
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


/** The next 48 hours, a row an hour under a day header with sunrise and sunset (HourlyCard). */
function hourlyCard(forecast, now, stale) {
  const list = nextHours(forecast.hours, now, 48);
  const head = `<div class="hrow hhead">
    <span>${icon("clock")}</span><span>${dot("grey", 8)}</span><span>${icon("cloud-sun")}</span>
    ${[["temperature", unitSymbol("temperature")], ["feelsLike", unitSymbol("temperature")], ["wind", windUnit()], ["waves", unitSymbol("waves")],
      ["precipitation", unitSymbol("rain")], ["visibility", unitSymbol("distance")]]
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
      <span class="num">${h(num(inUnit("temperature", x.temperatureC)))}</span>
      <span class="num sub">${h(num(inUnit("temperature", x.apparentTemperatureC)))}</span>
      <span class="num">${h(windRange(x.windSpeedMs, x.windGustMs))}</span>
      <span class="num">${h(wavesNumber(x.waveHeightM))}</span>
      <span class="num ${(x.precipitationMm ?? 0) >= 0.1 ? "blue" : ""}">${h(rainNumber(x.precipitationMm))}</span>
      <span class="num ${fog && fog !== "green" ? (fog === "red" ? "red" : "orange") : ""}">${h(distanceNumber(x.visibilityM))}</span>
    </button>`;
  }).join("");
  return card(t("Next 48 hours"), "clock", `<div class="hourly ${usesAMPM() ? "ampm" : ""}">${head}${rows}</div>`, { legend: "hourly", cls: "hourly-card" });
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

/**
 * Sizes the satellite picture so its whole card fits the window above the
 * bottom bar, never wider than the card. Runs again on every resize or turn.
 */
function fitSatellite() {
  const picture = root.querySelector("#satellite .picture");
  if (!picture) return;
  const card = picture.closest(".card");
  const chrome = card.offsetHeight - picture.offsetHeight;
  const bar = document.querySelector(".bottom")?.offsetHeight ?? 0;
  const height = Math.max(240, window.innerHeight - bar - chrome - 32);
  picture.style.width = `min(100%, ${Math.round(height * Number(picture.dataset.ratio))}px)`;
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

/** Settings › Language and units › Units, with each value's icon. */
const UNIT_ROWS = [
  ["temperature", "temperature", key("Air and water temperature")], ["wind", "wind", key("Wind and gusts")], ["waves", "waves", key("Waves")],
  ["rain", "precipitation", key("Rain, hail, snow")], ["distance", "visibility", key("Visibility and distances")], ["pressure", "pressure", key("Air pressure")],
];
const TIME_TITLES = { device: key("Device"), h24: key("24-hour"), h12: key("12-hour") };
const DATE_TITLES = { device: key("Device"), long: key("Long"), short: key("Short"), dmy: key("Day.Month.Year"), mdy: key("Month/Day/Year") };
// 18:30 in the lakes' time zone, to show each time format.
const SAMPLE_TIME = Date.UTC(2026, 0, 15, 17, 30);

function renderSettings() {
  setTitle(t("Settings"));
  const accepted = store.safety?.at ? new Intl.DateTimeFormat(locale(), { dateStyle: "long" }).format(new Date(store.safety.at)) : null;
  const back = store.clubs[0] ? `#/club/${encodeURIComponent(store.clubs[0].id)}` : "#/list";
  root.innerHTML = `
    <header class="nav"><span class="spacer"></span><a class="link strong" href="${back}">${h(t("Done"))}</a></header>
    ${testing()}
    <main class="page">
      <h1 class="large">${h(t("Settings"))}</h1>
      <section class="card group">
        <a class="row-setting" href="#/settings/boats"><span>${icon("sailboat")} ${h(t("Boats and limits"))}</span>
          <span class="sub">${h(boatTitle(selectedBoat()))} ${icon("chevron-right")}</span></a>
      </section>
      <h3 class="section">${icon("sun-moon")} ${h(t("Appearance"))}</h3>
      <section class="card group">
        <div class="row-setting"><span class="segmented wide" id="appearance">${[["device", t("Device")], ["light", t("Light")], ["dark", t("Dark")]]
          .map(([k, label]) => `<button data-appearance="${k}" class="${store.appearance === k ? "on" : ""}">${h(label)}</button>`).join("")}</span></div>
      </section>
      <p class="footer">${h(t("Device follows the light or dark setting of your computer or phone."))}</p>
      <h3 class="section">${icon("languages")} ${h(t("Language"))}</h3>
      <section class="card group">${languagePicker()}</section>
      <h3 class="section">${icon("ruler")} ${h(t("Units"))}</h3>
      <section class="card group">${UNIT_ROWS.map(([kind, condition, title]) => `<label class="row-setting"><span>${conditionIcon(condition)} ${h(t(title))}</span>
          <select data-unit="${kind}">${Object.entries(UNITS[kind].options).map(([id, u]) => `<option value="${id}" ${id === unitId(kind) ? "selected" : ""}>${h(`${t(u.label)} · ${t(u.title)}`)}</option>`).join("")}</select></label>`).join("")}
      </section>
      <p class="footer">${h(t("Cloud cover stays in percent."))}</p>
      <h3 class="section">${icon("calendar-clock")} ${h(t("Date and time"))}</h3>
      <section class="card group">
        <label class="row-setting"><span>${icon("clock")} ${h(t("Time"))}</span>
          <select id="time-format">${TIME_FORMATS.map((f) => `<option value="${f}" ${f === store.timeFormat ? "selected" : ""}>${h(`${t(TIME_TITLES[f])} · ${time(SAMPLE_TIME, f)}`)}</option>`).join("")}</select></label>
        <label class="row-setting"><span>${icon("calendar")} ${h(t("Date"))}</span>
          <select id="date-format">${DATE_FORMATS.map((f) => `<option value="${f}" ${f === store.dateFormat ? "selected" : ""}>${h(`${f === "iso" ? "ISO 8601" : t(DATE_TITLES[f])} · ${dateText(localDay(new Date()), f)}`)}</option>`).join("")}</select></label>
      </section>
      <p class="footer">${h(t("Device follows the browser's settings. Today and tomorrow are always written as words."))}</p>
      <h3 class="section">${icon("arrow-up-down")} ${h(t("Club pages"))}</h3>
      <section class="card group">
        <button class="row-setting" id="arrange"><span>${h(t("Order of the club page cards"))}</span>${icon("chevron-right")}</button>
      </section>
      <p class="footer">${h(t("The order set here is for all clubs. A club can have its own from \"Arrange this page\" at the end of its page."))}</p>
      <section class="card group">
        <a class="row-setting" href="#/settings/backgrounds"><span class="stack"><span>${h(t("Background pictures"))}</span><small class="sub">${h(backgroundSummary())}</small></span>${icon("chevron-right")}</a>
      </section>
      <p class="footer">${h(t("Pictures for all pages, single pages or single clubs, and how the tiles look over them."))}</p>
      <h3 class="section">${icon("map")} ${h(t("Weather maps"))}</h3>
      <section class="card group">
        <div class="row-setting"><span>${h(t("Maps start"))}</span>
          <span class="segmented small" id="map-zoom">${[["close", lang() === "de" ? t("Close (map zoom)") : "Close"], ["normal", t("Normal")], ["wide", t("Wide")]]
            .map(([k, label]) => `<button data-zoom="${k}" class="${store.mapZoom === k ? "on" : ""}">${h(label)}</button>`).join("")}</span></div>
      </section>
      <p class="footer">${h(t("The weather maps in the detail views open %@ across around the club, rain and lightning %@. Zooming out loads more.",
        distance(50000 * (MAP_ZOOMS[store.mapZoom] ?? 1)), distance(120000 * (MAP_ZOOMS[store.mapZoom] ?? 1))))}</p>
      <h3 class="section">${icon("arrow-up-down")} ${h(t("Data use"))}</h3>
      <section class="card group">
        <label class="row-setting"><span>${icon("radio-tower")} ${h(t("Save mobile data"))}</span><input type="checkbox" class="switch" id="save-data" ${store.saveData ? "checked" : ""}></label>
        ${dataSaving() ? `<p class="row-setting green small">${icon("circle-check")} ${h(dataSaving() === "browser" ? t("Your browser asks to save data: the website is saving data now.") : t("On mobile data: the website is saving data now."))}</p>` : ""}
      </section>
      <p class="footer">${h(t("On mobile data, satellite pictures load only when you tap them; forecasts and warnings always load. When your browser or phone asks to save data, the website always does. Not every browser tells the website whether it is on mobile data."))}</p>
      <h3 class="section">${icon("circle-help")} ${h(t("Help"))}</h3>
      <section class="card group">
        <a class="row-setting" href="#/tour"><span>${icon("circle-help")} ${h(t("Show the tour again"))}</span>${icon("chevron-right")}</a>
        <button class="row-setting" id="tips-again"><span>${icon("lightbulb")} ${h(t("Show the tips again"))}</span></button>
        <button class="row-setting" id="legend"><span>${icon("info")} ${h(t("Legend: what the symbols mean"))}</span>${icon("chevron-right")}</button>
      </section>
      <p class="footer" id="tips-note"></p>
      ${card(t("Safety notice"), "shield-check", `${safetyList()}${accepted ? `<p class="sub">${h(t("You accepted this notice on %@.", accepted))}</p>` : ""}`)}
      ${card(t("Stored in this browser"), "info", `<p>${h(t("Your clubs, settings and your acceptance of the safety notice stay in this browser. Nothing is sent anywhere."))}</p>
        <button id="reset" class="quiet">${h(t("Delete everything stored here"))}</button>`)}
      ${footerLinks()}
    </main>`;
  wireLanguage(renderSettings);
  root.querySelectorAll("[data-unit]").forEach((select) => select.addEventListener("change", () => setUnit(select.dataset.unit, select.value)));
  root.querySelector("#tips-again").addEventListener("click", () => {
    replayTips();
    root.querySelector("#tips-note").textContent = t("The tips are back.");
  });
  root.querySelector("#legend").addEventListener("click", () => openSheet(t("Legend"),
    ["lights", "conditions", "hourly"].map((part) => `<h3 class="section">${h({ lights: t("Rowing light"), conditions: t("Weather symbols"), hourly: t("The columns") }[part])}</h3>${legendBody(part)}`).join("")));
  root.querySelector("#save-data").addEventListener("change", (e) => {
    store.saveData = e.target.checked;
    renderSettings();
  });
  root.querySelector("#time-format").addEventListener("change", (e) => (store.timeFormat = e.target.value));
  root.querySelector("#date-format").addEventListener("change", (e) => (store.dateFormat = e.target.value));
  root.querySelectorAll("[data-appearance]").forEach((b) => b.addEventListener("click", () => {
    store.appearance = b.dataset.appearance;
    applyAppearance();
    renderSettings();
  }));
  root.querySelector("#arrange").addEventListener("click", () => openArrange(null));
  root.querySelectorAll("[data-zoom]").forEach((b) => b.addEventListener("click", () => {
    store.mapZoom = b.dataset.zoom;
    renderSettings();
  }));
  root.querySelector("#reset").addEventListener("click", () => {
    if (!confirm(t("Delete your clubs, settings and the accepted safety notice from this browser?"))) return;
    try {
      for (const name of Object.keys(localStorage)) if (name.startsWith("rf.")) localStorage.removeItem(name);
    } catch {}
    location.hash = "#/";
    route();
  });
}

// ---- Boats and limits (RowingLimitsView, BoatLimitsView) -------------------------------

const settingsNav = (back) => `<header class="nav"><a class="link" href="${back}">${icon("chevron-left")} ${h(t("Settings"))}</a><span class="spacer"></span></header>`;

function renderBoats() {
  setTitle(t("Rowing limits"));
  const row = (boat) => {
    const changed = Object.keys(store.limits[boat.id] ?? {}).length > 0;
    const on = store.boat === boat.id;
    return `<li class="boat-row"><button data-tick="${h(boat.id)}">
        <span><strong>${h(boatTitle(boat))}</strong><small class="${changed ? "orange" : ""}">${h(changed ? t("%@ · your limits", boatDetail(boat)) : boatDetail(boat))}</small></span>
        ${on ? icon("check") : ""}</button>
      <a class="round" href="#/settings/boat/${encodeURIComponent(boat.id)}" aria-label="${h(t("Limits for %@", boatTitle(boat)))}">${icon("sliders-horizontal")}</a></li>`;
  };
  root.innerHTML = `${settingsNav("#/settings")}${testing()}
    <main class="page">
      <h1 class="large">${h(t("Rowing limits"))}</h1>
      ${tip("myBoats")}
      <h3 class="section">${icon("sailboat")} ${h(t("Your boat"))}</h3>
      <ul class="boats">${GROUPS.map(row).join("")}</ul>
      <p class="footer">${h(t("The rowing light is for the boat with the tick, until you pick another. Big boats sit higher and steadier, so the app allows more wind and higher waves for them. Tap the sliders to fine-tune a boat's limits."))}</p>
      <h3 class="section">${icon("list")} ${h(t("My boats"))}</h3>
      <ul class="boats">${store.boats.map(row).join("")}
        <li><button id="add-boat" class="tint">${icon("circle-plus")} <span>${h(t("Add a boat"))}</span></button></li></ul>
      <p class="footer">${h(t("Add the boats you can row, such as the club's gig. Each has limits for its type. When it is too rough for the ticked boat, the app says which of your boats would be fine."))}</p>
      <h3 class="section">${icon("map")} ${h(t("Lake map colours"))}</h3>
      <ul class="boats">${[["follow", t("Same as the ticked boat")], ...allBoats().map((b) => [b.id, boatTitle(b)])].map(([id, title]) => `<li class="boat-row"><button data-map-boat="${h(id)}">
        <span><strong>${h(title)}</strong></span>${store.mapBoat === id ? icon("check") : ""}</button></li>`).join("")}</ul>
      ${allowsMore(mapLimits(), currentLimits()) ? `<p class="footer orange">${icon("triangle-alert")} ${h(t("The map uses the limits for %@, which are higher than those for %@. The map points this out too.", boatInSentence(mapBoat()), boatInSentence(selectedBoat())))}</p>` : ""}
      <p class="footer">${h(t("The boat whose limits colour the lake view and route planning."))}</p>
      ${footerLinks()}
    </main>`;
  root.querySelectorAll("[data-tick]").forEach((b) => b.addEventListener("click", () => {
    store.boat = b.dataset.tick;
    renderBoats();
  }));
  root.querySelectorAll("[data-map-boat]").forEach((b) => b.addEventListener("click", () => {
    store.mapBoat = b.dataset.mapBoat;
    renderBoats();
  }));
  root.querySelector("#add-boat").addEventListener("click", () => {
    const boat = { id: crypto.randomUUID?.() ?? `b${Date.now()}`, name: "", type: "gig", class: "4x" };
    store.boats = [...store.boats, boat];
    location.hash = `#/settings/boat/${encodeURIComponent(boat.id)}`;
  });
}

function renderBoat(id) {
  const boat = allBoats().find((b) => b.id === id);
  if (!boat) {
    location.hash = "#/settings/boats";
    return;
  }
  setTitle(boatTitle(boat));
  const limits = boatLimits(boat);
  const changed = Object.keys(store.limits[boat.id] ?? {}).length > 0;
  const option = (value, label, chosen) => `<option value="${h(value)}" ${value === chosen ? "selected" : ""}>${h(label)}</option>`;
  const limitRow = (limit) => {
    const mine = limits.isMine(limit);
    const usual = standardLimit(limit, boat);
    return `<div class="limit-row">
      <span class="limit-name">${conditionIcon(LIMITS[limit].condition)}<span><span>${h(t(LIMITS[limit].title))}</span>
        <small class="${mine ? "orange" : "sub"}">${h(mine ? t("Your limit · the app's: %@", limitText(limit, usual)) : t("The app's limit"))}</small></span></span>
      <strong class="num">${h(limitText(limit, limits.value(limit)))}</strong>
      <span class="stepper"><button data-step="${limit}" data-by="-1" aria-label="−">−</button><button data-step="${limit}" data-by="1" aria-label="+">+</button></span>
    </div>`;
  };
  root.innerHTML = `<header class="nav"><a class="link" href="#/settings/boats">${icon("chevron-left")} ${h(t("Rowing limits"))}</a><span class="spacer"></span></header>${testing()}
    <main class="page">
      <h1 class="large">${h(boatTitle(boat))}</h1>
      ${isGroup(boat) ? "" : `<h3 class="section">${icon("sailboat")} ${h(t("Boat"))}</h3>
        <section class="card group">
          <label class="row-setting"><input id="boat-name" type="text" value="${h(boat.name)}" placeholder="${h(t("Name, e.g. the boat's name"))}"></label>
          <label class="row-setting"><span>${h(t("Type"))}</span><select id="boat-type">${Object.entries(BOAT_TYPES).map(([k, v]) => option(k, t(v.title), boat.type)).join("")}</select></label>
          <label class="row-setting"><span>${h(t("Size and rigging"))}</span><select id="boat-class">${Object.entries(BOAT_CLASSES).map(([k, v]) => option(k, t(v), boat.class)).join("")}</select></label>
        </section>
        <p class="footer">${h(t(BOAT_TYPES[boat.type].detail))}</p>`}
      <h3 class="section">${icon("sliders-horizontal")} ${h(t("Fine-tune the limits"))}</h3>
      <section class="card group">${Object.keys(LIMITS).map(limitRow).join("")}
        ${changed ? `<button id="reset-limits" class="link">${h(t("Use the app's limits again"))}</button>` : ""}</section>
      <p class="footer">${h(`${t("A limit you change shows as “your limit” on the rowing light. When a value is above the app's usual limit but within yours, the app still says so. Official warnings, thunderstorms, fog, hail and darkness always count.")} ${t("Below %@ water the app lowers its own wind and gust limits by %@. Limits you set yourself stay as they are, and the rowing light then reminds you to take extra care.", temperature(COLD.waterC), wind(COLD.marginMs))}`)}</p>
      ${isGroup(boat) ? "" : `<button id="remove-boat" class="quiet red">${h(t("Remove this boat"))}</button>`}
      ${footerLinks()}
    </main>`;
  const update = (change) => {
    store.boats = store.boats.map((b) => (b.id === id ? { ...b, ...change } : b));
  };
  root.querySelector("#boat-name")?.addEventListener("input", (e) => update({ name: e.target.value }));
  root.querySelector("#boat-type")?.addEventListener("change", (e) => {
    update({ type: e.target.value });
    renderBoat(id);
  });
  root.querySelector("#boat-class")?.addEventListener("change", (e) => {
    update({ class: e.target.value });
    renderBoat(id);
  });
  root.querySelectorAll("[data-step]").forEach((b) => b.addEventListener("click", () => {
    const limit = b.dataset.step;
    const { step, range } = LIMITS[limit];
    const raw = limits.value(limit) + Number(b.dataset.by) * step;
    const clamped = Math.min(Math.max(Math.round(raw / step) * step, range[0]), range[1]);
    const all = store.limits;
    const custom = { ...(all[id] ?? {}) };
    // Back on the app's value: no longer the user's own.
    if (Math.abs(clamped - standardLimit(limit, boat)) < step / 2) delete custom[limit];
    else custom[limit] = Number(clamped.toFixed(2));
    if (Object.keys(custom).length) all[id] = custom;
    else delete all[id];
    store.limits = all;
    renderBoat(id);
  }));
  root.querySelector("#reset-limits")?.addEventListener("click", () => {
    const all = store.limits;
    delete all[id];
    store.limits = all;
    renderBoat(id);
  });
  root.querySelector("#remove-boat")?.addEventListener("click", () => {
    store.boats = store.boats.filter((b) => b.id !== id);
    const all = store.limits;
    delete all[id];
    store.limits = all;
    if (store.boat === id) store.boat = "small";
    if (store.mapBoat === id) store.mapBoat = "small";
    location.hash = "#/settings/boats";
  });
}


// ---- Routing -------------------------------------------------------------------------

/** As the app opens: the home base's page, or the list while there is no club yet. */
/** The background picture for the page the hash opens: club pages, the list and the settings have one. */
function pagePicture(hash) {
  const club = hash.match(/^\/club\/([^/]+)$/);
  if (club) return showBackground("clubPages", decodeURIComponent(club[1]));
  if (hash.startsWith("/settings")) return showBackground("settings");
  if (hash === "/list" || !store.clubs.length) return showBackground("list");
  if (!hash || hash === "/") return showBackground("clubPages", store.clubs[0].id);
  return showBackground(null);
}

function route(scroll = true) {
  swipeOff?.();
  document.querySelector("dialog.sheet")?.remove();
  document.querySelectorAll(".wm-full, .sat-full").forEach((x) => x.remove());
  document.body.classList.remove("locked");
  if (scroll) window.scrollTo(0, 0);
  if (!store.safety || store.safety.version < SAFETY_VERSION) return renderSafetyGate();
  // The tour once, after the safety notice, and again from Settings › Help.
  if (!tourSeen() || location.hash === "#/tour") {
    showBackground(null);
    return renderTour(root, { languagePicker, wireLanguage, done: () => (location.hash === "#/tour" ? (location.hash = "#/settings") : route()) });
  }
  const hash = location.hash.replace(/^#/, "");
  pagePicture(hash);
  const value = hash.match(/^\/club\/([^/]+)\/value\/([a-zA-Z]+)(?:\/(.+))?$/);
  if (value) return renderValuePage(root, decodeURIComponent(value[1]), value[2], value[3] ? decodeURIComponent(value[3]) : null);
  const club = hash.match(/^\/club\/(.+)$/);
  if (club) return renderClub(decodeURIComponent(club[1]));
  const lake = hash.match(/^\/lake\/([^/]+)(?:\/(.+))?$/);
  if (lake) {
    const clubId = lake[2] ? decodeURIComponent(lake[2]) : null;
    return renderLakeMap(root, decodeURIComponent(lake[1]), clubId, clubId ? `#/club/${encodeURIComponent(clubId)}` : "#/");
  }
  const add = hash.match(/^\/add-place(?:\?name=(.*))?$/);
  if (add) return renderAddPlace(root, add[1] ? decodeURIComponent(add[1]) : "");
  if (hash === "/countries") return renderCountries(root);
  const water = hash.match(/^\/countries\/([a-z]{2})\/(.+)$/);
  if (water) return renderWater(root, water[1], decodeURIComponent(water[2]));
  const country = hash.match(/^\/countries\/([a-z]{2})(?:\?q=(.*))?$/);
  if (country) return renderCountry(root, country[1], country[2] ? decodeURIComponent(country[2]) : "");
  if (hash === "/settings") return renderSettings();
  if (hash === "/settings/boats") return renderBoats();
  if (hash === "/settings/backgrounds") return renderBackgrounds(root);
  const boat = hash.match(/^\/settings\/boat\/(.+)$/);
  if (boat) return renderBoat(decodeURIComponent(boat[1]));
  if (hash === "/list" || !store.clubs.length) return renderList();
  return renderClub(store.clubs[0].id);
}

window.addEventListener("hashchange", () => route());
// Back on the page after a while: show fresh numbers.
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") forecasts.clear();
});

applyAppearance();
await setLanguage(savedLanguage());
route();
