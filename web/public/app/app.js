// Row Frog in the browser, laid out like the iPhone app: a page per club with
// the rowing light on top, the DWD warnings, the current conditions tiles, the
// next 48 hours, the launch point and the satellite picture, and the list of
// clubs with search. It reads the same published files as the app
// (api.rowfrog.com/v1). No account and no cookies: the chosen clubs, units,
// boat, language and the accepted safety notice stay in this browser.

import { t, num, locale, setLanguage, savedLanguage, resolve, lang } from "./i18n.js";
import { icon, filledIcon, skyArt } from "./icons.js";
import { baseMap } from "./basemap.js";
import {
  store, TILE_ORDER, conditionTexts, iceDetail, allBoats, tickedBoat, selectedBoat, isKept, boatsKeptAt, keepBoat, unkeepBoat, pickBoat, keepUnplacedBoats, setPageClub, pageClubId, clubNameOf, listJoin, boatLimits, currentLimits, boatTitle, boatInSentence,
  boatDetail, boatTag, boatControl, MAPS_APPS, limitText, forBoat, loadCatalog, findClub, forecasts, loadForecast, h, time, dayLabel, dayTime, duration,
  degrees, temperature, windUnit, windNumber, wind, windRange, wavesNumber, waves, rainNumber, rain, distanceNumber, distance,
  precipitationText, lightTitle, reasonLabel, warningInfoOnly, warningSlippery, lakeTitle, hourExplanation, noteText, reasonExplanation, coldWaterText,
  coldWaterBadge, setTitle, dot, skySymbol, CONDITION_ICONS, conditionIcon, conditionGraphic, card, sunPath, openSheet, openMenu,
  loadLeaflet, testing, adviceOnly, footerLinks, unitSymbol, inUnit, pressureNumber, usesAMPM, hourOnly,
  applyAppearance, unitId, setUnit, TIME_FORMATS, DATE_FORMATS, dateText, dataSaving, clubNameHtml, refreshSavedClubs, refreshFailure, markIcon, closeX } from "./shared.js";
import {
  isStale, shownLight, nowHour, nextHours, UNITS, compass, searchClubs, town, localDay, SKY_TITLES, skyIcon, REASONS,
  lightFor, reasonCondition, feelsLikeNote, pressureChange, pressureTrend, estimatedWater, iceOff, ICE_TITLES, iceValue, sunState,
  coldWaterKit, place, GROUPS, BOAT_TYPES, BOAT_CLASSES, LIMITS, isGroup, standardLimit, applyLimits, steadierBoat, COLD,
  waterForHour, key, nightParts, nightSummary, sky, hourHalves, sunDaysOf, nearbyCondition, shownWind, shownWaveHeightM, shownVisibilityM,
  forecastStatus, coarserModel, endsAtSunrise,
} from "./logic.js";
import { fillLakeCard, renderLakeMap, renderAllRoutes, openSharedRoutes, forgetView, splitClubPins } from "./lakeview.js";
import { clubhouseOf, showsOars } from "./lake.js";
import { suggestRow, openSuggestLaunchPoint } from "./suggest.js";
import { osmPlaceCard } from "./osmplace.js";
import { currentTile, currentBody } from "./river.js";
import { isLowered, waterLevelTile, waterLevelBody } from "./lakelevel.js";
import { satelliteCard } from "./satellite.js";
import { renderAddPlace } from "./addplace.js";
import { isOwn } from "./ownplace.js";
import { loadCountries, inCountry, countryChips, resultRow, wireResults, renderCountries, renderCountry, renderWater } from "./countries.js";
import { renderValuePage } from "./valuepage.js";
import { layoutFor, visibleCards, openArrange, ownOrder } from "./arrange.js";
import { showBackground, renderBackgrounds, backgroundSummary, backgroundPreview, forgetOwnPictures, backgrounds, choiceTitle } from "./backgrounds.js";
import { renderTour, tourSeen, tip, withTip, wireTips, closeTip, replayTips, paceTips, bubbleTip } from "./tour.js";
import { MAP_ZOOMS } from "./weathermap.js";
import { conditionData } from "./values.js";
import {
  radarAt, radarStatus, followRadar, reloadRadar, rainLines, skyNow, radarAhead, radarGraphic, radarMark, radarTitleMark, radarCard, radarCardBody, wireRadarCard,
} from "./radar.js";

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
      ${store.developerOptions ? `<section class="card">${languagePicker()}</section>` : ""}
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

/** The tour's language choice: a caption over three segments, as the app's welcome page. */
function tourLanguagePicker() {
  const choice = savedLanguage();
  return `<p class="label tour-language-title">${icon("globe")} ${h(t("Language"))}</p>
    <span class="segmented wide" id="tour-language">${[["auto", t("Device language")], ["en", "English"], ["de", "Deutsch"]]
      .map(([value, label]) => `<button data-language="${value}" class="${choice === value ? "on" : ""}">${h(label)}</button>`).join("")}</span>`;
}

function wireLanguage(again) {
  root.querySelector("#language")?.addEventListener("change", async (e) => {
    await setLanguage(e.target.value);
    again();
  });
  root.querySelectorAll("#tour-language [data-language]").forEach((b) => b.addEventListener("click", async () => {
    await setLanguage(b.dataset.language);
    again();
  }));
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
    return `<li><span class="sky ${colour}">${skyArt(name)}</span><span>${h(t(SKY_TITLES[k]))}</span></li>`;
  }).join("")}</ul><p class="sub">${h(t("At night the sun becomes a moon and the row is dimmed."))}</p>`;
  const explain = (list) => `<ul class="legend">${list.map(([c, title, unit, text]) => `<li>${conditionIcon(c)}<span><strong>${h(unit ? `${title} (${unit})` : title)}</strong><small>${h(text)}</small></span></li>`).join("")}</ul>`;
  const rows = conditionTexts();
  if (part === "hourly") {
    return `<ul class="legend">
      <li><span class="cond">${icon("clock")}</span><span>${h(t("Time; the hour starts here."))}</span></li>
      <li>${dot("green", 12)}<span>${h(t("Rowing light for your boat in that hour."))}</span></li>
      <li><span class="cond">${icon("cloud-sun")}</span><span>${h(t("Weather symbol; it also shows how cloudy it is."))}</span></li></ul>
      ${explain(["temperature", "feelsLike", "wind", "waves", "precipitation", "visibility"].map((c) => rows[c]))}
      <ul class="legend"><li><span class="cond">${icon("moon")}</span><span>${h(t("Night line: the hours between sunset and sunrise in one line, with the night's lowest temperature and feels-like, strongest wind and gusts, highest waves, all its rain and its poorest visibility. Tap it to see each hour."))}</span></li></ul>
      <p class="sub">${h(t("Hours after sunset are dimmed. Tap an hour to see all its values."))}</p>`;
  }
  return symbols + explain(TILE_ORDER.map((c) => rows[c]));
}



/**
 * Picks the boat for the rowing light, with the light each boat gets now (BoatMenu).
 * Own boats kept at other clubs come last, with one tap to take them to this
 * club too (owner's choice A, 30 Oct 2026).
 */
function openBoatMenu(raw, anchor, picked = () => route(false)) {
  const now = raw ? new Date() : null;
  const club = pageClubId();
  const inUse = selectedBoat().id;
  const row = (boat) => {
    let light = null;
    if (raw) {
      const hour = nowHour(applyLimits(raw, boatLimits(boat)), now);
      light = hour.light;
    }
    const on = inUse === boat.id;
    return `<li><button data-boat="${h(boat.id)}" class="${on ? "on" : ""}">
      ${light ? dot(light, 16, isStale(raw)) : icon("rower")}
      <span><strong>${h(boatTitle(boat))}</strong><small>${h(light ? lightTitle(light, isStale(raw)) : boatDetail(boat))}</small></span>
      ${on ? icon("check") : ""}</button></li>`;
  };
  const here = boatsKeptAt();
  const away = club ? store.boats.filter((b) => !isKept(b)) : [];
  const awayRow = (boat) => `<li><button data-take="${h(boat.id)}">${icon("circle-arrow-down")}
      <span><strong>${h(boatTitle(boat))}</strong><small>${h(t("At %@ · tap to take it here", listJoin(boat.clubs.map(clubNameOf))))}</small></span></button></li>`;
  const body = `<h3>${h(t("Rowing light for"))}</h3><ul class="boats">${GROUPS.map(row).join("")}</ul>
    ${here.length ? `<h3>${h(away.length ? t("Your boats here") : t("My boats"))}</h3><ul class="boats">${here.map(row).join("")}</ul>` : ""}
    ${away.length ? `<h3>${h(t("At other clubs"))}</h3><ul class="boats">${away.map(awayRow).join("")}</ul>` : ""}
    <a class="pill" href="#/settings/boats">${icon("sliders-horizontal")} ${h(t("Boats and limits…"))}</a>`;
  openMenu(anchor, body, (dialog) => {
    dialog.querySelectorAll("[data-boat]").forEach((b) => b.addEventListener("click", () => {
      pickBoat(b.dataset.boat, club);
      dialog.close();
      picked();
    }));
    dialog.querySelectorAll("[data-take]").forEach((b) => b.addEventListener("click", () => {
      keepBoat(b.dataset.take, club);
      pickBoat(b.dataset.take, club);
      // Taking a boat along is what the tip asks for, so it closes for good.
      closeTip(root, "boatsElsewhere");
      dialog.close();
      picked();
    }));
    dialog.querySelector("a.pill").addEventListener("click", () => dialog.close());
  });
}

// ---- Bottom bar ----------------------------------------------------------------------------

/**
 * The page bar (RootView.PageBar): on a narrow window the cog with the boat beside it, a dot
 * per club page and the list, as in Weather (owner's pick, 4 Nov 2026: easy to reach on big
 * phones); beside the list nothing, as the list switches clubs; with the list slid away the
 * dots only, the sidebar button, cog and boat being level with the club's name.
 */
function bottomBar(currentId) {
  const clubs = store.clubs;
  if (sideShown()) return `<nav class="bottom"></nav>`;
  const dots = `<span class="glass piece dots">${clubs.map((c, i) => `<a href="#/club/${encodeURIComponent(c.id)}" class="${c.id === currentId ? "on" : ""}" aria-label="${h(c.shortName || c.name)}">${i === 0 ? icon("house") : "<span></span>"}</a>`).join("")}</span>`;
  if (sideList.matches) return `<nav class="bottom"><span class="bar-side"></span>${dots}<span class="bar-side end"></span></nav>`;
  return `<nav class="bottom">
    <span class="bar-side"><a href="#/settings" class="glass piece round tool" aria-label="${h(t("Settings"))}">${icon("settings")}</a>${boatButton()}${boatsElsewhereTip()}</span>
    ${dots}
    <span class="bar-side end"><a href="#/list" class="glass piece round tool" aria-label="${h(t("Locations"))}">${icon("list")}</a></span>
  </nav>`;
}

/** The button that opens the boat menu, right beside the cog (PageBoatButton). */
function boatButton() {
  return `<button class="glass round tool boat" data-boat-button aria-label="${h(t("For %@", boatInSentence(selectedBoat())))}">${boatClassTag(selectedBoat())}</button>`;
}

// The lake map and the satellite picture's full view show the same button (owner's pick B, 5 Nov 2026).
boatControl.html = () => boatButton().replace("data-boat-button", "data-map-boat");
boatControl.open = (anchor, picked) => openBoatMenu(forecasts.get(pageClubId())?.value ?? null, anchor, picked);

/** Once, on the first club page where an own boat is kept elsewhere (BoatsElsewhereTip), beside the boat button. */
const boatsElsewhereTip = () => (store.boats.some((b) => !isKept(b)) ? tip("boatsElsewhere").replace('class="tip"', 'class="tip pop"') : "");

/**
 * The buttons level with the club's big name on wide windows, and again in the small top bar
 * once it has shrunk there (PageTopButtons): on the left the sidebar button while the list
 * beside the page is slid away and the cog, on the right the boat (owner, 4 Nov 2026: as
 * before on wide windows). Narrow windows have none: their cog and boat sit in the bottom bar.
 */
function pageButtons(side, withTip = false) {
  if (!sideList.matches) return "";
  if (side === "right") return `<span class="head-side end">${boatButton()}${withTip ? boatsElsewhereTip() : ""}</span>`;
  return `<span class="head-side">
    ${sideHidden ? `<button class="glass round tool ${slideIn ? "slide-in" : ""}" data-show-list aria-label="${h(t("Show the club list"))}">${icon("panel-left")}</button>` : ""}
    <a href="#/settings" class="glass round tool" aria-label="${h(t("Settings"))}">${icon("settings")}</a>
  </span>`;
}

/** What each side of the big and small title keeps free for these buttons (PageTopButtons.sideRoom). */
const sideRoom = () => (!sideList.matches ? 0 : sideHidden ? 104 : 56);

/** The boat button's symbol: the class in a small frame, dashed for the two groups, in the accent colour for an own boat (BoatClassTag). */
function boatClassTag(boat) {
  const tag = boatTag(boat);
  return `<span class="class-tag ${isGroup(boat) ? "group" : ""} ${tag.length > 2 ? "long" : ""}" aria-hidden="true">${h(tag)}</span>`;
}

/** An hour of the 48 hours read as one sentence by a screen reader, not ten loose numbers (HourRow.accessibilityText). */
function hourSentence(x, stale, halves = null) {
  const light = halves ? t("%@, then %@", lightTitle(halves.start), lightTitle(halves.end)) : lightTitle(x.light, stale);
  const parts = [time(x.time), light, t(SKY_TITLES[sky(x.weatherCode)]), degrees(x.temperatureC), t("Feels like %@", degrees(x.apparentTemperatureC))];
  if (x.windSpeedMs != null) parts.push(t("wind %@", wind(x.windSpeedMs)));
  if (x.windGustMs != null) parts.push(t("gusts up to %@", wind(x.windGustMs)));
  if (x.waveHeightM != null) parts.push(t("waves %@", waves(x.waveHeightM)));
  parts.push((x.precipitationMm ?? 0) >= 0.1 ? t("%@ rain", rain(x.precipitationMm)) : t("dry"));
  if (x.visibilityM != null) parts.push(t("visibility %@", distance(x.visibilityM)));
  return parts.join(", ");
}

/** The forecast the boat menu reads; the buttons are drawn before it loads. */
let boatRaw = null;

function wireBoatButton() {
  const wire = (selector, act) => root.querySelectorAll(selector).forEach((button) => {
    if (button.dataset.wired) return;
    button.dataset.wired = "1";
    button.addEventListener("click", act);
  });
  wire("[data-boat-button]", (e) => openBoatMenu(boatRaw, e.currentTarget));
  wire("[data-show-list]", () => slideList(false));
  wire("#hide-list", () => slideList(true));
}

function wireBottomBar(raw) {
  boatRaw = raw;
  wireBoatButton();
  // The boats-elsewhere tip sits over the boat button in the bar on narrow windows.
  const nav = root.querySelector("nav.bottom");
  if (nav && !nav.dataset.tips) {
    nav.dataset.tips = "1";
    wireTips(nav);
  }
  const dots = root.querySelector(".bottom .dots");
  dots?.addEventListener("pointerdown", (e) => {
    dotSlide = e.clientX;
    dotSlid = false;
  });
  // As Weather's page dots (PageJump.step): a tap moves one club towards the tapped dot, with the slide.
  dots?.addEventListener("click", (e) => {
    const link = e.target.closest("a");
    if (!link) return;
    e.preventDefault();
    if (dotSlid) return;
    const links = [...dots.querySelectorAll("a")];
    const at = links.findIndex((a) => a.classList.contains("on"));
    const to = links.indexOf(link);
    if (at < 0 || to === at) return;
    moveTo(links[at + (to > at ? 1 : -1)].getAttribute("href"), to > at ? "next" : "prev");
  });
  // A mouse sliding along the dots would otherwise drag the link away.
  dots?.addEventListener("dragstart", (e) => e.preventDefault());
}

// A finger or the mouse sliding along the dots moves through the clubs, as in Weather. On the
// document, since each club page draws the bar anew while the finger is still down.
let dotSlide = null;
/** Whether the finger moved along the dots, so the click at its end does not step on as well. */
let dotSlid = false;
document.addEventListener("pointermove", (e) => {
  const dots = root.querySelector(".bottom .dots");
  if (dotSlide == null || !dots || Math.abs(e.clientX - dotSlide) < 6) return;
  const links = [...dots.querySelectorAll("a")];
  const at = links.find((a) => {
    const r = a.getBoundingClientRect();
    return e.clientX >= r.left && e.clientX < r.right;
  }) ?? (e.clientX < links[0].getBoundingClientRect().left ? links[0] : links[links.length - 1]);
  if (!at.classList.contains("on")) {
    dotSlid = true;
    location.replace(at.getAttribute("href"));
  }
});
for (const end of ["pointerup", "pointercancel"]) document.addEventListener(end, () => { dotSlide = null; });

// ---- List and search (LocationListView) -----------------------------------------------------

let editing = false;

async function renderList() {
  setTitle(t("Locations"));
  // As in the Weather app: the big title level with "…", small and centred once the list scrolls; no way
  // back but the clubs' cards; the cog beside the search at the bottom (LocationListView).
  root.innerHTML = `
    <div class="top-title"><strong>${h(t("Locations"))}</strong></div>
    ${testing()}
    <main class="page list-page">
      <header class="list-head"><h1 class="large">${h(t("Locations"))}</h1>${moreMenu()}</header>
      ${listBody()}
      ${footerLinks()}
    </main>
    ${searchBar("list-bottom")}`;
  await wireList(renderList);
}

/** Edit list, browsing by country and adding an own place, behind "…" at the top right; Done while editing (moreMenu). */
function moreMenu() {
  if (editing) return `<button class="link strong" id="edit">${h(t("Done"))}</button>`;
  return `<details class="more-menu"><summary class="glass round" aria-label="${h(t("More"))}">${icon("ellipsis")}</summary>
    <div class="menu">
      <button id="edit" ${store.clubs.length < 2 ? "disabled" : ""}>${icon("pencil")} ${h(t("Edit list"))}</button>
      <a id="browse" href="#/countries" hidden>${icon("globe")} ${h(t("Browse clubs by country"))}</a>
      <a href="#/add-place">${icon("map-pin")} ${h(t("Add a place yourself"))}</a>
    </div></details>`;
}

/** The settings cog and the search field side by side at the bottom (settingsBesideSearch); beside a club page the search alone, at the top of the list. */
function searchBar(cls, cog = true) {
  return `<div class="${cls} search-bar">
    ${cog ? `<a href="#/settings" class="glass round tool" aria-label="${h(t("Settings"))}">${icon("settings")}</a>` : ""}
    <label class="search glass">${icon("search")}
      <input id="query" type="search" autocomplete="off" placeholder="${h(t("Search clubs, lakes or towns"))}" aria-label="${h(t("Search clubs, lakes or towns"))}"></label>
  </div>`;
}

/** The search results, the saved clubs and the line when they were updated: the list page's, and the list's beside a club page. */
function listBody(currentId = null) {
  const clubs = store.clubs;
  return `<div id="chips" hidden></div>
    <ul id="results" class="results" hidden></ul>
    <p class="add-own" id="add-own" hidden><a class="link" href="#/add-place">${icon("map-pin")} ${h(t("Not in the list? Add a place"))}</a>
      <small class="sub">${h(t("Put your club, boathouse or spot on the map yourself."))}</small></p>
    <div id="saved">
      ${clubs.length ? "" : `<p class="empty">${h(t("Pick your home club first, then any others you row at."))}</p>
      <p class="footnote">${h(t("Search by club, lake or town to find any club in Germany, Austria or Switzerland."))}
        ${h(t("Clubs nobody has opened for a while update less often at first. After you add one, it is up to date within about 30 minutes."))}</p>`}
      <ul class="rows">${clubs.map((c, i) => `
        <li class="${editing ? "editing" : ""}">
          ${editing ? `<button class="round red" data-remove="${h(c.id)}" aria-label="${h(t("Remove"))}">${icon("trash-2")}</button>` : ""}
          <a class="row ${c.id === currentId ? "current" : ""}" href="#/club/${encodeURIComponent(c.id)}" data-id="${h(c.id)}">${rowSkeleton(c, i === 0)}</a>
          ${editing && i > 0 ? `<button class="round" data-home="${h(c.id)}" aria-label="${h(t("Home base"))}">${icon("house")}</button>` : ""}
        </li>`).join("")}</ul>
      <p class="footnote" id="updated"></p>
    </div>`;
}

/** Edit, remove, home base, search and the rows' weather; `again` draws the list anew after a change. */
async function wireList(again) {
  root.querySelector("#edit")?.addEventListener("click", () => {
    editing = !editing;
    again();
  });
  root.querySelectorAll("[data-remove]").forEach((b) => b.addEventListener("click", () => {
    store.clubs = store.clubs.filter((c) => c.id !== b.dataset.remove);
    again();
  }));
  root.querySelectorAll("[data-home]").forEach((b) => b.addEventListener("click", () => {
    const list = store.clubs;
    store.clubs = [list.find((c) => c.id === b.dataset.home), ...list.filter((c) => c.id !== b.dataset.home)];
    again();
  }));
  wireSearch();
  const updated = [];
  await Promise.all([...root.querySelectorAll("#saved .row")].map(async (row) => {
    const at = await fillRow(row);
    if (at) updated.push(at);
  }));
  if (updated.length) {
    const loaded = store.clubs.map((c) => forecasts.get(c.id)?.loadedAt ?? undefined);
    root.querySelector("#updated").textContent = updatedLine(Math.min(...updated.map((d) => new Date(d))),
      loaded.includes(undefined) ? null : Math.min(...loaded));
  }
}

/**
 * Club names on one line: the long name with the short one in brackets
 * where it fits, else the short name (ViewThatFits in ClubTitle). Checked
 * whenever a name appears or its space changes size.
 */
const nameWatch = new ResizeObserver((entries) => {
  for (const { target } of entries) {
    target.classList.remove("short");
    target.classList.toggle("short", target.scrollWidth > target.clientWidth + 1);
  }
});
new MutationObserver(() => {
  for (const el of document.querySelectorAll(".fit-name:not([data-fit])")) {
    el.dataset.fit = "";
    nameWatch.observe(el);
  }
}).observe(document.body, { childList: true, subtree: true });

function rowSkeleton(club, isHome) {
  return `<div class="row-top">
      <div class="row-name">
        <strong>${isHome ? filledIcon("house") : ""}${clubNameHtml(club)}</strong>
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
  const forecast = forBoat(raw, row.dataset.id);
  const stale = isStale(forecast);
  const hour = nowHour(forecast);
  const water = forecast.waterTemperature?.celsius;
  const estimate = estimatedWater(forecast);
  row.style.setProperty("--tint", `var(--${shownLight(hour.light, stale)})`);
  row.classList.add("tinted");
  row.querySelector(".row-now").innerHTML = `<div class="now-line">${dot(hour.light, 18, stale)}${skySymbol(hour)}${conditionIcon("temperature")}<span class="big-temp">${h(degrees(hour.temperatureC))}</span></div>
    ${hour.apparentTemperatureC != null ? `<small class="sub">${icon("person-standing")} ${h(t("Feels like %@", degrees(hour.apparentTemperatureC)))}</small>` : ""}`;
  const headline = warningHeadline(forecast.warnings);
  const sun = sunState(forecast);
  const ice = forecast.ice;
  const kit = coldWaterKit(water ?? estimate, currentLimits(row.dataset.id));
  const iceText = iceOff(ice) ? t("Off season") : ice && ice.status !== "unavailable" ? t(ICE_TITLES[ice.status] ?? "No data") : "–";
  row.querySelector(".row-bottom").innerHTML = `
    <div class="row-why">
      <strong>${h(lightTitle(hour.light, stale))}</strong>
      ${stale ? `<small class="orange">${icon("clock")} ${h(t("As of %@", dayTime(forecast.generatedAt)))}</small>` : ""}
      <small class="why${hour.reasons.length ? "" : " one-line"}">${h(hour.reasons.length ? t("Why: %@", hour.reasons.map(reasonLabel).join(", ")) : t("All within the limits"))}</small>
      ${kit ? `<small class="kit-line" title="${h(coldWaterText(kit)[1])}">${icon("life-buoy")} ${h(coldWaterText(kit)[0])}</small>` : ""}
      ${headline ? warningListLine(headline) : ""}
      ${sun ? `<small class="sub"><span role="img" aria-label="${h(sun.up ? t("Sunset %@", time(sun.sunset)) : t("Sunrise %@", time(sun.sunrise)))}">${icon(sun.up ? "sunset" : "sunrise")} ${h(time(sun.up ? sun.sunset : sun.sunrise))}</span></small>` : ""}
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
  return isDWD(w) ? t("DWD warning: %@", warningEvent(w)) : t("%@ warning: %@", serviceShort(w.source), warningEvent(w));
}

/** The list's warning line: amber or red when it changes the light now or soon; later or frost-like ones grey and short, "Frost from 23:00". */
function warningListLine({ warning, urgency }) {
  if (urgency === "info") return `<small class="warn sub">${icon("info")} ${h(warningLine(warning, new Date(), true))}</small>`;
  return `<small class="warn strong ${warning.severity === "minor" ? "orange" : "red"}">${icon("triangle-alert")} ${h(warningLine(warning))}</small>`;
}

/** The event alone, e.g. "Frost" or "Wind gusts" (DWDWarning.eventName). */
function warningEvent(w) {
  if (w.kind === "lake") return t("DWD lake warning");
  const event = lang() === "en" && w.english ? w.english.event : w.event;
  return event ? event[0].toUpperCase() + event.slice(1).toLowerCase() : "";
}

/** In force at `now`: begun (or no start given) and not yet expired (DWDWarning.isActive). */
function warningActive(w, now = new Date()) {
  return (!w.onset || new Date(w.onset) <= now) && (!w.expires || now < new Date(w.expires));
}

/** "23:00" today, else "Tomorrow 08:00", for "from …" in short lines. */
function warningStart(w) {
  if (!w.onset) return null;
  return localDay(w.onset) === localDay(new Date()) ? time(w.onset) : dayTime(w.onset);
}

/** "DWD warning: Frost" while in force, else "DWD warning: Frost from 23:00"; compact: "Frost from 23:00". */
function warningLine(w, now = new Date(), compact = false) {
  const label = compact ? warningEvent(w) : shortWarning(w);
  const start = warningActive(w, now) ? null : warningStart(w);
  return start ? t("%@ from %@", label, start) : label;
}

/** Counting warnings starting within this many hours already show amber in the list. */
const SOON_HOURS = 3;

/**
 * The one warning the short lines (club list, top tile) show, and how: "now" when it
 * counts for the light and is in force, "soon" when it counts and starts within
 * 3 hours, else "info", grey with its start (Warnings.headline).
 */
function warningHeadline(warnings, now = new Date()) {
  const current = (warnings?.items ?? []).filter((w) => !w.expires || new Date(w.expires) > now);
  const rank = ["extreme", "severe", "moderate", "minor"];
  const at = (w) => (rank.includes(w.severity) ? rank.indexOf(w.severity) : 4);
  const worst = (list) => list.reduce((a, w) => (a == null || at(w) < at(a) ? w : a), null);
  const counts = current.filter((w) => !warningInfoOnly(w));
  let w = worst(counts.filter((x) => warningActive(x, now)));
  if (w) return { warning: w, urgency: "now" };
  const soonEnd = now.getTime() + SOON_HOURS * 3600000;
  w = worst(counts.filter((x) => (x.onset ? new Date(x.onset).getTime() : now.getTime()) < soonEnd));
  if (w) return { warning: w, urgency: "soon" };
  const start = (x) => (x.onset ? new Date(x.onset).getTime() : now.getTime());
  w = current.reduce((a, x) => (a == null || start(x) < start(a) ? x : a), null);
  return w ? { warning: w, urgency: "info" } : null;
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
  // New results start at the top of the list, not where the saved clubs were scrolled to (or where Safari moved the page to show the field).
  const scroller = input.closest(".side") ?? document.scrollingElement;
  input.addEventListener("input", async () => {
    await show();
    scroller.scrollTop = 0;
  });
  const bar = input.closest(".list-bottom");
  if (bar) keepAboveKeyboard(bar);
  chips.addEventListener("click", (e) => {
    const chip = e.target.closest("[data-country]");
    if (!chip) return;
    country = chip.dataset.country || null;
    show();
  });
  wireResults(results, { find: (f) => lakes?.find(f) });
}

/**
 * Keeps the search at the bottom just above the on-screen keyboard. Safari on iPhone pins a fixed bar to the page's
 * full height, under the keyboard, and moves the visible part of the page while the results scroll, so the bar follows
 * the visible part (visualViewport) and the list gets room to scroll its last rows above the keyboard.
 */
function keepAboveKeyboard(bar) {
  const vv = window.visualViewport;
  if (!vv) return;
  let frame = 0;
  const place = () => {
    frame = 0;
    if (!bar.isConnected) {
      vv.removeEventListener("resize", queue);
      vv.removeEventListener("scroll", queue);
      window.removeEventListener("scroll", queue);
      document.documentElement.style.removeProperty("--kb");
      return;
    }
    const layout = document.documentElement.clientHeight;
    const keyboard = Math.max(0, layout - vv.height);
    const covered = Math.max(0, layout - (vv.offsetTop + vv.height));
    // Small gaps are the browser's own bars coming and going, not a keyboard.
    const open = keyboard > 80;
    bar.style.transform = open && covered > 1 ? `translateY(${-covered}px)` : "";
    bar.classList.toggle("over-keyboard", open);
    document.documentElement.style.setProperty("--kb", `${open ? keyboard : 0}px`);
  };
  const queue = () => { frame ||= requestAnimationFrame(place); };
  vv.addEventListener("resize", queue);
  vv.addEventListener("scroll", queue);
  window.addEventListener("scroll", queue, { passive: true });
  place();
}

// ---- Club page (LocationPageView) ------------------------------------------------------------


/** Counts club page renders, so the radar of a page left behind stops refreshing. */
let clubRenders = 0;

async function renderClub(id) {
  const shown = ++clubRenders;
  setPageClub(id);
  let club = store.clubs.find((c) => c.id === id);
  if (!club?.launchPoint) club = (await findClub(id)) ?? club;
  const saved = store.clubs.some((c) => c.id === id);
  const name = club ? club.shortName || club.name : id;
  setTitle(name);
  const isHome = store.clubs[0]?.id === id;
  const side = sideShown();
  root.innerHTML = `${testing()}<div class="split">
      ${side ? `<aside class="side">${sideListHtml(id)}</aside>` : ""}
      <main class="page club">
        ${clubHeader(club, name, isHome, null)}
        <section class="card loading"><p>${h(t("Loading the forecast…"))}</p></section>
      </main>
    </div>${bottomBar(id)}`;
  if (side) wireSideList(id);
  wireBottomBar(null);
  wireSwipe(id);
  wireLaunchOpen(club);
  // The club's load state (loadable): a forecast loaded before stays, with why
  // the update failed (as ForecastStore and LocationPageView in the app).
  await loadForecast(id, true).catch(() => {});
  const state = forecasts.get(id);
  const raw = state?.value ?? null;
  const failure = state?.failure ? refreshFailure(state.failure, isOwn(id)) : null;
  if (!raw) {
    root.querySelector(".loading").innerHTML = `<p><strong>${icon("wifi-off")} ${h(t("No forecast"))}</strong>: ${h(failure[0])}</p>
      <p class="small sub">${h(failure[1])}</p><button class="primary" id="retry">${h(t("Try again"))}</button>`;
    root.querySelector("#retry").addEventListener("click", () => renderClub(id));
    return;
  }
  const forecast = forBoat(raw);
  const now = new Date();
  const stale = isStale(forecast, now);
  const hour = nowHour(forecast, now);
  const warnings = forecast.warnings;
  const showWarnings = warnings && (warnings.status !== "ok" || !localChecked(warnings) || warnings.items?.length);
  // Where the tips sit (owner's placement rules, 12 Nov 2026; TipPlacement.swift): a tip about a card
  // inside it under its title or first line, a tip about one control as a bubble on it. paceTips then
  // shows one of them. Current conditions' card tip: the water level's first while the lake is let
  // down (Forggensee), the water estimate's only where no station measures the water.
  const conditionsTip = isLowered(forecast.waterLevel) && tip("waterLevel") ? "waterLevel"
    : tip("conditionsExtras") || forecast.waterTemperature != null || forecast.waterEstimate?.reading == null ? "conditionsExtras" : "waterEstimate";
  // The nearby-water tip first, the first time the Why line counts the water within 1 km (NearbyWaterTip).
  const nearbyTip = hour?.reasons?.some((r) => r.condition === "nearby_water") ? tip("nearbyWater") : "";
  const topCardTip = nearbyTip || (store.combinedTopTile ? tip(conditionsTip) : "");
  // Bubbles on the top tile's values, or on All values under it (topTileBubble).
  const valuesBubble = ["topTile", forecast.river ? "riverCurrent" : null, "rainRadar"].find((x) => x && tip(x));
  const gripBubble = store.combinedTopTile ? bubbleTip("allValues") : "";
  // The cards in the order chosen under "Arrange this page".
  const cards = {
    // One tip at a time; the water level's first while the lake is let down (Forggensee),
    // the water estimate's only where no station measures the water.
    conditions: () => withTip(conditionsCard(forecast, hour, radarAt(club?.launchPoint), radarStatus(club?.launchPoint)), conditionsTip),
    // Off by default: the rain tile shows the radar; "Arrange this page" switches the card on.
    radar: () => (club?.launchPoint ? radarCard(club.launchPoint) : ""),
    lakeView: () => (forecast.lakeId ? `<section class="card" id="lake-view" hidden></section>` : ""),
    hourly: () => withTip(hourlyCard(forecast, now, stale), "hourly"),
    launchPoint: () => (club?.launchPoint ? withTip(launchPointCard(club), "launchPoint") : ""),
    satellite: () => `<section class="card" id="satellite" hidden></section>`,
  };
  root.querySelector("main").innerHTML = `
    <div class="top-title" style="--side-room:${sideRoom()}px">${pageButtons("left")}<span class="top-name" aria-hidden="true">${dot(hour.light, 12, stale)}<strong>${h(name)}</strong></span>${pageButtons("right", true)}</div>
    ${clubHeader(club, name, isHome, forecast, stale, failure)}
    ${saved ? "" : `<button class="primary wide" id="add">${icon("plus")} ${h(t("Add to my clubs"))}</button>`}
    ${nowCard(forecast, hour, { stale, radar: radarAt(club?.launchPoint), radarState: radarStatus(club?.launchPoint) })}
    ${showWarnings ? warningsCard(warnings, club, forecast.generatedAt) : ""}
    <div class="cards">${visibleCards(layoutFor(id)).map((c) => cards[c]?.() ?? "").join("")}</div>
    <div class="page-end">
      ${sourceLine(forecast)}
      <button class="pill" id="arrange">${icon("arrow-up-down")} ${h(t("Arrange this page"))}</button>
      <button class="pill" id="updates">${icon("info")} ${h(t("How often data is updated"))}</button>
      ${credits(forecast, club)}
      ${footerLinks()}
    </div>`;
  root.querySelector("nav.bottom").outerHTML = bottomBar(id);
  wireBottomBar(raw);
  wireClubPage(id, club, raw, forecast, hour);
  placeClubTips(root.querySelector("main"), { topCardTip, valuesBubble, gripBubble });
  wireTips(root.querySelector("main"));
  balanceCards();
  updateTopBar();
  if (root.querySelector("#launch-map")) showLaunchMap(club);
  wireRadarCard(root.querySelector("#radar"), club?.launchPoint, markIcon(club?.id));
  followRadar(club?.launchPoint, () => shown === clubRenders && root.querySelector("main.club") != null, () => showRadar(club, forecast, hour));
  const satelliteBox = root.querySelector("#satellite");
  if (forecast.lakeId && satelliteBox) satelliteCard(satelliteBox, forecast.lakeId, id, balanceCards);
  const lakeBox = root.querySelector("#lake-view");
  if (lakeBox) {
    fillLakeCard(lakeBox, forecast.lakeId, id, waterForHour(raw, hour)).then(() => {
      if (!lakeBox.hidden) lakeBox.querySelector(".card-title")?.insertAdjacentHTML("afterend", tip("lakeView"));
      // A tip that comes after the page was drawn still waits its turn (paceTips).
      paceTips(root.querySelector("main"));
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
  replace(root.querySelector('.card:not(.now) [data-tile="precipitation"]'), conditionTile("precipitation", forecast, hour, radar, radarStatus(club?.launchPoint)));
  const cell = root.querySelector(".card.now .now-rain");
  if (cell) cell.innerHTML = rainCell(conditionData(forecast, hour, radar));
  const box = root.querySelector("#radar");
  if (box && club?.launchPoint) {
    box.innerHTML = radarCardBody(club.launchPoint);
    wireRadarCard(box, club.launchPoint, markIcon(club.id));
  }
  balanceCards();
}

// ---- Wide screens (iPad, Mac, PC), as in the app on iPad ------------------------------------

/** The list beside the club page from this size on (RootView's side list). */
const sideList = matchMedia("(min-width: 860px) and (min-height: 560px)");
/** The list beside the page slid away with the sidebar button, as in Weather; for this visit only. */
let sideHidden = false;
/** The sidebar button slides in once, right after the list slid away, and the cog moves over. */
let slideIn = false;
const sideShown = () => sideList.matches && !sideHidden;

/** Slides the list beside the page away or back (RootView.slide, 0.3 s). */
function slideList(hide) {
  const split = root.querySelector(".split");
  const done = () => {
    sideHidden = hide;
    slideIn = hide;
    route(false);
    slideIn = false;
    if (!hide) root.querySelector("aside.side")?.classList.add("slide-in");
  };
  if (!hide || !split || matchMedia("(prefers-reduced-motion: reduce)").matches) return done();
  split.classList.add("hiding");
  setTimeout(done, 300);
}
sideList.addEventListener("change", () => location.hash.startsWith("#/club/") && route(false));

/** From this page width, padding included and counted as if the list were shown, the cards go into two columns (LocationPageView.twoColumnWidth). */
const TWO_COLUMNS = 600;

/**
 * Club page columns on wide windows (owner's pick B, 12 Nov 2026, docs/decisions/0023), the app's rule
 * (ClubPageColumns in ios/RowFrog/ClubPageLayout.swift leads, the website follows): up to three, each card 380
 * to 560 px wide. The window sets the count, worked out as if the list beside the page were shown, so sliding the
 * list away or back only widens or narrows the same columns and no card moves to another one. Three columns when
 * the room (the page without its 16 px padding) reaches 1,200 px, back to two only under 1,172 px (3 × 380 + 2
 * gaps), so a window right at the edge does not flip. Counted again 300 ms after a resize rests.
 */
const COLUMNS = { cardMax: 560, gap: 16, pad: 32, threeFrom: 1200, threeUntil: 1172, side: 400 };
let columnCount = 0;

/** How many columns the cards get, by the window as if the list were shown (pick B): 1 under TWO_COLUMNS, else 2 or 3. */
function columnsFor() {
  const pageWidth = document.documentElement.clientWidth - (sideList.matches ? COLUMNS.side : 0);
  if (pageWidth < TWO_COLUMNS) return 1;
  return pageWidth - COLUMNS.pad >= (columnCount === 3 ? COLUMNS.threeUntil : COLUMNS.threeFrom) ? 3 : 2;
}

/** The page's widest size for a column count: cards no wider than COLUMNS.cardMax, then the page sits in the middle. */
const pageMaxFor = (n) => `${n * COLUMNS.cardMax + (n - 1) * COLUMNS.gap + COLUMNS.pad}px`;

/**
 * Beside the page, the whole list: search, Edit and the saved clubs, the shown
 * one marked, so the page needs no list button (LocationListView beside the page).
 */
function sideListHtml(currentId) {
  // The sidebar button, the title and "…" on one line, the search at the top of the list
  // below them, as Apple's guide has it for a sidebar (SideListHeader).
  return `<header class="side-head"><button class="glass round tool" id="hide-list" aria-label="${h(t("Hide the club list"))}">${icon("panel-left")}</button>
      <h2>${h(t("Locations"))}</h2>${moreMenu()}</header>
    ${searchBar("side-search", false)}${listBody(currentId)}`;
}

/** A change in the list draws the list anew, not the page beside it. */
function wireSideList(currentId) {
  const side = root.querySelector("aside.side");
  if (!side) return;
  wireBoatButton();
  wireList(() => {
    side.innerHTML = sideListHtml(currentId);
    wireSideList(currentId);
    // The arrow keys follow the list's new order.
    wireSwipe(currentId);
  });
}

/**
 * The cards in two columns on a wide page, each going to the shorter column
 * in turn (BalancedColumns in the app); one column on a narrow one. In two
 * columns the page's end (source, Arrange, credits) goes into the shorter
 * column too, and the lake view and launch point maps there grow until both
 * columns end level, each card at most one window tall.
 */
/**
 * A line with a shorter wording (data-short) keeps its full text where that
 * fits on one line, else takes the short one (ViewThatFits in the app); checked
 * again whenever its width changes.
 */
const fitWatch = new ResizeObserver((entries) => entries.forEach(({ target }) => {
  if (target.matches(".now-grid")) return fitGreyLines(target);
  target.querySelectorAll(".fit-line").forEach(fitLine);
  target.querySelectorAll(".now-head").forEach(fitHead);
}));
/**
 * The top tile's grey lines (feels like, measured at, open water ...) get the
 * whole width up to the next column, as TopTileGrid gives them in the app: the
 * columns are only as wide as their titles and values, so the lines wrapped
 * within that, where the app keeps them on one line at the same width.
 */
function fitGreyLines(grid) {
  const cells = [...grid.children];
  if (cells.length < 3) return;
  // Three columns while their titles and values fit side by side; else two, else one, so
  // no word breaks or gets cut (TopTileGrid.columnCount in the app, 12 Nov 2026).
  cells.forEach((cell) => cell.querySelectorAll(".grey").forEach((line) => { line.style.marginInlineEnd = ""; }));
  grid.classList.remove("cols2", "cols1");
  // Three columns: their tracks (as wide as titles and values) must fit side by side. Two or
  // one: no title or value wider than its cell.
  const colGap = () => parseFloat(getComputedStyle(grid).columnGap) || 0;
  const tracks = () => getComputedStyle(grid).gridTemplateColumns.split(" ").map(parseFloat);
  const tooWide = () => tracks().reduce((a, b) => a + b, 0) + 2 * colGap() > grid.clientWidth + 1;
  // The wind's arrow reaches a few pixels past its value at every size; words cut are wider.
  const cut = () => [...grid.querySelectorAll(".label, .v28, .v17")].some((e) => e.scrollWidth > e.clientWidth + 6);
  if (tooWide()) {
    grid.classList.add("cols2");
    if (cut()) grid.classList.replace("cols2", "cols1");
  }
  if (grid.classList.contains("cols2") || grid.classList.contains("cols1")) return;
  const left = grid.getBoundingClientRect().left;
  const xs = cells.slice(0, 3).map((cell) => cell.getBoundingClientRect().left - left);
  const gap = parseFloat(getComputedStyle(grid).columnGap) || 0;
  const widths = [xs[1] - xs[0] - gap, xs[2] - xs[1] - gap, grid.clientWidth - xs[2]];
  // A negative end margin widens a line past its column without widening the column.
  cells.forEach((cell, i) => {
    const extra = Math.max(0, Math.round(widths[i % 3] - cell.clientWidth));
    cell.querySelectorAll(".grey").forEach((line) => { line.style.marginInlineEnd = extra ? `-${extra}px` : ""; });
  });
}
function fitLine(el) {
  const width = el.parentElement?.clientWidth ?? 0;
  if (!width || el.dataset.width === String(width)) return;
  el.dataset.width = width;
  el.dataset.full ??= el.textContent;
  el.textContent = el.dataset.full;
  const line = parseFloat(getComputedStyle(el).lineHeight) || 20;
  if (el.getClientRects().length > 1 || el.offsetHeight > line * 1.5) el.textContent = el.dataset.short;
}
/**
 * The top tile's verdict stays on one line beside the weather; one size smaller
 * where that does not fit; and only where that does not fit either, the weather
 * moves under the verdict (ViewThatFits in NowCard, owner's choice 2 Nov 2026).
 */
function fitHead(head) {
  const width = head.clientWidth;
  if (!width || head.dataset.width === String(width)) return;
  head.dataset.width = width;
  const title = head.querySelector("h2");
  const overflows = () => title.scrollWidth > title.clientWidth + 0.5;
  head.classList.remove("step", "stacked", "wrap");
  if (!overflows()) return;
  head.classList.add("step");
  if (!overflows()) return;
  // The weather moves under the verdict, which again tries one line, then one size
  // smaller, and wraps only when neither fits.
  head.classList.replace("step", "stacked");
  if (!overflows()) return;
  head.classList.add("step");
  if (overflows()) head.classList.add("wrap");
}
function watchFitLines(scope = root) {
  scope.querySelectorAll(".fit-line").forEach((el) => {
    fitLine(el);
    if (el.parentElement) fitWatch.observe(el.parentElement);
  });
  scope.querySelectorAll(".now-head").forEach((el) => {
    fitHead(el);
    if (el.parentElement) fitWatch.observe(el.parentElement);
  });
  scope.querySelectorAll(".now-grid").forEach((el) => {
    fitGreyLines(el);
    fitWatch.observe(el);
  });
}

function balanceCards() {
  watchFitLines();
  const box = root.querySelector(".cards");
  if (!box) return;
  // Always in page order, never in the columns' order from the last sorting.
  const cards = [...box.querySelectorAll(".card")];
  cards.forEach((card, i) => (card.dataset.order ??= i));
  cards.sort((a, b) => a.dataset.order - b.dataset.order);
  const end = root.querySelector(".page-end");
  // Keep the page's height while the cards move: emptied, it would be shorter
  // than the window and Safari, which has no scroll anchoring, jumps to the top.
  const scroller = document.scrollingElement;
  let y = scroller.scrollTop;
  box.style.minHeight = `${box.offsetHeight + (end?.offsetHeight ?? 0)}px`;
  requestAnimationFrame(() => {
    box.style.minHeight = "";
    if (scroller.scrollTop !== y) scroller.scrollTop = y;
  });
  // When the count changes, the card at the top of the window stays at the top (pick B).
  const barHeight = root.querySelector(".top-title")?.offsetHeight ?? 0;
  const anchor = y > 0 ? cards.find((card) => card.getBoundingClientRect().bottom > barHeight) : null;
  const anchorTop = anchor?.getBoundingClientRect().top;
  unfill(cards);
  box.replaceChildren();
  const page = box.closest(".page");
  // Never more columns than page cards (the page end does not count), so none stays empty, but never under two
  // once two apply (the app's rule); data-columns keeps what the window allows.
  const allowed = columnsFor();
  box.dataset.columns = allowed;
  const n = allowed === 1 ? 1 : Math.max(2, Math.min(allowed, cards.length));
  if (page) page.style.maxWidth = n > 1 ? pageMaxFor(n) : "";
  const changed = columnCount !== 0 && allowed !== columnCount;
  columnCount = allowed;
  box.classList.toggle("two", n > 1);
  box.classList.toggle("three", n === 3);
  const keepAnchor = () => {
    if (!changed || !anchor) return;
    y = scroller.scrollTop + anchor.getBoundingClientRect().top - anchorTop;
    scroller.scrollTop = y;
  };
  if (n === 1) {
    cardWatch?.disconnect();
    box.append(...cards);
    if (end) box.after(end);
    keepAnchor();
    return fitSatellite();
  }
  const columns = Array.from({ length: n }, () => document.createElement("div"));
  columns.forEach((c) => (c.className = "col"));
  box.append(...columns);
  // An opened 48 hours count with their folded height, so opening them moves
  // and grows nothing else.
  const extra = columns.map(() => 0);
  const counted = (i) => columns[i].offsetHeight - extra[i];
  const shorter = () => columns.reduce((best, _, i) => (counted(i) < counted(best) ? i : best), 0);
  for (const item of end ? [...cards, end] : cards) {
    const i = shorter();
    columns[i].append(item);
    if (item.classList.contains("open")) extra[i] += Math.max(0, item.offsetHeight - Number(item.dataset.folded || item.offsetHeight));
    else if (item.classList.contains("folds")) item.dataset.folded = item.offsetHeight;
  }
  // The columns set the card's width, and with it the caption's lines.
  fitSatellite();
  // Every shorter column's maps share out what it lacks against the tallest.
  const tallest = Math.max(...columns.map((_, i) => counted(i)));
  columns.forEach((column, i) => fill(column, tallest - counted(i)));
  keepAnchor();
  watchCards(cards);
}

/** The maps that may grow to fill a column, by card. */
function fillerMap(card) {
  return card.querySelector("#launch-map, .lake-card canvas.mini");
}

/** Every map back at its own height. */
function unfill(cards) {
  for (const card of cards) {
    const map = fillerMap(card);
    if (map?.dataset.base != null) map.style.height = map.dataset.base;
  }
}

/** The maps in the shorter column share out what it lacks, each card up to one window. */
function fill(column, missing) {
  const bar = document.querySelector(".bottom")?.offsetHeight ?? 0;
  const tallest = window.innerHeight - bar - 32;
  let open = [...column.querySelectorAll(".card")].filter((card) => fillerMap(card) && card.offsetHeight < tallest);
  const grow = new Map(open.map((card) => [card, 0]));
  while (missing > 0.5 && open.length) {
    const share = missing / open.length;
    for (const card of open) {
      const more = Math.min(share, tallest - card.offsetHeight - grow.get(card));
      grow.set(card, grow.get(card) + more);
      missing -= more;
    }
    open = open.filter((card) => card.offsetHeight + grow.get(card) < tallest - 0.5);
  }
  for (const [card, more] of grow) {
    if (more < 1) continue;
    const map = fillerMap(card);
    map.dataset.base ??= map.style.height;
    map.style.height = `${map.offsetHeight + Math.round(more)}px`;
  }
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

/**
 * The top of the page (RootView.TopEdgeFade): clear at rest, blurred once the
 * page scrolls under the top edge, and with the club's name and light once its
 * big title has scrolled away (InlineClubTitle); the 48 hours' header then sits below it.
 */
/** Between the line of top buttons and the page's first card (PageTopButtons.gapBelow in the app). */
const PAGE_GAP_BELOW = 10;
let headRoom = null;

function updateTopBar() {
  const body = document.body;
  body.classList.toggle("scrolled", window.scrollY > 0);
  const title = root.querySelector(".club-head h1, .list-head h1");
  const bar = root.querySelector(".top-title");
  // The bar and the strip behind the clock cover the page's own column only, never the list beside it.
  const main = root.querySelector("main");
  // The list beside the page ends at the window's bottom also while the test banner above it shows.
  const split = root.querySelector(".split");
  if (split) body.style.setProperty("--side-top", `${Math.max(0, split.getBoundingClientRect().top)}px`);
  if (main) {
    const page = main.getBoundingClientRect();
    body.style.setProperty("--main-left", `${page.left}px`);
    body.style.setProperty("--main-width", `${page.width}px`);
    // The bar's glass spans the whole area beside the list, edge to edge, as the app's top fade does in its
    // pane; its buttons and name stay on the page's column (owner, 12 Nov 2026: no cut-off over the margins).
    const side = sideShown() ? root.querySelector("aside.side")?.getBoundingClientRect() : null;
    const areaLeft = Math.max(0, side ? side.right : 0);
    const areaRight = document.documentElement.clientWidth;
    body.style.setProperty("--area-left", `${areaLeft}px`);
    body.style.setProperty("--area-width", `${areaRight - areaLeft}px`);
    body.style.setProperty("--column-pad-left", `${Math.max(0, page.left - areaLeft)}px`);
    body.style.setProperty("--column-pad-right", `${Math.max(0, areaRight - page.right)}px`);
  }
  // Wide windows: the page's buttons stay level with the buttons at the top of the list beside it, at rest and
  // while scrolling (owner, 12 Nov 2026); the small bar is centred on the same line.
  // Only beside the list: the list page itself keeps its big title and the small one only once scrolled.
  const wide = sideList.matches && Boolean(bar) && !root.querySelector(".list-page");
  body.classList.toggle("wide-bar", wide);
  if (wide) {
    const tool = root.querySelector(".side-head > .round");
    const rect = tool?.getBoundingClientRect();
    const mid = rect?.height ? rect.top + rect.height / 2 : Math.max(0, split?.getBoundingClientRect().top ?? 0) + 34;
    body.style.setProperty("--head-mid", `${Math.max(22, mid)}px`);
    // The page starts 10 px below the line of buttons, so the header's top is level with the list's search field
    // and nothing sits under the buttons at rest, however long the name (PageTopButtons.gapBelow, owner's iPad
    // shot, 12 Nov 2026). Measured at the top of the page; while scrolled the last room stays.
    const head = root.querySelector(".club-head");
    if (head && window.scrollY === 0) {
      const now = parseFloat(head.style.marginTop) || 0;
      const base = head.getBoundingClientRect().top - (now || parseFloat(getComputedStyle(head).marginTop) || 0);
      headRoom = Math.max(0, Math.round(Math.max(22, mid) + 22 + PAGE_GAP_BELOW - base));
    }
    if (head && headRoom != null && head.style.marginTop !== `${headRoom}px`) head.style.marginTop = `${headRoom}px`;
  } else {
    const head = root.querySelector(".club-head");
    if (head?.style.marginTop) head.style.marginTop = "";
  }
  const gone = Boolean(title && bar && title.getBoundingClientRect().bottom < bar.offsetHeight);
  body.classList.toggle("title-gone", gone);
  stickHourlyHeader();
}

/** While the 48 hours' header stays at the top, the tile ends at it, rounded like the header (StickyHourlyCut). */
function stickHourlyHeader() {
  const head = root.querySelector(".hhead");
  const card = head?.closest(".card");
  if (!card) return;
  const table = head.parentElement.getBoundingClientRect();
  const at = head.getBoundingClientRect();
  const top = parseFloat(getComputedStyle(head).top) || 0;
  const stuck = table.top < top - 1 && at.bottom > table.top;
  head.classList.toggle("stuck", stuck);
  if (stuck) {
    // The day whose header has passed under the pinned header, else the first.
    const days = [...head.parentElement.querySelectorAll(".dayhead")].filter((d) => d.offsetParent);
    const under = days.filter((d) => d.getBoundingClientRect().top <= at.bottom).pop() ?? days[0];
    const label = under?.querySelector("strong")?.textContent ?? "";
    const slot = head.querySelector(".hhead-day");
    if (slot.textContent !== label) slot.textContent = label;
  }
  // The caption strip above the pinned row stays inside the cut.
  const cap = stuck ? parseFloat(getComputedStyle(head).getPropertyValue("--hcap")) || 0 : 0;
  card.style.clipPath = stuck ? `inset(${at.top - cap - card.getBoundingClientRect().top}px 0 0 0 round 16px)` : "";
  // The rows end at the pinned header's bottom, so none shows through it. Safari does not blur
  // behind the header inside a frosted tile (a blur within a blur), and the rows read through
  // its layer (owner's iPhone shot, 12 Nov 2026); the app's header hides them.
  const rows = head.nextElementSibling;
  if (rows) rows.style.clipPath = stuck ? `inset(${Math.max(0, at.bottom - rows.getBoundingClientRect().top)}px 0 0 0)` : "";
}
window.addEventListener("scroll", updateTopBar, { passive: true });
window.addEventListener("hashchange", () => requestAnimationFrame(updateTopBar));
// The bar and its buttons follow the page's column whenever it moves without a scroll: the list beside it sliding
// back in (its 0.3 s animation), the window being resized, or the list's own cards loading late.
const columnWatch = new ResizeObserver(() => updateTopBar());
let watchedMain = null;
new MutationObserver(() => {
  const main = root.querySelector("main");
  if (main === watchedMain) return;
  if (watchedMain) columnWatch.unobserve(watchedMain);
  watchedMain = main;
  if (main) columnWatch.observe(main);
}).observe(root, { childList: true, subtree: true });
document.addEventListener("animationend", (event) => event.target.closest?.("aside.side") && updateTopBar());
document.addEventListener("transitionend", (event) => event.target.closest?.(".split, aside.side") && updateTopBar());

let resizeTimer = null;
window.addEventListener("resize", () => {
  clearTimeout(resizeTimer);
  updateTopBar();
  resizeTimer = setTimeout(() => {
    updateTopBar();
    fitSatellite();
    fitPlaceLines();
    // The columns, and how far the maps grow, follow the window's width and height.
    if (root.querySelector(".cards")) balanceCards();
  }, 300);
});

/**
 * When the weather in this forecast came out: the model run's arrival, or without it when the server
 * built the file (ClubForecast.forecastTime).
 */
export const forecastTime = (forecast) => forecast.weatherRun?.available ?? forecast.generatedAt;

/** How often each value is renewed at its source and fetched by Row Frog, with its symbol on the club page (UpdateCyclesSheet). */
const UPDATE_CYCLES = [
  ["wind", key("Weather forecast"), key("Wind, gusts, temperature, rain, clouds and visibility: DWD's ICON-D2 model, a new run every 3 hours, ready about 1½ to 3 hours after it starts."), key("Fetched once the new run is ready, checked every 30 minutes. Clubs nobody opened lately: every 6 hours.")],
  ["waves", key("Waves"), key("Worked out from the forecast wind and the open water in front of the club."), key("With every new forecast.")],
  ["triangle-alert", key("Official warnings"), key("DWD, GeoSphere Austria or MeteoSwiss, whenever they issue or change one."), key("Every 30 minutes.")],
  ["thermometer", key("Water temperature"), key("Measuring stations, every 15 to 60 minutes; without a station, satellites once a day or an estimate from the air temperatures."), key("Every 30 minutes.")],
  ["gauge", key("River current and lake level"), key("Gauges, every 15 minutes."), key("Every 30 minutes.")],
  ["cloud-rain", key("Rain radar"), key("DWD, every 5 minutes."), key("The radar map loads live when you open it; the widget's rain line every 30 minutes.")],
  ["map", key("Lake view"), key("The same model runs as the forecast, for points across the water."), key("Every 3 hours; lakes nobody opened lately twice a day.")],
  ["spline", key("8-day outlook"), key("The same model runs, longer models after 2 days."), key("Every 3 hours.")],
  ["globe", key("Satellite picture"), key("Sentinel-2 passes every few days; clouds can hide the water."), key("Looked for once a day.")],
  ["snowflake", key("Ice"), key("A satellite ice map once a day in winter, and an estimate from the water and air temperatures."), key("Twice a day.")],
  ["sunrise", key("Daylight"), key("Worked out from the date and the place."), key("Always current.")],
];

export function updateCyclesBody(forecast) {
  const run = forecast.weatherRun;
  const rows = UPDATE_CYCLES.map(([symbol, title, source, fetched]) => `<li><span class="tint">${icon(symbol)}</span><span>
    <strong>${h(t(title))}</strong><small>${h(t(source))}</small><small class="sub">${h(t(fetched))}</small></span></li>`).join("");
  return `<p>${h(run ? t("This forecast: model run of %@, ready at %@.", time(run.started), time(run.available))
      : t("This forecast was built at %@.", time(forecast.generatedAt)))}</p>
    <p>${h(t("Warnings, water and gauges checked at %@.", time(forecast.generatedAt)))}</p>
    <p class="small sub">${h(t("The server renews the clubs you use every 30 minutes; your browser loads them when you open or come back to this page, or tap Refresh."))}</p>
    <h3>${h(t("How often values are renewed"))}</h3>
    <ul class="legend cycles">${rows}</ul>`;
}

/** When the forecast was made and, if another minute, when this browser loaded it (LocationPageView.updatedLine). */
function updatedLine(made, loaded) {
  return loaded == null || time(loaded) === time(made)
    ? t("Forecast from %@", time(made))
    : t("Forecast from %@ · loaded %@", time(made), time(loaded));
}

/** Clubs loaded longer ago than this are loaded again on coming back (ForecastStore.reloadAfter). */
const RELOAD_AFTER = 10 * 60 * 1000;
const due = (id) => {
  const kept = forecasts.get(id);
  return !kept?.loadedAt || Date.now() - kept.loadedAt > RELOAD_AFTER;
};

/** The other saved clubs after the one in front, so a swipe already has new data; all of them, or only those due. */
function reloadOthers(except, onlyDue) {
  for (const c of store.clubs) {
    if (c.id !== except && (!onlyDue || due(c.id))) loadForecast(c.id, true).catch(() => {});
  }
}

/** The "Refresh" button: this club with its lake view first, then all other clubs (ForecastStore.refresh). */
async function refreshClub(id, lakeId) {
  const line = root.querySelector("#updated-line");
  if (line) line.textContent = t("Updating…");
  if (lakeId) forgetView(lakeId);
  // The radar too, unless it was read less than a minute ago (RadarStore.reload); the page's radar follows the same read.
  const radar = reloadRadar(store.clubs.find((c) => c.id === id)?.launchPoint);
  await renderClub(id);
  await radar;
  reloadOthers(id, false);
}

/**
 * Back in the tab: the club page or the list in front loads again first, its
 * lake view too, then the other saved clubs; clubs loaded in the last ten
 * minutes stay as they are (ForecastStore.refreshOnReturn).
 */
function refreshOnReturn() {
  const hash = location.hash.replace(/^#/, "");
  const club = hash.match(/^\/club\/([^/?]+)$/);
  const onList = hash === "/list" || hash === "" || hash === "/";
  const shown = club ? decodeURIComponent(club[1]) : !onList ? null : hash === "/list" || !store.clubs.length ? null : store.clubs[0].id;
  const inFront = shown ? [shown] : onList ? store.clubs.map((c) => c.id) : [];
  const first = inFront.filter(due);
  const lakeId = shown ? forecasts.get(shown)?.value?.lakeId : null;
  if (!first.length) return reloadOthers(shown, true);
  if (lakeId) forgetView(lakeId);
  Promise.resolve(route(false)).finally(() => reloadOthers(shown, true));
}

/** Whether the header opens the launch point (Settings > Club pages > Location in the club header). */
const inHeader = (club) => Boolean(club?.launchPoint) && store.launchPointInHeader;

/** The lake and town; with the launch point in the header a button (pin and chevron) that opens it (ClubPageHeader.placeLine). */
function placeLine(club) {
  const text = place(club?.lakeName, town(club?.address), lakeTitle);
  // Lake and town as their own parts, so fitPlaceLines can break the line where the dot sits.
  const [lake, townName] = text.includes(" · ") ? [text.slice(0, text.indexOf(" · ")), text.slice(text.indexOf(" · ") + 3)] : [null, text];
  const parts = (chevron = "") => lake
    ? `<span class="pl-lake">${h(lake)}</span><span class="pl-dot"> · </span><span class="pl-town">${h(townName)}${chevron}</span>`
    : `<span class="pl-town">${h(townName)}${chevron}</span>`;
  if (!inHeader(club)) return `<p class="sub place-text">${parts()}</p>`;
  return `<div class="place-line place-text"><button class="link launch-open" aria-label="${h(text)}" title="${h(t("Shows the club's location on a map, with directions"))}">${icon("map-pinned")} <span>${parts(` ${icon("chevron-right")}`)}</span></button>${tip("placeLine").replace('class="tip"', 'class="tip pop"')}</div>`;
}

/**
 * The lake and town on one line if they fit; otherwise broken where the dot sits (lake on the first line, town
 * and chevron on the second), if each part then fits; otherwise wrapped as the words fall (ClubPageHeader.placeText,
 * owner 5 Nov 2026). Runs after each header render and on resize.
 */
function fitPlaceLines() {
  for (const line of root.querySelectorAll(".club-head .place-text")) {
    const fits = (mode) => {
      line.dataset.fit = mode;
      return line.scrollWidth <= line.clientWidth + 1;
    };
    if (fits("one")) continue;
    if (line.querySelector(".pl-lake") && fits("split")) continue;
    line.dataset.fit = "wrap";
  }
}

/** The header's lake and town line and the not-confirmed line open the launch point. */
const wireLaunchOpen = (club) => {
  fitPlaceLines();
  root.querySelectorAll(".club-head .launch-open").forEach((b) => b.addEventListener("click", () => {
    closeTip(root, "placeLine");
    openLaunchPoint(club);
  }));
};

// "Suggest the launch point" in the Location sheet or the Launch point card (SuggestLaunchPointView); from the
// sheet, the Location sheet opens again afterwards with the thanks, as the app's sheet comes back.
document.addEventListener("click", (e) => {
  const button = e.target.closest("[data-suggest-lp]");
  if (!button) return;
  const club = store.clubs.find((c) => c.id === button.dataset.suggestLp);
  if (!club) return;
  const fromSheet = !!button.closest("dialog.sheet");
  closeTip(document, "suggestLaunchPoint");
  openSuggestLaunchPoint(club, () => (fromSheet ? openLaunchPoint(club) : route(false)));
});

/** The launch point opened from the header (LaunchPointSheet): the same map, note, coordinates and Open in Maps as the card. */
function openLaunchPoint(club) {
  openSheet(t("Location"), launchPointBody(club, "launch-sheet-map"), (sheet) => {
    showLaunchMap(club, sheet.querySelector("#launch-sheet-map"));
    wireTips(sheet);
    // Map full screen and back, at the right of the title bar; the X has the left (LaunchPointSheet, owner's pick A).
    const header = sheet.querySelector("header");
    header.insertAdjacentHTML("beforeend", `<button class="map-full" type="button"></button>`);
    const button = header.querySelector(".map-full");
    const show = (full) => {
      sheet.classList.toggle("full-map", full);
      button.innerHTML = icon(full ? "minimize-2" : "maximize-2");
      const label = full ? t("Smaller map") : t("Map full screen");
      button.setAttribute("aria-label", label);
      button.title = label;
    };
    show(false);
    button.addEventListener("click", () => show(!sheet.classList.contains("full-map")));
  });
}

function clubHeader(club, name, isHome, forecast, stale = false, failure = null) {
  const slow = forecast?.refresh && forecast.refresh.used === false;
  return `<header class="club-head">
    ${isHome ? `<p class="home">${filledIcon("house")} ${h(t("Home base"))}</p>` : ""}
    <div class="title-row" style="--side-room:${sideRoom()}px">${pageButtons("left")}<h1>${clubNameHtml(club, name)}</h1>${pageButtons("right")}</div>
    ${placeLine(club)}
    ${club && club.launchPointVerified === false ? (inHeader(club)
      ? `<p class="orange small"><button class="link plain launch-open">${icon("map-pin-off")} ${h(t("Launch point not yet confirmed"))}</button></p>`
      : `<p class="orange small">${icon("map-pin-off")} ${h(t("Launch point not yet confirmed"))}</p>`) : ""}
    ${isOwn(club?.id) ? `<p class="sub small own-note">${icon("map-pin")} ${h(t("Your own place, kept in this browser. No waves, water temperature or warnings here."))}</p>` : ""}
    ${forecastLines(club, forecast, forecastStatus({ hasForecast: !!forecast, outOfDate: stale, failure }))}
    ${slow ? `<p class="sub small">${icon("hourglass")} ${h(t("Nobody opened this club lately, so it updates less often. From the next server update, within about 30 minutes, it updates every half hour."))}</p>` : ""}
  </header>`;
}

/** The header's forecast lines, one state at a time (forecastStatus, as ClubPageHeader in the app). */
function forecastLines(club, forecast, status) {
  if (!forecast) return "";
  const outOfDate = status.name === "outOfDate" || status.name === "outOfDateAndUpdateFailed";
  const old = outOfDate ? `<p class="orange small">${icon("clock")} ${h(t("Forecast out of date: from %@. Check the conditions yourself.", dayTime(forecast.generatedAt)))}</p>` : "";
  switch (status.name) {
    case "updateFailed":
    case "outOfDateAndUpdateFailed":
      return `${old}<p class="orange small"><button class="link failed" id="failed" data-why="${h(status.failure[1])}">${icon("wifi-off")} ${h(t("Could not update: %@. Showing data from %@.", status.failure[0], outOfDate ? dayTime(forecast.generatedAt) : time(forecast.generatedAt)))} ${icon("info")}</button></p>`;
    case "current":
    case "updating":
      return `<p class="sub small" id="updated-line">${h(updatedLine(forecastTime(forecast), forecasts.get(club?.id)?.loadedAt))} · <button class="link" id="refresh">${h(t("Refresh"))}</button></p>`;
    default:
      return old;
  }
}

function wireClubPage(id, club, raw, forecast, hour) {
  wireLaunchOpen(club);
  root.querySelector("#refresh")?.addEventListener("click", () => refreshClub(id, forecast.lakeId));
  root.querySelector("#failed")?.addEventListener("click", (e) => openSheet(t("Could not update"), `<p>${h(e.currentTarget.dataset.why)}</p>
    <button class="primary wide" id="retry">${h(t("Try again"))}</button>`, (sheet) => sheet.querySelector("#retry").addEventListener("click", () => { sheet.close(); renderClub(id); })));
  root.querySelector("#arrange").addEventListener("click", () => openArrange(club ?? { id }, () => renderClub(id)));
  root.querySelector("#updates")?.addEventListener("click", () => openSheet(t("Updates"), updateCyclesBody(forecast)));
  root.querySelector(".hourly-card .fold")?.addEventListener("click", (e) => foldHourly(e.currentTarget));
  root.querySelectorAll(".hourly-card .nightline").forEach((b) => b.addEventListener("click", () => toggleNight(b)));
  root.querySelector("#add")?.addEventListener("click", () => {
    store.clubs = [...store.clubs, club];
    renderClub(id);
  });
  root.querySelectorAll("[data-legend]").forEach((b) => b.addEventListener("click", () => {
    const part = b.dataset.legend;
    openSheet({ lights: t("Rowing light"), conditions: t("Weather symbols"), hourly: t("The columns") }[part], legendBody(part));
  }));
  root.querySelector("#no-warning")?.addEventListener("click", () => {
    openSheet(t("Official warnings"), warningsBody(forecast.warnings, club, forecast.generatedAt, true));
  });
  root.querySelectorAll("[data-tile]").forEach((b) => b.addEventListener("click", () => {
    location.hash = `#/club/${encodeURIComponent(id)}/value/${b.dataset.tile}`;
  }));
  wireTopTile(root.querySelector(".card.now"), id);
  wireCurrent(root, forecast);
  root.querySelector("#source-line")?.addEventListener("click", () => openSheet(t("Where the forecast comes from"), sourceBody(forecast.forecastSource)));
  root.querySelectorAll("[data-hour]").forEach((b) => b.addEventListener("click", () => {
    const at = forecast.hours.find((x) => x.time === b.dataset.hour);
    // Within the radar's 2 hours the rain values come from the radar, later from the forecast.
    const radar = radarAt(club?.launchPoint);
    // The lake map at this hour, when the page has a lake view (HourDetailView).
    const lakeMap = root.querySelector("#lake-view .lake-card")
      ? `<a class="pill wide" href="#/lake/${encodeURIComponent(forecast.lakeId)}/${encodeURIComponent(id)}?at=${encodeURIComponent(at.time)}">${icon("map")} ${h(t("Lake map at %@", dayTime(at.time)))}</a>`
      : "";
    // With Current conditions in the top tile, the hour's top tile opens into its tiles too.
    openSheet(dayTime(at.time), nowCard(forecast, at, { at: new Date(at.time), stale: isStale(forecast), radar, radarState: radarStatus(club?.launchPoint) })
      + (store.combinedTopTile ? "" : conditionsCard(forecast, at, radar, radarStatus(club?.launchPoint))) + lakeMap, (sheet) => {
      // A value from a later hour opens its page at that hour.
      sheet.querySelectorAll("[data-tile]").forEach((t2) => t2.addEventListener("click", () => {
        location.hash = `#/club/${encodeURIComponent(id)}/value/${t2.dataset.tile}/${encodeURIComponent(at.time)}`;
      }));
      wireTopTile(sheet.querySelector(".card.now"), id, at.time);
      wireCurrent(sheet, forecast);
      watchFitLines(sheet);
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
    if (next) moveTo(`#/club/${encodeURIComponent(next)}`, step > 0 ? "next" : "prev");
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
/** The light a value sets in an hour while amber or red, never green, so a coloured value always means "this is why" (Condition.cause). */
function causeOf(condition, hour) {
  let light = REASONS[condition] ? lightFor(hour, REASONS[condition]) : null;
  // Also when the water within 1 km sets the light through this value (Condition.cause).
  for (const r of hour?.reasons ?? []) {
    if (r.condition === "nearby_water" && REASONS[condition]?.includes(r.topic) && (light == null || RANK_OF[r.light] > RANK_OF[light])) light = r.light;
  }
  return light && light !== "green" ? light : null;
}
const RANK_OF = { green: 0, amber: 1, red: 2 };
/** The class that colours a value in the light it sets, or the cold-water blue on the water (causeTinted, ColdWaterKit.valueTint). */
const causeClass = (light, cold = false) => (light ? ` cause-${light}` : cold ? " cause-cold" : "");

/**
 * The values the closed combined top tile does not show, while they count for the light;
 * ice also whenever the ice line would show (NowCard.peeks). On rivers and lowered lakes
 * the Current or Water level tile takes the ice tile's place, so ice has no line there.
 */
function peeks(forecast, hour) {
  const iceTile = !forecast.river && !isLowered(forecast.waterLevel);
  return ["thunderstorm", "cloudCover", "humidity", "pressure", "uvIndex", "ice"].filter((c) => {
    if (c === "ice") return iceTile && (iceValue(forecast) != null || causeOf(c, hour) != null);
    return causeOf(c, hour) != null;
  });
}

/** One hidden value as a line under the sun line, in its tile's own words, the value in the light's colour (TilePeekLine, P3). */
function peekLine(condition, forecast, hour, radar) {
  const parts = conditionTile(condition, forecast, hour, radar, null, true);
  if (!parts) return "";
  const light = causeOf(condition, hour);
  return `<p class="peek-line" data-top="${condition}" role="button" tabindex="0"><span class="peek-title">${conditionIcon(condition)} ${h(conditionTexts()[condition][1])}</span>
    <strong class="${causeClass(light).trim()}">${h(parts.value)}</strong>${parts.detail ? `<span class="sub">· ${h(parts.detail)}</span>` : ""}<span class="chev">${icon("chevron-right")}</span></p>`;
}

function nowCard(forecast, hour, { stale = false, at = null, radar = null, radarState = null } = {}) {
  // Current conditions inside the top tile, opening into all its tiles (app #315).
  const combined = store.combinedTopTile;
  const water = forecast.waterTemperature;
  const estimate = estimatedWater(forecast);
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
  const steadier = steadierBoat(hour, hourWater, boatsKeptAt(), selectedBoat().id, boatLimits);
  const d = conditionData(forecast, hour, radar);
  // The sky as the rain tile sees it: the radar decides whether anything falls.
  const kind = skyNow(d);
  // The waves line in fewer words than the tile's, so it fits under the value in German too.
  const fetch = hour.fetchM;
  const wavesCaption = fetch == null ? "" : fetch < 50 ? t("Offshore wind") : t("%@ open water", distance(fetch));
  const fogNow = (hour.visibilityM ?? Infinity) < 1000;
  const fog = d.next24.find((x) => (x.visibilityM ?? Infinity) < 1000);
  const visibilityCaption = fogNow ? t("Fog") : fog ? t("Fog from %@", time(fog.time)) : t("No fog");
  const iceLine = forecast.ice ? iceDetail(forecast.ice) : t("Check the lake yourself");
  // As wide as its longest direction ("from NW"), so the column keeps one width whatever the wind does.
  // The sun line's time in the light's colour while the daylight sets it, as every other value (owner's pick S1, 5 Nov 2026).
  const sunCause = causeClass(causeOf("daylight", hour)).trim();
  // Where the worst value within 1 km sets the light, the tile shows it, marked "Nearby" (app #409).
  const near = nearbyCondition(hour);
  const shown = shownWind(hour);
  const unitLine = (deg) => windUnit() + (near === "wind" ? ` · ${t("Nearby")}` : deg != null ? ` · ${t("from %@", compass(deg, lang()))}` : "");
  return `<section class="card now ${combined && store.topTileOpen ? "all-open" : ""}">
    <div class="now-head">
      ${dot(hour.light, 36, stale, at ? hourHalves(forecast, hour, stale) : null)}
      <div class="now-title">
        <h2><span class="verdict">${h(lightTitle(hour.light, stale))}</span> ${at ? "" : `<button class="info" data-legend="lights" aria-label="${h(t("What the symbols mean"))}">${icon("info")}</button>`}</h2>
        <small class="sub boat-for">${h(boat)}</small>
      </div>
      <div class="now-sky">${skySymbol(hour, "large", kind)}<small class="sub">${h(t(SKY_TITLES[kind]))}</small></div>
    </div>
    ${kit ? coldWaterBadge(kit, water == null) : ""}
    <ul class="reasons">
      ${stale && !at ? `<li class="orange">${icon("clock")}<span>${h(t("The forecast is more than 3 hours old. Check the conditions yourself before you go out."))}</span></li>` : ""}
      ${reasons.length ? reasons.map((r) => {
        const text = water == null && waterReasons.includes(r.condition) ? t("Estimated: %@", reasonExplanation(r.condition, r.light, r.topic)) : hourExplanation(forecast, r, hour);
        return `<li class="${r.light === "red" ? "red" : "orange"}">${icon(CONDITION_ICONS[reasonCondition(r.condition, r.topic)])}<span>${h(text)}</span></li>`;
      }).join("") : `<li>${icon("circle-check")}<span class="fit-line" data-short="${h(t("All within the limits."))}">${h(t("All conditions are within the limits."))}</span></li>`}
      ${(hour.notes ?? []).map((n) => `<li class="sub">${icon("info")}<span>${h(noteText(n))}</span></li>`).join("")}
      ${steadier ? `<li class="tint">${icon("rower")}<span>${h(steadier.light === "green"
        ? t("A steadier boat helps: %@ would be green now.", boatTitle(steadier.boat))
        : t("A steadier boat helps: %@ would only need care now.", boatTitle(steadier.boat)))}</span></li>` : ""}
      ${!at && warnings?.status === "ok" && localChecked(warnings) && !warnings.items?.length ? `<li><button class="no-warning" id="no-warning"><span class="green">${filledIcon("shield-check")} ${h(t("No official warning"))}</span>
        <span class="sub">· ${h(t("checked %@", time(forecast.generatedAt)))}</span> <span class="tint">${icon("info")}</span></button></li>` : ""}
      ${!at && warnings?.status === "ok" ? laterWarningLine(warningHeadline(warnings)) : ""}
    </ul>
    ${adviceOnly()}
    <hr>
    ${combined ? `<div class="tt-closed">` : ""}
    <div class="now-grid">
      <div class="air" data-top="temperature" role="button" tabindex="0">
        <small class="label">${conditionIcon("temperature")} ${h(t("Air"))}</small>
        <span class="v28${causeClass(causeOf("temperature", hour))}">${h(degrees(hour.temperatureC))}</span>
        ${hour.apparentTemperatureC != null ? `<small class="sub grey" data-top="feelsLike" role="button" tabindex="0">${icon("person-standing")} ${h(t("Feels like %@", degrees(hour.apparentTemperatureC)))}</small>` : ""}
      </div>
      <div class="${water == null && estimate != null ? "secondary" : ""}" data-top="waterTemperature" role="button" tabindex="0">
        <small class="label">${conditionIcon("waterTemperature")} ${h(t("Water"))}</small>
        <span class="v28${causeClass(causeOf("waterTemperature", hour), !!kit)}">${h(water == null && estimate != null ? degrees(estimate) : degrees(water?.celsius, 1))}</span>
        <small class="sub grey">${h(water ? t("Measured %@", time(water.measuredAt)) : estimate != null ? t("Estimated") : " ")}</small>
      </div>
      <div data-top="wind" role="button" tabindex="0">
        <small class="label">${conditionIcon("wind")} ${h(t("Wind"))}</small>
        <span class="v28${causeClass(causeOf("wind", hour))}">${h(windRange(shown.speed, shown.gust))}${hour.windFromDeg != null ? `<span class="arrow" style="transform:rotate(${hour.windFromDeg + 180}deg)">${icon("arrow-up")}</span>` : ""}</span>
        <small class="sub stack">${[0, 45, 90, 135, 180, 225, 270, 315].map((deg) => `<span aria-hidden="true">${h(unitLine(deg))}</span>`).join("")}<span>${h(unitLine(hour.windFromDeg))}</span></small>
      </div>
      <div data-top="waves" role="button" tabindex="0">
        <small class="label">${conditionIcon("waves")} ${h(t("Waves"))}</small><span class="v17${causeClass(causeOf("waves", hour))}">${h(waves(shownWaveHeightM(hour)))}</span>
        ${near === "waves" ? `<small class="sub grey">${h(t("Nearby"))}</small>` : wavesCaption ? `<small class="sub grey">${h(wavesCaption)}</small>` : ""}
      </div>
      <div class="now-rain" data-top="precipitation" role="button" tabindex="0">${rainCell(d, causeOf("precipitation", hour))}</div>
      <div data-top="visibility" role="button" tabindex="0">
        <small class="label">${conditionIcon("visibility")} ${h(t("Visibility"))}</small><span class="v17${causeClass(causeOf("visibility", hour))}">${h(distance(shownVisibilityM(hour)))}</span>
        <small class="sub grey">${h(near === "visibility" ? t("Nearby") : visibilityCaption)}</small>
      </div>
    </div>
    ${ice && !combined ? `<p class="ice-line" data-top="ice" role="button" tabindex="0"><small class="label">${conditionIcon("ice")} ${h(t("Ice"))}</small><span class="v17${causeClass(causeOf("ice", hour))}">${h(t(ice))}</span>
      <small class="sub">${h(iceLine === t("Bays and harbours first") ? t("Bays first") : iceLine)}</small></p>` : ""}
    ${sun ? `<p class="daylight" data-top="daylight" data-order="all" role="button" tabindex="0" aria-description="${h(t("Opens sunrise, sunset and daylight"))}">${sun.up
      ? `${sunPath(sun.sunrise, sun.sunset, at ?? new Date(), 44, 22)}<span class="sunline" aria-label="${h(t("Rowing until sunset at %@, %@ left", time(sun.sunset), duration(at ?? new Date(), sun.sunset)))}"><span class="nowrap">${h(t("Rowing until"))} <span class="sunsym">${icon("sunset")}</span><span class="${sunCause}">${h(time(sun.sunset))}</span></span> · <span class="nowrap">${h(t("%@ left", duration(at ?? new Date(), sun.sunset)))}</span></span>`
      : `<span class="moon">${icon("moon-star")}</span><span class="sunline" aria-label="${h(t("Rowing again from sunrise at %@", time(sun.sunrise)))}">${h(t("Rowing again from"))} <span class="sunsym">${icon("sunrise")}</span><span class="${sunCause}">${h(time(sun.sunrise))}</span></span>`}<span class="chev">${icon("chevron-right")}</span></p>` : ""}
    ${combined ? `${peeks(forecast, hour).map((c) => peekLine(c, forecast, hour, radar)).join("")}</div>
    <div class="tt-open"><div class="tiles">${TILE_ORDER.map((c) => conditionTile(c, forecast, hour, radar, radarState)).join("")}</div></div>
    ${allValuesButton()}` : ""}
  </section>`;
}

/**
 * Puts the club page's tips in their places (owner's placement rules, 12 Nov 2026): the top tile's
 * card tip under its first line; bubbles on its values, on All values, on the first hour and on the
 * forecast line. paceTips (in wireTips) then shows at most one of the page's tips.
 */
function placeClubTips(main, { topCardTip, valuesBubble, gripBubble }) {
  const now = main?.querySelector(".card.now");
  if (!now) return;
  now.querySelector(".now-head")?.insertAdjacentHTML("afterend", topCardTip);
  const values = now.querySelector(store.combinedTopTile && store.topTileOpen ? ".tt-open .tiles" : ".now-grid");
  if (valuesBubble) values?.insertAdjacentHTML("beforeend", bubbleTip(valuesBubble).replace('class="tip pop"', 'class="tip pop up"'));
  if (gripBubble) now.querySelector(".all-values")?.insertAdjacentHTML("afterend", gripBubble);
  main.querySelector("p.source")?.insertAdjacentHTML("beforeend", bubbleTip("source"));
  // One hour in full points at the table's first hour: the bubble sits just under that row.
  const row = main.querySelector(".hrow[data-hour]");
  const hours = bubbleTip("hourView");
  if (row && hours) {
    row.insertAdjacentHTML("afterend", hours);
    const bubble = row.nextElementSibling;
    bubble.style.top = `${row.offsetTop + row.offsetHeight + 10}px`;
  }
  // A closed tip hands over to the next in its chain, so a bubble's tip can also turn up as a card tip: the bubble wins.
  for (const pop of main.querySelectorAll(".tip.pop[data-tip]")) {
    main.querySelectorAll(`.tip:not(.pop)[data-tip="${pop.dataset.tip}"]`).forEach((other) => other.remove());
  }
}

/** The words under the top tile that open and close it, as Apple's "Show more" rows (grip G2). */
function allValuesButton(open = store.topTileOpen) {
  return `<button class="all-values" aria-expanded="${open}" aria-description="${h(open ? t("Shows the short top tile again") : t("Opens all values in the top tile"))}">
    <span>${h(open ? t("Fewer values") : t("All values"))}</span>${icon("chevron-down")}</button>`;
}

/** The top tile's rain value with the rain tile's line under it, so both always say the same. */
/**
 * The top tile's values open their own pages, and swiping there moves through
 * the tile's values in its order (NowCard.tileValues), as in the app.
 */
/** The Current tile opens the water level and current (CurrentDetailView). */
function wireCurrent(box, forecast) {
  box.querySelectorAll("[data-current]").forEach((b) => b.addEventListener("click", () => {
    // Using the tile closes its tip, as the app's invalidate(reason: .actionPerformed).
    closeTip(root, "riverCurrent");
    openSheet(t("Current"), currentBody(forecast.river));
  }));
  box.querySelectorAll("[data-water-level]").forEach((b) => b.addEventListener("click", () => {
    closeTip(root, "waterLevel");
    openSheet(t("Water level"), waterLevelBody(forecast.waterLevel));
  }));
}

function wireTopTile(card, id, at = null) {
  // Open or closed, the same on every club page and in the hour view: a tap on the words only, so a swipe that
  // starts on them scrolls the page (owner's pick A, app #372).
  const handle = card?.querySelector(".all-values");
  if (handle) {
    const toggle = () => {
      closeTip(document, "allValues");
      store.topTileOpen = !store.topTileOpen;
      document.querySelectorAll(".card.now").forEach((c) => {
        c.classList.toggle("all-open", store.topTileOpen);
        c.querySelector(".all-values")?.replaceWith(document.createRange().createContextualFragment(allValuesButton()));
      });
      document.querySelectorAll(".card.now").forEach((c) => wireHandle(c));
    };
    const wireHandle = (c) => {
      const b = c.querySelector(".all-values");
      if (!b || b.dataset.wired) return;
      b.dataset.wired = "1";
      // A finger or mouse that moved more than a little was a swipe, not a tap: it does nothing.
      let start = null;
      let moved = 0;
      b.addEventListener("pointerdown", (e) => (start = [e.clientX, e.clientY]));
      b.addEventListener("pointerup", (e) => (moved = start ? Math.hypot(e.clientX - start[0], e.clientY - start[1]) : 0));
      b.addEventListener("click", () => {
        const swipe = moved > 10;
        moved = 0;
        start = null;
        if (!swipe) toggle();
      });
    };
    wireHandle(card);
  }
  for (const el of card?.querySelectorAll("[data-top]") ?? []) {
    const open = (e) => {
      e.stopPropagation();
      // In the combined tile the value pages swipe through all values (ConditionTiles.order).
      const all = el.dataset.order === "all" || store.combinedTopTile;
      location.hash = `#/club/${encodeURIComponent(id)}/value/${el.dataset.top}${at ? `/${encodeURIComponent(at)}` : ""}${all ? "" : "?order=top"}`;
    };
    el.addEventListener("click", open);
    el.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        open(e);
      }
    });
  }
}

function rainCell(d, cause = null) {
  const lines = rainLines(d);
  const caption = lines.detail === t("Dry next 24 h") ? t("Dry for 24 h") : lines.detail;
  return `<small class="label">${conditionIcon("precipitation")} ${h(t("Precipitation"))}</small><span class="v17${causeClass(cause)}">${h(lines.value)}</span>
    ${caption ? `<small class="sub grey">${lines.fromRadar ? radarMark() : ""}${h(caption)}</small>` : ""}`;
}

/** The DWD warnings card, shown while a warning is out or DWD could not be checked (WarningsCard). */
/**
 * For a warning that starts later or does not count for the light, one line in the
 * top tile naming it (amber when it counts and starts within hours, else grey), so
 * the light and the warnings card tell the same story. Counting warnings in force
 * are reasons already. Tapping it opens the warnings.
 */
function laterWarningLine(headline) {
  if (!headline || headline.urgency === "now") return "";
  const { warning, urgency } = headline;
  const soon = urgency === "soon";
  const text = warningInfoOnly(warning) ? t("%@ · not part of the rowing light", warningLine(warning)) : warningLine(warning);
  return `<li><button class="no-warning ${soon ? "orange" : "sub"}" id="no-warning" aria-description="${h(t("Opens the warnings"))}">${icon(soon ? "triangle-alert" : "info")}<span>${h(text)}</span></button></li>`;
}

function warningsCard(warnings, club, checkedAt) {
  const title = t("Official warnings");
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
    return `${lakeRows}${notCheckedNote(warnings.local)}<p class="sub small">${h(note)}</p>${lightsInfo(warnings, guideOpen)}`;
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
  const guide = lightsInfo(warnings, guideOpen);
  if (!items.length) {
    return `<p class="green strong">${icon("shield-check")} ${h(t("No warning right now"))}</p>
      <p class="sub small">${h(`${coverage} ${t("Checked %@.", time(checkedAt))}`)}</p>${guide}`;
  }
  const lake = items.filter((w) => w.kind === "lake");
  const other = items.filter((w) => w.kind !== "lake");
  // "Now" and "Later" so a warning for tonight is not read as one for this hour.
  const now = other.filter((w) => warningActive(w));
  const later = other.filter((w) => !warningActive(w)).sort((a, b) => new Date(a.onset ?? 0) - new Date(b.onset ?? 0));
  const label = (text) => `<p class="warn-group">${h(text)}</p>`;
  return `${lake.map(warningRow).join("")}${guide}${now.length && later.length ? label(t("Now")) : ""}${now.map(warningRow).join("")}
    ${later.length ? label(t("Later")) : ""}${later.map(warningRow).join("")}<p class="sub small">${h(coverage)}</p>`;
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
    ${warningInfoOnly(w) ? `<p class="sub small info-line">${icon("info")} <span>${h(warningSlippery(w)
      ? t("Not part of the rowing light. The jetty and boat area may be slippery.")
      : t("Not part of the rowing light: it is not about the water."))}</span></p>` : ""}
    ${sourceLinks(w)}
  </div>`;
}

// DWD's WarnWetter app (App Store id 986420993); it has no web links to open it at a place.
const WARNWETTER_APP_STORE = "https://apps.apple.com/de/app/id986420993";

/**
 * Where the warning can be read at the service that issued it (SourceLinks in
 * WarningsCard.swift): DWD's town or inland lake page, GeoSphere's map at the
 * launch point, MeteoSwiss's hazards page (its app opens that page on an iPhone).
 */
function sourceLinks(w) {
  const url = w.links?.[lang()] ?? w.links?.de;
  if (!url) return "";
  const main = w.source === "meteoswiss" ? t("Show in the MeteoSwiss app or website") : t("Show on the %@ website", serviceShort(w.source));
  return `<p class="source-links"><a class="strong" href="${h(url)}" target="_blank" rel="noopener">${icon("link")} ${h(main)}</a>`
    + (isDWD(w) ? `<br><a class="small" href="${WARNWETTER_APP_STORE}" target="_blank" rel="noopener">${icon("link")} ${h(t("DWD WarnWetter app in the App Store"))}</a>` : "")
    + `</p>`;
}

/**
 * The shore lights explained where the lake has them; where DWD warns for the
 * lake without lights (e.g. the Alster), one line saying so instead (WarningsCard.lightsInfo).
 */
function lightsInfo(warnings, open) {
  if (!warnings.lakeArea) return "";
  if (warnings.shoreLights ?? true) return shoreLights(open);
  return `<p class="sub small info-line">${icon("siren")} <span>${h(t("This lake has no storm warning lights on the shore. DWD's lake warning shows here in the app."))}</span></p>`;
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
function conditionsCard(forecast, hour, radar = null, radarState = null) {
  const kind = skyNow(conditionData(forecast, hour, radar));
  const head = `<div class="cc-head">${skySymbol(hour, "large", kind)}<div><strong>${h(t(SKY_TITLES[kind]))}</strong>
    <small class="sub">${h(t("%@ · feels like %@", degrees(hour.temperatureC), degrees(hour.apparentTemperatureC)))}</small></div></div>`;
  const tiles = TILE_ORDER.map((c) => conditionTile(c, forecast, hour, radar, radarState)).join("");
  return card(t("Current conditions"), "gauge", `${head}<div class="tiles">${tiles}</div>`, { legend: "conditions" });
}

function conditionTile(condition, forecast, hour, radar = null, radarState = null, parts = false) {
  const i = forecast.hours.indexOf(hour);
  const next24 = forecast.hours.slice(Math.max(0, i), Math.max(0, i) + 24);
  const titles = conditionTexts();
  const graphic = conditionGraphic(condition, forecast, hour);
  const light = REASONS[condition] ? lightFor(hour, REASONS[condition]) : null;
  // Whether the rain tile's bars come from the radar; faint while it is read, struck through when it could not be.
  // Only for now: a picked later hour is past the radar's two hours anyway (ConditionTile).
  const rainData = condition === "precipitation" ? conditionData(forecast, hour, radar) : null;
  const mark = !rainData ? "" : radarAhead(rainData) ? radarTitleMark() : radarState && rainData.isNow ? radarTitleMark(radarState) : "";
  // No dot: the value that sets the light takes its colour, and its tile a faint wash and rim (C1 + T2); the water blue while the life jacket shows (W2).
  const header = (title) => `<span class="tile-head">${conditionIcon(condition)}<span>${h(title)}</span>${mark}${icon("chevron-right")}</span>`;
  const water = forecast.waterTemperature;
  const estimate = estimatedWater(forecast);
  const cause = causeClass(causeOf(condition, hour), condition === "waterTemperature" && !!coldWaterKit(water?.celsius ?? estimate, currentLimits()));
  const sets = causeOf(condition, hour) ? `, ${t("Sets the light: %@", lightTitle(causeOf(condition, hour)))}` : "";
  // `mark`: rain read from the radar starts its line with the radar's symbol.
  const tile = (value, detail, graphic = "", off = false, mark = "") => parts ? { value, detail } : `<button class="tile ${off ? "off" : ""}${cause}" data-tile="${condition}">
    ${header(titles[condition][1])}
    <span class="tile-body"><span><strong aria-label="${h(value + sets)}">${h(value)}</strong><small${condition === "precipitation" ? ' class="may-wrap"' : ""}>${mark}${h(detail)}</small></span><span class="graphic">${graphic}</span></span></button>`;
  const temps = next24.map((x) => x.temperatureC).filter((v) => v != null);
  switch (condition) {
    case "temperature":
      return tile(degrees(hour.temperatureC), temps.length ? t("High %@ · low %@", degrees(Math.max(...temps)), degrees(Math.min(...temps))) : "", graphic);
    case "feelsLike":
      return tile(degrees(hour.apparentTemperatureC), feelsLikeNote(hour) ? t(feelsLikeNote(hour)) : "", graphic);
    case "wind": {
      const gust = t("Gusts %@", windNumber(hour.windGustMs));
      return tile(wind(hour.windSpeedMs), hour.windFromDeg != null ? `${gust} · ${t("from %@", compass(hour.windFromDeg, lang()))}` : gust, graphic);
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
      // On a river the Current tile takes the ice tile's place (ConditionsCard).
      if (forecast.river) return currentTile(forecast.river);
      // On a lake let down for the winter the Water level tile takes it.
      if (isLowered(forecast.waterLevel)) return waterLevelTile(forecast.waterLevel);
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
      const lines = rainLines(rainData);
      return tile(lines.value, lines.detail, radarGraphic(rainData) ?? graphic, false, lines.fromRadar ? radarMark() : "");
    }
    case "thunderstorm": {
      const level = light === "red" ? 3 : light === "amber" ? 2 : 1;
      const storm = (forecast.warnings?.items ?? []).some((w) => /GEWITTER/i.test(w.event ?? ""));
      const note = !localChecked(forecast.warnings) ? t("Warnings not checked")
        : storm ? t("Official warning") : t("No warning");
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
        ? `<button class="tile${cause}" data-tile="daylight">${header(t("Sunset"))}<span class="tile-body"><span><strong>${h(time(sun.sunset))}</strong><small>${h(t("Sunrise %@", time(sun.sunrise)))}</small></span><span class="graphic">${graphic}</span></span></button>`
        : `<button class="tile${cause}" data-tile="daylight">${header(t("Sunrise"))}<span class="tile-body"><span><strong>${h(time(sun.sunrise))}</strong><small>${h(t("Sunset %@", time(sun.sunset)))}</small></span><span class="graphic">${graphic}</span></span></button>`;
    }
    default:
      return "";
  }
}


/** The next 48 hours and the rest of their last night, a row an hour under a day header
 * with sunrise and sunset (HourlyCard). */
function hourlyCard(forecast, now, stale) {
  const list = nextHours(forecast.hours, now);
  // While it stays at the top, the header also names the tile and the day in view (HourlyStickyHeader).
  const head = `<div class="hrow hhead">
    <span class="hhead-title" aria-hidden="true">${icon("clock")}<span>${h(t("Next 48 hours"))}</span><span class="hhead-day"></span></span>
    <span>${icon("clock")}</span><span>${dot("grey", 8)}</span><span>${icon("cloud-sun")}</span>
    ${[["temperature", unitSymbol("temperature")], ["feelsLike", unitSymbol("temperature")], ["wind", windUnit()], ["waves", unitSymbol("waves")],
      ["precipitation", unitSymbol("rain")], ["visibility", unitSymbol("distance")]]
      .map(([c, unit]) => `<span class="num">${icon(CONDITION_ICONS[c])}<small>${h(unit)}</small></span>`).join("")}</div>`;
  let lastDay = null;
  const index = new Map(list.map((x, i) => [x, i]));
  // Past the first 24 hours: hidden while the table is folded in two columns.
  const later = (x) => (index.get(x) >= FOLDED_HOURS ? "later" : "");
  const row = (x) => {
    const day = localDay(x.time);
    let header = "";
    if (day !== lastDay) {
      const sun = forecast.daylight?.find((d) => d.date === day);
      header = `<div class="dayhead ${later(x)}" data-day="${day}"><strong>${h(dayLabel(day))}</strong>${sun ? `<span>${icon("sunrise")} ${h(time(sun.sunrise))} ${icon("sunset")} ${h(time(sun.sunset))}</span>` : ""}</div>`;
      lastDay = day;
    }
    const fog = lightFor(x, ["fog"]);
    const halves = hourHalves(forecast, x, stale);
    const coarser = coarserModel(forecast, x) ? "≈" : "";
    const sentence = hourSentence(x, stale, halves) + (coarser ? `, ${t("coarser model")}` : "");
    return `${header}<button class="hrow ${x.sunUp === false ? "night" : ""} ${later(x)}" data-hour="${h(x.time)}" aria-label="${h(sentence)}">
      <span>${h(coarser + time(x.time))}</span><span>${dot(x.light, 12, stale, halves)}</span><span>${skySymbol(x)}</span>
      <span class="num">${h(num(inUnit("temperature", x.temperatureC)))}</span>
      <span class="num sub">${h(num(inUnit("temperature", x.apparentTemperatureC)))}</span>
      <span class="num">${h(windRange(x.windSpeedMs, x.windGustMs))}</span>
      <span class="num">${h(wavesNumber(x.waveHeightM))}</span>
      <span class="num ${(x.precipitationMm ?? 0) >= 0.1 ? "blue" : ""}">${h(rainNumber(x.precipitationMm))}</span>
      <span class="num ${fog && fog !== "green" ? (fog === "red" ? "red" : "orange") : ""}">${h(distanceNumber(x.visibilityM))}</span>
    </button>`;
  };
  // Every night hour on its own row: a developer choice (NightHours.all).
  const parts = store.nightHours === "all" ? list.map((hour) => ({ hour })) : nightParts(list, sunDaysOf(forecast));
  const rows = parts.map((part) => {
    if (part.hour) return row(part.hour);
    // The night's day header after midnight shows inside the opened night; folded,
    // the next hour shown brings its own (hidden again while the night is open).
    const dayBefore = lastDay;
    const inside = part.night.map(row).join("");
    const crossed = lastDay !== dayBefore;
    lastDay = dayBefore;
    const after = crossed ? "afternight" : "";
    return nightLine(part.night, list, later(part.night[0]), forecast) + `<div class="nightrows" hidden>${inside}</div>` + `<span class="nightmark ${after}" hidden></span>`;
  }).join("");
  const fold = foldsHourly() && list.length > FOLDED_HOURS ? `<button class="fold" type="button" aria-expanded="false">${foldLabel(false)}</button>` : "";
  return card(t("Next 48 hours"), "clock", `<div class="hourly ${usesAMPM() ? "ampm" : ""}">${head}<div class="hrows">${rows}</div></div>${fold}`,
    { legend: "hourly", cls: `hourly-card ${fold ? "folds" : ""}` });
}

/**
 * A folded night as one row of the 48 hours (NightRow in the app): its hours, a
 * chevron and the moon in the first three columns, then under each column the
 * night's worst. A tap shows or hides the night's hours (toggleNight).
 */
function nightLine(hours, list, later, forecast) {
  const n = nightSummary(hours);
  // The night's later hours from a coarser model (after the 48 hours): said inside the line (owner, 12 Nov 2026).
  const from = hours.find((x) => coarserModel(forecast, x));
  const coarser = from ? coarserText(from.time, coarserModel(forecast, from)) : "";
  // Open-ended only where the night really starts or ends the table (NightRow.startsTable/endsTable);
  // a night after the current hour's row starts at a known hour, "18–07", not "–07".
  const start = hours[0] === list[0] ? "" : hourOnly(n.start);
  const cut = hours[hours.length - 1] === list[list.length - 1] && !endsAtSunrise(Date.parse(n.end), sunDaysOf(forecast));
  const to = cut ? "" : hourOnly(n.end);
  const fog = n.fog && n.fog !== "green" ? (n.fog === "red" ? "red" : "orange") : "";
  const rain = (n.rainMm ?? 0) >= 0.1;
  const label = [t("Night from %@ to %@", time(n.start), time(n.end)), t("lowest %@", degrees(n.lowestC)), n.frost ? t("frost") : "",
    n.gustMs != null ? t("gusts up to %@", wind(n.gustMs)) : "", rain ? t("%@ rain", rainNumber(n.rainMm) + " " + unitSymbol("rain")) : t("dry"),
    fog ? t("fog, visibility down to %@", distance(n.visibilityM)) : "", coarser.slice(2)].filter(Boolean).join(", ");
  return `<button class="hrow nightline ${later}" type="button" aria-expanded="false" aria-label="${h(label)}" title="${h(t("Shows the night hours"))}">
    <span class="range">${h(`${start}–${to}`)}</span><span class="chev">${icon("chevron-down")}</span><span class="moon">${icon("moon")}</span>
    <span class="num ${n.frost ? "blue" : ""}">${n.frost ? icon("snowflake") : ""}${h(num(inUnit("temperature", n.lowestC)))}</span>
    <span class="num sub">${h(num(inUnit("temperature", n.lowestFeelsLikeC)))}</span>
    <span class="num">${h(windRange(n.windMs, n.gustMs))}</span>
    <span class="num">${h(wavesNumber(n.wavesM))}</span>
    <span class="num ${rain ? "blue" : ""}">${h(rainNumber(n.rainMm))}</span>
    <span class="num ${fog}">${h(distanceNumber(n.visibilityM))}</span>
    ${coarser ? `<span class="coarser">${h(coarser)}</span>` : ""}
  </button>`;
}

/** "≈ from 00:00 coarser model: ICON-EU, 7 km grid" (NightRow.coarserText in the app). */
function coarserText(from, part) {
  return `≈ ${t("from %@ coarser model: %@", time(from), `${part.model}, ${gridText(part.resolutionKm)}`)}`;
}

/** Opens or folds one night of the 48 hours. */
function toggleNight(button) {
  const open = button.getAttribute("aria-expanded") !== "true";
  button.setAttribute("aria-expanded", String(open));
  button.title = open ? t("Folds the night hours") : t("Shows the night hours");
  button.querySelector(".chev").innerHTML = icon(open ? "chevron-up" : "chevron-down");
  const rows = button.nextElementSibling;
  rows.hidden = !open;
  // The next day's header, when the night crossed midnight: shown inside while open.
  if (rows.nextElementSibling?.classList.contains("afternight")) {
    rows.nextElementSibling.nextElementSibling?.classList.toggle("dup", open);
  }
}

/**
 * True: in two columns the 48 hours show the first 24 until opened, so the
 * columns end level (ColumnFill.fold, a developer choice in the app). False,
 * the default since each night folds into one line: the whole table
 * (ColumnFill.fill, "Always 48 hours").
 */
const foldsHourly = () => store.columnFill === "fold";
const FOLDED_HOURS = 24;

function foldLabel(open) {
  return `${icon(open ? "chevron-up" : "chevron-down")} <span>${h(open ? t("Show fewer hours") : t("Show 24 more hours"))}</span>`;
}

/**
 * Opens the rest of the table or folds it back. Its folded height stays what
 * the columns count with (balanceCards), so no other card moves or grows; folding
 * keeps the button where it was in the window.
 */
function foldHourly(button) {
  const box = button.closest(".hourly-card");
  const open = !box.classList.contains("open");
  const before = button.getBoundingClientRect().top;
  if (open) box.dataset.folded = box.offsetHeight;
  box.classList.toggle("open", open);
  button.setAttribute("aria-expanded", String(open));
  button.innerHTML = foldLabel(open);
  if (!open) document.scrollingElement.scrollTop += button.getBoundingClientRect().top - before;
}

/** Where directions to the club go: its address, and its name with it; null without an address (own places). */
function clubAddress(club) {
  const address = club.address?.trim();
  return address ? { address, named: `${club.name || club.shortName}, ${address}` } : null;
}

/** The launch point on a map, with what it stands for (LaunchPointMapCard), when it is not in the header. */
function launchPointCard(club) {
  return card(t("Launch point"), "map-pin", launchPointBody(club, "launch-map"));
}

/** The map, the note on what it is for, and the coordinates with Open in Maps (LaunchPointDetails). */
function launchPointBody(club, mapId) {
  const { lat, lon } = club.launchPoint;
  // Opens in the map service chosen under Settings > Maps.
  const maps = MAPS_APPS[store.mapsApp];
  // Which point the forecast is for, said for this club (as in the app's Location sheet).
  const unconfirmed = club.source === "drv"
    ? t("No launch point set yet: the forecast, waves and warnings are for the club's address.")
    : t("No launch point set yet: the forecast, waves and warnings are for the club's place on OpenStreetMap.");
  return `
    <div class="map" id="${mapId}" role="img" aria-label="${h(t("Map of the launch point of %@", club.shortName || club.name))}"></div>
    ${club.launchPointVerified || club.launchPointSet ? `<p class="forecast-point">${h(t("The forecast, waves and warnings are for the club's launch point."))}</p>` : `<p class="orange">${icon("map-pin-off")} ${h(unconfirmed)}</p>`}
    ${mapId === "launch-sheet-map" && suggestRow(club).includes("data-suggest-lp") ? suggestRow(club).replace(/<\/p>$/, `${bubbleTip("suggestLaunchPoint")}</p>`) : suggestRow(club)}
    <div class="osm-slot"></div>
    <div class="map-foot"><small class="sub coords">${h(`${lat.toFixed(5)}° N, ${lon.toFixed(5)}° E`)}</small>
      <details class="maps-menu"><summary class="pill">${icon("map")} ${h(t("Open in Maps"))}</summary>
        <div class="menu" role="menu">
          <a role="menuitem" href="${h(maps.directions(lat, lon, clubAddress(club)))}" target="_blank" rel="noopener noreferrer">${icon("map-pinned")} ${h(t("Directions to the club"))}</a>
          <a role="menuitem" href="${h(maps.place(lat, lon))}" target="_blank" rel="noopener noreferrer">${icon("map-pin")} ${h(t("Launch point on the map"))}</a>
          <small class="sub">${h(maps.name)}</small>
        </div></details></div>`;
}

// The "Open in Maps" and "…" menus close on a tap outside it, on one of its links and with Escape, as a menu does.
document.addEventListener("click", (e) => {
  for (const menu of document.querySelectorAll(".maps-menu[open], .more-menu[open]")) if (!menu.contains(e.target) || e.target.closest(".menu a, .menu button")) menu.open = false;
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") for (const menu of document.querySelectorAll(".maps-menu[open], .more-menu[open]")) menu.open = false;
});

async function showLaunchMap(club, place = root.querySelector("#launch-map")) {
  // The club's OpenStreetMap place, as the app's "In Apple Maps as …" line (osmplace.js); also without the map.
  loadCatalog().catch(() => []).then((lakes) => {
    const slot = place?.parentElement?.querySelector(".osm-slot");
    const known = lakes.flatMap((l) => l.clubs).find((c) => c.id === club.id);
    if (slot) slot.innerHTML = osmPlaceCard(known?.mapPlace, MAPS_APPS[store.mapsApp]);
  });
  const L = await loadLeaflet().catch(() => null);
  const box = place;
  if (!L || !box) return;
  const { lat, lon } = club.launchPoint;
  const map = L.map(box, { scrollWheelZoom: false, attributionControl: true }).setView([lat, lon], 14);
  // Map or satellite pictures, remembered, as the app's Location card (RWLaunchImagery).
  baseMap(L, map, { storeKey: "rf.launchImagery", small: true });
  const marker = L.marker([lat, lon], {
    icon: L.divIcon({ className: "pin", html: icon(markIcon(club.id)), iconSize: [30, 30], iconAnchor: [15, 15] }),
    keyboard: false,
  }).addTo(map);
  // Zoomed in, the club's pin moves onto its own place on the map, and oars mark a set launch point (ClubMarks).
  loadCatalog().catch(() => []).then((lakes) => {
    const known = { ...lakes.flatMap((l) => l.clubs).find((c) => c.id === club.id), launchPoint: club.launchPoint };
    const clubhouse = clubhouseOf(known);
    if (clubhouse && box.isConnected) splitClubPins(L, map, [{ marker, launch: club.launchPoint, clubhouse, oars: showsOars(known), own: true }]);
    // With a clubhouse of its own, say which of the two the forecast is for (forecastPointLine).
    const line = box.parentElement?.querySelector(".forecast-point");
    if (clubhouse && line) line.textContent = t("The forecast, waves and warnings are for the launch point (oars), not the clubhouse.");
  });
  // Moved or zoomed away: a button back to the launch point, at the top left (LaunchPointDetails' scope button).
  const home = () => map.setView([lat, lon], 14);
  const back = L.control({ position: "topleft" });
  back.onAdd = () => {
    const button = L.DomUtil.create("button", "glass sat-switch small back-home");
    button.type = "button";
    button.innerHTML = icon("locate-fixed");
    button.setAttribute("aria-label", t("Back to the launch point"));
    button.title = t("Back to the launch point");
    button.hidden = true;
    L.DomEvent.disableClickPropagation(button);
    button.addEventListener("click", home);
    return button;
  };
  back.addTo(map);
  map.on("moveend zoomend", () => {
    const moved = map.distance(map.getCenter(), [lat, lon]) > 30 || map.getZoom() !== 14;
    back.getContainer().hidden = !moved;
  });
  // Grown or shrunk to fill its column (balanceCards).
  new ResizeObserver(() => map.invalidateSize()).observe(box);
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
  // As the app's line: the weather symbol first, the info symbol after the text.
  return `<p class="source"><button class="link" id="source-line">${icon("cloud-sun")}<span>${h(t("Forecast: %@", `${short} ${part.model}, ${gridText(part.resolutionKm)}`))}</span>${icon("info")}</button></p>`;
}

const gridText = (km) => t("%@ km grid", num(km, km % 1 ? 1 : 0));

/** Which weather models the forecast comes from, for which hours (ForecastSourceSheet). */
function sourceBody(source) {
  const parts = source.parts.map((part) => `<li><strong>${h(part.model)}</strong><span>${h(part.provider)}</span>
    <small class="sub">${h(t("Hours %@ to %@ · %@", String(part.fromHour), String(part.toHour), gridText(part.resolutionKm)))}</small></li>`).join("");
  return `<ul class="source-parts">${parts}</ul>
    <p class="small sub">${h(t("Weather models are computer forecasts from national weather services. A finer grid shows more of the lake and the hills around it."))}</p>
    <ul class="legend">
      ${source.picked == null ? `<li>${icon("badge-check")}<span>${h(t("The app picks the weather model that does best for this region."))}</span></li>` : ""}
      <li>${icon("gauge")}<span>${h(t("The choice is checked regularly against measured wind and temperature."))}</span></li>
      <li>${icon("radio-tower")}<span>${h(t("Data via Open-Meteo."))}</span></li>
    </ul>`;
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
  ["rain", "precipitation", key("Precipitation")], ["distance", "visibility", key("Visibility and distances")], ["pressure", "pressure", key("Air pressure")],
];
const TIME_TITLES = { device: key("Device"), h24: key("24-hour"), h12: key("12-hour") };
const DATE_TITLES = { device: key("Device"), long: key("Long"), short: key("Short"), dmy: key("Day.Month.Year"), mdy: key("Month/Day/Year") };
// 18:30 in the lakes' time zone, to show each time format.
const SAMPLE_TIME = Date.UTC(2026, 0, 15, 17, 30);

/** What a factory reset keeps: the visitor's clubs, own boats and routes, and what they have already seen (AppSettings.resetToFactorySettings). */
const FACTORY_KEEPS = ["rf.clubs", "rf.boats", "rf.routes", "rf.safety", "rf.catalog", "rf.tourSeen", "rf.tourPage", "rf.tourDay", "rf.tipsClosed", "rf.tipsOff", "rf.tipDay", "rf.countryByTown"];

/** "Like the iPhone", "Like the iPad" or, elsewhere, "Like this browser": the app's "Like the iPhone" switches (owner, 4 Nov 2026). */
function likeDeviceTitle() {
  const ua = navigator.userAgent;
  if (/iPhone|iPod/.test(ua)) return t("Like the iPhone");
  if (/iPad/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return t("Like the iPad");
  return t("Like this browser");
}

/** A switch row as Date & Time > Set Automatically: on follows the device, with what it gives now under it. */
const likeDeviceRow = (id, on, now) => `<label class="row-setting"><span class="stack"><span>${h(likeDeviceTitle())}</span>${on ? `<small class="sub">${h(now)}</small>` : ""}</span>
  <input type="checkbox" class="switch" role="switch" id="${id}" ${on ? "checked" : ""}></label>`;

/** Time and date both follow the device (AppSettings.dateTimeLikeDevice). */
const dateTimeLikeDevice = () => store.timeFormat === "device" && store.dateFormat === "device";

/** On: both follow the device. Off: the formats closest to what the device shows now, so nothing jumps. */
function setDateTimeLikeDevice(on) {
  if (on) {
    store.timeFormat = "device";
    store.dateFormat = "device";
    return;
  }
  if (store.timeFormat === "device") store.timeFormat = usesAMPM() ? "h12" : "h24";
  if (store.dateFormat === "device") store.dateFormat = "long";
}

/** The topics of the first settings page, each with its own page (SettingsTopic). */
const SETTINGS_TOPICS = [
  // The app's symbols (SettingsTopic.symbol) and colours.
  ["appearance", key("Appearance"), "circle-half", "#007aff"],
  ["clubpages", key("Club pages"), "rectangle-stack", "#5856d6"],
  ["language", key("Language and units"), "globe", "#8e8e93"],
  ["data", key("Battery and data"), "battery-75", "#34c759"],
  ["help", key("Help"), "question", "#007aff"],
  ["about", key("About"), "info-plain", "#8e8e93"],
  ["developer", key("Developer"), "hammer", "#8e8e93"],
];
const settingsIcon = (name, colour) => `<span class="set-icon" style="--c: ${colour}">${icon(name)}</span>`;

/** The website's version, as Settings > About > Version in the app: "0.1.0 (723) · 22a69ce" (BuildInfo.swift, written by the build). */
let websiteVersion = "";
async function loadVersion() {
  if (websiteVersion) return websiteVersion;
  try {
    const found = await (await fetch(new URL("version.json", import.meta.url))).json();
    websiteVersion = found.summary || found.version || "–";
  } catch {
    websiteVersion = "–";
  }
  return websiteVersion;
}

/** The browser's language, as the page speaks it without the developer options. */
const browserLanguage = () => (resolve("auto") === "de" ? "Deutsch" : "English");

/**
 * Each topic page's cards, as the app's sub pages of Settings. After Apple's guidelines (owner's picks,
 * 5 Nov 2026, app #355): Light/Dark, the language and the time and date formats follow the browser; the
 * website's own choices for them show only with the developer options.
 */
function settingsTopicBody(topic, accepted) {
  const dev = store.developerOptions;
  switch (topic) {
    case "appearance": return `
      ${dev ? `<section class="card group appearance-pick" id="appearance">${[["device", t("Device"), "smartphone"], ["light", t("Light"), "sun"], ["dark", t("Dark"), "moon"]]
        .map(([k, label, sym]) => `<button data-appearance="${k}" aria-pressed="${store.appearance === k}"><span class="phone ${k}">${icon(sym)}</span><span>${h(label)}</span>
          <span class="tick ${store.appearance === k ? "on" : ""}">${store.appearance === k ? icon("check") : ""}</span></button>`).join("")}
      </section>
      <p class="footer">${h(t("Device follows the light or dark setting of your computer or phone."))}</p>` : ""}
      <section class="card group">
        <a class="row-setting bg-row" href="#/settings/backgrounds"><span><span class="bg-thumb" id="bg-thumb">${icon("nosign")}</span><span class="stack"><span>${h(t("Background pictures"))}</span><small class="sub">${h(backgroundSummary())}</small></span></span>${icon("chevron-right")}</a>
      </section>
`;
    case "clubpages": return `
      <section class="card group">
        <label class="row-setting"><span>${icon("gauge")} ${h(t("Current conditions in the top tile"))}</span><input type="checkbox" class="switch" id="combined-top" ${store.combinedTopTile ? "checked" : ""}></label>
      </section>
      <p class="footer">${h(store.combinedTopTile
        ? t("The top tile opens into all values: tap \"All values\" under it. Values it hides show as a line while they matter for the rowing light.")
        : t("Current conditions is a card of its own under the top tile, as before."))}</p>
      <section class="card group">
        <button class="row-setting topic" id="arrange"><span>${icon("arrow-up-down")} ${h(t("Card order"))}</span><span class="sub">${h(ownOrder() ? t("Own order") : t("App's order"))} ${icon("chevron-right")}</span></button>
      </section>
      <p class="footer">${h(t("For all clubs. Each club can have its own from \"Arrange this page\"."))}</p>
      <section class="card group">
        <label class="row-setting"><span>${icon("map-pin")} ${h(t("Location in the club header"))}</span><input type="checkbox" class="switch" id="launch-in-header" ${store.launchPointInHeader ? "checked" : ""}></label>
      </section>
      <p class="footer">${h(store.launchPointInHeader
        ? t("Tap the lake and town under the club's name for a map with the launch point.")
        : t("The Launch point card is on the page."))}</p>
      <h3 class="section">${icon("map")} ${h(t("Maps"))}</h3>
      <section class="card group">
        <label class="row-setting topic"><span>${h(t("Weather maps start"))}</span>
          <select id="map-zoom">${[["close", lang() === "de" ? t("Close (map zoom)") : "Close"], ["normal", t("Normal")], ["wide", t("Wide")]]
            .map(([k, label]) => `<option value="${k}" ${store.mapZoom === k ? "selected" : ""}>${h(label)}</option>`).join("")}</select></label>
        <label class="row-setting topic"><span>${h(t("Open places in"))}</span>
          <select id="maps-app">${Object.entries(MAPS_APPS).map(([k, app]) => `<option value="${k}" ${store.mapsApp === k ? "selected" : ""}>${h(app.name)}</option>`).join("")}</select></label>
      </section>
      <p class="footer">${h(t("Weather maps open %@ around the club, rain and lightning %@.",
        distance(50000 * (MAP_ZOOMS[store.mapZoom] ?? 1)), distance(120000 * (MAP_ZOOMS[store.mapZoom] ?? 1))))} ${h(t("Places open in a new tab. Until you pick one, iPhone and iPad use Apple Maps, other devices Google Maps."))}</p>
`;
    case "language": return `
      <h3 class="section">${icon("languages")} ${h(t("Language"))}</h3>
      <section class="card group">
        <div class="row-setting"><span class="stack"><span>${h(t("Language"))}</span><small class="sub">${h(t("In your browser's language settings"))}</small></span><span class="sub">${h(browserLanguage())}</span></div>
        ${dev ? likeDeviceRow("language-like", savedLanguage() === "auto", browserLanguage()) : ""}
        ${dev && savedLanguage() !== "auto" ? `<div class="row-setting"><span class="segmented wide" id="language-pick">${[["en", "English"], ["de", "Deutsch"]]
          .map(([k, label]) => `<button data-language="${k}" class="${savedLanguage() === k ? "on" : ""}">${h(label)}</button>`).join("")}</span></div>` : ""}</section>
      <h3 class="section">${icon("ruler")} ${h(t("Units"))}</h3>
      <section class="card group">${UNIT_ROWS.map(([kind, condition, title]) => `<label class="row-setting"><span>${conditionIcon(condition)} ${h(t(title))}</span>
          <select data-unit="${kind}">${Object.entries(UNITS[kind].options).map(([id, u]) => `<option value="${id}" ${id === unitId(kind) ? "selected" : ""}>${h(`${t(u.label)} · ${t(u.title)}`)}</option>`).join("")}</select></label>`).join("")}
      </section>
      <p class="footer">${h(t("Cloud cover stays in percent."))}</p>
      ${dev ? `<h3 class="section">${icon("calendar-clock")} ${h(t("Date and time"))}</h3>
      <section class="card group">${likeDeviceRow("datetime-like", dateTimeLikeDevice(), `${time(SAMPLE_TIME, "device")} · ${dateText(localDay(new Date()), "device")}`)}
        ${dateTimeLikeDevice() ? "" : `<label class="row-setting"><span>${icon("clock")} ${h(t("Time"))}</span>
          <select id="time-format">${TIME_FORMATS.filter((f) => f !== "device").map((f) => `<option value="${f}" ${f === store.timeFormat ? "selected" : ""}>${h(`${t(TIME_TITLES[f])} · ${time(SAMPLE_TIME, f)}`)}</option>`).join("")}</select></label>
        <label class="row-setting"><span>${icon("calendar")} ${h(t("Date"))}</span>
          <select id="date-format">${DATE_FORMATS.filter((f) => f !== "device").map((f) => `<option value="${f}" ${f === store.dateFormat ? "selected" : ""}>${h(`${f === "iso" ? "ISO 8601" : t(DATE_TITLES[f])} · ${dateText(localDay(new Date()), f)}`)}</option>`).join("")}</select></label>`}
      </section>
      <p class="footer">${h(t("Today and tomorrow are always written as words."))}</p>` : ""}
`;
    case "data": return `
      <h3 class="section">${icon("arrow-up-down")} ${h(t("Data use"))}</h3>
      <section class="card group">
        <label class="row-setting"><span>${icon("radio-tower")} ${h(t("Save mobile data"))}</span><input type="checkbox" class="switch" id="save-data" ${store.saveData ? "checked" : ""}></label>
        ${dataSaving() ? `<p class="row-setting green small">${icon("circle-check")} ${h(dataSaving() === "browser" ? t("Your browser asks to save data: the website is saving data now.") : t("On mobile data: the website is saving data now."))}</p>` : ""}
      </section>
      <p class="footer">${h(t("On mobile data, satellite pictures load only when you tap them; forecasts and warnings always load. When your browser or phone asks to save data, the website always does. Not every browser tells the website whether it is on mobile data."))}</p>
`;
    case "help": return `
      <section class="card group">
        <a class="row-setting" href="#/tour"><span>${icon("circle-help")} ${h(t("Show the tour again"))}</span>${icon("chevron-right")}</a>
        <button class="row-setting" id="tips-again"><span>${icon("lightbulb")} ${h(t("Show the tips again"))}</span></button>
        <button class="row-setting" id="legend"><span>${icon("info")} ${h(t("Legend: what the symbols mean"))}</span>${icon("chevron-right")}</button>
        <button class="row-setting" id="safety-again"><span>${icon("shield-check")} ${h(t("Safety notice"))}</span>${icon("chevron-right")}</button>
      </section>
      <p class="footer" id="tips-note"></p>
`;
    case "about": return `
      <section class="card group">
        <button class="row-setting topic" id="version"><span>${h(t("Version"))}</span><span class="sub" id="version-value">${h(websiteVersion)}</span></button>
      </section>
      <h3 class="section">${icon("file-text")} ${h(t("Legal"))}</h3>
      <section class="card group">
        <a class="row-setting" href="/privacy/"><span>${icon("hand")} ${h(t("Privacy"))}</span>${icon("chevron-right")}</a>
        <a class="row-setting" href="/impressum/"><span>${icon("landmark")} ${h(t("Legal notice"))}</span>${icon("chevron-right")}</a>
        <a class="row-setting" href="/credits/"><span>${icon("database")} ${h(t("Data sources"))}</span>${icon("chevron-right")}</a>
      </section>
      ${card(t("Stored in this browser"), "info", `<p>${h(t("Your clubs, settings and your acceptance of the safety notice stay in this browser. Nothing is sent anywhere."))}</p>
        <button id="factory" class="quiet">${icon("rotate-ccw")} ${h(t("Reset to factory settings"))}</button>
        <p class="small sub">${h(t("Appearance, units, language, background pictures and the order of the club page cards go back to how the website came, and your own pictures are deleted. The boat for the rowing light is Small boats again and every boat's limits go back to the standard ones. Your clubs, home base, own boats and routes stay."))}</p>
        <button id="reset" class="quiet">${h(t("Delete everything stored here"))}</button>`)}
      ${card(t("Website login"), "lock", `<p>${h(t("The website is still in testing. This browser stays logged in for 90 days."))}</p>
        <button id="log-out" class="quiet">${icon("lock")} ${h(t("Log out"))}</button>`)}`;
    case "developer": return `
      <section class="card group">
        <label class="row-setting"><span>${icon("hammer")} ${h(t("Developer options"))}</span><input type="checkbox" class="switch" role="switch" id="developer-options" ${dev ? "checked" : ""}></label>
      </section>
      <p class="footer">${h(t("With the developer options, Appearance offers Device, Light and Dark, Language and units the website's own language and time and date formats, Background pictures a picture for the Settings pages, and the first-start screens the language choice. Switched off, the website follows the browser again. Tap the version seven times to show this again."))}</p>
      ${dev ? `<section class="card group">
        <label class="row-setting topic"><span>${h(t("Club page columns"))}</span>
          <select id="column-fill">${[["fold", key("Fold the 48 hours")], ["fill", key("Always 48 hours")]].map(([k, label]) => `<option value="${k}" ${store.columnFill === k ? "selected" : ""}>${h(t(label))}</option>`).join("")}</select></label>
      </section>
      <p class="footer">${h(t("On wide screens, how the two columns of a club page end level. Fold the 48 hours: the table shows 24 hours until opened. Always 48 hours: the whole table, so columns may end further apart. Switching the developer options off goes back to the whole table."))}</p>
      <section class="card group">
        <label class="row-setting topic"><span>${h(t("Night in the 48 hours"))}</span>
          <select id="night-hours">${[["fold", key("One line per night")], ["all", key("Every night hour")]].map(([k, label]) => `<option value="${k}" ${store.nightHours === k ? "selected" : ""}>${h(t(label))}</option>`).join("")}</select></label>
      </section>
      <p class="footer">${h(t("One line per night: the dark hours fold into one line with the night's lowest temperatures, strongest wind, highest waves, all its rain and its poorest visibility; a tap opens them. Every night hour: one row per hour, as before. Switching the developer options off goes back to one line per night."))}</p>` : ""}`;
    default: return "";
  }
}

/** The value shown at the end of a topic's row (SettingsRow). */
function settingsTopicValue(topic) {
  if (topic === "appearance") {
    const picture = choiceTitle(backgrounds.all);
    return store.developerOptions ? `${t({ device: "Device", light: "Light", dark: "Dark" }[store.appearance] ?? "Device")} · ${picture}` : picture;
  }
  if (topic === "clubpages") return ownOrder() ? t("Own order") : t("App's order");
  if (topic === "language") return `${resolve() === "de" ? "Deutsch" : "English"} · ${unitSymbol("temperature")}`;
  if (topic === "data") return dataSaving() ? t("Saving data") : "";
  if (topic === "about") return websiteVersion;
  return "";
}

/**
 * Settings as in the app (option C, 25 Oct 2026): the boat for the rowing light and Boats and limits first,
 * then one row per topic with its own page, and the search at the end.
 */
function renderSettings(topic = null) {
  const named = SETTINGS_TOPICS.find(([id]) => id === topic && (id !== "developer" || store.developerOptions));
  if (topic && !named) topic = null;
  const again = () => renderSettings(topic);
  setTitle(named ? t(named[1]) : t("Settings"));
  const accepted = store.safety?.at ? new Intl.DateTimeFormat(locale(), { dateStyle: "long" }).format(new Date(store.safety.at)) : null;
  const back = store.clubs[0] ? `#/club/${encodeURIComponent(store.clubs[0].id)}` : "#/list";
  const row = ([id, title, name, colour]) => `<a class="row-setting topic" href="#/settings/${id}"><span>${settingsIcon(name, colour)} ${h(t(title))}</span>
          <span class="sub"><span data-value="${id}">${h(settingsTopicValue(id))}</span> ${icon("chevron-right")}</span></a>`;
  const changed = Object.values(store.limits).filter((l) => Object.keys(l ?? {}).length).length;
  const groups = [["appearance", "clubpages"], ["language", "data"], ["help", "about", ...(store.developerOptions ? ["developer"] : [])]];
  root.innerHTML = topic
    ? `<header class="nav"><a class="link back" href="#/settings" aria-label="${h(t("Settings"))}">${icon("chevron-left")}</a><strong class="nav-title">${h(t(named[1]))}</strong><span class="nav-side"></span></header>
    ${testing()}
    <main class="page settings-topic">${settingsTopicBody(topic, accepted)}
    </main>`
    : `<header class="nav">${closeX(`class="link close-x"`, back)}<strong class="nav-title">${h(t("Settings"))}</strong><span class="nav-side"></span></header>
    ${testing()}
    <main class="page settings-main">
      <div id="settings-topics">
      <section class="card group">
        <label class="row-setting topic"><span>${settingsIcon("rower", "#34c759")} ${h(t("Rowing light for"))}</span>
          <select id="settings-boat">${allBoats().map((b) => `<option value="${h(b.id)}" ${b.id === tickedBoat().id ? "selected" : ""}>${h(boatTitle(b))}</option>`).join("")}</select></label>
        <a class="row-setting topic" href="#/settings/boats"><span>${settingsIcon("sliders-horizontal", "#30b0c7")} ${h(t("Boats and limits"))}</span>
          <span class="sub">${changed ? h(t("%@ changed", String(changed))) : ""} ${icon("chevron-right")}</span></a>
        <a class="row-setting topic" href="#/settings/routes"><span>${settingsIcon("route", "#af52de")} ${h(t("Routes"))}</span>
          <span class="sub">${store.routes.length ? h(store.routes.length === 1 ? t("1 route") : t("%@ routes", String(store.routes.length))) : ""} ${icon("chevron-right")}</span></a>
      </section>
      <p class="footer">${h(t("The boat the rowing light is worked out for, on every club page and in the widgets. Routes holds the routes you saved on the lake maps."))}</p>
      ${groups.map((ids) => `<section class="card group">${ids.map((id) => row(SETTINGS_TOPICS.find(([x]) => x === id))).join("")}</section>`).join("\n      ")}
      </div>
      <div id="settings-results" hidden></div>
      <label class="search settings-search">${icon("search")}<input type="search" id="settings-search" placeholder="${h(t("Search"))}" aria-label="${h(t("Search the settings"))}"></label>
    </main>`;
  if (!topic && !websiteVersion) loadVersion().then((v) => {
    const value = root.querySelector('[data-value="about"]');
    if (value) value.textContent = v;
  });
  root.querySelector("#settings-boat")?.addEventListener("change", (e) => {
    pickBoat(e.target.value, null);
    again();
  });
  wireLanguage(again);
  if (!topic) wireSettingsSearch(root.querySelector("main"));
  wireTips(root.querySelector("main"));
  root.querySelectorAll("[data-unit]").forEach((select) => {
    select.addEventListener("change", () => setUnit(select.dataset.unit, select.value));
    // The whole row opens the choice, as a picker row in iOS Settings; only the unit at the end did before.
    select.closest(".row-setting").addEventListener("click", (e) => {
      if (e.target === select) return;
      e.preventDefault();
      try {
        select.showPicker();
      } catch {
        select.focus();
      }
    });
  });
  root.querySelector("#tips-again")?.addEventListener("click", () => {
    replayTips();
    root.querySelector("#tips-note").textContent = t("The tips are back.");
  });
  root.querySelector("#legend")?.addEventListener("click", () => openSheet(t("Legend"),
    ["lights", "conditions", "hourly"].map((part) => `<h3 class="section">${h({ lights: t("Rowing light"), conditions: t("Weather symbols"), hourly: t("The columns") }[part])}</h3>${legendBody(part)}`).join("")));
  root.querySelector("#combined-top")?.addEventListener("change", (e) => {
    store.combinedTopTile = e.target.checked;
    again();
  });
  root.querySelector("#launch-in-header")?.addEventListener("change", (e) => {
    store.launchPointInHeader = e.target.checked;
    again();
  });
  root.querySelector("#save-data")?.addEventListener("change", (e) => {
    store.saveData = e.target.checked;
    again();
  });
  root.querySelector("#time-format")?.addEventListener("change", (e) => (store.timeFormat = e.target.value));
  root.querySelector("#date-format")?.addEventListener("change", (e) => (store.dateFormat = e.target.value));
  root.querySelector("#language-like")?.addEventListener("change", async (e) => {
    // Off starts with the language shown now, so nothing changes at once (languageLikeDevice).
    await setLanguage(e.target.checked ? "auto" : resolve("auto"));
    again();
  });
  root.querySelectorAll("[data-language]").forEach((b) => b.addEventListener("click", async () => {
    await setLanguage(b.dataset.language);
    again();
  }));
  root.querySelector("#datetime-like")?.addEventListener("change", (e) => {
    setDateTimeLikeDevice(e.target.checked);
    again();
  });
  root.querySelectorAll("[data-appearance]").forEach((b) => b.addEventListener("click", () => {
    store.appearance = b.dataset.appearance;
    applyAppearance();
    again();
  }));
  root.querySelector("#arrange")?.addEventListener("click", () => openArrange(null));
  root.querySelector("#maps-app")?.addEventListener("change", (e) => {
    store.mapsApp = e.target.value;
    again();
  });
  // The picture for all pages, small, as the app's preview in the Background pictures row.
  const thumb = root.querySelector("#bg-thumb");
  if (thumb) backgroundPreview().then((url) => {
    if (url && thumb.isConnected) thumb.innerHTML = `<img src="${h(url)}" alt="">`;
  }).catch(() => {});
  root.querySelector("#map-zoom")?.addEventListener("change", (e) => {
    store.mapZoom = e.target.value;
    again();
  });
  root.querySelector("#safety-again")?.addEventListener("click", () => openSheet(t("Safety notice"),
    `${safetyList()}${accepted ? `<p class="sub">${h(t("You accepted this notice on %@.", accepted))}</p>` : ""}`));
  // Seven taps on the version show the developer options, as in the app (Settings > About > Version).
  const version = root.querySelector("#version");
  if (version) {
    loadVersion().then((v) => {
      const value = root.querySelector("#version-value");
      if (value) value.textContent = v;
    });
    let taps = 0;
    version.addEventListener("click", () => {
      if (store.developerOptions) return;
      taps += 1;
      if (taps < 7) return;
      store.developerOptions = true;
      location.hash = "#/settings/developer";
    });
  }
  root.querySelector("#developer-options")?.addEventListener("change", async (e) => {
    store.developerOptions = e.target.checked;
    // The website's own looks and language count only with the developer options.
    applyAppearance();
    await setLanguage(savedLanguage());
    if (e.target.checked) again();
    else location.hash = "#/settings";
  });
  root.querySelector("#column-fill")?.addEventListener("change", (e) => { store.columnFill = e.target.value; });
  root.querySelector("#night-hours")?.addEventListener("change", (e) => { store.nightHours = e.target.value; });
  root.querySelector("#log-out")?.addEventListener("click", () => location.assign("/__logout"));
  root.querySelector("#factory")?.addEventListener("click", async () => {
    if (!confirm(t("Reset all settings?"))) return;
    await forgetOwnPictures();
    try {
      for (const name of Object.keys(localStorage)) if (name.startsWith("rf.") && !FACTORY_KEEPS.includes(name)) localStorage.removeItem(name);
    } catch {}
    location.reload();
  });
  root.querySelector("#reset")?.addEventListener("click", () => {
    if (!confirm(t("Delete your clubs, settings and the accepted safety notice from this browser?"))) return;
    try {
      for (const name of Object.keys(localStorage)) if (name.startsWith("rf.")) localStorage.removeItem(name);
    } catch {}
    location.hash = "#/";
    route();
  });
}

/**
 * The search at the end of Settings: every card of every topic page whose title, rows or footer hold the
 * words typed, with the page it is on; tapping one opens that page (SettingsSearch).
 */
function wireSettingsSearch(main) {
  const input = main.querySelector("#settings-search");
  const list = main.querySelector("#settings-topics");
  const results = main.querySelector("#settings-results");
  const box = document.createElement("div");
  const entries = SETTINGS_TOPICS.filter(([id]) => id !== "developer" || store.developerOptions).flatMap(([id, title, name, colour]) => {
    box.innerHTML = settingsTopicBody(id, null);
    return [...box.querySelectorAll(":scope > section.card")].map((card) => {
      const parts = [card];
      const before = card.previousElementSibling;
      if (before?.matches("h3.section")) parts.unshift(before);
      const after = card.nextElementSibling;
      if (after?.matches("p.footer")) parts.push(after);
      const heading = parts[0].matches("h3.section") ? parts[0] : card.querySelector(".card-title, .row-setting > span, .row-setting");
      return { id, topic: t(title), name, colour, title: (heading?.textContent ?? "").trim().replace(/\s+/g, " ") || t(title), text: parts.map((x) => x.textContent).join(" ").toLowerCase() };
    });
  });
  input.addEventListener("input", () => {
    const words = input.value.trim().toLowerCase().split(/\s+/).filter(Boolean);
    list.hidden = words.length > 0;
    results.hidden = !words.length;
    if (!words.length) return;
    const found = entries.filter((e) => words.every((w) => e.text.includes(w)) || words.every((w) => e.topic.toLowerCase().includes(w)));
    results.innerHTML = found.length
      ? `<section class="card group">${found.map((e) => `<a class="row-setting topic" href="#/settings/${e.id}"><span>${settingsIcon(e.name, e.colour)}<span class="stack"><span>${h(e.title)}</span><small class="sub">${h(e.topic)}</small></span></span>${icon("chevron-right")}</a>`).join("")}</section>`
      : `<p class="sub">${h(t("No settings found for “%@”.", input.value.trim()))}</p>`;
  });
}

// ---- Boats and limits (RowingLimitsView, BoatLimitsView) -------------------------------

/**
 * A row that a swipe to the left (finger or mouse) opens on a red Remove button, as a list row in iOS
 * (owner's pick for My boats and Kept at, app #355). The button is also reached with Tab.
 */
const swipeRow = (body, removeAttr, cls = "") => `<li class="swipe ${cls}"><div class="swipe-body">${body}</div>
    <button class="swipe-remove" ${removeAttr}>${h(t("Remove"))}</button></li>`;

const SWIPE_OPEN = 88;

/** Wires the swipe rows inside el. A drag that moved swallows the click that follows, so it never ticks a boat. */
function wireSwipeRows(el) {
  const closeAll = (except) => el.querySelectorAll(".swipe.open").forEach((r) => r !== except && r.classList.remove("open"));
  el.querySelectorAll(".swipe").forEach((row) => {
    const body = row.querySelector(".swipe-body");
    let start = null;
    let moved = false;
    body.addEventListener("pointerdown", (e) => {
      start = { x: e.clientX, y: e.clientY, open: row.classList.contains("open") };
      moved = false;
    });
    body.addEventListener("pointermove", (e) => {
      if (!start) return;
      const dx = e.clientX - start.x;
      if (!moved && (Math.abs(dx) < 8 || Math.abs(dx) < Math.abs(e.clientY - start.y))) return;
      if (!moved) body.setPointerCapture?.(e.pointerId);
      moved = true;
      const x = Math.min(0, Math.max(-SWIPE_OPEN - 24, dx + (start.open ? -SWIPE_OPEN : 0)));
      row.classList.add("dragging");
      body.style.transform = `translateX(${x}px)`;
    });
    const end = (e) => {
      if (!start) return;
      const dx = e.clientX - start.x + (start.open ? -SWIPE_OPEN : 0);
      row.classList.remove("dragging");
      body.style.transform = "";
      if (moved) {
        row.classList.toggle("open", dx < -SWIPE_OPEN / 2);
        closeAll(row);
      } else if (start.open) {
        row.classList.remove("open");
        moved = true;
      }
      start = null;
    };
    body.addEventListener("pointerup", end);
    body.addEventListener("pointercancel", end);
    body.addEventListener("click", (e) => {
      if (!moved) return;
      e.preventDefault();
      e.stopPropagation();
      moved = false;
    }, true);
    row.querySelector(".swipe-remove").addEventListener("focus", () => {
      closeAll(row);
      row.classList.add("open");
    });
  });
}

function renderBoats() {
  setTitle(t("Boats and limits"));
  // As Wi-Fi in iOS Settings: the tick on the left, the row picks the boat, and ⓘ opens its details (BoatRow).
  const body = (boat) => {
    const changed = Object.keys(store.limits[boat.id] ?? {}).length > 0;
    const on = store.boat === boat.id;
    return `<div class="boat-row"><button data-tick="${h(boat.id)}" aria-pressed="${on}"><span class="tick">${on ? icon("check") : ""}</span>
        <span><strong>${h(boatTitle(boat))}</strong><small class="${changed ? "orange" : ""}">${h(changed ? t("%@ · your limits", boatDetail(boat)) : boatDetail(boat))}</small></span></button>
      <a class="round" href="#/settings/boat/${encodeURIComponent(boat.id)}" aria-label="${h(t("Limits for %@", boatTitle(boat)))}">${icon("info")}</a></div>`;
  };
  root.innerHTML = `<header class="nav"><a class="link" href="#/settings">${icon("chevron-left")} ${h(t("Settings"))}</a><span class="spacer"></span></header>${testing()}
    <main class="page">
      <h1 class="large">${h(t("Boats and limits"))}</h1>
      ${tip("myBoats")}
      <h3 class="section">${icon("rower")} ${h(t("Your boat"))}</h3>
      <ul class="boats">${GROUPS.map((b) => `<li>${body(b)}</li>`).join("")}</ul>
      <h3 class="section">${icon("list")} ${h(t("My boats"))}</h3>
      <ul class="boats">${store.boats.map((b) => swipeRow(body(b), `data-remove-boat="${h(b.id)}"`)).join("")}
        <li><button id="add-boat" class="tint">${icon("circle-plus")} <span>${h(t("Add a boat"))}</span></button></li></ul>
      <p class="footer">${h(t("Tap a boat to use it for the rowing light, ⓘ for its type and limits. Swipe to remove one."))}</p>
      ${footerLinks()}
    </main>`;
  wireTips(root.querySelector("main"));
  wireSwipeRows(root);
  root.querySelectorAll("[data-tick]").forEach((b) => b.addEventListener("click", () => {
    store.boat = b.dataset.tick;
    renderBoats();
  }));
  root.querySelectorAll("[data-remove-boat]").forEach((b) => b.addEventListener("click", () => {
    removeBoat(b.dataset.removeBoat);
    renderBoats();
  }));
  root.querySelector("#add-boat").addEventListener("click", () => {
    const home = store.clubs[0]?.id;
    const boat = { id: crypto.randomUUID?.() ?? `b${Date.now()}`, name: "", type: "gig", class: "4x", clubs: home ? [home] : [] };
    store.boats = [...store.boats, boat];
    openNewBoat(boat.id);
  });
}

/** The clubs where an own boat is kept: swipe one away, add one from the menu; the last club stays (KeptAtSection, owner's choice A, 30 Oct 2026). */
function keptAtSection(boat) {
  const clubs = boat.clubs ?? [];
  const home = store.clubs[0]?.id;
  const others = store.clubs.filter((c) => !clubs.includes(c.id));
  const body = (id) => `<div class="row-setting kept-row">
      <span>${icon(markIcon(id))} ${h(clubNameOf(id))}</span>
      ${id === home ? `<small class="sub">${h(t("Home base"))}</small>` : ""}
    </div>`;
  return `<h3 class="section">${icon("map-pin")} ${h(t("Kept at"))}</h3>
    <ul class="card group kept">${clubs.map((id) => (clubs.length > 1 ? swipeRow(body(id), `data-unkeep="${h(id)}"`) : `<li>${body(id)}</li>`)).join("")}
      ${others.length ? `<li><label class="row-setting add-club">${icon("circle-plus")}<select id="keep-at" aria-label="${h(t("Add a club"))}">
        <option value="">${h(t("Add a club"))}</option>${others.map((c) => `<option value="${h(c.id)}">${h(c.shortName || c.name)}</option>`).join("")}</select></label></li>` : ""}
    </ul>
    <p class="footer">${h(t("The boat shows on these clubs' pages. Elsewhere it waits in the boat menu under “At other clubs”."))}</p>`;
}

/** The boat's form: name, type and size, where it is kept, the limits switch and the limits (BoatLimitsView). */
function boatForm(boat, isNew, ownLimits) {
  const limits = boatLimits(boat);
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
  // The app's footer under the limits (SettingsBoats): what always counts, or how to set your own.
  const footer = ownLimits
    ? t("Warnings, thunderstorms, fog, hail and darkness always count. Below %@ water the light reminds you to take extra care.", temperature(COLD.waterC))
    : t("Turn off to set your own. Below %@ water the app lowers its wind and gust limits by %@.", temperature(COLD.waterC), wind(COLD.marginMs));
  return `${isGroup(boat) ? "" : `<h3 class="section">${icon("rower")} ${h(t("Boat"))}</h3>
        <section class="card group">
          <label class="row-setting"><input id="boat-name" type="text" value="${h(boat.name)}" placeholder="${h(t("Name, e.g. the boat's name"))}"></label>
          <label class="row-setting"><span>${h(t("Type"))}</span><select id="boat-type">${Object.entries(BOAT_TYPES).map(([k, v]) => option(k, t(v.title), boat.type)).join("")}</select></label>
          <label class="row-setting"><span>${h(t("Size and rigging"))}</span><select id="boat-class">${Object.entries(BOAT_CLASSES).map(([k, v]) => option(k, t(v), boat.class)).join("")}</select></label>
        </section>
        <p class="footer">${h(t(BOAT_TYPES[boat.type].detail))}</p>
        ${keptAtSection(boat)}`}
      <h3 class="section">${icon("sliders-horizontal")} ${h(t("Limits"))}</h3>
      ${isNew ? "" : tip("coldWater")}
      <section class="card group">
        <label class="row-setting"><span>${h(t("The app's limits for this boat"))}</span><input type="checkbox" class="switch" role="switch" id="app-limits" ${ownLimits ? "" : "checked"}></label>
        ${ownLimits ? Object.keys(LIMITS).map(limitRow).join("") : ""}</section>
      <p class="footer">${h(footer)}</p>
      ${isGroup(boat) || isNew ? "" : `<button id="remove-boat" class="quiet red">${h(t("Remove this boat"))}</button>`}`;
}

/** Wires a boat form inside el; again() draws it anew. Returns nothing; state lives in store and the own-limits flag. */
function wireBoatForm(el, id, again, own) {
  const boat = allBoats().find((b) => b.id === id);
  const limits = boatLimits(boat);
  const update = (change) => {
    store.boats = store.boats.map((b) => (b.id === id ? { ...b, ...change } : b));
  };
  el.querySelector("#boat-name")?.addEventListener("input", (e) => {
    update({ name: e.target.value });
    el.dispatchEvent(new Event("boatnamed"));
  });
  el.querySelector("#boat-type")?.addEventListener("change", (e) => {
    update({ type: e.target.value });
    again();
  });
  el.querySelector("#boat-class")?.addEventListener("change", (e) => {
    update({ class: e.target.value });
    again();
  });
  el.querySelectorAll("[data-step]").forEach((b) => b.addEventListener("click", () => {
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
    again();
  }));
  wireSwipeRows(el);
  el.querySelectorAll("[data-unkeep]").forEach((b) => b.addEventListener("click", () => {
    unkeepBoat(id, b.dataset.unkeep);
    again();
  }));
  el.querySelector("#keep-at")?.addEventListener("change", (e) => {
    if (e.target.value) keepBoat(id, e.target.value);
    again();
  });
  // As Date & Time > Set Automatically: the app's limits by default, the list only for the user's own.
  el.querySelector("#app-limits").addEventListener("change", (e) => {
    const changed = Object.keys(store.limits[id] ?? {}).length > 0;
    if (!e.target.checked) {
      own.value = true;
    } else if (changed && !confirm(`${t("Use the app's limits again?")}\n${t("The limits you set for this boat are dropped.")}`)) {
      e.target.checked = false;
      return;
    } else {
      const all = store.limits;
      delete all[id];
      store.limits = all;
      own.value = false;
    }
    again();
  });
  el.querySelector("#remove-boat")?.addEventListener("click", () => {
    removeBoat(id);
    location.hash = "#/settings/boats";
  });
}

function removeBoat(id) {
  store.boats = store.boats.filter((b) => b.id !== id);
  const all = store.limits;
  delete all[id];
  store.limits = all;
  if (store.boat === id) store.boat = "small";
  store.clubBoats = Object.fromEntries(Object.entries(store.clubBoats).filter(([, boat]) => boat !== id));
}

/** Whether the boat has limits of its own, so the list shows. */
const hasOwnLimits = (id) => Object.keys(store.limits[id] ?? {}).length > 0;

/** Remembered per boat while its page is open, so switching the app's limits off shows the list before any change. */
const ownLimitsShown = {};

function renderBoat(id) {
  const boat = allBoats().find((b) => b.id === id);
  if (!boat) {
    location.hash = "#/settings/boats";
    return;
  }
  setTitle(boatTitle(boat));
  const own = { get value() { return ownLimitsShown[id] ?? hasOwnLimits(id); }, set value(v) { ownLimitsShown[id] = v; } };
  root.innerHTML = `<header class="nav"><a class="link" href="#/settings/boats">${icon("chevron-left")} ${h(t("Boats and limits"))}</a><span class="spacer"></span></header>${testing()}
    <main class="page">
      <h1 class="large">${h(boatTitle(boat))}</h1>
      ${boatForm(boat, false, own.value)}
      ${footerLinks()}
    </main>`;
  wireBoatForm(root, id, () => renderBoat(id), own);
  // The cold-water tip at the limits, as the app's Settings › Boats (ColdWaterTip).
  wireTips(root.querySelector("main"));
}

/**
 * Adding a boat, as creating something in Apple's own apps: a sheet with Cancel and Add, where only
 * Add keeps the boat (NewBoatSheet, owner 4 Nov 2026). Add needs a name. Only the two buttons close
 * it, so a boat is never kept or lost by a tap beside it; Escape counts as Cancel.
 */
function openNewBoat(id) {
  document.querySelector("dialog.sheet")?.remove();
  const dialog = document.createElement("dialog");
  dialog.className = "sheet new-boat";
  dialog.innerHTML = `<header><button class="link cancel">${h(t("Cancel"))}</button><strong>${h(t("New boat"))}</strong><button class="done">${h(t("Add"))}</button></header><div class="sheet-body"></div>`;
  document.body.append(dialog);
  let added = false;
  const own = { value: false };
  const body = dialog.querySelector(".sheet-body");
  const add = dialog.querySelector(".done");
  const named = () => Boolean(allBoats().find((b) => b.id === id)?.name.trim());
  const draw = () => {
    const boat = allBoats().find((b) => b.id === id);
    body.innerHTML = boatForm(boat, true, own.value);
    wireBoatForm(body, id, draw, own);
    add.disabled = !named();
  };
  body.addEventListener("boatnamed", () => (add.disabled = !named()));
  dialog.querySelector(".cancel").addEventListener("click", () => dialog.close());
  add.addEventListener("click", () => {
    added = true;
    dialog.close();
  });
  dialog.addEventListener("close", () => {
    dialog.remove();
    if (!added) removeBoat(id);
    renderBoats();
  });
  draw();
  dialog.showModal();
  body.querySelector("#boat-name")?.focus();
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

/**
 * Settings open as a sheet over the page, as in the app (RootView's .sheet): on iPad sizes a centred card
 * with the page dimmed behind it (style.css, body.settings-over), on phones the full-height sheet. The page
 * behind is a still copy of the one that was shown, kept while moving between the settings' topics.
 */
function settingsOverPage(on) {
  const under = document.getElementById("under") ?? document.body.insertBefore(Object.assign(document.createElement("div"), { id: "under", inert: true }), root);
  under.setAttribute("aria-hidden", "true");
  if (on && !document.body.classList.contains("settings-over")) {
    under.innerHTML = root.querySelector("main") ? root.innerHTML : "";
    under.querySelectorAll("[id]").forEach((el) => el.removeAttribute("id"));
  }
  if (!on) under.innerHTML = "";
  document.body.classList.toggle("settings-over", on);
}

function route(scroll = true) {
  swipeOff?.();
  document.querySelector("dialog.sheet")?.remove();
  document.querySelectorAll(".wm-full, .sat-full").forEach((x) => x.remove());
  document.body.classList.remove("locked");
  if (scroll) window.scrollTo(0, 0);
  // The pages the app shows as sheets look like one on a phone.
  document.body.classList.toggle("sheet-page", /^\/(club\/[^/]+\/value\/|settings|add-place|countries)/.test(location.hash.slice(1)));
  settingsOverPage(location.hash.startsWith("#/settings"));
  if (!store.safety || store.safety.version < SAFETY_VERSION) return renderSafetyGate();
  // The tour once, after the safety notice, and again from Settings › Help.
  if (!tourSeen() || location.hash === "#/tour") {
    showBackground(null);
    const done = () => (location.hash === "#/tour" ? (location.hash = "#/settings") : route());
    // The club list, for the club choice on a first visit and the river page (TutorialView.hasRiver); null when it failed.
    return loadCatalog().catch(() => null).then((lakes) => {
      // Another page may have opened while the club list loaded.
      if (tourSeen() && location.hash !== "#/tour") return;
      renderTour(root, { languagePicker: tourLanguagePicker, wireLanguage, done, lakes, reload: loadCatalog });
    });
  }
  const hash = location.hash.replace(/^#/, "");
  pagePicture(hash);
  keepUnplacedBoats();
  // The club whose boats count: the club page's, its value pages' and its lake map's.
  const pageOf = hash.match(/^\/club\/([^/]+)/) ?? hash.match(/^\/lake\/[^/?]+\/([^?]+)/);
  setPageClub(pageOf ? decodeURIComponent(pageOf[1]) : !hash || hash === "/" ? store.clubs[0]?.id : null);
  const value = hash.match(/^\/club\/([^/]+)\/value\/([a-zA-Z]+)(?:\/([^?]+))?(?:\?order=(\w+))?$/);
  if (value) return renderValuePage(root, decodeURIComponent(value[1]), value[2], value[3] ? decodeURIComponent(value[3]) : null, value[4] ?? null);
  const club = hash.match(/^\/club\/(.+)$/);
  if (club) return renderClub(decodeURIComponent(club[1]));
  const lake = hash.match(/^\/lake\/([^/?]+)(?:\/([^?]+))?(?:\?(.+))?$/);
  if (lake) {
    const clubId = lake[2] ? decodeURIComponent(lake[2]) : null;
    // ?at=<time> opens an hour; ?route=<id> a saved route, from Settings › Routes (and goes back there).
    const query = new URLSearchParams(lake[3] ?? "");
    const at = query.get("at") ? new Date(query.get("at")) : null;
    const routeId = query.get("route");
    // From the waves page's map (?layer=waves), back to that page, as the app's full-screen cover.
    const back = routeId ? "#/settings/routes" : !clubId ? "#/"
      : query.get("layer") === "waves" ? `#/club/${encodeURIComponent(clubId)}/value/waves` : `#/club/${encodeURIComponent(clubId)}`;
    // ?layer=waves from the waves page's map.
    return renderLakeMap(root, decodeURIComponent(lake[1]), clubId, back, at, routeId, query.get("layer"));
  }
  const add = hash.match(/^\/add-place(?:\?name=(.*))?$/);
  if (add) return renderAddPlace(root, add[1] ? decodeURIComponent(add[1]) : "");
  if (hash === "/countries") return renderCountries(root);
  const water = hash.match(/^\/countries\/([a-z]{2})\/(.+)$/);
  if (water) return renderWater(root, water[1], decodeURIComponent(water[2]));
  const country = hash.match(/^\/countries\/([a-z]{2})(?:\?q=(.*))?$/);
  if (country) return renderCountry(root, country[1], country[2] ? decodeURIComponent(country[2]) : "");
  if (hash === "/settings") return renderSettings();
  const topic = hash.match(/^\/settings\/(appearance|clubpages|language|data|help|about|developer)$/);
  if (topic) return renderSettings(topic[1]);
  if (hash === "/settings/boats") return renderBoats();
  if (hash === "/settings/routes") return renderAllRoutes(root);
  // A route link from the app's Share link or another browser (routelink.js).
  const shared = hash.match(/^\/routes\/add\?r=([A-Za-z0-9_-]+)$/);
  if (shared) return openSharedRoutes(shared[1]);
  if (hash === "/settings/backgrounds") return renderBackgrounds(root);
  const boat = hash.match(/^\/settings\/boat\/(.+)$/);
  if (boat) return renderBoat(decodeURIComponent(boat[1]));
  if (hash === "/list" || !store.clubs.length) return renderList();
  return renderClub(store.clubs[0].id);
}

// ---- How pages change, as the app (and Weather): a swipe, an arrow key or a tap on the dots slides one club;
// a finger along the dots jumps straight there; a club picked in the list zooms open from its row. Same-document
// view transitions (Safari 18, Chrome 111); without them, or with Reduce Motion, the page just changes.
/** The motion for the next page change: "next", "prev" or "zoom"; null changes it straight away. */
let pageMotion = null;
function moveTo(hash, motion) {
  pageMotion = motion;
  location.hash = hash;
}
window.addEventListener("hashchange", () => {
  const motion = pageMotion;
  pageMotion = null;
  if (!motion || !document.startViewTransition || matchMedia("(prefers-reduced-motion: reduce)").matches) return route();
  document.documentElement.dataset.motion = motion;
  const change = document.startViewTransition(() => route());
  change.finished.finally(() => {
    delete document.documentElement.dataset.motion;
    document.querySelectorAll("[data-zoom-from]").forEach((el) => { el.style.viewTransitionName = ""; delete el.dataset.zoomFrom; });
  });
});
// A club picked in the list (not the list beside a page) zooms open from its row, as in Weather.
document.addEventListener("click", (e) => {
  const row = e.target.closest?.("main.list-page a.row[data-id]");
  if (!row || editing || e.defaultPrevented || e.metaKey || e.ctrlKey || e.shiftKey || row.closest(".swipe.open")) return;
  e.preventDefault();
  row.style.viewTransitionName = "club-zoom";
  row.dataset.zoomFrom = "1";
  moveTo(row.getAttribute("href"), "zoom");
});
document.addEventListener("rf-boat-picked", () => route(false));
// Back on the page after a while: show fresh numbers.
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") refreshOnReturn();
});

applyAppearance();
await setLanguage(savedLanguage());
route();
// Saved clubs that moved to another water or were renamed: show them as they are now.
refreshSavedClubs().then((changed) => changed && route());
