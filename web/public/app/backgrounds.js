// Background pictures (Backgrounds.swift, BackgroundSettingsView): a picture
// for all pages, for one kind of page or for one club, clear or blurred, and
// how the cards look over it. The samples are the app's own pictures; the
// visitor's own pictures stay in this browser (IndexedDB).

import { t } from "./i18n.js";
import { icon } from "./icons.js";
import { API, key } from "./logic.js";
import { store, h, load, save, getJSON, setTitle, testing, footerLinks, openSheet, savingData, dot, lightTitle, degrees, wind, waves, conditionIcon } from "./shared.js";
import { tip, wireTips } from "./tour.js";

/** The pictures that come with the app, in its order (BackgroundLibrary.samples). */
export const SAMPLES = [
  ["lake-waves", key("Lake waves")], ["soft-waves", key("Soft waves")], ["sunrise-sculler", key("Sunrise sculler")],
  ["alpine-lake", key("Alpine lake")], ["cloud-shell", key("Frog in the cloud shell")], ["cloud-sculler", key("Cloud sculler")],
  ["sunny-day", key("Sunny day")], ["morning-mist", key("Morning mist")], ["rain-on-the-lake", key("Rain on the lake")],
  ["thunderstorm", key("Thunderstorm")], ["winter-ice", key("Winter ice")], ["night-lake", key("Night on the lake")],
];

/** The kinds of page a picture can be set for (PageKind). */
const PAGES = [["clubPages", key("Club pages"), "house"], ["list", key("Location list"), "list"], ["settings", key("Settings"), "settings"]];

export const TILE_STYLES = [["frosted", key("Picture blurred")], ["solid", key("No picture")]];

const object = (value) => (value && typeof value === "object" && !Array.isArray(value) ? value : {});

// A choice is stored as the app writes it: "none", "satellite", "sample:<id>" or "custom:<name>".
const valid = (choice) => typeof choice === "string" && (choice === "none" || choice === "satellite" || /^(sample|custom):./.test(choice));

export const backgrounds = {
  get all() { const c = load("rf.background", "none"); return valid(c) ? c : "none"; },
  set all(c) { save("rf.background", c); },
  get pages() { return object(load("rf.pageBackgrounds", {})); },
  set pages(v) { save("rf.pageBackgrounds", v); },
  get clubs() { return object(load("rf.clubBackgrounds", {})); },
  set clubs(v) { save("rf.clubBackgrounds", v); },
  get blur() { return load("rf.blurBackground", false) === true; },
  set blur(on) { save("rf.blurBackground", on); },
  get tiles() { const s = load("rf.tileStyle", "frosted"); return TILE_STYLES.some(([k]) => k === s) ? s : "frosted"; },
  set tiles(s) { save("rf.tileStyle", s); },
  /** The visitor's own pictures, newest first. */
  get mine() { const l = load("rf.userPictures", []); return Array.isArray(l) ? l : []; },
  set mine(l) { save("rf.userPictures", l); },
};

/** A club's own picture, else its kind of page's, else the one for all pages (AppSettings.background(for:clubID:)). */
export function backgroundFor(page, clubId = null, b = backgrounds) {
  // The settings keep their plain background, unless the developer options are on (#355).
  if (page === "settings" && !store.developerOptions) return "none";
  const own = clubId ? b.clubs[clubId] : null;
  if (page === "clubPages" && valid(own)) return own;
  const forPage = b.pages[page];
  return valid(forPage) ? forPage : b.all;
}

export function choiceTitle(choice) {
  if (choice === "none") return t("No picture");
  if (choice === "satellite") return t("Satellite picture of the lake");
  if (choice.startsWith("custom:")) return t("Your picture");
  const sample = SAMPLES.find(([id]) => `sample:${id}` === choice);
  return sample ? t(sample[1]) : choice;
}

// ---- The visitor's own pictures --------------------------------------------------------

function database() {
  return new Promise((resolve, reject) => {
    const open = indexedDB.open("rowfrog", 1);
    open.onupgradeneeded = () => open.result.createObjectStore("pictures");
    open.onsuccess = () => resolve(open.result);
    open.onerror = () => reject(open.error);
  });
}

async function pictures(mode, run) {
  const db = await database();
  return new Promise((resolve, reject) => {
    const request = run(db.transaction("pictures", mode).objectStore("pictures"));
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

const objectUrls = new Map();

async function ownPictureUrl(name) {
  if (objectUrls.has(name)) return objectUrls.get(name);
  const blob = await pictures("readonly", (s) => s.get(name)).catch(() => null);
  if (!blob) return null;
  const url = URL.createObjectURL(blob);
  objectUrls.set(name, url);
  return url;
}

/** Saves a picture scaled to at most 2600 px, as the app does, and returns its name. */
async function addOwnPicture(file) {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, 2600 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.85));
  const name = `user-${crypto.randomUUID?.() ?? Date.now().toString(36)}.jpg`;
  await pictures("readwrite", (s) => s.put(blob, name));
  backgrounds.mine = [name, ...backgrounds.mine];
  return name;
}

/** Deletes one of the visitor's pictures; pages that used it go back to no picture (forgetUserPicture). */
async function forgetOwnPicture(name) {
  const gone = `custom:${name}`;
  if (backgrounds.all === gone) backgrounds.all = "none";
  backgrounds.pages = Object.fromEntries(Object.entries(backgrounds.pages).filter(([, c]) => c !== gone));
  backgrounds.clubs = Object.fromEntries(Object.entries(backgrounds.clubs).filter(([, c]) => c !== gone));
  backgrounds.mine = backgrounds.mine.filter((n) => n !== name);
  await pictures("readwrite", (s) => s.delete(name)).catch(() => {});
  URL.revokeObjectURL(objectUrls.get(name));
  objectUrls.delete(name);
}

/** Deletes all the visitor's own pictures, for the factory reset (BackgroundLibrary.deleteUserPicture). */
export async function forgetOwnPictures() {
  await pictures("readwrite", (s) => s.clear()).catch(() => {});
  for (const url of objectUrls.values()) URL.revokeObjectURL(url);
  objectUrls.clear();
}

// ---- Drawing the picture behind the page -------------------------------------------------

const sampleUrl = (id) => `backgrounds/bg-${id}.jpg`;

/**
 * The clearest satellite picture of the club's lake (the home base's without a club), with where
 * the club's launch point lies in it, as shares of its width and height, so the page can show the
 * club (BackgroundLibrary.focus(of:)).
 */
async function satellitePicture(clubId) {
  if (savingData()) return null;
  const club = store.clubs.find((c) => c.id === clubId) ?? store.clubs[0];
  if (!club?.lakeId) return null;
  // A river club's picture is the one around the club (satelliteCard).
  for (const place of [club.lakeId, `club-${club.id}`]) {
    const meta = await getJSON(`lakes/${encodeURIComponent(place)}/satellite`).catch(() => null);
    const shot = meta?.clearest ?? meta?.mostlyClear ?? meta?.latest;
    if (!shot?.image) continue;
    const box = meta.bbox;
    const at = club.launchPoint;
    const focus = at && box?.length === 4 && box[2] > box[0] && box[3] > box[1] && meta.width > 0 && meta.height > 0
      ? { x: clamp01((at.lon - box[0]) / (box[2] - box[0])), y: clamp01((box[3] - at.lat) / (box[3] - box[1])), width: meta.width, height: meta.height }
      : null;
    return { url: `${API}/lakes/${encodeURIComponent(place)}/${encodeURIComponent(shot.image)}`, focus };
  }
  return null;
}

const clamp01 = (v) => Math.min(Math.max(v, 0), 1);

/**
 * Where a picture lies when it fills an area: scaled to cover it, with its focus point as near the
 * area's middle as the picture's edges allow (PicturePlace.rect). Returns the offset and size in pixels.
 */
export function picturePlace(picture, area, focus) {
  if (!(picture.width > 0 && picture.height > 0)) return { x: 0, y: 0, width: area.width, height: area.height };
  const scale = Math.max(area.width / picture.width, area.height / picture.height);
  const width = picture.width * scale;
  const height = picture.height * scale;
  const f = focus ?? { x: 0.5, y: 0.5 };
  return {
    x: Math.min(0, Math.max(area.width - width, area.width / 2 - f.x * width)),
    y: Math.min(0, Math.max(area.height - height, area.height / 2 - f.y * height)),
    width, height,
  };
}

async function picture(choice, clubId) {
  if (choice === "satellite") return satellitePicture(clubId);
  if (choice.startsWith("sample:")) return { url: sampleUrl(choice.slice(7)) };
  if (choice.startsWith("custom:")) {
    const url = await ownPictureUrl(choice.slice(7));
    return url ? { url } : null;
  }
  return null;
}

const pictureUrl = async (choice, clubId) => (await picture(choice, clubId))?.url ?? null;

/** The picture chosen for all pages, for the preview in Settings › Appearance; null without one. */
export function backgroundPreview() {
  return backgrounds.all && backgrounds.all !== "none" ? pictureUrl(backgrounds.all, null) : Promise.resolve(null);
}

let shown = 0;
/** The shown satellite picture's size and the club's place in it; null for a picture shown centred. */
let focus = null;

/** A satellite picture shows the club: placed so its launch point is as near the window's middle as the picture allows. */
function placePicture() {
  const layer = document.querySelector("#page-picture");
  if (!layer) return;
  if (!focus) {
    layer.style.backgroundSize = layer.style.backgroundPosition = "";
    return;
  }
  const place = picturePlace(focus, { width: layer.clientWidth || innerWidth, height: layer.clientHeight || innerHeight }, focus);
  layer.style.backgroundSize = `${place.width}px ${place.height}px`;
  layer.style.backgroundPosition = `${place.x}px ${place.y}px`;
}
if (typeof window !== "undefined") window.addEventListener("resize", placePicture);

/** Puts the page's picture behind it, or none (page null: pages without pictures). */
export async function showBackground(page, clubId = null) {
  const ticket = ++shown;
  const choice = page ? backgroundFor(page, clubId) : "none";
  const shownPicture = choice === "none" ? null : await picture(choice, clubId).catch(() => null);
  const url = shownPicture?.url;
  if (ticket !== shown) return;
  let layer = document.querySelector("#page-picture");
  if (!url) {
    layer?.remove();
    document.body.classList.remove("has-picture");
    delete document.body.dataset.tiles;
    return;
  }
  if (!layer) {
    layer = document.createElement("div");
    layer.id = "page-picture";
    layer.setAttribute("aria-hidden", "true");
    document.body.prepend(layer);
  }
  layer.style.backgroundImage = `url("${url}")`;
  focus = shownPicture.focus ?? null;
  placePicture();
  layer.classList.toggle("blurred", backgrounds.blur);
  document.body.classList.add("has-picture");
  document.body.dataset.tiles = backgrounds.tiles;
}

// ---- Settings › Background pictures ------------------------------------------------------

const settingsNav = () => `<header class="nav"><a class="link" href="#/settings/appearance">${icon("chevron-left")} ${h(t("Appearance"))}</a><span class="spacer"></span></header>`;

/** "All pages: Lake waves · 2 with their own", for the settings row. */
export function backgroundSummary() {
  const own = Object.keys(backgrounds.pages).length + Object.keys(backgrounds.clubs).length;
  const all = t("All pages: %@", choiceTitle(backgrounds.all));
  return own ? `${all} · ${t("%@ with their own", String(own))}` : all;
}

export function renderBackgrounds(root) {
  setTitle(t("Background pictures"));
  const b = backgrounds;
  const row = (target, title, iconName, choice, inherited) => `<button class="row-setting" data-target="${h(target)}">
      <span>${icon(iconName)} ${h(title)}</span><span class="sub">${h(choice ? choiceTitle(choice) : inherited)} ${icon("chevron-right")}</span></button>`;
  root.innerHTML = `${settingsNav()}${testing()}
    <main class="page">
      <h1 class="large">${h(t("Background pictures"))}</h1>
      ${tip("backgrounds")}
      ${previewHtml()}
      <p class="footer">${h(t("Preview of the club pages with the picture for all pages."))}</p>
      <h3 class="section">${icon("layers")} ${h(t("All pages"))}</h3>
      <section class="card group">${row("all", t("All pages"), "layers", b.all)}</section>
      <h3 class="section">${icon("copy")} ${h(t("Single pages"))}</h3>
      <section class="card group">${PAGES.filter(([id]) => id !== "settings" || store.developerOptions).map(([id, title, ic]) => row(`page:${id}`, t(title), ic, b.pages[id], t("Same as all pages"))).join("")}</section>
      <p class="footer">${h(t("A picture set here replaces the one for all pages on that page."))}</p>
      ${store.clubs.length ? `<h3 class="section">${icon("rower")} ${h(t("Single clubs"))}</h3>
      <section class="card group">${store.clubs.map((c) => row(`club:${c.id}`, c.shortName || c.name, "house", b.clubs[c.id], t("Same as club pages"))).join("")}</section>
      <p class="footer">${h(t("A club's own picture shows only on that club's page."))}</p>` : ""}
      <h3 class="section">${icon("sliders-horizontal")} ${h(t("Look"))}</h3>
      <section class="card group">
        <label class="row-setting"><span>${h(t("Blur the picture"))}</span><input type="checkbox" class="switch" role="switch" id="blur" ${b.blur ? "checked" : ""}></label>
        <label class="row-setting"><span>${h(t("In the tiles"))}</span>
          <select id="tiles">${TILE_STYLES.map(([k, title]) => `<option value="${k}" ${k === b.tiles ? "selected" : ""}>${h(t(title))}</option>`).join("")}</select></label>
      </section>
      <p class="footer">${h(t("Solid tiles keep the full rowing-light shading and use less battery while scrolling."))}</p>
      <section class="card group"><button class="row-setting red" id="remove-all">${icon("trash-2")} ${h(t("Remove all background pictures"))}</button></section>
      <p class="footer">${h(t("No picture on any page. Your own pictures stay available to pick again."))}</p>
      ${footerLinks()}
    </main>`;
  wireTips(root.querySelector("main"));
  const again = () => {
    renderBackgrounds(root);
    showBackground("settings");
  };
  root.querySelectorAll("[data-target]").forEach((el) => el.addEventListener("click", () => openPicker(el.dataset.target, again)));
  root.querySelector("#blur").addEventListener("change", (e) => {
    b.blur = e.target.checked;
    again();
  });
  fillPreview(root.querySelector("#bg-preview"));
  root.querySelector("#tiles").addEventListener("change", (e) => {
    b.tiles = e.target.value;
    again();
  });
  root.querySelector("#remove-all").addEventListener("click", () => {
    if (!confirm(t("Remove all background pictures?"))) return;
    b.all = "none";
    b.pages = {};
    b.clubs = {};
    again();
  });
}

/** A club page in small with the picture for the club pages, as it will look (BackgroundPreview in the app). */
function previewHtml() {
  const tile = (light) => `<span class="bg-sample tinted" style="--tint: var(--${light})">${dot(light, 12)}<strong>${h(lightTitle(light))}</strong><span class="deg">${h(degrees(14))}</span></span>`;
  return `<div class="bg-preview" id="bg-preview" role="img" aria-label="${h(t("Preview"))}"><span class="bg-layer"></span>
      <span class="bg-name">MRC 1880</span>
      <span class="bg-tiles">${tile("green")}${tile("amber")}</span>
      <span class="bg-sample now"><small>${icon("gauge")} ${h(t("Current conditions").toUpperCase())}</small>
        <span class="vals"><span>${conditionIcon("wind")} ${h(wind(4))}</span><span>${conditionIcon("waves")} ${h(waves(0.12))}</span></span></span></div>`;
}

async function fillPreview(box) {
  if (!box) return;
  const b = backgrounds;
  const url = await pictureUrl(b.pages.clubPages ?? b.all, null).catch(() => null);
  if (!box.isConnected) return;
  box.classList.toggle("with-picture", !!url);
  box.classList.toggle("blurred", !!url && b.blur);
  box.dataset.tiles = url ? b.tiles : "solid";
  if (url) box.querySelector(".bg-layer").style.backgroundImage = `url("${url.replace(/"/g, "%22")}")`;
}

/** The choices for one target: inherited, none, satellite, the visitor's own, then the samples (BackgroundPickerView). */
function openPicker(target, done) {
  const b = backgrounds;
  const [kind, id] = target.includes(":") ? [target.slice(0, target.indexOf(":")), target.slice(target.indexOf(":") + 1)] : [target, null];
  const current = kind === "all" ? b.all : kind === "page" ? b.pages[id] ?? null : b.clubs[id] ?? null;
  const inherited = kind === "page" ? t("Same as all pages") : kind === "club" ? t("Same as club pages") : null;
  const title = kind === "all" ? t("All pages") : kind === "page" ? t(PAGES.find(([p]) => p === id)?.[1] ?? "") : store.clubs.find((c) => c.id === id)?.shortName ?? t("Club");
  const pick = (choice) => {
    if (kind === "all") b.all = choice ?? "none";
    else {
      const map = kind === "page" ? b.pages : b.clubs;
      if (choice == null) delete map[id];
      else map[id] = choice;
      if (kind === "page") b.pages = map;
      else b.clubs = map;
    }
  };
  const option = (choice, label, thumb) => `<button class="bg-option ${choice === current ? "on" : ""}" data-choice="${h(choice ?? "")}">
      <span class="thumb" ${thumb ? `style="background-image:url('${h(thumb)}')"` : ""}>${thumb ? "" : icon(choice == null ? "copy" : choice === "satellite" ? "satellite" : "circle-slash")}</span>
      <small>${h(label)}</small></button>`;
  const body = () => `<div class="bg-grid">
      ${inherited ? option(null, inherited) : ""}
      ${option("none", t("No picture"))}
      ${option("satellite", t("Satellite picture of the lake"))}
      <label class="bg-option add"><span class="thumb">${icon("image-plus")}</span><small>${h(t("Your own photo"))}</small>
        <input type="file" accept="image/*" id="own-photo" hidden></label>
      ${b.mine.map((name) => `<div class="bg-mine">${option(`custom:${name}`, t("Your picture"), "")}
        <button class="bg-delete" data-delete="${h(name)}" aria-label="${h(t("Delete picture"))}">${icon("x")}</button></div>`).join("")}
    </div>
    <h3 class="section">${h(t("Samples"))}</h3>
    <div class="bg-grid">${SAMPLES.map(([sid, label]) => option(`sample:${sid}`, t(label), sampleUrl(sid))).join("")}</div>
    <p class="footer">${h(t("Your own pictures stay in this browser."))}</p>`;
  openSheet(title, body(), function wire(dialog) {
    const box = dialog.querySelector(".sheet-body");
    // The visitor's pictures come from IndexedDB, so their thumbnails fill in after.
    box.querySelectorAll(".bg-mine .bg-option").forEach(async (el) => {
      const url = await ownPictureUrl(el.dataset.choice.slice(7));
      if (url) {
        const thumb = el.querySelector(".thumb");
        thumb.style.backgroundImage = `url("${url}")`;
        thumb.innerHTML = "";
      }
    });
    box.querySelectorAll("[data-choice]").forEach((el) => el.addEventListener("click", () => {
      pick(el.dataset.choice || null);
      dialog.close();
      done();
    }));
    box.querySelectorAll("[data-delete]").forEach((el) => el.addEventListener("click", async () => {
      await forgetOwnPicture(el.dataset.delete);
      box.innerHTML = body();
      wire(dialog);
      done();
    }));
    box.querySelector("#own-photo").addEventListener("change", async (e) => {
      const file = e.target.files?.[0];
      if (!file) return;
      try {
        const name = await addOwnPicture(file);
        pick(`custom:${name}`);
        dialog.close();
        done();
      } catch {
        alert(t("Could not use this photo"));
      }
    });
  });
}
