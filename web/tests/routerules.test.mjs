// testdata/rules/routes.json: the route rules (editing the turning points,
// distance, heading, wind relation, current, pace), which the app's tests
// (RouteRulesTableTests.swift) read too, so a route behaves alike in both.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { RouteEdit, distanceM, heading, pace, windRelation, withCurrent } from "../public/app/lake.js";

const table = JSON.parse(readFileSync(new URL("../../testdata/rules/routes.json", import.meta.url), "utf8"));
const at = (name) => {
  const [lat, lon] = table.points[name];
  return { lat, lon, name };
};
const names = (points) => points.map((p) => p.name);

test("distances are the table's, within 0.5 %", () => {
  for (const c of table.distance) {
    const m = distanceM(at(c.from), at(c.to));
    assert.ok(Math.abs(m - c.m) <= c.m * 0.005, `${c.from}→${c.to}: ${m} instead of ${c.m}`);
  }
});

test("headings are the table's", () => {
  for (const c of table.heading) {
    const deg = heading(at(c.from), at(c.to));
    assert.ok(Math.abs(deg - c.deg) <= 0.01, `${c.from}→${c.to}: ${deg} instead of ${c.deg}`);
  }
});

test("head, tail and cross wind are the table's", () => {
  for (const c of table.windRelation) assert.equal(windRelation(c.heading, c.windFrom), c.relation, `${c.heading}/${c.windFrom}`);
});

test("paces are written as in the table", () => {
  for (const c of table.pace) assert.equal(pace(c.seconds), c.text, String(c.seconds));
});

test("editing the turning points gives the table's routes", () => {
  for (const c of table.edits) {
    let points = c.start.map(at);
    for (const o of c.ops) {
      if (o.op === "add") points = RouteEdit.add(at(o.point), points);
      else if (o.op === "close") points = RouteEdit.close(points);
      else if (o.op === "open") points = RouteEdit.open(points);
      else if (o.op === "remove") points = RouteEdit.remove(o.index, points);
      else if (o.op === "insert") points = RouteEdit.insert(at(o.point), o.index, points);
      else if (o.op === "move") points = RouteEdit.move(o.index, at(o.point), points);
      else assert.fail(`unknown step ${o.op}`);
    }
    assert.deepEqual(names(points), c.points, c.case);
    assert.equal(RouteEdit.isLoop(points), c.loop, `${c.case}: loop`);
  }
});

test("the current along the route is the table's", () => {
  for (const c of table.withCurrent) {
    const pieces = c.flow.map(([a, b]) => [at(a), at(b)]);
    const cos = withCurrent(at(c.at), c.heading, pieces);
    assert.ok(Math.abs(cos - c.cosine) <= 0.001, `${c.at} ${c.heading}°: ${cos} instead of ${c.cosine}`);
  }
});
