// The tour (TutorialView, TourPage) and the one-time tips (the app's TipKit
// tips). On a first visit, with no clubs yet, the tour asks for the home base
// and more clubs as the app's does (ClubChoicePage); the texts name the
// website's own controls where the app's differ (no swiping a row, no pulling
// down, no widgets or app icon).

import { t } from "./i18n.js";
import { icon, filledIcon } from "./icons.js";
import { key, COLD, standardLimit, searchClubs, town } from "./logic.js";
import { h, store, load, save, setTitle, dot, lightTitle, conditionIcon, conditionTexts, TILE_ORDER, temperature, wind, savedClub } from "./shared.js";

// ---- The tour ---------------------------------------------------------------------------

const p = (iconName, text) => ({ icon: iconName, text });

/**
 * The pages, as TourPage: the club choice only while the list was empty when the tour began
 * (TutorialView drops it once there is a home base), the river page only with a river or canal club in the list.
 */
export function tourPages(river = false, choice = false) {
  return [
    {
      id: "welcome", icon: "rower", tint: "blue", title: key("Welcome to Row Frog"), intro: key("Weather and a rowing forecast for your club's launch point."),
      points: [p("house", key("Your home base opens first when you start the app.")), p("hand", key("To change it, open the list, tap Edit and then the house next to a club."))],
    },
    choice && { id: "homeBase", choice: true, icon: "house", tint: "blue", title: key("Choose your home base"), intro: key("It opens first when you start the app. You can change it later.") },
    choice && { id: "moreClubs", choice: true, icon: "circle-plus", tint: "blue", title: key("Add more clubs"), intro: key("Add the other places you row, or skip this and add clubs later in the list.") },
    {
      id: "rowingLight", icon: "siren", tint: "green", title: key("The rowing light"), intro: key("Every page starts with the rowing light for the hour ahead."),
      points: [
        p("message-square-text", key("The \"Why\" line names what sets the light.")), p("sunrise", key("Rowing is only advised while the sun is up.")),
        p("clock", key("Each of the next 48 hours has its own light. Tap a night's line to see its hours.")),
        p("umbrella", key("The rain tile shows DWD's radar for the next two hours, then the forecast.")),
        p("clock-alert", key("Grey instead of green: the forecast is over 3 hours old. Tap Refresh under the club's name.")),
        p("user-round-search", key("The light is advice. You decide, and when in doubt you stay ashore.")),
      ],
    },
    {
      id: "conditions", icon: "thermometer", tint: "teal", title: key("Conditions at a glance"), intro: store.combinedTopTile
        // With Current conditions inside the top tile (app #357), it opens into all values.
        ? key("The tile with the light shows what matters on the water. Tap “All values” under it for the rest.")
        : key("Below the light you find what matters on the water."),
      points: [
        p("snowflake", key("In winter, the app estimates ice on the water from frost and water temperature, checked against satellite pictures on larger lakes. Always look at the water yourself.")),
        p("cloud-sun", key("The forecast comes from the weather model that does best for your lake. The line near the end of each page names it.")),
        p("info", key("Tap ⓘ on a card to see what its icons and colours mean. Settings › Help has the full legend.")),
      ],
    },
    {
      id: "warnings", icon: "triangle-alert", tint: "orange", title: key("Official warnings"), intro: key("Official warnings come right under the rowing light."),
      points: [
        p("waves", key("Storm warnings for the lake and weather warnings for the town.")), p("message-square-text", key("A warning also appears in the Why line and on the location list.")),
        p("siren", key("On the lake, also watch the storm warning lights on the shore. The warnings card explains what they mean.")),
        p("arrow-up-down", key("The light and the warnings always stay on top. Arrange this page, at the end of each page, sorts or hides the other cards.")),
      ],
    },
    {
      id: "boats", icon: "rower", tint: "mint", title: key("Your boats and limits"), intro: key("The rowing light is worked out for one boat. Switch it with the boat button on the club page."),
      points: [
        p("check", key("Small boats are picked at first. Tap Big boats if you row a four or an eight.")),
        p("list", key("Add your own boats under My boats. When it is too rough for yours, the app names one that would be fine.")),
        p("info", key("ⓘ next to a boat opens its limits.")), p("map", key("Pick the boat that colours the lake map.")),
        { icon: "thermometer-snowflake", text: key("Below %@ water a blue life-jacket badge shows; the light stays about the weather. Below %@ the advice is stricter."), args: () => [temperature(standardLimit("lifeJacket")), temperature(COLD.waterC)] },
      ],
    },
    {
      id: "lake", icon: "map", tint: "teal", title: key("Lake view and routes"), intro: key("Below the current conditions, the Lake view shows the whole lake."),
      points: [
        p("map", key("The Lake view shows the light, waves and wind across the whole lake. Tap it for the full map.")),
        p("clock", key("On the map, move through the hours in the strip at the bottom and tap the water for one spot.")),
        p("route", key("Plan a route: tap your turning points to see the light along the way and the best time to start.")),
        p("bookmark", key("Save the routes you row often in the Routes menu. Settings › Routes shows them all. Share routes as a link for a browser or as a GPX file for other apps.")),
        p("earth", key("Below it, the latest satellite picture of the lake, with a switch to the clearest one.")),
      ],
    },
    river && {
      id: "river", icon: "circle-arrow-right", tint: "teal", title: key("Rivers and canals"), intro: key("A river or canal club gets its own two tiles."),
      points: [
        p("map", key("The River view or Canal view shows your stretch between weirs or locks, with markers where it ends.")),
        p("circle-arrow-right", key("The Current tile shows the nearest gauge's flow speed, water level and trend. It is amber at high water or a fast current, red when shipping is stopped or the current is too strong.")),
        p("waves", key("High water starts at the gauge's shipping mark I, or at mean high water where the gauge has no mark.")),
        p("pointer", key("Tap it for the level chart and your pace upstream and downstream.")),
      ],
    },
    {
      id: "locations", icon: "list", tint: "blue", title: key("Your locations"), intro: key("Keep all the places you row in one list."),
      points: [
        p("hand", key("Swipe left and right, or use the arrow keys, to move between your clubs. The house marks your home base.")),
        p("search", key("Search the list for a club and tap + to add it, or open ⋯ to browse by country or add a place of your own.")),
        p("trash-2", key("Tap Edit in the list to remove a club or make it your home base.")),
      ],
    },
    {
      id: "wideScreen", icon: "columns-2", tint: "indigo", title: key("Landscape and wide screens"), intro: key("On a wide window or a tablet you see more at once."),
      points: [p("panel-left", key("The location list stays on the left, the club page on the right.")), p("layout-grid", key("The cards on the club page sit in two columns."))],
    },
    {
      id: "settings", icon: "settings", tint: "grey", title: key("Settings"), intro: key("Open the settings with the cog at the top of the list or at the bottom of a club page."),
      points: [
        p("globe", key("English or German, as your browser's languages set it.")), p("ruler", key("Units for temperature, wind, waves, rain, distances and air pressure.")),
        p("image", key("Background pictures, including your own photos.")),
        p("circle-help", key("Settings › Help shows this tour again.")),
      ],
    },
  ].filter(Boolean);
}

export const tourSeen = () => load("rf.tourSeen", false) === true;

/** A small picture of the feature, as TourPageView.extra. */
function extra(page, languagePicker) {
  // The page speaks the browser's language; the website's own choice is for the developer options only (#355).
  if (page.id === "welcome") return store.developerOptions ? `<div class="tour-language">${languagePicker()}</div>` : "";
  if (page.id === "rowingLight") {
    return `<div class="tour-lights">${["green", "amber", "red"].map((l) => `<div class="${l}">${dot(l, 30)}<small>${h(lightTitle(l))}</small></div>`).join("")}</div>`;
  }
  if (page.id === "conditions") {
    const texts = conditionTexts();
    return `<div class="card tour-conditions">${TILE_ORDER.map((c) => `<span>${conditionIcon(c)} ${h(texts[c][1])}</span>`).join("")}</div>`;
  }
  return "";
}

/** Rough distance in km, good enough to sort clubs by (LocationStore.distance). */
function distanceKm(a, b) {
  const x = (b.lon - a.lon) * Math.cos(((a.lat + b.lat) / 2) * Math.PI / 180);
  return Math.hypot(x, b.lat - a.lat) * 111.2;
}

/** Clubs offered before a search: the five nearest, or three at random without the location (LocationStore.suggestions). */
function suggestions(all, near, random) {
  if (near) return [...all].sort((a, b) => distanceKm(a.club.launchPoint, near) - distanceKm(b.club.launchPoint, near)).slice(0, 5);
  return random;
}

/** One club on a choice page, with the house, an empty circle, a tick or + at its end (ClubChoicePage.row). */
function choiceRow({ club, lake }, page) {
  const clubs = store.clubs;
  const isHome = clubs[0]?.id === club.id;
  const saved = clubs.some((c) => c.id === club.id);
  const mark = isHome ? `<span class="add home" aria-label="${h(t("Home base"))}">${icon("house")}</span>`
    : page === "homeBase" ? `<span class="add off">${icon("circle")}</span>`
    : saved ? `<span class="add in" aria-label="${h(t("In your list"))}">${filledIcon("circle-check")}</span>`
    : `<span class="add" aria-label="${h(t("Add %@", club.shortName || club.name))}">${icon("circle-plus")}</span>`;
  const where = [lake.name, town(club.address)].filter(Boolean).join(" · ");
  return `<li><button class="result" data-club="${h(club.id)}" data-lake="${h(lake.id)}"><span class="result-text"><strong>${h(club.name)}</strong><small>${h(where)}</small></span>${mark}</button></li>`;
}

/** The search, the clubs in the list (more clubs) and the suggestions or results (ClubChoicePage). */
function choiceList(page, state) {
  if (state.failed) {
    return `<div class="card tour-empty">${icon("wifi-off")}<strong>${h(t("No connection"))}</strong><p class="sub">${h(t("Could not load the rowing locations."))}</p><button class="pill" id="tour-retry">${h(t("Try again"))}</button></div>`;
  }
  if (!state.lakes) return `<div class="tour-empty">${icon("loader-circle")}</div>`;
  const query = state.query.trim();
  if (query) {
    const found = searchClubs(state.lakes, query, 50);
    return found.length ? `<ul class="results">${found.map((x) => choiceRow(x, page)).join("")}</ul>` : `<p class="sub tour-empty">${h(t("No clubs found."))}</p>`;
  }
  const all = state.lakes.flatMap((lake) => lake.clubs.map((club) => ({ club, lake })));
  const saved = store.clubs.map((c) => all.find((x) => x.club.id === c.id)).filter(Boolean);
  const offered = suggestions(all, state.near, state.random).filter((x) => page === "homeBase" || !store.clubs.some((c) => c.id === x.club.id));
  return `${page === "moreClubs" && saved.length ? `<h3 class="section">${h(t("In your list"))}</h3><ul class="results">${saved.map((x) => choiceRow(x, page)).join("")}</ul>` : ""}
    ${offered.length ? `<h3 class="section">${h(state.near ? t("Near you") : t("Suggestions"))}</h3><ul class="results">${offered.map((x) => choiceRow(x, page)).join("")}</ul>` : ""}
    <p class="sub tour-foot">${h(t("Search by club, lake or town to find any club in Germany, Austria or Switzerland."))}</p>
    <p class="sub tour-foot">${h(t("Clubs nobody has opened for a while update less often at first. After you add one, it is up to date within about 30 minutes."))}</p>`;
}

/** A tap on a club: the home base replaces the old one, more clubs come and go, the home base stays (ClubChoicePage.row). */
function pickClub(page, club, lake) {
  const clubs = store.clubs;
  const saved = savedClub(club, lake);
  if (page === "homeBase") {
    store.clubs = [saved, ...clubs.slice(1).filter((c) => c.id !== club.id)];
  } else if (!clubs.some((c) => c.id === club.id)) {
    store.clubs = [...clubs, saved];
  } else if (clubs[0]?.id !== club.id) {
    store.clubs = clubs.filter((c) => c.id !== club.id);
  }
}

/**
 * The tour: a page at a time with dots, Skip, Next and Let's row at the end. `lakes` is the club catalog
 * (null when it could not load), for the club choice and to know whether a river or canal club is in the list.
 */
export function renderTour(root, { languagePicker, wireLanguage, done, lakes, reload }) {
  // The club choice only when the tour starts with an empty list, as the app's (TourProgress.pages).
  const choice = store.clubs.length === 0;
  const state = { lakes: lakes ?? null, failed: lakes == null, query: "", near: null, random: [], asked: false };
  const pickRandom = () => {
    const all = (state.lakes ?? []).flatMap((lake) => lake.clubs.map((club) => ({ club, lake })));
    state.random = [...all].sort(() => Math.random() - 0.5).slice(0, 3);
  };
  pickRandom();
  const hasRiver = () => (state.lakes ?? []).some((l) => l.section && store.clubs.some((c) => c.lakeId === l.id));
  const pages = () => tourPages(hasRiver(), choice);
  // The page is kept by its name, so the river page coming or going doesn't move it (an older visit kept a number).
  const kept = load("rf.tourPage", 0);
  let id = typeof kept === "string" ? kept : pages()[Math.max(0, kept)]?.id ?? "welcome";
  if (!pages().some((x) => x.id === id)) id = "welcome";
  const needsHome = () => choice && store.clubs.length === 0;
  const finish = () => {
    save("rf.tourSeen", true);
    save("rf.tourPage", 0);
    // No tips on the day of the tour: it has just explained the page (TipPacing.tourEnded).
    save("rf.tourDay", dayKey());
    done();
  };
  const go = (i) => {
    const list = pages();
    let next = list[Math.min(Math.max(0, i), list.length - 1)].id;
    // No going past the home base choice without one (TutorialView's onChange(of: page)).
    const homeAt = list.findIndex((x) => x.id === "homeBase");
    if (needsHome() && homeAt >= 0 && list.findIndex((x) => x.id === next) > homeAt) next = "homeBase";
    id = next;
    save("rf.tourPage", id);
    draw();
    window.scrollTo(0, 0);
  };
  const askLocation = () => {
    // Asked on the home base page, for the clubs nearby (TutorialView asks there too).
    if (state.asked || !navigator.geolocation) return;
    state.asked = true;
    navigator.geolocation.getCurrentPosition((pos) => {
      state.near = { lat: pos.coords.latitude, lon: pos.coords.longitude };
      drawList();
    }, () => {}, { timeout: 10000, maximumAge: 600000 });
  };
  const drawList = () => {
    const box = root.querySelector("#tour-clubs");
    if (!box) return;
    box.innerHTML = choiceList(id, state);
    root.querySelector("#next").disabled = id === "homeBase" && needsHome();
  };
  const draw = () => {
    const list = pages();
    const index = Math.max(0, list.findIndex((x) => x.id === id));
    const page = list[index];
    id = page.id;
    const last = index === list.length - 1;
    setTitle(t(page.title));
    // The river page says what the river current tip would (RiverCurrentTip), so that tip stays away.
    if (page.id === "river") save("rf.tipsClosed", [...new Set([...closed(), "riverCurrent"])]);
    const body = page.choice
      ? `<label class="search tour-search">${icon("search")}<input id="tour-search" type="search" autocomplete="off" placeholder="${h(t("Club, lake or town"))}" aria-label="${h(t("Club, lake or town"))}"></label>
          <div id="tour-clubs" class="tour-clubs"></div>`
      : `${extra(page, languagePicker)}
          <ul class="card tour-points">${page.points.map((x) => `<li>${icon(x.icon)}<span>${h(t(x.text, ...(x.args?.() ?? [])))}</span></li>`).join("")}</ul>`;
    root.innerHTML = `<main class="page tour">
        <header class="nav"><span class="spacer"></span>${last || page.choice ? "" : `<button class="link" id="skip">${h(t("Skip"))}</button>`}</header>
        <div class="tour-page${page.choice ? " tour-choice" : ""}" style="--tint: var(--${page.tint === "mint" ? "teal" : page.tint})">
          <span class="tour-icon">${icon(page.icon)}</span>
          <h1>${h(t(page.title))}</h1>
          <p class="sub">${h(t(page.intro))}</p>
          ${body}
        </div>
        <nav class="tour-dots glass" aria-label="${h(t("Tour"))}">${list.map((x, i) => `<button data-page="${i}" class="${i === index ? "on" : ""}" aria-label="${i + 1}" ${i === index ? 'aria-current="step"' : ""}></button>`).join("")}</nav>
        <button class="primary wide" id="next">${h(last ? t("Let's row") : t("Next"))}</button>
      </main>`;
    // Skipping still asks for a home base first.
    root.querySelector("#skip")?.addEventListener("click", () => (needsHome() ? go(list.findIndex((x) => x.id === "homeBase")) : finish()));
    root.querySelector("#next").addEventListener("click", () => (last ? finish() : go(index + 1)));
    root.querySelectorAll("[data-page]").forEach((b) => b.addEventListener("click", () => go(+b.dataset.page)));
    if (page.choice) {
      const input = root.querySelector("#tour-search");
      input.value = state.query;
      input.addEventListener("input", () => {
        state.query = input.value;
        drawList();
      });
      const box = root.querySelector("#tour-clubs");
      box.addEventListener("click", async (e) => {
        if (e.target.closest("#tour-retry")) {
          const fresh = await reload?.().catch(() => null);
          state.lakes = fresh ?? null;
          state.failed = fresh == null;
          pickRandom();
          return drawList();
        }
        const button = e.target.closest(".result");
        const lake = state.lakes?.find((l) => l.id === button?.dataset.lake);
        const club = lake?.clubs.find((c) => c.id === button.dataset.club);
        if (!club) return;
        pickClub(id, club, lake);
        // The river page and the dots follow the clubs picked; the search stays as it was.
        draw();
      });
      drawList();
      if (id === "homeBase") askLocation();
    }
    wireLanguage?.(draw);
  };
  // Swipes and arrow keys page through, as the app's paged view; not while typing in the search.
  let startX = null;
  root.ontouchstart = (e) => (startX = e.target.closest?.(".tour-clubs") ? null : e.touches[0].clientX);
  root.ontouchend = (e) => {
    if (startX == null || !root.querySelector(".tour")) return;
    const dx = e.changedTouches[0].clientX - startX;
    startX = null;
    const index = pages().findIndex((x) => x.id === id);
    if (Math.abs(dx) > 60) go(index + (dx < 0 ? 1 : -1));
  };
  const keys = (e) => {
    if (!root.querySelector(".tour")) return document.removeEventListener("keydown", keys);
    if (e.target.closest?.("input")) return;
    const index = pages().findIndex((x) => x.id === id);
    if (e.key === "ArrowRight") go(index + 1);
    if (e.key === "ArrowLeft") go(index - 1);
  };
  document.addEventListener("keydown", keys);
  draw();
}

// ---- One-time tips ------------------------------------------------------------------------

/** The tips: title, message, icon, and the tip that follows once this one is closed. */
const TIPS = {
  // Under the top tile, the first time its Why line has a "… nearby" reason (NearbyWaterTip, app #401).
  nearbyWater: [key("Water nearby"), key("The light also looks at the water within 1 km of the launch point. If it is rougher or foggier out there, the Why line says so."), "crosshair"],
  topTile: [key("Tap a value"), key("Tap a value in the tile above to open its chart. Swiping there goes through only this tile's values."), "pointer", "allValues"],
  allValues: [key("All values in the top tile"), key("Tap \"All values\" under the tile to see every value there. Tap \"Fewer values\" to close it."), "chevrons-up-down"],
  conditionsExtras: [key("More on the air"), key("Feels like now covers wind chill and heat. Humidity shows the dew point underneath, and the gauge shows the air pressure and where it is heading."), "gauge", "rainRadar"],
  // One tip for the rain tile and its radar map (owner, 12 Nov 2026: the two merged).
  rainRadar: [key("Rain on the way?"), key("For the next two hours the rain tile reads the radar of the Deutscher Wetterdienst at the launch point, then the forecast. Open it for the radar map: tap the map to play it, or drag the slider from an hour ago to two hours ahead."), "umbrella"],
  hourly: [key("Plan your outing"), key("Each hour has its own rowing light. The icons on top name the columns, and rows after dark are dimmed."), "clock", "hourView"],
  hourView: [key("One hour in full"), key("Tap an hour to see all its conditions and the lake map at that time."), "pointer"],
  launchPoint: [key("Where the forecast is for"), key("Wind, waves and warnings are worked out for this launch point. Tap Directions to the club for the way there."), "map-pin-ellipse"],
  lakeView: [key("Look across the lake"), key("Tap the map to see the rowing light, waves and wind for the whole lake, hour by hour. Tap the water for the details of one spot."), "map"],
  satellite: [key("Satellite picture"), key("The latest picture from the Sentinel-2 satellites, which pass over every 2 to 5 days, so it can be a few days old and show clouds. Clearest shows the most recent picture with a clear view of the lake. Draw the shore, clubs, your routes, the wind, the waves, the rowing light or the ice map over it."), "earth"],
  source: [key("Where the forecast comes from"), key("The app picks the weather model that does best for this lake. Tap the line to see which one."), "cloud-sun"],
  coldWater: [key("Cold water"), key("A capsize in water below %@ gets dangerous within minutes. The app then lowers its own wind and gust limits by %@. Limits you set stay as they are, with a reminder on the rowing light."), "thermometer-snowflake"],
  myBoats: [key("Which boat do you row?"), key("Tap the boat the rowing light is for. ⓘ opens its limits, and below you can add your own boats."), "rower"],
  backgrounds: [key("One picture or many"), key("Pick a picture for all pages, a different one for single pages, or give a club its own. Under Look, choose whether the tiles show the picture or stay solid."), "image"],
  chartScrub: [key("Read any hour"), key("Drag the chart back to yesterday or up to 7 days ahead. Hold it, then slide along to read the value at each hour."), "hand"],
  weatherMap: [key("Weather on the map"), key("The map shows this weather around the lake. Press play to watch it move, or open it full screen with the arrows."), "map", "mapLink"],
  mapLink: [key("Chart and map together"), key("The map shows the hour of the chart's blue line. Tap the chain to give the map its own time, and again to link them."), "link"],
  rowImport: [key("Import a row"), key("Rowed it before? Bring in a GPX, TCX or FIT file (CrewNerd, Garmin, Strava) with Import a row, and plan with your real route and pace."), "import"],
  // On a river or canal club's page, for a club added after the tour; the tour's river page closes it (RiverCurrentTip).
  riverCurrent: [key("Current on the river"), key("The Current tile shows the nearest gauge's flow speed, water level and trend. Tap it for the level chart and your pace upstream and downstream."), "circle-arrow-right"],
  waterLevel: [key("Water level in winter"), key("Forggensee is let down every winter. While it is lowered, the Water level tile below takes the place of the ice estimate. Tap it for the last week's levels."), "arrow-down-to-line"],
  waterEstimate: [key("Water temperature from space"), key("No station measures the water here, so the app takes the last satellite reading of the lake and carries it forward with the air temperatures since. Tap the water tile for the satellite and its date."), "thermometer-waves"],
  // On a phone's lake map, under the grabber (RoutePanelTip).
  routePanel: [key("More or less panel"), key("Pull up for details, push down for more map."), "panel-bottom"],
  turningPoint: [key("Change a turning point"), key("Drag a point to move it, or delete just this one."), "hand"],
  boatTime: [key("Lake at the boat's time"), key("Move the boat along your route to see the lake at the time you get there."), "rower"],
  stretchPoint: [key("Add a point on the way"), key("Tap a stretch of your route to add a turning point there, or pull the stretch to add one and move it at once."), "spline"],
  // One way, out and back, or a loop (owner, 12 Nov 2026: Row a loop and One way merged; WayBackTip).
  wayBack: [key("The way back"), key("New routes go one way. Under the way back, pick Out and back to row the same way back, or Loop. Tapping within 50 m of your club also closes a loop."), "undo-2"],
  boatsElsewhere: [key("Your boats at other clubs"), key("Your boats show at the clubs where they are kept. At a regatta, tap a boat under “At other clubs” to take it along."), "circle-arrow-down"],
  placeLine: [key("Where the forecast is for"), key("Tap the place to see on a map the spot the forecast is for, with directions."), "map-pin-ellipse"],
  // At "Suggest the launch point" in the Location sheet, not in the page's card (SuggestLaunchPointTip).
  suggestLaunchPoint: [key("Know the launch point?"), key("Know where this club's boats go on the water? Suggest the launch point."), "oars"],
  routePlanning: [key("Plan a route"), key("Tap here, then tap your turning points on the water. You see the light along the route and the best time to start."), "route"],
};

/** Tips closed in this browser; a follow-up tip shows only after the one before. */
const closed = () => {
  const list = load("rf.tipsClosed", []);
  return Array.isArray(list) ? list : [];
};

const waitsFor = (id) => Object.keys(TIPS).find((k) => TIPS[k][3] === id);

// ---- Pacing (owner, 12 Nov 2026; the app's TipPacing and ClubPageTip) ----------------------
// One tip on a screen, at most one new tip a day, none on the day of the tour, closing one never
// brings the next at once, and "No more tips" stops them. The tips below are for a rare case or
// the moment of use: they skip the daily limit and the quiet first day (the app's MomentTip).
const MOMENT = new Set(["nearbyWater", "waterLevel", "riverCurrent", "coldWater", "boatsElsewhere", "turningPoint", "boatTime", "stretchPoint", "wayBack"]);

/** The order in which the paced tips take their day, where several are on a screen. */
const ORDER = ["topTile", "allValues", "placeLine", "hourly", "lakeView", "launchPoint", "conditionsExtras", "hourView", "satellite", "rainRadar", "source", "waterEstimate"];

/** Today as "2026-11-12", in this browser's time. */
export function dayKey(now = new Date()) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

/**
 * Which of the tips on a screen may show, as ids: the first tip for a rare case if there is one,
 * else today's paced tip. `state` is { day, id }, the paced tip that took the day; `pick` says
 * which tip takes a new day. Pure, for the tests.
 */
export function pacedChoice(ids, { today, tourDay, off, state }) {
  if (off) return { show: [], state };
  const moment = ids.find((id) => MOMENT.has(id));
  if (moment) return { show: [moment], state };
  if (tourDay === today) return { show: [], state };
  if (state?.day === today) return { show: ids.includes(state.id) ? [state.id] : [], state };
  const rank = (id) => (ORDER.includes(id) ? ORDER.indexOf(id) : ORDER.length);
  const pick = [...ids].sort((a, b) => rank(a) - rank(b))[0];
  return pick ? { show: [pick], state: { day: today, id: pick } } : { show: [], state };
}

/** Shows the one tip of this screen that the pacing allows and leaves the others hidden. */
export function paceTips(box) {
  if (!box) return;
  const asides = [...box.querySelectorAll(".tip[data-tip]")];
  const before = load("rf.tipDay", null);
  const { show, state } = pacedChoice(asides.map((a) => a.dataset.tip), {
    today: dayKey(), tourDay: load("rf.tourDay", null), off: load("rf.tipsOff", false) === true, state: before,
  });
  if (state !== before) save("rf.tipDay", state);
  for (const aside of asides) aside.hidden = !show.includes(aside.dataset.tip);
}

/** A tip's box, hidden until paceTips shows it, or nothing once it was closed or while the tip before it is still open. */
export function tip(id) {
  const spec = TIPS[id];
  const shut = closed();
  const before = waitsFor(id);
  if (spec && shut.includes(id)) return spec[3] ? tip(spec[3]) : "";
  if (!spec || (before && !shut.includes(before))) return "";
  const combined = load("rf.combinedTopTile", true) !== false;
  // All values only with Current conditions in the top tile; Tap a value then names it (TopTileTip).
  if (id === "allValues" && !combined) return "";
  const [title, plain, iconName] = spec;
  const message = id === "topTile" && combined ? key("Tap a value in the tile above to open its chart; swiping there goes through all values. \"All values\" under the tile opens the rest.") : plain;
  const args = id === "coldWater" ? [temperature(COLD.waterC), wind(COLD.marginMs)] : [];
  return `<aside class="tip" data-tip="${id}" hidden>${icon(iconName)}<div><strong>${h(t(title))}</strong><p>${h(t(message, ...args))}</p>
    <p class="tip-actions"><button class="link tip-got">${h(t("Got it"))}</button><button class="link tip-off">${h(t("No more tips"))}</button></p></div>
    <button class="tip-close" aria-label="${h(t("Close"))}">${icon("x")}</button></aside>`;
}

/** Shows the screen's one tip; closing it ("Got it" or ×) keeps it closed, and the next waits for another day. */
export function wireTips(box) {
  if (!box) return;
  paceTips(box);
  if (box.dataset.tipsWired) return;
  box.dataset.tipsWired = "1";
  box.addEventListener("click", (e) => {
    const button = e.target.closest(".tip-close, .tip-got, .tip-off");
    if (!button) return;
    const aside = button.closest(".tip");
    save("rf.tipsClosed", [...new Set([...closed(), aside.dataset.tip])]);
    aside.remove();
    // "No more tips": every tip goes, until "Show the tips again".
    if (button.classList.contains("tip-off")) {
      save("rf.tipsOff", true);
      document.querySelectorAll(".tip[data-tip]").forEach((other) => { other.hidden = true; });
    }
  });
}

/** Using what a tip points at closes it, as the app's invalidate(reason: .actionPerformed). */
export function closeTip(box, id) {
  save("rf.tipsClosed", [...new Set([...closed(), id])]);
  box.querySelectorAll(`.tip[data-tip="${id}"]`).forEach((aside) => aside.remove());
}

/** "Show the tips again", also after "No more tips". */
export const replayTips = () => {
  save("rf.tipsClosed", []);
  save("rf.tipsOff", false);
  save("rf.tipDay", null);
};

/** A tip as a bubble on the control before it (placement rule R2; the app's popoverTip). */
export const bubbleTip = (id) => {
  // Only the tip itself: a bubble points at one control, so it never hands over to the next tip in a chain.
  const html = tip(id);
  return html.includes(`data-tip="${id}"`) ? html.replace('class="tip"', 'class="tip pop"') : "";
};

/** Puts a tip just under a card's title. */
export function withTip(cardHtml, id) {
  const html = tip(id);
  if (!html) return cardHtml;
  const at = cardHtml.indexOf("</header>");
  return at < 0 ? cardHtml : `${cardHtml.slice(0, at + 9)}${html}${cardHtml.slice(at + 9)}`;
}
