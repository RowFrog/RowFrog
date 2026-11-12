import { test } from "node:test";
import assert from "node:assert/strict";
import { osmUrl, osmPlaceCard } from "../public/app/osmplace.js";
import { MAPS_APPS } from "../public/app/shared.js";

const place = { lat: 47.99667, lon: 11.34745, name: "Münchener Ruder-Club von 1880", osm: "way/42123014" };

test("only node, way and relation ids make an OpenStreetMap link", () => {
  assert.equal(osmUrl("way/42123014"), "https://www.openstreetmap.org/way/42123014");
  assert.equal(osmUrl("node/1"), "https://www.openstreetmap.org/node/1");
  for (const bad of [null, undefined, "", "way/", "street/1", "way/1?x", "javascript:alert(1)"]) assert.equal(osmUrl(bad), null);
});

test("the card names the place and links its directions and OpenStreetMap page", () => {
  const html = osmPlaceCard(place, MAPS_APPS.osm);
  assert.match(html, /In OpenStreetMap as “Münchener Ruder-Club von 1880”/);
  assert.match(html, /href="https:\/\/www\.openstreetmap\.org\/way\/42123014"/);
  assert.match(html, /openstreetmap\.org\/directions\?to=47\.99667%2C11\.34745/);
  assert.match(html, /© OpenStreetMap contributors/);
});

test("no card without a place, its name or its id", () => {
  assert.equal(osmPlaceCard(null, MAPS_APPS.osm), "");
  assert.equal(osmPlaceCard({ ...place, osm: null }, MAPS_APPS.osm), "");
  assert.equal(osmPlaceCard({ ...place, name: "" }, MAPS_APPS.osm), "");
});

test("the place name is escaped", () => {
  assert.doesNotMatch(osmPlaceCard({ ...place, name: "<b>x</b>" }, MAPS_APPS.osm), /<b>x<\/b>/);
});
