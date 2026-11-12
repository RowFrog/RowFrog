import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { statechart } from "../public/app/statechart.js";
import { routeDraft, ROUTE_GUARDS, ROUTE_ACTIONS, HISTORY } from "../public/app/routedraft.js";

// The route editor's chart (read by the app too) and testdata/states/route-editor.json, the cases the app's tests run.
const read = (path) => JSON.parse(readFileSync(new URL(path, import.meta.url), "utf8"));
const chart = read("../../ios/RowFrog/Charts/route-editor.json");
const table = read("../../testdata/states/route-editor.json");

const point = (name) => ({ lat: table.points[name][0], lon: table.points[name][1] });
const nameOf = (p) => Object.keys(table.points).find((n) => table.points[n][0] === p.lat && table.points[n][1] === p.lon) ?? `${p.lat},${p.lon}`;
const route = (id) => ({ id, lakeId: "lake", ...table.routes[id], points: table.routes[id].points.map(point) });

function event(spec) {
  const e = { ...spec };
  if (typeof e.point === "string") e.point = point(e.point);
  if (typeof e.route === "string") e.route = route(e.route);
  return e;
}

test("the chart names only guards and actions the website writes, and every target is a state", () => {
  const machine = statechart(chart);
  assert.deepEqual(machine.names().guards, ROUTE_GUARDS);
  assert.deepEqual(machine.names().actions, ROUTE_ACTIONS);
  assert.deepEqual(machine.initial(), ["looking"]);
  assert.ok(machine.targets().length > 10);
});

for (const c of table.cases) {
  test(`route editor: ${c.name}`, () => {
    const draft = routeDraft(chart, { lakeId: "lake", launch: point("club") });
    c.steps.forEach((step, i) => {
      const at = `step ${i + 1} (${step.send.type})`;
      const taken = draft.send(event(step.send));
      const want = step.expect ?? {};
      assert.equal(taken, want.taken ?? true, `${at}: taken`);
      if ("state" in want) assert.equal(draft.stateName, want.state, `${at}: state`);
      if ("status" in want) assert.equal(draft.status, want.status, `${at}: status`);
      if ("points" in want) assert.deepEqual(draft.points.map(nameOf), want.points, `${at}: points`);
      if ("outAndBack" in want) assert.equal(draft.outAndBack, want.outAndBack, `${at}: outAndBack`);
      if ("canUndo" in want) assert.equal(draft.canUndo, want.canUndo, `${at}: canUndo`);
      if ("selected" in want) assert.equal(draft.selected, want.selected, `${at}: selected`);
      if ("saved" in want) {
        const id = draft.saved?.id ?? null;
        assert.equal(id == null ? null : table.routes[id] ? id : "other", want.saved, `${at}: saved`);
      }
      if ("savedName" in want) assert.equal(draft.saved?.name, want.savedName, `${at}: savedName`);
    });
  });
}

test("Undo goes back at most HISTORY changes", () => {
  const draft = routeDraft(chart, { lakeId: "lake", launch: point("club") });
  draft.send({ type: "TOGGLE_PLANNING" });
  for (let i = 0; i < HISTORY + 20; i++) draft.send({ type: "ADD", point: { lat: 48 + i / 1000, lon: 11.3 } });
  let undone = 0;
  while (draft.send({ type: "UNDO" })) undone++;
  assert.equal(undone, HISTORY);
});

test("a saved route keeps an imported row's track, and loses it once the route is cleared", () => {
  const rowed = { ...route("lap"), track: [point("a")], rowedAt: "2026-11-01T08:00:00Z", importedFrom: "file" };
  const draft = routeDraft(chart, { lakeId: "lake", launch: point("club") });
  draft.send({ type: "OPEN_ROUTE", route: rowed });
  draft.send({ type: "ADD", point: point("c") });
  draft.send({ type: "SAVE_AS_NEW", name: "Copy" });
  assert.deepEqual(draft.saved.track, rowed.track);
  draft.send({ type: "CLEAR" });
  draft.send({ type: "ADD", point: point("b") });
  draft.send({ type: "SAVE", name: "Plain" });
  assert.equal(draft.saved.track, undefined);
  assert.equal(draft.saved.importedFrom, undefined);
});

test("the reader passes an event to the parent and enters states once", () => {
  const machine = statechart({
    id: "t", initial: "a",
    states: {
      a: { initial: "x", entry: ["inA"], on: { GO: { target: "b" } }, states: { x: { entry: ["inX"], on: { GO: { guard: "no", target: "y" } } }, y: {} } },
      b: { entry: ["inB"], on: { BACK: [{ guard: "no", target: "b" }, { target: "a", actions: ["back"] }] } },
    },
  });
  assert.deepEqual(machine.initial(), ["a", "x"]);
  assert.deepEqual(machine.transition(["a", "x"], "GO", () => false), { state: ["b"], actions: ["inB"] });
  assert.deepEqual(machine.transition(["b"], "BACK", () => false), { state: ["a", "x"], actions: ["back", "inA", "inX"] });
  assert.equal(machine.transition(["b"], "GO", () => true), null);
  assert.throws(() => statechart({ id: "t", initial: "a", states: { a: { on: { GO: { target: "nowhere" } } } } }).targets());
});
