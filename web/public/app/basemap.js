// The ground under a Leaflet map: the OpenStreetMap street map (MapTiler's dark street map in dark mode), or satellite pictures with roads and
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

/**
 * Satellite tiles with roads and names; 512 px tiles drawn one zoom step lower, so the names stay readable.
 * `{r}` asks for MapTiler's double-size tiles on sharp (retina) screens, so names and roads stay crisp
 * on a phone (owner, 12 Nov 2026); the number of tiles, and so the free plan's count, stays the same.
 */
export const satelliteUrl = (key) => `https://api.maptiler.com/maps/hybrid/{z}/{x}/{y}{r}.jpg?key=${encodeURIComponent(key)}`;

/**
 * The dark street map (MapTiler "streets-v2-dark"), as the app's Apple map in dark mode. OpenStreetMap has no
 * dark tiles, and its turned-round colours (CSS .street-tiles) showed the forests as dark green patches, so
 * on a phone the map read as satellite pictures (owner, 15 Nov 2026). Only with a MapTiler key.
 */
export const darkStreetUrl = (key) => `https://api.maptiler.com/maps/streets-v2-dark/{z}/{x}/{y}{r}.png?key=${encodeURIComponent(key)}`;

/** Whether the page is in dark mode: the page's own setting, else the device's. */
export function darkMode() {
  const theme = document.documentElement.dataset.theme;
  return theme ? theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
}

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
  const street = L.tileLayer(OSM, { maxZoom: 19, referrerPolicy: "strict-origin", className: "street-tiles", attribution: OSM_CREDIT });
  const { maptilerKey } = await siteConfig();
  if (!maptilerKey) {
    street.addTo(map);
    onChange(false);
    return { satellite: () => false };
  }
  const imagery = L.tileLayer(satelliteUrl(maptilerKey), {
    tileSize: 512, zoomOffset: -1, minZoom: 1, maxZoom: 20, crossOrigin: true, attribution: MAPTILER_CREDIT,
  });
  const darkStreet = L.tileLayer(darkStreetUrl(maptilerKey), {
    tileSize: 512, zoomOffset: -1, minZoom: 1, maxZoom: 20, crossOrigin: true, attribution: MAPTILER_CREDIT,
  });
  let on = remembered(storeKey, start);
  let streetNow = darkMode() ? darkStreet : street;
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
    for (const layer of [street, darkStreet, imagery]) if (layer !== (on ? imagery : streetNow)) map.removeLayer(layer);
    (on ? imagery : streetNow).addTo(map);
    control.button.innerHTML = icon(on ? "map" : "earth");
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
  // Dark mode switched on or off while the map is open (the page's setting or the device's): the street map follows.
  const follow = () => {
    if (!map.getContainer().isConnected) return stopFollowing();
    const next = darkMode() ? darkStreet : street;
    if (next === streetNow) return;
    streetNow = next;
    if (!on) show();
  };
  const media = matchMedia("(prefers-color-scheme: dark)");
  const watcher = new MutationObserver(follow);
  watcher.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
  media.addEventListener?.("change", follow);
  function stopFollowing() {
    watcher.disconnect();
    media.removeEventListener?.("change", follow);
  }
  map.on("unload", stopFollowing);
  return { satellite: () => on };
}
