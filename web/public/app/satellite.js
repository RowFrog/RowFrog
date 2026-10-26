// The Sentinel-2 pictures of a lake (SatellitePicture.swift): the card on a
// club page with the choice of picture, the layers drawn over it and their
// legend, and the picture full screen with zoom and pan.

import { t, num } from "./i18n.js";
import { icon } from "./icons.js";
import { API, key } from "./logic.js";
import { store, getJSON, h, dayLabel, windNumber, openSheet, savingData } from "./shared.js";
import { tip } from "./tour.js";
import { hourIndex, gridEdges } from "./lake.js";
import { viewForMap, rasterCanvas, layerLegend, mapBoatNote } from "./lakeview.js";

/** What can be drawn over the picture: shore, clubs and routes, then as on the lake view; ice last. */
const LAYERS = [
  { id: "shore", title: key("Shore"), icon: "signature" },
  { id: "clubs", title: key("Clubs"), icon: "map-pin" },
  { id: "routes", title: key("Routes"), icon: "route" },
  { id: "light", title: key("Rowing light"), icon: "circle-dot", water: true },
  { id: "waves", title: key("Waves"), icon: "waves", water: true },
  { id: "wind", title: key("Wind"), icon: "wind" },
  { id: "ice", title: key("Ice map"), icon: "snowflake" },
];

const KINDS = [["latest", key("Latest")], ["mostlyClear", key("Mostly clear")], ["clearest", key("Clearest")]];

/** Waves and rowing light both colour the water, so only one is on at a time. */
export function toggleLayer(on, id) {
  if (on.includes(id)) return on.filter((x) => x !== id);
  const water = LAYERS.find((l) => l.id === id)?.water;
  return [...on.filter((x) => !(water && LAYERS.find((l) => l.id === x)?.water)), id];
}

/** Everything drawn over a lake's picture redraws when a layer is switched. */
const redraws = new Set();

function switchLayer(id) {
  store.satLayers = toggleLayer(store.satLayers, id);
  for (const f of redraws) f();
}

/** The lake's pictures and its lake view (for the layers), loaded once per page. */
async function loadLake(lakeId) {
  const meta = await getJSON(`lakes/${encodeURIComponent(lakeId)}/satellite`);
  const view = await viewForMap(lakeId).catch(() => null);
  return { lakeId, meta, view, kinds: KINDS.filter(([k]) => meta[k]?.image) };
}

/** The layers with something to show on this lake. */
function available(lake) {
  const { view, meta } = lake;
  return LAYERS.filter(({ id }) => {
    if (id === "shore") return view != null;
    if (id === "clubs") return view?.clubs?.length > 0;
    if (id === "routes") return store.routes.some((r) => r.lakeId === lake.lakeId && r.points.length > 1);
    if (id === "ice") return meta.ice?.image != null && meta.ice.bbox?.length === 4;
    return view?.hours?.length > 0;
  });
}

const fileUrl = (lake, file) => `${API}/lakes/${encodeURIComponent(lake.lakeId)}/${encodeURIComponent(file)}`;

function caption(lake, shot) {
  const { meta } = lake;
  const cloud = (shot.lakeCloud ?? 0) * 100;
  const ice = store.satLayers.includes("ice") && available(lake).some((l) => l.id === "ice");
  return `<p class="sub small">${h(cloud < 1 ? t("Sentinel-2 · %@ · no cloud over the lake", dayLabel(shot.date)) : t("Sentinel-2 · %@ · %@ %% of the lake under cloud", dayLabel(shot.date), num(cloud)))}</p>
    ${ice ? `<p class="sub small">${h(t("Satellite ice map, %@", dayLabel(meta.ice.date)))}</p>` : ""}
    <p class="sub small">${h(meta.attribution)}${ice && meta.ice.attribution ? ` · ${h(meta.ice.attribution)}` : ""}</p>`;
}

function chips(lake) {
  const on = store.satLayers;
  return `<div class="chips"><button class="chip" data-sat-legend aria-label="${h(t("Legend"))}">${icon("list")}</button>
    ${available(lake).map((l) => `<button class="chip ${on.includes(l.id) ? "on" : ""}" data-layer="${l.id}" aria-pressed="${on.includes(l.id)}">${icon(l.icon)} ${h(t(l.title))}</button>`).join("")}</div>`;
}

function kindPicker(lake, kind) {
  if (lake.kinds.length < 2) return "";
  return `<div class="segmented">${lake.kinds.map(([k, label]) => `<button data-kind="${k}" class="${k === kind ? "on" : ""}">${h(t(label))}</button>`).join("")}</div>`;
}

function wireControls(el, lake, setKind) {
  el.querySelectorAll("[data-kind]").forEach((b) => b.addEventListener("click", () => setKind(b.dataset.kind)));
  el.querySelectorAll("[data-layer]").forEach((b) => b.addEventListener("click", () => switchLayer(b.dataset.layer)));
  el.querySelector("[data-sat-legend]")?.addEventListener("click", () => openSheet(t("Legend"), legend(lake)));
}

/** The picture with an empty layer for the overlay, which is drawn once its size is known. */
const pictureHtml = (lake, shot) => `<img src="${fileUrl(lake, shot.image)}" alt="${h(t("Satellite picture of the lake"))}" draggable="false"><div class="sat-over"></div>`;

// ---- The card --------------------------------------------------------------------------

/**
 * "Satellite picture" on a club page: the latest picture, the mostly clear
 * and clearest ones to pick, the layers, and a tap for full screen. The
 * card stays hidden when the lake has no picture.
 */
export async function satelliteCard(box, lakeId, clubId, changed) {
  let lake;
  try {
    lake = await loadLake(lakeId);
  } catch {
    return;
  }
  if (!lake.kinds.length || !box.isConnected) return;
  const { meta } = lake;
  let kind = lake.kinds[0][0];
  const show = () => {
    const shot = meta[kind];
    // Saving data: the picture loads only when tapped (SatellitePictureStore.mayDownload).
    if (savingData() && !tapped.has(lakeId)) {
      box.innerHTML = `<header class="card-title">${icon("globe")}<span>${h(t("Satellite picture"))}</span></header>
        <button class="picture tap-to-load" style="aspect-ratio:${meta.width}/${meta.height}">${icon("satellite")}<span>${h(t("Tap to load the picture"))}</span></button>
        <p class="sub small">${h(meta.attribution)}</p>`;
      box.querySelector(".tap-to-load").addEventListener("click", () => {
        tapped.add(lakeId);
        show();
      });
      changed?.();
      return;
    }
    box.innerHTML = `<header class="card-title">${icon("globe")}<span>${h(t("Satellite picture"))}</span></header>
      ${tip("satellite")}
      ${kindPicker(lake, kind)}
      <div class="picture" role="button" tabindex="0" aria-label="${h(t("Satellite picture"))}" data-ratio="${meta.width / meta.height}" style="aspect-ratio:${meta.width}/${meta.height}">${pictureHtml(lake, shot)}</div>
      ${caption(lake, shot)}
      ${chips(lake)}`;
    const picture = box.querySelector(".picture");
    const open = () => openSatelliteScreen(lake, clubId, kind, (k) => { kind = k; show(); });
    picture.addEventListener("click", open);
    picture.addEventListener("keydown", (e) => (e.key === "Enter" || e.key === " ") && (e.preventDefault(), open()));
    wireControls(box, lake, (k) => { kind = k; show(); });
    watchSize(picture, () => drawOver(picture, lake, shot, clubId));
    changed?.();
  };
  redraws.add(function redraw() {
    if (!box.isConnected) return redraws.delete(redraw);
    show();
  });
  box.hidden = false;
  show();
}

/** Lakes whose picture was tapped to load while saving data, for this visit. */
const tapped = new Set();

const sizeWatch = new WeakMap();

/** Draws again whenever the picture changes size (the page or window is resized, the device turns). */
function watchSize(el, draw) {
  sizeWatch.get(el)?.disconnect();
  let last = "";
  const watch = new ResizeObserver(() => {
    const size = `${el.clientWidth}x${el.clientHeight}`;
    if (size !== last && el.clientWidth) {
      last = size;
      draw();
    }
  });
  watch.observe(el);
  sizeWatch.set(el, watch);
}

// ---- What is drawn over the picture -------------------------------------------------------

let clipCount = 0;
let measure = null;

function textWidth(text) {
  measure ??= document.createElement("canvas").getContext("2d");
  measure.font = "600 11px -apple-system, system-ui, sans-serif";
  return measure.measureText(text).width;
}

function drawOver(el, lake, shot, clubId) {
  const layer = el.querySelector(".sat-over");
  if (!layer) return;
  layer.innerHTML = overlaySvg(lake, shot, clubId, el.clientWidth, el.clientHeight);
}

/**
 * Shore, clubs, routes, wind, the coloured water and the ice map in the
 * picture's own lon/lat box, sized in screen pixels (SatelliteOverlay).
 */
export function overlaySvg(lake, shot, clubId, w, hgt) {
  const { meta, view } = lake;
  const on = new Set(store.satLayers.filter((id) => available(lake).some((l) => l.id === id)));
  const box = meta.bbox;
  if (!on.size || box?.length !== 4 || !w || !hgt) return "";
  const pt = (lon, lat) => [((lon - box[0]) / (box[2] - box[0])) * w, ((box[3] - lat) / (box[3] - box[1])) * hgt];
  const f = (v) => v.toFixed(1);
  const ringsPath = () => view.outline.filter((r) => r.length > 1).map((r) => `M${r.map(([lon, lat]) => pt(lon, lat).map(f).join(" ")).join("L")}Z`).join("");
  const parts = [];
  if (on.has("ice")) {
    const ice = meta.ice.bbox;
    const [x0, y0] = pt(ice[0], ice[3]);
    const [x1, y1] = pt(ice[2], ice[1]);
    parts.push(`<image href="${fileUrl(lake, meta.ice.image)}" x="${f(x0)}" y="${f(y0)}" width="${f(x1 - x0)}" height="${f(y1 - y0)}" preserveAspectRatio="none" style="image-rendering:pixelated"/>`);
  }
  const hour = view?.hours?.length ? view.hours[hourIndex(view)] : null;
  const fill = ["light", "waves"].find((x) => on.has(x));
  if (fill && hour) {
    // The lake view's squares for the hour now, clipped to the shore.
    const id = `sat-clip-${++clipCount}`;
    const g = gridEdges(view.grid);
    const [x0, y0] = pt(g.west, g.north);
    const [x1, y1] = pt(g.east, g.south);
    parts.push(`<clipPath id="${id}"><path d="${ringsPath()}" clip-rule="evenodd"/></clipPath>
      <image href="${rasterCanvas(view, hour, fill).toDataURL()}" x="${f(x0)}" y="${f(y0)}" width="${f(x1 - x0)}" height="${f(y1 - y0)}" preserveAspectRatio="none" opacity=".55" clip-path="url(#${id})"/>`);
  }
  // Wind under the lines and marks, so shore, routes and clubs stay on top.
  if (on.has("wind") && hour) {
    const arrows = [];
    const labels = [];
    view.points.forEach((p, i) => {
      const wnd = hour.wind[i];
      if (wnd?.fromDeg == null || wnd.speedMs == null) return;
      const [cx, cy] = pt(p.lon, p.lat);
      const toward = ((wnd.fromDeg + 180) * Math.PI) / 180;
      const length = 10 + Math.min(wnd.speedMs, 15) * 1.6;
      const dx = (Math.sin(toward) * length) / 2;
      const dy = (-Math.cos(toward) * length) / 2;
      const tip = [cx + dx, cy + dy];
      let d = `M${f(cx - dx)} ${f(cy - dy)}L${f(tip[0])} ${f(tip[1])}`;
      for (const side of [-0.5, 0.5]) {
        const a = toward + Math.PI + side;
        d += `M${f(tip[0])} ${f(tip[1])}L${f(tip[0] + Math.sin(a) * 6)} ${f(tip[1] - Math.cos(a) * 6)}`;
      }
      arrows.push(d);
      labels.push(`<text x="${f(cx - dx)}" y="${f(cy - dy)}">${h(windNumber(wnd.speedMs))}</text>`);
    });
    const d = arrows.join("");
    parts.push(`<g fill="none" stroke-linecap="round"><path d="${d}" stroke="rgba(0,0,0,.6)" stroke-width="3.5"/><path d="${d}" stroke="#fff" stroke-width="2"/></g>
      <g class="sat-wind">${labels.join("")}</g>`);
  }
  if (on.has("shore")) {
    // Over mostly white cloud the shore is dark with a light edge, over a clear lake light with a dark edge.
    const cloudy = (shot.lakeCloud ?? 0) >= 0.5;
    const [edge, core] = cloudy ? ["rgba(255,255,255,.85)", "rgb(13,31,77)"] : ["rgba(0,0,0,.7)", "#fff"];
    const d = ringsPath();
    parts.push(`<g fill="none" stroke-linejoin="round"><path d="${d}" stroke="${edge}" stroke-width="3.5"/><path d="${d}" stroke="${core}" stroke-width="1.5"/></g>`);
  }
  if (on.has("routes")) {
    const d = store.routes.filter((r) => r.lakeId === lake.lakeId && r.points.length > 1)
      .map((r) => `M${r.points.map((p) => pt(p.lon, p.lat).map(f).join(" ")).join("L")}`).join("");
    parts.push(`<g fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="${d}" stroke="rgba(0,0,0,.6)" stroke-width="4"/><path d="${d}" stroke="#ffcc00" stroke-width="2.5"/></g>`);
  }
  if (on.has("clubs")) parts.push(clubMarks(view, pt, clubId, w, hgt));
  return `<svg viewBox="0 0 ${f(w)} ${f(hgt)}" width="${f(w)}" height="${f(hgt)}" aria-hidden="true">${parts.join("")}</svg>`;
}

/**
 * As on the lake view: a grey round mark per club, the page's club blue (with
 * a house for the home base). Names go right, left, above or below the mark,
 * wherever they touch no other; with no room the mark stays alone.
 */
function clubMarks(view, pt, clubId, w, hgt) {
  const marks = view.clubs.map((club) => ({ club, p: pt(club.launchPoint.lon, club.launchPoint.lat) }));
  const taken = marks.map(({ p }) => [p[0] - 9, p[1] - 9, 18, 18]);
  const meets = (a, b) => a[0] < b[0] + b[2] && b[0] < a[0] + a[2] && a[1] < b[1] + b[3] && b[1] < a[1] + a[3];
  const home = store.clubs[0]?.id;
  const out = [];
  marks.sort((a, b) => (a.club.id === clubId ? 0 : 1) - (b.club.id === clubId ? 0 : 1) || a.p[1] - b.p[1]);
  for (const { club, p } of marks) {
    const own = club.id === clubId;
    out.push(`<circle cx="${p[0].toFixed(1)}" cy="${p[1].toFixed(1)}" r="9" fill="${own ? "#007aff" : "#737373"}" stroke="#fff" stroke-width="1.5"/>`);
    if (own && club.id === home) out.push(`<svg x="${(p[0] - 6).toFixed(1)}" y="${(p[1] - 6).toFixed(1)}" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">${icon("house").replace(/^<svg[^>]*>|<\/svg>$/g, "")}</svg>`);
    const name = club.shortName ?? club.name ?? "";
    const lw = textWidth(name);
    const lh = 13;
    const spots = [
      [p[0] + 12, p[1] - lh / 2], [p[0] - 12 - lw, p[1] - lh / 2], [p[0] - lw / 2, p[1] - 11 - lh], [p[0] - lw / 2, p[1] + 11],
    ].map(([x, y]) => [x, y, lw, lh]);
    const spot = spots.find((r) => {
      // The pill must stay on the picture, not run off its edge.
      const inside = r[0] >= 5 && r[1] >= 2 && r[0] + r[2] <= w - 5 && r[1] + r[3] <= hgt - 2;
      return inside && !taken.some((x) => meets(x, [r[0] - 2, r[1] - 1, r[2] + 4, r[3] + 2]));
    });
    if (!spot) continue;
    taken.push(spot);
    out.push(`<rect x="${(spot[0] - 4).toFixed(1)}" y="${(spot[1] - 1).toFixed(1)}" width="${(lw + 8).toFixed(1)}" height="${lh + 2}" rx="6" fill="rgba(0,0,0,.55)"/>
      <text class="sat-name" x="${spot[0].toFixed(1)}" y="${(spot[1] + lh - 3).toFixed(1)}">${h(name)}</text>`);
  }
  return `<g>${out.join("")}</g>`;
}

// ---- The legend ---------------------------------------------------------------------------

function legend(lake) {
  const on = new Set(store.satLayers.filter((id) => available(lake).some((l) => l.id === id)));
  const row = (sym, text) => `<li>${sym}<span>${h(text)}</span></li>`;
  const swatch = (colour) => `<span class="swatch" style="background:${colour}"></span>`;
  const line = (colour) => `<span class="line-mark" style="background:${colour}"></span>`;
  const own = lake.view?.clubs?.some((c) => c.id === store.clubs[0]?.id) && store.clubs[0]?.id;
  let body = `<h3>${h(t("The picture"))}</h3><ul class="legend">
      ${row(icon("satellite"), t("A true-colour photo from the Sentinel-2 satellites, as a camera would see it from space."))}
      ${row(icon("cloud"), t("White and grey: clouds, haze, or snow and ice on the ground."))}
      ${row(`<span style="color:rgb(26,51,77)">${icon("droplet")}</span>`, t("Dark blue to black: open water."))}</ul>`;
  if (on.has("light")) body += `<h3>${h(t("Rowing light"))}</h3>${layerLegend("light")}${mapBoatNote()}`;
  if (on.has("waves")) body += `<h3>${h(t("Waves"))}</h3>${layerLegend("waves")}`;
  if (on.has("wind")) {
    body += `<h3>${h(t("Wind"))}</h3><ul class="legend">${row(icon("arrow-up"), t("Points where the wind blows to, at the forecast points for the current hour; longer arrows mean stronger wind. The number is the wind speed."))}</ul>`;
  }
  if (on.has("ice")) {
    body += `<h3>${h(t("Ice map"))}</h3><ul class="legend">
      ${row(swatch("#fff"), t("Snow-covered ice"))}${row(swatch("rgb(200,235,255)"), t("Clear ice"))}${row(swatch("rgba(0,90,200,.5)"), t("Open water"))}</ul>`;
  }
  if (on.has("shore") || on.has("routes") || on.has("clubs")) {
    body += `<h3>${h(t("Lines and marks"))}</h3><ul class="legend">
      ${on.has("shore") ? row(line("#fff"), t("Shore line: white on a clear picture, dark blue on a cloudy one")) : ""}
      ${on.has("routes") ? row(line("#ffcc00"), t("Your saved routes on this lake")) : ""}
      ${on.has("clubs") ? row(`<span class="club-mark own"></span>`, own ? t("Your home base, the club of this page") : t("The club of this page")) + row(`<span class="club-mark other"></span>`, t("Other clubs on the lake")) : ""}</ul>`;
  }
  return `${body}<p class="sub small">${h(t("Switch layers on and off with the buttons under the picture."))}</p>`;
}

// ---- Full screen ------------------------------------------------------------------------------

/**
 * The picture on its own, filling the window, with wheel or pinch to zoom,
 * drag to move, a double click or tap to zoom in or back, and the same
 * switches (SatellitePictureScreen).
 */
function openSatelliteScreen(lake, clubId, startKind, onKind) {
  document.querySelector(".sat-full")?.remove();
  const { meta } = lake;
  const ratio = meta.width / meta.height;
  let kind = startKind;
  const el = document.createElement("div");
  el.className = "sat-full";
  el.setAttribute("role", "dialog");
  el.setAttribute("aria-label", t("Satellite picture"));
  document.body.append(el);
  document.body.classList.add("locked");
  const zoom = { s: 1, x: 0, y: 0, fit: 0 };

  const close = () => {
    redraws.delete(render);
    window.removeEventListener("resize", layout);
    document.removeEventListener("keydown", keys);
    el.remove();
    document.body.classList.remove("locked");
    if (kind !== startKind) onKind(kind);
  };
  const keys = (e) => e.key === "Escape" && close();

  function render() {
    if (!el.isConnected) return redraws.delete(render);
    const shot = meta[kind];
    el.innerHTML = `<header class="nav value-nav"><span class="spacer"></span><strong class="nav-title">${h(t("Satellite picture"))}</strong><button class="link strong" id="sat-done">${h(t("Done"))}</button></header>
      ${kindPicker(lake, kind)}
      <div class="sat-stage"><div class="sat-zoom">${pictureHtml(lake, shot)}</div></div>
      <div class="sat-panel">${caption(lake, shot)}${chips(lake)}</div>`;
    el.querySelector("#sat-done").addEventListener("click", close);
    wireControls(el, lake, (k) => { kind = k; render(); });
    wireGestures(el.querySelector(".sat-stage"));
    layout(true);
  }

  /** The whole picture fits at first; `fresh` also sets where it opens. */
  function layout(fresh) {
    const stage = el.querySelector(".sat-stage");
    const content = el.querySelector(".sat-zoom");
    if (!stage || !content) return;
    const W = stage.clientWidth;
    const H = stage.clientHeight;
    const fit = Math.min(W, H * ratio);
    const changed = Math.abs(fit - zoom.fit) > 0.5;
    zoom.fit = fit;
    content.style.width = `${fit}px`;
    content.style.height = `${fit / ratio}px`;
    if (changed || fresh) content.querySelector(".sat-over").innerHTML = overlaySvg(lake, meta[kind], clubId, fit, fit / ratio);
    if (fresh === true) focus(W, H, fit, fit / ratio);
    apply();
  }

  /** Opens on the saved routes on this lake, all in view; without routes on the page's club, filling the width. */
  function focus(W, H, cw, ch) {
    const box = meta.bbox;
    const pt = (lon, lat) => [((lon - box[0]) / (box[2] - box[0])) * cw, ((box[3] - lat) / (box[3] - box[1])) * ch];
    const points = store.routes.filter((r) => r.lakeId === lake.lakeId).flatMap((r) => r.points).map((p) => pt(p.lon, p.lat));
    if (points.length && store.satLayers.includes("routes")) {
      const xs = points.map((p) => p[0]);
      const ys = points.map((p) => p[1]);
      const [x0, x1, y0, y1] = [Math.min(...xs) - 24, Math.max(...xs) + 24, Math.min(...ys) - 24, Math.max(...ys) + 24];
      zoom.s = clamp(Math.min(W / (x1 - x0), H / (y1 - y0)), 1, 6);
      zoom.x = W / 2 - ((x0 + x1) / 2) * zoom.s;
      zoom.y = H / 2 - ((y0 + y1) / 2) * zoom.s;
      return;
    }
    // In a wide window, filling its width would show only a sliver of the lake: the whole picture shows instead.
    if (W > H) {
      zoom.s = 1;
      return;
    }
    const club = lake.view?.clubs?.find((c) => c.id === clubId);
    const centre = club ? pt(club.launchPoint.lon, club.launchPoint.lat) : [cw / 2, ch / 2];
    zoom.s = clamp(W / cw, 1, 6);
    zoom.x = W / 2 - centre[0] * zoom.s;
    zoom.y = H / 2 - centre[1] * zoom.s;
  }

  /** Keeps the picture in the middle while it is smaller than the window, and on screen when bigger. */
  function apply() {
    const stage = el.querySelector(".sat-stage");
    const content = el.querySelector(".sat-zoom");
    if (!stage || !content) return;
    const W = stage.clientWidth;
    const H = stage.clientHeight;
    const w = zoom.fit * zoom.s;
    const hh = (zoom.fit / ratio) * zoom.s;
    zoom.x = w <= W ? (W - w) / 2 : clamp(zoom.x, W - w, 0);
    zoom.y = hh <= H ? (H - hh) / 2 : clamp(zoom.y, H - hh, 0);
    content.style.transform = `translate(${zoom.x}px, ${zoom.y}px) scale(${zoom.s})`;
  }

  /** Zooms by a factor around a point of the stage. */
  function zoomAt(factor, px, py) {
    const s = clamp(zoom.s * factor, 1, 6);
    zoom.x = px - ((px - zoom.x) * s) / zoom.s;
    zoom.y = py - ((py - zoom.y) * s) / zoom.s;
    zoom.s = s;
    apply();
  }

  function wireGestures(stage) {
    const pointers = new Map();
    let pinch = null;
    let lastTap = null;
    let moved = false;
    const local = (e) => {
      const r = stage.getBoundingClientRect();
      return [e.clientX - r.left, e.clientY - r.top];
    };
    stage.addEventListener("wheel", (e) => {
      e.preventDefault();
      zoomAt(Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.002)), ...local(e));
    }, { passive: false });
    stage.addEventListener("pointerdown", (e) => {
      stage.setPointerCapture(e.pointerId);
      pointers.set(e.pointerId, local(e));
      moved = false;
      if (pointers.size === 2) {
        const [a, b] = [...pointers.values()];
        pinch = { d: Math.hypot(a[0] - b[0], a[1] - b[1]) };
      }
    });
    stage.addEventListener("pointermove", (e) => {
      const before = pointers.get(e.pointerId);
      if (!before) return;
      const now = local(e);
      pointers.set(e.pointerId, now);
      if (pointers.size === 2 && pinch) {
        const [a, b] = [...pointers.values()];
        const d = Math.hypot(a[0] - b[0], a[1] - b[1]);
        if (pinch.d > 0) zoomAt(d / pinch.d, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2);
        pinch.d = d;
        moved = true;
        return;
      }
      if (Math.hypot(now[0] - before[0], now[1] - before[1]) > 0) {
        zoom.x += now[0] - before[0];
        zoom.y += now[1] - before[1];
        if (Math.abs(now[0] - before[0]) + Math.abs(now[1] - before[1]) > 1) moved = true;
        apply();
      }
    });
    const up = (e) => {
      const p = pointers.get(e.pointerId);
      pointers.delete(e.pointerId);
      if (pointers.size < 2) pinch = null;
      if (!p || moved || e.type === "pointercancel") return;
      // A double tap or click: in when the whole picture shows, otherwise back to it.
      const now = Date.now();
      if (lastTap && now - lastTap.at < 350 && Math.hypot(p[0] - lastTap.p[0], p[1] - lastTap.p[1]) < 30) {
        lastTap = null;
        if (zoom.s > 1.05) {
          zoom.s = 1;
          apply();
        } else zoomAt(2.5, ...p);
      } else lastTap = { at: now, p };
    };
    stage.addEventListener("pointerup", up);
    stage.addEventListener("pointercancel", up);
  }

  redraws.add(render);
  window.addEventListener("resize", layout);
  document.addEventListener("keydown", keys);
  render();
}

const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);
