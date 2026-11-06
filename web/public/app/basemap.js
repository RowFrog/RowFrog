// The ground under a Leaflet map: the OpenStreetMap street map, or satellite pictures with roads and
// names (MapTiler "hybrid") behind a round glass button at the top right, as the app's globe button on the
// lake map, the Location card, Suggest a launch point and Add a place (Apple's satellite pictures there).
// The satellite pictures need a MapTiler key: the deploy writes it to config.json from the MAPTILER_KEY
// secret. Without the key there is no button and the street map stays.

import { icon } from "./icons.js";
import { t } from "./i18n.js";

let config = null;

/** The site's settings from the deploy (config.json); empty when there are none. */
export function siteConfig() {
  config ??= fetch(new URL("config.json", import.meta.url), { cache: "no-cache" })
    .then((r) => (r.ok ? r.json() : {}))
    .catch(() => ({}));
  return config;
}

const OSM = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
const OSM_CREDIT = '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>';
const MAPTILER_CREDIT = '<a href="https://www.maptiler.com/copyright/" target="_blank" rel="noopener">© MapTiler</a> ' + OSM_CREDIT;

/** Satellite tiles with roads and names; 512 px tiles drawn one zoom step lower, so the names stay readable. */
export const satelliteUrl = (key) => `https://api.maptiler.com/maps/hybrid/{z}/{x}/{y}.jpg?key=${encodeURIComponent(key)}`;

function remembered(storeKey, fallback) {
  if (!storeKey) return fallback;
  try {
    const v = localStorage.getItem(storeKey);
    return v == null ? fallback : v === "true";
  } catch {
    return fallback;
  }
}

function remember(storeKey, on) {
  if (!storeKey) return;
  try {
    localStorage.setItem(storeKey, String(on));
  } catch {
    // Private windows may refuse; the choice then lasts for this page only.
  }
}

/**
 * Puts the street map under `map` and, with a MapTiler key, the satellite button at the top right.
 * `storeKey` remembers the choice in this browser (the app's RWLakeImagery, RWLaunchImagery); without it the
 * map opens on `start` each time (Suggest a launch point and Add a place open on satellite pictures).
 * `onChange(satellite)` runs after every switch, and once at the start.
 */
export async function baseMap(L, map, { storeKey = null, start = false, small = false, onChange = () => {} } = {}) {
  const street = L.tileLayer(OSM, { maxZoom: 19, referrerPolicy: "strict-origin", attribution: OSM_CREDIT });
  const { maptilerKey } = await siteConfig();
  if (!maptilerKey) {
    street.addTo(map);
    onChange(false);
    return { satellite: () => false };
  }
  const imagery = L.tileLayer(satelliteUrl(maptilerKey), {
    tileSize: 512, zoomOffset: -1, minZoom: 1, maxZoom: 20, crossOrigin: true, attribution: MAPTILER_CREDIT,
  });
  let on = remembered(storeKey, start);
  const Control = L.Control.extend({
    options: { position: "topright" },
    onAdd() {
      const button = L.DomUtil.create("button", `glass sat-switch${small ? " small" : ""}`);
      button.type = "button";
      L.DomEvent.disableClickPropagation(button);
      L.DomEvent.on(button, "click", () => set(!on));
      this.button = button;
      return button;
    },
  });
  const control = new Control();
  function show() {
    map.removeLayer(on ? street : imagery);
    (on ? imagery : street).addTo(map);
    control.button.innerHTML = icon(on ? "map" : "globe");
    const label = on ? t("Show the map") : t("Show satellite pictures");
    control.button.setAttribute("aria-label", label);
    control.button.title = label;
    map.getContainer().classList.toggle("on-satellite", on);
  }
  function set(value) {
    on = value;
    remember(storeKey, on);
    show();
    onChange(on);
  }
  control.addTo(map);
  show();
  onChange(on);
  return { satellite: () => on };
}
