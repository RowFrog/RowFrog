// Background pictures (Backgrounds.swift, BackgroundSettingsView): a picture
// for all pages, for one kind of page or for one club, clear or blurred, and
// how the cards look over it. The samples are the app's own pictures; the
// visitor's own pictures stay in this browser (IndexedDB).

import { t } from "./i18n.js";
import { icon } from "./icons.js";
import { API, key } from "./logic.js";
import { store, h, load, save, getJSON, setTitle, testing, footerLinks, openSheet, savingData } from "./shared.js";
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

export const TILE_STYLES = [["frosted", key("Picture blurred")], ["glass", key("Liquid Glass")], ["solid", key("No picture")]];

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

// ---- Drawing the picture behind the page -------------------------------------------------

const sampleUrl = (id) => `backgrounds/bg-${id}.jpg`;

/** The clearest satellite picture of the club's lake (the home base's without a club). */
async function satelliteUrl(clubId) {
  if (savingData()) return null;
  const club = store.clubs.find((c) => c.id === clubId) ?? store.clubs[0];
  if (!club?.lakeId) return null;
  const meta = await getJSON(`lakes/${encodeURIComponent(club.lakeId)}/satellite`).catch(() => null);
  const shot = meta?.clearest ?? meta?.mostlyClear ?? meta?.latest;
  return shot?.image ? `${API}/lakes/${encodeURIComponent(club.lakeId)}/${encodeURIComponent(shot.image)}` : null;
}

async function pictureUrl(choice, clubId) {
  if (choice === "satellite") return satelliteUrl(clubId);
  if (choice.startsWith("sample:")) return sampleUrl(choice.slice(7));
  if (choice.startsWith("custom:")) return ownPictureUrl(choice.slice(7));
  return null;
}

let shown = 0;

/** Puts the page's picture behind it, or none (page null: pages without pictures). */
export async function showBackground(page, clubId = null) {
  const ticket = ++shown;
  const choice = page ? backgroundFor(page, clubId) : "none";
  const url = choice === "none" ? null : await pictureUrl(choice, clubId).catch(() => null);
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
  layer.classList.toggle("blurred", backgrounds.blur);
  document.body.classList.add("has-picture");
  document.body.dataset.tiles = backgrounds.tiles;
}

// ---- Settings › Background pictures ------------------------------------------------------

const settingsNav = () => `<header class="nav"><a class="link" href="#/settings">${icon("chevron-left")} ${h(t("Settings"))}</a><span class="spacer"></span></header>`;

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
      <h3 class="section">${icon("layers")} ${h(t("All pages"))}</h3>
      <section class="card group">${row("all", t("All pages"), "layers", b.all)}</section>
      <h3 class="section">${icon("copy")} ${h(t("Single pages"))}</h3>
      <section class="card group">${PAGES.map(([id, title, ic]) => row(`page:${id}`, t(title), ic, b.pages[id], t("Same as all pages"))).join("")}</section>
      <p class="footer">${h(t("A picture set here replaces the one for all pages on that page."))}</p>
      ${store.clubs.length ? `<h3 class="section">${icon("sailboat")} ${h(t("Single clubs"))}</h3>
      <section class="card group">${store.clubs.map((c) => row(`club:${c.id}`, c.shortName || c.name, "house", b.clubs[c.id], t("Same as club pages"))).join("")}</section>
      <p class="footer">${h(t("A club's own picture shows only on that club's page."))}</p>` : ""}
      <h3 class="section">${icon("sliders-horizontal")} ${h(t("Look"))}</h3>
      <section class="card group">
        <div class="row-setting"><span>${h(t("Picture"))}</span><span class="segmented small" id="blur">
          <button data-blur="false" class="${b.blur ? "" : "on"}">${h(t("Clear"))}</button><button data-blur="true" class="${b.blur ? "on" : ""}">${h(t("Blurred"))}</button></span></div>
        <label class="row-setting"><span>${h(t("In the tiles"))}</span>
          <select id="tiles">${TILE_STYLES.map(([k, title]) => `<option value="${k}" ${k === b.tiles ? "selected" : ""}>${h(t(title))}</option>`).join("")}</select></label>
      </section>
      <p class="footer">${h(t("Picture blurred: the picture shows through the tiles like frosted glass. Liquid Glass: clearer glass. No picture: the tiles stay solid and keep the full rowing-light shading."))}</p>
      <section class="card group"><button class="row-setting red" id="remove-all">${icon("trash-2")} ${h(t("Remove all background pictures"))}</button></section>
      <p class="footer">${h(t("Back to the factory setting: no picture on any page. Your own pictures stay available to pick again."))}</p>
      ${footerLinks()}
    </main>`;
  wireTips(root.querySelector("main"));
  const again = () => {
    renderBackgrounds(root);
    showBackground("settings");
  };
  root.querySelectorAll("[data-target]").forEach((el) => el.addEventListener("click", () => openPicker(el.dataset.target, again)));
  root.querySelectorAll("[data-blur]").forEach((el) => el.addEventListener("click", () => {
    b.blur = el.dataset.blur === "true";
    again();
  }));
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
