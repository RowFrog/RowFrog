// Route links: the app's RouteLink.swift and the website make and read the same links.
import { test } from "node:test";
import assert from "node:assert/strict";
import { routeLink, readRouteLink, addSharedRoutes, LINK_BASE } from "../public/app/routelink.js";

const route = { id: "a", name: "Rund um die Roseninsel – ÄÖÜ", lakeId: "starnberger-see", outAndBack: true,
  points: [{ lat: 47.9312345, lon: 11.3123456 }, { lat: 47.94, lon: 11.32 }, { lat: 47.95, lon: 11.31 }], track: [{ lat: 1, lon: 2 }], importedFrom: "file" };

test("a link carries name, water, way back and points rounded to 5 decimals, not the track", () => {
  const link = routeLink([route]);
  assert.ok(link.startsWith(LINK_BASE));
  assert.match(link.slice(LINK_BASE.length), /^[A-Za-z0-9_-]+$/, "URL-safe");
  let n = 0;
  const [back] = readRouteLink(link.slice(LINK_BASE.length), () => `n${++n}`);
  assert.deepEqual(back, { id: "n1", name: route.name, lakeId: "starnberger-see", outAndBack: true,
    points: [{ lat: 47.93123, lon: 11.31235 }, { lat: 47.94, lon: 11.32 }, { lat: 47.95, lon: 11.31 }] });
});

test("the app's link reads the same (payload as RouteLink.swift writes it)", () => {
  const json = '{"v":1,"routes":[{"back":false,"lake":"ammersee","name":"Kurz","p":[[48,11.1],[48.01,11.12]]}]}';
  const value = Buffer.from(json).toString("base64url");
  const [r] = readRouteLink(value, () => "x");
  assert.deepEqual(r, { id: "x", name: "Kurz", lakeId: "ammersee", outAndBack: false, points: [{ lat: 48, lon: 11.1 }, { lat: 48.01, lon: 11.12 }] });
});

test("broken links and bad routes are left out", () => {
  assert.equal(readRouteLink("%%%"), null);
  assert.equal(readRouteLink(Buffer.from('{"v":2,"routes":[]}').toString("base64url")), null);
  const json = JSON.stringify({ v: 1, routes: [{ lake: "x", p: [[1, 2]] }, { lake: "", p: [[1, 2], [3, 4]] }, { lake: "x", p: [[100, 2], [3, 4]] }, { lake: "x", p: [[1, 2], [3, 4]] }] });
  const list = readRouteLink(Buffer.from(json).toString("base64url"));
  assert.equal(list.length, 1);
  assert.equal(list[0].name, "Route");
});

test("a route already saved is not saved again", () => {
  const [shared] = readRouteLink(routeLink([route]).slice(LINK_BASE.length));
  const first = addSharedRoutes([], [shared]);
  assert.equal(first.list.length, 1);
  const [again] = readRouteLink(routeLink([route]).slice(LINK_BASE.length));
  const second = addSharedRoutes(first.list, [again]);
  assert.equal(second.list.length, 1);
  assert.equal(second.routes[0].id, shared.id);
});
