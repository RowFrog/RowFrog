// "Not in the list? Add a place" (AddPlaceView): the user moves the map until
// the pin sits on their launch point, names it and saves it. It stays in this
// browser; a switch (off unless the user turns it on) suggests it for
// everyone's list.

import { t } from "./i18n.js";
import { icon } from "./icons.js";
import { API, key } from "./logic.js";
import { store, h, setTitle, testing, loadLeaflet, loadCatalog } from "./shared.js";
import { OWN_PREFIX } from "./ownplace.js";

const KINDS = [["club", key("Club")], ["boathouse", key("Boathouse")], ["water", key("Place on the water")]];

const distanceKm = (a, b) => {
  const k = Math.cos((((a.lat + b.lat) / 2) * Math.PI) / 180);
  return Math.hypot((a.lat - b.lat) * 111.2, (a.lon - b.lon) * 111.2 * k);
};

/** The catalog water nearest the pin within 2 km, to name the place's water. */
export function nearestWater(lakes, point, withinKm = 2) {
  let best = null;
  for (const lake of lakes ?? []) {
    if (!lake.center) continue;
    const d = distanceKm(lake.center, point);
    if (d <= withinKm && (!best || d < best.d)) best = { lake, d };
  }
  return best?.lake ?? null;
}

/** The place as a club, so the list and the pages treat it like any other. */
export function ownClub({ name, kind, website, point, water, shared }) {
  let site = website.trim();
  if (site && !site.includes("://")) site = `https://${site}`;
  return {
    id: OWN_PREFIX + (crypto.randomUUID?.() ?? `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`),
    name: name.trim(), shortName: name.trim(), address: "", website: site || null,
    launchPoint: { lat: +point.lat.toFixed(5), lon: +point.lon.toFixed(5) }, launchPointVerified: true, source: "own",
    lakeId: null, lakeName: water?.name ?? null, country: water?.country ?? null,
    own: { kind, shared, added: new Date().toISOString() },
  };
}

/**
 * Sends the suggestion to the Row Frog service (cloudflare/suggestions), which
 * files it as a GitHub issue, so the user needs no GitHub account. The service
 * reads the body whatever its type, so it goes as a plain form post the
 * browser sends without asking first; its answer cannot be read from here.
 */
function suggest(club) {
  const body = JSON.stringify({
    name: club.name, kind: club.own.kind, lat: club.launchPoint.lat, lon: club.launchPoint.lon,
    water: club.lakeName, website: club.website, country: club.country,
  });
  fetch(`${API}/suggestions`, { method: "POST", mode: "no-cors", headers: { "Content-Type": "text/plain" }, body }).catch(() => {});
}

export async function renderAddPlace(root, startName = "") {
  setTitle(t("Add a place"));
  root.innerHTML = `
    <header class="nav"><a class="link" href="#/list">${h(t("Cancel"))}</a><strong class="nav-title">${h(t("Add a place"))}</strong><button class="link strong" id="save" disabled>${h(t("Save"))}</button></header>
    ${testing()}
    <main class="page add-place">
      <h3 class="section">${h(t("Move the map until the pin sits where you launch"))}</h3>
      <div class="pin-map"><div id="place-map"></div><span class="center-pin" aria-hidden="true">${icon("map-pin")}</span></div>
      <p class="footer" id="near"></p>
      <section class="card group">
        <label class="row-setting"><span>${h(t("Name"))}</span><input id="name" type="text" maxlength="80" autocomplete="off" value="${h(startName)}"></label>
        <label class="row-setting"><span>${h(t("What it is"))}</span><select id="kind">${KINDS.map(([k, label]) => `<option value="${k}">${h(t(label))}</option>`).join("")}</select></label>
        <label class="row-setting"><span>${h(t("Website (optional)"))}</span><input id="website" type="url" inputmode="url" autocomplete="off" autocapitalize="off" spellcheck="false"></label>
      </section>
      <section class="card group">
        <label class="row-setting"><span>${h(t("Suggest it for everyone's list"))}</span><input id="share" type="checkbox" class="switch"></label>
      </section>
      <p class="footer" id="share-note"></p>
      <p class="footer">${h(t("The forecast for your own place is worked out in this browser: wind, gusts, rain, fog, thunderstorms and daylight. Waves, water temperature and warnings are not available for it."))}</p>
    </main>`;
  const $ = (s) => root.querySelector(s);
  const shareNote = () => {
    $("#share-note").textContent = $("#share").checked
      ? t("When you save, the name, kind, position, water and website are sent to us. Nothing about you is sent. We check the place and add it to the list for everyone.")
      : t("The place stays in this browser and nobody else sees it.");
  };
  shareNote();
  $("#share").addEventListener("change", shareNote);
  const name = $("#name");
  const canSave = () => ($("#save").disabled = !name.value.trim());
  name.addEventListener("input", canSave);
  canSave();

  // Starts at the home base, else over the Alps' northern lakes.
  let point = store.clubs[0]?.launchPoint ?? { lat: 47.9, lon: 11.3 };
  let water = null;
  const lakes = await loadCatalog().catch(() => null);
  const L = await loadLeaflet();
  if (!$("#place-map")) return;
  const map = L.map("place-map", { zoomControl: true }).setView([point.lat, point.lon], 15);
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19, referrerPolicy: "strict-origin", attribution: '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>',
  }).addTo(map);
  // Once the map stops: the nearest water is looked up among every lake.
  const moved = () => {
    const c = map.getCenter();
    point = { lat: c.lat, lon: c.lng };
    water = nearestWater(lakes, point);
    $("#near").textContent = water ? t("Near %@.", water.name) : "";
  };
  map.on("moveend", moved);
  moved();

  $("#save").addEventListener("click", () => {
    if (!name.value.trim()) return;
    const club = ownClub({ name: name.value, kind: $("#kind").value, website: $("#website").value, point, water, shared: $("#share").checked });
    store.clubs = [...store.clubs, club];
    if (club.own.shared) suggest(club);
    location.hash = `#/club/${encodeURIComponent(club.id)}`;
  });
}
