// Suggest a launch point (SuggestLaunchPoint.swift): for a club whose club has not confirmed its
// launch point, the visitor moves the map under fixed oars until they sit where the club's boats
// go on the water, and sends that point to the Row Frog service (cloudflare/suggestions, kind
// "launchPoint"), which files it as a public GitHub issue for the owner to check and /accept.
// Only the club and the point are sent, never where the visitor is.

import { t, num } from "./i18n.js";
import { icon } from "./icons.js";
import { API } from "./logic.js";
import { h, load, save, loadLeaflet } from "./shared.js";
import { distanceM } from "./lake.js";
import { isOwn } from "./ownplace.js";

const SENT_KEY = "rf.suggestedLaunchPoints";

/** Whether the Location sheet and card offer it: a club from the lists whose club has not confirmed its launch point. */
export const suggestOffered = (club) => !!club?.launchPoint && !club.launchPointVerified && !isOwn(club.id);

/** Clubs this browser already sent a launch point for, so the sheet thanks instead of asking again. */
export function wasSent(id) {
  const ids = load(SENT_KEY, []);
  return Array.isArray(ids) && ids.includes(id);
}

function markSent(id) {
  const ids = load(SENT_KEY, []);
  save(SENT_KEY, [...new Set([...(Array.isArray(ids) ? ids : []), id])]);
}

/** The row under the Location map: the button, or the thanks once sent. */
export function suggestRow(club) {
  if (!suggestOffered(club)) return "";
  if (wasSent(club.id)) return `<p class="sub small suggest-done">${icon("circle-check")} ${h(t("Thank you: your suggestion is with us."))}</p>`;
  return `<p class="suggest-row"><button class="link strong suggest-lp" type="button" data-suggest-lp="${h(club.id)}">${icon("oars")} ${h(club.launchPointSet ? t("Suggest a better launch point") : t("Suggest the launch point"))}</button></p>`;
}

/** "120 m" or "1.4 km" from today's point, as the app's MeasurementFormatter in natural scale. */
const distanceText = (m) => (m < 1000 ? `${num(Math.round(m))} m` : `${num(m / 1000, 1)} km`);

/** A prefilled GitHub issue with the same lines, for when the service cannot be reached. */
function issueUrl(club, point) {
  const body = `Suggested from the website: where this club's boats go on the water.\n\n- Club: \`${club.name}\`\n- Club id: \`${club.id}\`\n- Launch point: ${point.lat.toFixed(6)}, ${point.lon.toFixed(6)}`;
  const q = new URLSearchParams({ title: `Launch point suggestion: ${club.name}`, labels: "launch point suggestion", body });
  return `https://github.com/RowFrog/RowFrog/issues/new?${q}`;
}

/**
 * The sheet: the map moves under the oars in the middle, a white dot marks today's forecast point.
 * `done(sent)` runs when it closes, so the page or the Location sheet can show the thanks.
 */
export async function openSuggestLaunchPoint(club, done = () => {}) {
  document.querySelector("dialog.sheet")?.remove();
  const dialog = document.createElement("dialog");
  dialog.className = "sheet suggest-sheet";
  dialog.innerHTML = `<header><button class="link" id="sg-cancel" type="button">${h(t("Cancel"))}</button><strong>${h(t("Launch point"))}</strong><button class="link strong" id="sg-send" type="button">${h(t("Send"))}</button></header>
    <div class="sheet-body">
      <h3 class="section">${h(t("Move the map until the oars sit where the club's boats go on the water"))}</h3>
      <div class="pin-map"><div id="sg-map"></div><span class="center-oars" aria-hidden="true">${icon("oars")}</span></div>
      <p><button class="link" id="sg-here" type="button">${icon("navigation")} ${h(t("Where I am"))}</button></p>
      <p class="footer" id="sg-moved">${h(t("The white dot is where the forecast is worked out today."))}</p>
      <p class="footer">${h(t("Only the club and this point are sent to us, never where you are. The suggestion becomes a public issue on GitHub; we check it on the satellite view before the forecast uses it."))}</p>
      <p class="footer orange" id="sg-failed" hidden>${icon("triangle-alert")} ${h(t("It could not be sent. You can send it from GitHub instead."))}</p>
    </div>`;
  document.body.append(dialog);
  let sent = false;
  dialog.addEventListener("close", () => { dialog.remove(); done(sent); });
  dialog.addEventListener("click", (e) => e.target === dialog && dialog.close());
  dialog.querySelector("#sg-cancel").addEventListener("click", () => dialog.close());
  dialog.showModal();

  const start = club.launchPoint;
  let point = { ...start };
  const L = await loadLeaflet().catch(() => null);
  const box = dialog.querySelector("#sg-map");
  if (L && box) {
    // About 400 m across, as the app opens it; the website has no satellite tiles, so the map it is.
    const map = L.map(box, { zoomControl: true, attributionControl: true }).setView([start.lat, start.lon], 17);
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19, referrerPolicy: "strict-origin", attribution: '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>',
    }).addTo(map);
    L.circleMarker([start.lat, start.lon], { radius: 5, color: "#8e8e93", weight: 1, fillColor: "#fff", fillOpacity: 0.9, interactive: false }).addTo(map);
    const moved = () => {
      const c = map.getCenter();
      point = { lat: c.lat, lon: c.lng };
      const m = distanceM(point, start);
      dialog.querySelector("#sg-moved").textContent = m < 5
        ? t("The white dot is where the forecast is worked out today.")
        : t("%@ from where the forecast is worked out today (white dot).", distanceText(m));
    };
    map.on("move", moved);
    new ResizeObserver(() => map.invalidateSize()).observe(box);
    // "Where I am": the map goes to the visitor; the position stays in this browser.
    dialog.querySelector("#sg-here").addEventListener("click", () => navigator.geolocation?.getCurrentPosition(
      (p) => map.setView([p.coords.latitude, p.coords.longitude], 17),
      () => {}, { enableHighAccuracy: true, timeout: 10000 }));
  }

  const send = dialog.querySelector("#sg-send");
  let failed = false;
  send.addEventListener("click", async () => {
    if (failed) {
      window.open(issueUrl(club, point), "_blank", "noopener");
      markSent(club.id);
      sent = true;
      dialog.close();
      return;
    }
    send.disabled = true;
    const body = JSON.stringify({ name: club.name.slice(0, 80), kind: "launchPoint", club: club.id, lat: point.lat, lon: point.lon });
    try {
      // A plain form post the browser sends without asking first; the service reads the body whatever its type.
      // Its answer cannot be read from here, so only a network failure counts as not sent.
      await fetch(`${API}/suggestions`, { method: "POST", mode: "no-cors", headers: { "Content-Type": "text/plain" }, body });
      markSent(club.id);
      sent = true;
      dialog.close();
    } catch {
      failed = true;
      send.disabled = false;
      send.textContent = t("Open GitHub");
      dialog.querySelector("#sg-failed").hidden = false;
    }
  });
}
