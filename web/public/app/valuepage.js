// A value's own page (ConditionDetailView): the big value at the chart's blue
// line, the chart, the weather map linked to it in time, the facts and the
// advice, with the next and previous values a tap or arrow key away.

import { t } from "./i18n.js";
import { icon } from "./icons.js";
import { currentHour, iceValue } from "./logic.js";
import { store, h, time as clock, dayTime, setTitle, testing, conditionIcon, conditionTexts, TILE_ORDER, findClub, loadForecast, forBoat, footerLinks, conditionGraphic, loadLeaflet, distance } from "./shared.js";
import { conditionData, dataAt, conditionDetail } from "./values.js";
import { tip, wireTips } from "./tour.js";
import { detailTime, mountChart } from "./chart.js";
import { LAYERS, layerFor, weatherMap, frames, frameIndex, frameLabel, colourBar, layerOptions, loadIndex } from "./weathermap.js";
import { radarAt, readRadar, radarOverlay, radarFrames, radarCovers, nearestFrame, openRadarMap } from "./radar.js";

let current = null;

/** The page for `condition` of a club, opened at now or at a picked hour. */
export async function renderValuePage(root, clubId, condition, at, orderName = null) {
  current?.cleanup();
  // Clubs saved by an early version of the website have no launch point; the catalog has it.
  let club = store.clubs.find((c) => c.id === clubId);
  if (!club?.launchPoint) club = (await findClub(clubId)) ?? club;
  let raw;
  try {
    raw = await loadForecast(clubId);
  } catch {
    location.hash = `#/club/${encodeURIComponent(clubId)}`;
    return;
  }
  const forecast = forBoat(raw);
  const hour = (at && forecast.hours.find((x) => x.time === at)) ?? currentHour(forecast.hours);
  // DWD's radar at the launch point, as the club page read it; read now when it has not.
  const radar = radarAt(club?.launchPoint);
  const data = conditionData(forecast, hour, radar);
  const time = detailTime(store.mapLinked);
  const hidden = new Map();
  // Opened from the top tile, the arrows, the menu and a swipe go through its values only.
  const top = orderName === "top" ? topTileValues(forecast, hour) : null;
  const order = top?.includes(condition) ? top : TILE_ORDER;
  const page = { root, club, clubId, data, time, hidden, condition, order, orderName: order === top ? "top" : null, at, map: null, playing: null, showLimits: store.limitInfo };
  current = page;
  page.cleanup = () => {
    clearInterval(page.playing);
    page.map?.remove();
    document.removeEventListener("keydown", page.keys);
    document.querySelector(".wm-full")?.remove();
  };
  page.keys = (e) => {
    if (!root.querySelector(".value-page")) return document.removeEventListener("keydown", page.keys);
    if (e.target.closest?.("input, select, textarea") || document.querySelector(".wm-full, dialog.sheet")) return;
    if (e.key === "ArrowRight") go(page, 1);
    if (e.key === "ArrowLeft") go(page, -1);
    if (e.key === "Escape") location.hash = `#/club/${encodeURIComponent(clubId)}`;
  };
  document.addEventListener("keydown", page.keys);
  // The map's link to the chart is remembered across pages, as in the app.
  time.listeners.add(() => {
    if (store.mapLinked !== time.linked) store.mapLinked = time.linked;
  });
  show(page);
  if (!radar && club?.launchPoint) {
    readRadar(club.launchPoint).then((read) => {
      if (!read || current !== page || !root.querySelector(".value-page")) return;
      page.data = conditionData(forecast, hour, read);
      if (page.condition === "precipitation") show(page);
    });
  }
}

/** The top tile's values in its order (NowCard.tileValues). */
export function topTileValues(forecast, hour) {
  return [
    "temperature", ...(hour.apparentTemperatureC != null ? ["feelsLike"] : []),
    "waterTemperature", "wind", "waves", "precipitation", "visibility", ...(iceValue(forecast) ? ["ice"] : []),
  ];
}

function neighbour(page, by) {
  const { order } = page;
  const i = order.indexOf(page.condition);
  return order[(i + by + order.length) % order.length];
}

function pageHash(page) {
  return `#/club/${encodeURIComponent(page.clubId)}/value/${page.condition}${page.at ? `/${encodeURIComponent(page.at)}` : ""}${page.orderName ? `?order=${page.orderName}` : ""}`;
}

function go(page, by) {
  page.condition = neighbour(page, by);
  history.replaceState(null, "", pageHash(page));
  show(page);
}

/** A sideways swipe moves to the next or previous value; not on the chart or the map, where a drag scrubs or pans. */
function wireSwipe(page, main) {
  let start = null;
  main.addEventListener("touchstart", (e) => {
    const touch = e.touches[0];
    start = e.touches.length === 1 && !e.target.closest("#chart, .map-card, .wm-full, input, select") ? { x: touch.clientX, y: touch.clientY } : null;
  }, { passive: true });
  main.addEventListener("touchend", (e) => {
    if (!start) return;
    const touch = e.changedTouches[0];
    const dx = touch.clientX - start.x;
    const dy = touch.clientY - start.y;
    start = null;
    if (Math.abs(dx) > 60 && Math.abs(dx) > 1.5 * Math.abs(dy)) go(page, dx < 0 ? 1 : -1);
  }, { passive: true });
}

function show(page) {
  const { root, data, condition, time } = page;
  clearInterval(page.playing);
  page.playing = null;
  page.map?.remove();
  page.map = null;
  time.mapHours = null;
  for (const f of [...time.listeners]) if (f.page) time.listeners.delete(f);
  const titles = conditionTexts();
  const title = titles[condition][1];
  setTitle(title);
  const detail = conditionDetail(condition, data);
  const hidden = page.hidden.get(condition) ?? new Set();
  const layer = detail.history || !detail.lines.length ? null : layerFor(condition);
  const menu = page.order.map((c) => {
    const value = conditionDetail(c, data).value;
    return `<option value="${c}" ${c === condition ? "selected" : ""}>${h(value ? `${titles[c][1]} · ${value}` : titles[c][1])}</option>`;
  }).join("");
  root.innerHTML = `<header class="nav value-nav">
      <label class="jump">${conditionIcon(titles[condition][0])}<select id="jump" aria-label="${h(t("Go to another value"))}">${menu}</select>${icon("chevron-down")}</label>
      <strong class="nav-title">${h(title)}</strong>
      <a class="link strong" href="#/club/${encodeURIComponent(page.clubId)}">${h(t("Done"))}</a></header>
    ${testing()}
    <main class="page value-page">
      <div class="value-top">
        <button class="tool" id="prev" aria-label="${h(t(titles[neighbour(page, -1)][1]))}">${icon("chevron-left")}</button>
        <div class="value-head"><span class="big-value" id="big-value"></span><small class="sub" id="big-note"></small></div>
        <span class="value-big" id="big-graphic"></span>
        <button class="tool" id="next" aria-label="${h(t(titles[neighbour(page, 1)][1]))}">${icon("chevron-right")}</button>
      </div>
      <div class="value-body ${layer ? "with-map" : ""}">
        <div class="value-chart">
          ${detail.lines.length ? `<div id="chart"></div>` : ""}
          ${detail.lines.length > 1 ? `<div class="chart-legend">${detail.lines.map((l) => `<button data-line="${h(l.name)}" class="${hidden.has(l.name) ? "off" : ""}" style="color:${l.colour}">
            <i class="${l.dashed ? "dashed" : ""}"></i><span>${h(l.name)}</span></button>`).join("")}</div>` : ""}
          ${detail.lines.length ? tip("chartScrub") : ""}
          ${layer ? tip("weatherMap") : ""}
        </div>
        ${layer ? `<section class="map-card" id="map-card"></section>` : ""}
      </div>
      ${detail.limitInfo ? `<div class="limit-info"><button class="link" id="limit-info">${icon("info")} ${h(t("About the limits"))}</button>
        <p class="small boxed" id="limit-text" ${page.showLimits ? "" : "hidden"}>${h(detail.limitInfo)}</p></div>` : ""}
      ${facts(detail)}
      ${stationCard(condition, data)}
      <p class="rowing">${icon("sailboat")}<span>${h(detail.rowing)}</span></p>
      <p class="sub small">${h(detail.source)}</p>
      <p class="neighbours"><button class="link sub" id="prev-name">${icon("chevron-left")} ${h(titles[neighbour(page, -1)][1])}</button>
        <button class="link sub" id="next-name">${h(titles[neighbour(page, 1)][1])} ${icon("chevron-right")}</button></p>
      ${footerLinks()}
    </main>`;
  window.scrollTo(0, 0);
  showStationMap(root.querySelector("#station-map"), data.water?.station);
  wireTips(root.querySelector("main"));
  wireSwipe(page, root.querySelector("main"));
  const head = () => {
    // The big value at the chart's blue line; past measurements keep the measured value.
    const shown = detail.history || !detail.lines.length ? data : dataAt(data, time.hour);
    const top = shown === data ? detail : conditionDetail(condition, shown);
    root.querySelector("#big-value").textContent = top.value;
    root.querySelector("#big-note").textContent = shown.now.time === data.now.time ? top.note : [dayTime(shown.now.time), top.note].filter(Boolean).join(" · ");
    // The tile's graphic, larger, unless the page draws its own (wind dial, gauge, sun path).
    root.querySelector("#big-graphic").innerHTML = top.big || conditionGraphic(condition, shown.forecast, shown.now);
  };
  head();
  const headListener = () => head();
  headListener.page = true;
  time.listeners.add(headListener);
  const chartBox = root.querySelector("#chart");
  let redraw = null;
  if (chartBox) redraw = mountChart(chartBox, detail, data, time, { hidden });
  root.querySelectorAll("[data-line]").forEach((b) => b.addEventListener("click", () => {
    const name = b.dataset.line;
    if (hidden.has(name)) hidden.delete(name);
    else if (detail.lines.length - hidden.size > 1) hidden.add(name);
    page.hidden.set(condition, hidden);
    b.classList.toggle("off", hidden.has(name));
    redraw?.();
  }));
  root.querySelector("#jump").addEventListener("change", (e) => {
    page.condition = e.target.value;
    history.replaceState(null, "", pageHash(page));
    show(page);
  });
  for (const [sel, by] of [["#prev", -1], ["#next", 1], ["#prev-name", -1], ["#next-name", 1]]) root.querySelector(sel).addEventListener("click", () => go(page, by));
  root.querySelector("#limit-info")?.addEventListener("click", () => {
    page.showLimits = !page.showLimits;
    store.limitInfo = page.showLimits;
    root.querySelector("#limit-text").hidden = !page.showLimits;
  });
  if (layer) mapCard(page, layer, detail, hidden);
}

function facts(detail) {
  if (!detail.facts.length) return "";
  if (detail.twoColumnFacts) {
    return `<div class="facts two">${detail.facts.map(([k, v]) => `<div><small class="sub">${h(k)}</small><strong>${h(v)}</strong></div>`).join("")}</div>`;
  }
  return `<dl class="facts">${detail.facts.map(([k, v]) => `<dt>${h(k)}</dt><dd>${h(v)}</dd>`).join("")}</dl>`;
}

/**
 * The weather map under the chart (beside it on wide screens). Linked, it
 * shows the hour of the chart's blue line; the chain gives it its own time,
 * moved with its own slider and play button.
 */
async function mapCard(page, layerId, detail, hidden) {
  const { data, time, club } = page;
  const layer = LAYERS[layerId];
  const box = page.root.querySelector("#map-card");
  const point = club?.launchPoint;
  if (!point) return box.remove();
  let index = null;
  try {
    if (layer.model) index = await loadIndex();
  } catch {
    // The card says so below.
  }
  if (!box.isConnected) return;
  const list = frames(layer, index);
  const start = new Date(data.now.time).getTime();
  const x = (date) => (date - start) / 3600000;
  if (layer.links === "hour") time.mapHours = list.map(x);
  else if (layer.links === "day" && list.length) {
    const hours = [];
    for (let i = Math.ceil(x(list[0])); i <= x(list[list.length - 1]) + 23; i++) hours.push(i);
    time.mapHours = hours;
  }
  const mapDate = () => new Date(start + time.shownMapHour * 3600000);
  const current = () => (layer.links === "none" ? list.length - 1 : frameIndex(layer, list, mapDate()));
  // The rain map shows DWD's radar while it covers the time (an hour back to two ahead), at the first hour the latest picture.
  const panelDate = () => (layerId === "rain" && data.isNow && time.shownMapHour === 0 ? Date.now() : mapDate().getTime());
  const showsRadar = () => layerId === "rain" && radarCovers(panelDate());
  box.innerHTML = `<header class="map-head">${icon(layer.icon)}<strong id="map-time"></strong><span class="spacer"></span>
      ${layer.links !== "none" ? `<button class="chain" id="chain"></button>` : ""}
      <button class="tool" id="map-full" aria-label="${h(t("Opens the map full screen"))}">${icon("maximize-2")}</button></header>
    <div class="map-frame"><div class="wm" id="wm"></div><p class="map-note" id="map-note" hidden></p></div>
    ${list.length > 1 && layer.links !== "none" ? `<div class="map-controls"><button class="tool" id="play" aria-label="${h(t("Play"))}">${icon("play")}</button>
      <input type="range" id="slider" min="0" max="${list.length - 1}" step="1" aria-label="${h(t("Time"))}">
      <button class="tool ${store.mapLoop ? "on" : ""}" id="loop" aria-label="${h(t("Play 3 times"))}">${icon("repeat")}</button></div>` : ""}`;
  const wm = await weatherMap(box.querySelector("#wm"), point, layerId, { interactive: false });
  page.map = wm;
  const radar = layerId === "rain" ? radarOverlay(await loadLeaflet(), wm.map, point) : null;
  // Full screen: the radar map while the card shows the radar, else the weather map.
  const open = () => (showsRadar() ? openRadarMap(point, radarAt(point)?.reference) : openFull(page, layerId, detail, hidden));
  box.querySelector(".map-frame").addEventListener("click", open);
  box.querySelector("#map-full").addEventListener("click", open);
  const update = () => {
    if (!box.isConnected) return;
    const label = box.querySelector("#map-time");
    if (radar && showsRadar()) {
      const frame = nearestFrame(panelDate(), radarFrames(radarAt(point)?.reference));
      wm.show(null);
      radar.show(frame);
      label.textContent = t("Radar %@", clock(frame));
    } else {
      radar?.remove();
    }
    const i = current();
    if (i == null) return;
    if (!radar || !showsRadar()) {
      wm.show(list[i]);
      // Past the radar's two hours the rain map is the forecast, and says so.
      label.textContent = layer.links === "none" ? t("Live") : layerId === "rain" ? t("Forecast %@", dayTime(list[i])) : frameLabel(layer, list[i]);
    }
    const chain = box.querySelector("#chain");
    if (chain) {
      chain.className = `chain ${time.linked ? "on" : ""}`;
      chain.innerHTML = `${icon("link")} ${h(time.linked ? t("Linked") : t("Own time"))}`;
    }
    const slider = box.querySelector("#slider");
    if (slider) slider.value = i;
    const out = time.mapOutOfRange;
    box.querySelector(".map-frame").classList.toggle("out", out);
    const note = box.querySelector("#map-note");
    note.hidden = !out;
    if (out && list.length) note.textContent = mapDate() > list[list.length - 1] ? t("The maps end %@; the chart goes on.", dayTime(list[list.length - 1])) : t("The maps start %@.", dayTime(list[0]));
  };
  update.page = true;
  time.listeners.add(update);
  time.changed();
  wm.setLayer(layerId).then(update);
  box.querySelector("#chain")?.addEventListener("click", (e) => {
    e.stopPropagation();
    stop(page);
    time.setLinked(!time.linked);
  });
  box.querySelector("#slider")?.addEventListener("input", (e) => {
    stop(page);
    time.setMap(Math.round(x(list[Number(e.target.value)])));
  });
  // With repeat on it goes round 3 times, as the full-screen maps do, then stops on the hour it started from.
  box.querySelector("#play")?.addEventListener("click", () => {
    if (page.playing) return stop(page);
    let i = current() ?? 0;
    if (time.mapOutOfRange || i >= list.length - 1) i = 0;
    const from = i;
    let rounds = 0;
    box.querySelector("#play").innerHTML = icon("pause");
    time.setMap(Math.round(x(list[i])));
    page.playing = setInterval(() => {
      if (i < list.length - 1) i++;
      else if (store.mapLoop && rounds < 2) {
        rounds++;
        i = 0;
      } else {
        stop(page);
        if (store.mapLoop) time.setMap(Math.round(x(list[from])));
        return;
      }
      time.setMap(Math.round(x(list[i])));
    }, 700);
  });
  box.querySelector("#loop")?.addEventListener("click", (e) => {
    store.mapLoop = !store.mapLoop;
    e.currentTarget.classList.toggle("on", store.mapLoop);
  });
}

function stop(page) {
  clearInterval(page.playing);
  page.playing = null;
  const play = page.root.querySelector("#play");
  if (play) play.innerHTML = icon("play");
}

/** The map full screen, any layer, with a slim copy of the chart as its time bar while it follows the page. */
async function openFull(page, layerId, detail, hidden) {
  stop(page);
  const { data, time, club } = page;
  const start = new Date(data.now.time).getTime();
  const x = (date) => (date - start) / 3600000;
  const panel = document.createElement("div");
  panel.className = "wm-full";
  document.body.append(panel);
  document.body.classList.add("locked");
  let layer = LAYERS[layerId];
  let list = [];
  let index = 0;
  let playing = null;
  let own = new Date(start + time.shownMapHour * 3600000);
  const follows = () => layer.links !== "none" && layer.id === layerId;
  panel.innerHTML = `<header class="nav"><label class="jump">${icon("layers")}<select id="wm-layer" aria-label="${h(t("Choose what the map shows"))}">${layerOptions(layerId)}</select>${icon("chevron-down")}</label>
      <strong class="nav-title" id="wm-title"></strong><button class="link strong" id="wm-done">${h(t("Done"))}</button></header>
    <div class="wm" id="wm-full-map"></div>
    <section class="wm-panel" id="wm-panel"></section>`;
  let wm = null;
  wm = await weatherMap(panel.querySelector("#wm-full-map"), club.launchPoint, layerId, { onArea: () => wm && render() });
  const close = () => {
    clearInterval(playing);
    wm.remove();
    panel.remove();
    document.body.classList.remove("locked");
    page.map?.map.invalidateSize();
  };
  panel.querySelector("#wm-done").addEventListener("click", close);
  panel.addEventListener("keydown", (e) => e.key === "Escape" && close());
  const go = (i) => {
    index = i;
    own = list[i];
    if (follows()) time.setMap(Math.round(x(list[i])));
    render();
  };
  function render() {
    if (!panel.isConnected) return;
    panel.querySelector("#wm-title").textContent = t(layer.title);
    const at = list[index];
    if (at) wm.show(at);
    const value = wm.valueAtClub();
    const problem = wm.problem();
    const p = panel.querySelector("#wm-panel");
    const keepChart = p.querySelector("#wm-chart");
    p.innerHTML = `${follows() && detail.lines.length ? `<div id="wm-chart-slot"></div>` : ""}
      <p class="wm-line"><strong>${at ? h(frameLabel(layer, at)) : ""}</strong>${value ? `<span class="sub">${icon("map-pin")} ${h(value)}</span>` : ""}</p>
      ${problem ? `<p class="small orange">${h(problem)}</p>` : ""}
      ${colourBar(layer)}
      ${layer.note ? `<p class="small sub">${h(t(layer.note))}</p>` : ""}
      ${list.length > 1 ? `<div class="map-controls"><button class="tool" id="wm-play" aria-label="${h(playing ? t("Pause") : t("Play"))}">${icon(playing ? "pause" : "play")}</button>
        <input type="range" id="wm-slider" min="0" max="${list.length - 1}" step="1" value="${index}" aria-label="${h(t("Time"))}">
        <button class="tool ${store.mapLoop ? "on" : ""}" id="wm-loop" aria-label="${h(t("Play 3 times"))}">${icon("repeat")}</button></div>` : ""}
      <p class="small sub">${h(t(layer.credit))}</p>`;
    const slot = p.querySelector("#wm-chart-slot");
    if (slot) {
      if (keepChart) slot.replaceWith(keepChart);
      else {
        const box = document.createElement("div");
        box.id = "wm-chart";
        slot.replaceWith(box);
        mountChart(box, detail, data, time, { hidden, compact: true });
      }
    }
    p.querySelector("#wm-slider")?.addEventListener("input", (e) => {
      clearInterval(playing);
      playing = null;
      go(Number(e.target.value));
    });
    p.querySelector("#wm-play")?.addEventListener("click", () => {
      if (playing) {
        clearInterval(playing);
        playing = null;
        return render();
      }
      if (index >= list.length - 1) index = 0;
      const from = index;
      let rounds = 0;
      playing = setInterval(() => {
        if (index < list.length - 1) go(index + 1);
        else if (store.mapLoop && rounds < 2) {
          rounds++;
          go(0);
        } else {
          clearInterval(playing);
          playing = null;
          go(store.mapLoop ? from : index);
        }
      }, 700);
      render();
    });
    p.querySelector("#wm-loop")?.addEventListener("click", () => {
      store.mapLoop = !store.mapLoop;
      render();
    });
  }
  async function load(id) {
    clearInterval(playing);
    playing = null;
    layer = LAYERS[id];
    let idx = null;
    try {
      if (layer.model) idx = await loadIndex();
    } catch {
      // wm.problem() says so.
    }
    list = frames(layer, idx);
    const at = follows() ? new Date(start + time.shownMapHour * 3600000) : own;
    index = layer.links === "none" ? list.length - 1 : frameIndex(layer, list, at) ?? 0;
    render();
    await wm.setLayer(id);
    render();
  }
  panel.querySelector("#wm-layer").addEventListener("change", (e) => {
    panel.querySelector("#wm-chart")?.remove();
    load(e.target.value);
  });
  const follow = () => {
    if (!panel.isConnected || !follows() || playing) return;
    const i = frameIndex(layer, list, new Date(start + time.shownMapHour * 3600000));
    if (i != null && i !== index) {
      index = i;
      render();
    }
  };
  follow.page = true;
  time.listeners.add(follow);
  load(layerId);
}


/** Where the water temperature is measured, with the distance from the launch point and the station's page (WaterStationMap). */
function stationCard(condition, data) {
  const station = data.water?.station;
  if (condition !== "waterTemperature" || station?.lat == null || station?.lon == null) return "";
  const name = station.name ?? t("Lake station");
  return `<section class="station">
    <h3 class="section">${icon("map-pin")} ${h(t("Where it is measured"))}</h3>
    <div class="map" id="station-map" role="img" aria-label="${h(name)}"></div>
    <p class="small sub station-line"><span>${h(station.distanceM != null ? t("%@, %@ from the launch point", name, distance(station.distanceM)) : name)}</span>
      ${/^https:\/\//.test(station.url ?? "") ? `<a class="link" href="${h(station.url)}" target="_blank" rel="noopener noreferrer">${h(t("Station page"))}</a>` : ""}</p>
  </section>`;
}

async function showStationMap(box, station) {
  if (!box) return;
  const L = await loadLeaflet().catch(() => null);
  if (!L || !box.isConnected) return;
  const map = L.map(box, { scrollWheelZoom: false, attributionControl: true }).setView([station.lat, station.lon], 14);
  // OpenStreetMap asks for the site in the Referer; the page itself sends none.
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19, referrerPolicy: "strict-origin", attribution: '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>',
  }).addTo(map);
  L.marker([station.lat, station.lon], {
    icon: L.divIcon({ className: "pin station-pin", html: icon("thermometer"), iconSize: [30, 30], iconAnchor: [15, 15] }),
    keyboard: false,
  }).addTo(map);
}
