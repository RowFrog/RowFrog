// The club's place on OpenStreetMap, as a small card of our own (owner, 12 Nov 2026): the website's
// counterpart of the app's "In Apple Maps as …" line, which opens Apple's place card. The website has
// no Apple place, so the line names the OpenStreetMap place the catalog matched the club to
// (mapPlace in the API, from data/catalogs/osm-places.json) and opens a card with its name,
// directions to it and its OpenStreetMap page.

import { t } from "./i18n.js";
import { icon } from "./icons.js";
import { h } from "./shared.js";

/** The OpenStreetMap page of a place id such as "way/42123014", or null for anything else. */
export function osmUrl(osm) {
  return /^(node|way|relation)\/\d+$/.test(osm ?? "") ? `https://www.openstreetmap.org/${osm}` : null;
}

/**
 * The line under the Location map and the card it opens, or "" when the club has no OpenStreetMap
 * place with a name and an id. `maps` is the map service from Settings > Maps (MAPS_APPS).
 */
export function osmPlaceCard(place, maps) {
  const url = osmUrl(place?.osm);
  if (!url || !place.name) return "";
  return `<details class="osm-place">
    <summary>${icon("badge-check")} ${h(t("In OpenStreetMap as “%@”", place.name))}</summary>
    <div class="place-card">
      <b>${h(place.name)}</b>
      <small class="sub">${h(t("The club's place on OpenStreetMap"))}</small>
      <div class="place-actions">
        <a class="pill" href="${h(maps.directions(place.lat, place.lon))}" target="_blank" rel="noopener noreferrer">${icon("map-pinned")} ${h(t("Directions"))}</a>
        <a class="pill" href="${h(url)}" target="_blank" rel="noopener noreferrer">${icon("map")} ${h(t("On OpenStreetMap"))}</a>
      </div>
      <small class="sub">© OpenStreetMap contributors</small>
    </div></details>`;
}
