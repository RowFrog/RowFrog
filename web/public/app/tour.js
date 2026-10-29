// The tour (TutorialView, TourPage) and the one-time tips (the app's TipKit
// tips). The website keeps choosing the clubs in the list, so its tour has no
// home base pages; the texts name the website's own controls where the app's
// differ (no swiping a row, no pulling down, no widgets or app icon).

import { t } from "./i18n.js";
import { icon } from "./icons.js";
import { key, COLD, standardLimit } from "./logic.js";
import { h, load, save, setTitle, dot, lightTitle, conditionIcon, conditionTexts, TILE_ORDER, temperature, wind } from "./shared.js";

// ---- The tour ---------------------------------------------------------------------------

const p = (iconName, text) => ({ icon: iconName, text });

/** The pages, as TourPage without the club choice; the river page only with a river or canal club in the list. */
export function tourPages(river = false) {
  return [
    {
      id: "welcome", icon: "sailboat", tint: "blue", title: key("Welcome to Row Frog"), intro: key("Weather and a rowing forecast for your club's launch point."),
      points: [p("house", key("Your home base opens first when you start the app.")), p("hand", key("To change it, open the list, tap Edit and then the house next to a club."))],
    },
    {
      id: "rowingLight", icon: "siren", tint: "green", title: key("The rowing light"), intro: key("Every page starts with the rowing light for the hour ahead."),
      points: [
        p("message-square-text", key("The \"Why\" line names what sets the light.")), p("sunrise", key("Rowing is only advised while the sun is up.")),
        p("clock", key("Each of the next 48 hours has its own light.")),
        p("umbrella", key("The rain tile shows DWD's radar for the next two hours, then the forecast.")),
        p("clock-alert", key("Grey instead of green: the forecast is over 3 hours old. Tap Refresh under the club's name.")),
        p("user-round-search", key("The light is advice. You decide, and when in doubt you stay ashore.")),
      ],
    },
    {
      id: "conditions", icon: "thermometer", tint: "teal", title: key("Conditions at a glance"), intro: key("Below the light you find what matters on the water."),
      points: [
        p("person-standing", key("Feels like: colder with wind chill, warmer with humidity and heat.")), p("droplet", key("Humidity, with the dew point underneath.")),
        p("gauge", key("Air pressure on a gauge, with its trend for the hours ahead.")),
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
      id: "boats", icon: "sailboat", tint: "mint", title: key("Your boats and limits"), intro: key("The rowing light is worked out for one boat. Pick it at the top of the settings."),
      points: [
        p("check", key("Small boats are ticked at first. Tick Big boats if you row a four or an eight.")),
        p("list", key("Add your own boats under My boats. When it is too rough for yours, the app names one that would be fine.")),
        p("sliders-horizontal", key("The sliders next to a boat open its limits.")), p("map", key("Pick the boat that colours the lake map.")),
        { icon: "thermometer-snowflake", text: key("Below %@ water a blue life-jacket badge shows; the light stays about the weather. Below %@ the advice is stricter."), args: () => [temperature(standardLimit("lifeJacket")), temperature(COLD.waterC)] },
      ],
    },
    {
      id: "lake", icon: "map", tint: "teal", title: key("Lake view and routes"), intro: key("Below the current conditions, the Lake view shows the whole lake."),
      points: [
        p("map", key("The Lake view shows the light, waves and wind across the whole lake. Tap it for the full map.")),
        p("clock", key("On the map, move through the hours in the strip at the bottom and tap the water for one spot.")),
        p("route", key("Plan a route: tap your turning points to see the light along the way and the best time to start.")),
        p("bookmark", key("Save the routes you row often in the Routes menu.")),
        p("globe", key("Below it, the latest satellite picture of the lake, with a switch to the clearest one.")),
      ],
    },
    river && {
      id: "river", icon: "circle-arrow-right", tint: "teal", title: key("Rivers and canals"), intro: key("A river or canal club gets its own two tiles."),
      points: [
        p("map", key("The River view or Canal view shows your stretch between weirs or locks, with markers where it ends.")),
        p("circle-arrow-right", key("The Current tile shows the nearest gauge's flow speed, water level and trend. It is amber at high water or a fast current, red when shipping is stopped or the current is too strong.")),
        p("pointer", key("Tap it for the level chart and your pace upstream and downstream.")),
      ],
    },
    {
      id: "locations", icon: "list", tint: "blue", title: key("Your locations"), intro: key("Keep all the places you row in one list."),
      points: [
        p("move", key("Swipe left and right, or use the arrow keys, to move between your clubs. The house marks your home base.")),
        p("search", key("Search the list for any club in Germany, Austria or Switzerland and tap + to add it.")),
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
        p("languages", key("Language: English or German.")), p("ruler", key("Units for temperature, wind, waves, rain, distances and air pressure.")),
        p("sun-moon", key("Light, dark or like your device.")), p("image", key("Background pictures, including your own photos.")),
        p("circle-help", key("You can watch this tour again in the settings.")),
      ],
    },
  ].filter(Boolean);
}

export const tourSeen = () => load("rf.tourSeen", false) === true;

/** A small picture of the feature, as TourPageView.extra. */
function extra(page, languagePicker) {
  if (page.id === "welcome") return `<section class="card group tour-language">${languagePicker()}</section>`;
  if (page.id === "rowingLight") {
    return `<div class="tour-lights">${["green", "amber", "red"].map((l) => `<div class="${l}">${dot(l, 30)}<small>${h(lightTitle(l))}</small></div>`).join("")}</div>`;
  }
  if (page.id === "conditions") {
    const texts = conditionTexts();
    return `<div class="card tour-conditions">${TILE_ORDER.map((c) => `<span>${conditionIcon(c)} ${h(texts[c][1])}</span>`).join("")}</div>`;
  }
  return "";
}

/** The tour: a page at a time with dots, Skip, Next and Let's row at the end. */
export function renderTour(root, { languagePicker, wireLanguage, done, river }) {
  const pages = tourPages(river);
  let index = Math.min(Math.max(0, load("rf.tourPage", 0)), pages.length - 1);
  const finish = () => {
    save("rf.tourSeen", true);
    save("rf.tourPage", 0);
    done();
  };
  const draw = () => {
    const page = pages[index];
    const last = index === pages.length - 1;
    setTitle(t(page.title));
    root.innerHTML = `<main class="page tour">
        <header class="nav"><span class="spacer"></span>${last ? "" : `<button class="link" id="skip">${h(t("Skip"))}</button>`}</header>
        <div class="tour-page" style="--tint: var(--${page.tint === "mint" ? "teal" : page.tint})">
          <span class="tour-icon">${icon(page.icon)}</span>
          <h1>${h(t(page.title))}</h1>
          <p class="sub">${h(t(page.intro))}</p>
          ${extra(page, languagePicker)}
          <ul class="card tour-points">${page.points.map((x) => `<li>${icon(x.icon)}<span>${h(t(x.text, ...(x.args?.() ?? [])))}</span></li>`).join("")}</ul>
        </div>
        <nav class="tour-dots" aria-label="${h(t("Tour"))}">${pages.map((_, i) => `<button data-page="${i}" class="${i === index ? "on" : ""}" aria-label="${i + 1}" ${i === index ? 'aria-current="step"' : ""}></button>`).join("")}</nav>
        <button class="primary wide" id="next">${h(last ? t("Let's row") : t("Next"))}</button>
      </main>`;
    root.querySelector("#skip")?.addEventListener("click", finish);
    root.querySelector("#next").addEventListener("click", () => (last ? finish() : go(index + 1)));
    root.querySelectorAll("[data-page]").forEach((b) => b.addEventListener("click", () => go(+b.dataset.page)));
    wireLanguage?.(draw);
  };
  const go = (i) => {
    index = Math.min(Math.max(0, i), pages.length - 1);
    save("rf.tourPage", index);
    draw();
    window.scrollTo(0, 0);
  };
  // Swipes and arrow keys page through, as the app's paged view.
  let startX = null;
  root.ontouchstart = (e) => (startX = e.touches[0].clientX);
  root.ontouchend = (e) => {
    if (startX == null || !root.querySelector(".tour")) return;
    const dx = e.changedTouches[0].clientX - startX;
    startX = null;
    if (Math.abs(dx) > 60) go(index + (dx < 0 ? 1 : -1));
  };
  const keys = (e) => {
    if (!root.querySelector(".tour")) return document.removeEventListener("keydown", keys);
    if (e.key === "ArrowRight") go(index + 1);
    if (e.key === "ArrowLeft") go(index - 1);
  };
  document.addEventListener("keydown", keys);
  draw();
}

// ---- One-time tips ------------------------------------------------------------------------

/** The tips: title, message, icon, and the tip that follows once this one is closed. */
const TIPS = {
  topTile: [key("Tap a value"), key("Tap a value in the tile above to open its chart. Swiping there goes through only this tile's values."), "pointer"],
  conditionsExtras: [key("More on the air"), key("Feels like now covers wind chill and heat. Humidity shows the dew point underneath, and the gauge shows the air pressure and where it is heading."), "gauge", "rainRadar"],
  rainRadar: [key("Rain on the way?"), key("For the next two hours the rain tile reads the radar of the Deutscher Wetterdienst at the launch point, in 15-minute steps, and the forecast after that. The radar updates every few minutes."), "umbrella", "radarMap"],
  radarMap: [key("Rain radar map"), key("Open the rain tile: for the next two hours its map shows the radar. Tap the map to play it, or drag the slider from an hour ago to two hours ahead."), "map"],
  hourly: [key("Plan your outing"), key("Each hour has its own rowing light. The icons on top name the columns, and rows after dark are dimmed."), "clock", "hourView"],
  hourView: [key("One hour in full"), key("Tap an hour to see all its conditions and the lake map at that time."), "pointer"],
  launchPoint: [key("Where the forecast is for"), key("Wind, waves and warnings are worked out for this launch point. Tap Directions to the club for the way there."), "map-pin"],
  lakeView: [key("Look across the lake"), key("Tap the map to see the rowing light, waves and wind for the whole lake, hour by hour. Tap the water for the details of one spot."), "map"],
  satellite: [key("Satellite picture"), key("The latest picture from the Sentinel-2 satellites, which pass over every 2 to 5 days, so it can be a few days old and show clouds. Clearest shows the most recent picture with a clear view of the lake. Draw the shore, clubs, your routes, the wind, the waves, the rowing light or the ice map over it."), "globe"],
  source: [key("Where the forecast comes from"), key("The app picks the weather model that does best for this lake. Tap the line to see which one."), "cloud-sun"],
  coldWater: [key("Cold water"), key("A capsize in water below %@ gets dangerous within minutes. The app then lowers its own wind and gust limits by %@. Limits you set stay as they are, with a reminder on the rowing light."), "thermometer-snowflake"],
  myBoats: [key("Which boat do you row?"), key("Tick the boat the rowing light is for. The sliders open its limits, and below you can add your own boats."), "sailboat"],
  backgrounds: [key("One picture or many"), key("Pick a picture for all pages, a different one for single pages, or give a club its own. Under Look, choose whether the tiles show the picture or stay solid."), "image"],
  chartScrub: [key("Read any hour"), key("Hold the chart, then slide along it to read the value at each hour."), "hand"],
  weatherMap: [key("Weather on the map"), key("The map shows this weather around the lake. Press play to watch it move, or open it full screen with the arrows."), "map", "mapLink"],
  mapLink: [key("Chart and map together"), key("The map shows the hour of the chart's blue line. Tap the chain to give the map its own time, and again to link them."), "link"],
  rowImport: [key("Import a row"), key("Rowed it before? Bring in a GPX, TCX or FIT file (CrewNerd, Garmin, Strava) with Import a row, and plan with your real route and pace."), "upload"],
  saveData: [key("Out on mobile data?"), key("Switch on Save mobile data: satellite pictures then load only when you tap them and the radar needs fewer downloads. Forecasts and warnings always load."), "radio-tower"],
  factoryReset: [key("What a reset does"), key("Appearance, units, language and background pictures go back to how the app came, and your own pictures are deleted. Your locations and home base stay."), "rotate-ccw"],
  waterEstimate: [key("Water temperature from space"), key("No station measures the water here, so the app takes the last satellite reading of the lake and carries it forward with the air temperatures since. Tap the water tile for the satellite and its date."), "satellite"],
  closeLoop: [key("Row a loop"), key("Close the loop: tap within 50 m of your club, or use Close loop."), "repeat"],
  turningPoint: [key("Change a turning point"), key("Drag a point to move it, or delete just this one."), "move"],
  boatTime: [key("Lake at the boat's time"), key("Move the boat along your route to see the lake at the time you get there."), "sailboat"],
  stretchPoint: [key("Add a point on the way"), key("Tap a stretch of your route to add a turning point there, or pull the stretch to add one and move it at once."), "spline"],
  oneWay: [key("One way or out and back"), key("New routes go one way. Turn on Out and back to row the same way back."), "arrow-up-down"],
  routePlanning: [key("Plan a route"), key("Tap here, then tap your turning points on the water. You see the light along the route and the best time to start."), "route"],
};

/** Tips closed in this browser; a follow-up tip shows only after the one before. */
const closed = () => {
  const list = load("rf.tipsClosed", []);
  return Array.isArray(list) ? list : [];
};

const waitsFor = (id) => Object.keys(TIPS).find((k) => TIPS[k][3] === id);

/** A tip's box, or once it was closed the tip that follows it; nothing while the tip before it is still open. */
export function tip(id) {
  const spec = TIPS[id];
  const shut = closed();
  const before = waitsFor(id);
  if (spec && shut.includes(id)) return spec[3] ? tip(spec[3]) : "";
  if (!spec || (before && !shut.includes(before))) return "";
  const [title, message, iconName] = spec;
  const args = id === "coldWater" ? [temperature(COLD.waterC), wind(COLD.marginMs)] : [];
  return `<aside class="tip" data-tip="${id}">${icon(iconName)}<div><strong>${h(t(title))}</strong><p>${h(t(message, ...args))}</p></div>
    <button class="tip-close" aria-label="${h(t("Close"))}">${icon("x")}</button></aside>`;
}

/** Closing a tip keeps it closed; the tip that follows it (if any) takes its place. */
export function wireTips(box) {
  box.addEventListener("click", (e) => {
    const button = e.target.closest(".tip-close");
    if (!button) return;
    const aside = button.closest(".tip");
    const id = aside.dataset.tip;
    save("rf.tipsClosed", [...new Set([...closed(), id])]);
    const next = TIPS[id][3];
    if (next) aside.insertAdjacentHTML("afterend", tip(next));
    aside.remove();
  });
}

/** "Show the tips again". */
export const replayTips = () => save("rf.tipsClosed", []);

/** Puts a tip just under a card's title. */
export function withTip(cardHtml, id) {
  const html = tip(id);
  if (!html) return cardHtml;
  const at = cardHtml.indexOf("</header>");
  return at < 0 ? cardHtml : `${cardHtml.slice(0, at + 9)}${html}${cardHtml.slice(at + 9)}`;
}

