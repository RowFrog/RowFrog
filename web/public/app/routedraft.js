// The route being planned on the lake map: its turning points, the way back, the saved route it came from
// and the undo history, driven by the route editor's statechart (ios/RowFrog/Charts/route-editor.json),
// as the app's RouteDraft.swift. The page sends events (a tap, a button) and draws what this holds.

import { statechart } from "./statechart.js";
import { RouteEdit } from "./lake.js";

/** Undo goes back this many changes. */
export const HISTORY = 100;

const samePoints = (a, b) => a.length === b.length && a.every((p, i) => p.lat === b[i].lat && p.lon === b[i].lon);
const newId = () => globalThis.crypto?.randomUUID?.() ?? `r${Date.now()}${Math.random().toString(36).slice(2, 6)}`;
/** An imported row's track and date go with the route saved from it. */
const rowFields = (rowed) => (rowed ? { track: rowed.track, rowedAt: rowed.rowedAt, importedFrom: rowed.importedFrom } : {});
const ROW_KEYS = ["track", "rowedAt", "importedFrom"];
const withoutRow = (route) => Object.fromEntries(Object.entries(route).filter(([k]) => !ROW_KEYS.includes(k)));

const GUARDS = {
  /** A closed loop takes no more points. */
  canAdd: (d) => !RouteEdit.isLoop(d.points),
  /** A stretch to add a point on: before the point at `index`, not before the start. */
  isStretch: (d, e) => e.index > 0 && e.index < d.points.length,
  /** A turning point: not the start, nor a loop's end, which is the start again. */
  isTurningPoint: (d, e) => e.index > 0 && e.index < d.points.length && !(RouteEdit.isLoop(d.points) && e.index === d.points.length - 1),
  /** A loop needs two turning points first. */
  wayBackAllowed: (d, e) => e.way !== "loop" || d.points.length >= 3,
  hasRoute: (d) => d.points.length >= 2,
  canUndo: (d) => d.history.length > 0,
  hasSaved: (d) => d.saved != null,
  canSaveAsNew: (d) => d.points.length >= 2 && d.saved != null,
};

const ACTIONS = {
  deselect: (d) => { d.selected = null; },
  /** A new route starts at the club's launch point. */
  startAtClub: (d) => { if (!d.points.length && d.launch) d.points = [d.launch]; },
  newRoute: (d) => Object.assign(d, { points: [], outAndBack: false, saved: null, rowed: null, history: [] }),
  /** A saved route opens with its own history: undo does not go back to the route shown before. */
  openRoute: (d, e) => Object.assign(d, {
    points: e.route.points, outAndBack: e.route.outAndBack, saved: e.route, rowed: e.route.track ? e.route : null, history: [],
  }),
  record: (d) => {
    d.history.push(d.snapshot());
    if (d.history.length > HISTORY) d.history.shift();
  },
  add: (d, e) => {
    d.points = RouteEdit.add(e.point, d.points);
    if (RouteEdit.isLoop(d.points)) d.outAndBack = false;
  },
  /** The new point is the one tapped after, to drag or delete it. */
  insert: (d, e) => {
    d.points = RouteEdit.insert(e.point, e.index, d.points);
    d.selected = e.index;
  },
  move: (d, e) => { d.points = RouteEdit.move(e.index, e.point, d.points); },
  select: (d, e) => { d.selected = e.index; },
  removeSelected: (d) => { d.points = RouteEdit.remove(d.selected, d.points); },
  wayBack: (d, e) => {
    d.points = e.way === "loop" ? RouteEdit.close(d.points) : RouteEdit.open(d.points);
    d.outAndBack = e.way === "outAndBack";
  },
  /** Back to the launch point; the imported row's track goes too. */
  clear: (d) => {
    d.points = d.points.slice(0, 1);
    d.rowed = null;
  },
  undo: (d) => Object.assign(d, d.history.pop()),
  /** Updates the open saved route, or saves a new one. */
  save: (d, e) => {
    const base = d.saved ? withoutRow(d.saved) : { id: e.id ?? newId(), lakeId: d.lakeId };
    d.saved = { ...base, ...rowFields(d.rowed), name: e.name, points: d.points, outAndBack: d.outAndBack };
  },
  /** A new saved route; the one opened before stays as it was. */
  saveAsNew: (d, e) => {
    d.saved = { id: e.id ?? newId(), lakeId: d.lakeId, ...rowFields(d.rowed), name: e.name, points: d.points, outAndBack: d.outAndBack };
  },
  forgetSaved: (d) => Object.assign(d, { saved: null, rowed: null }),
  /** The open route was renamed or deleted in Manage routes. */
  routeChanged: (d, e) => { if (d.saved?.id === e.id) d.saved = e.route ?? null; },
};

export const ROUTE_GUARDS = Object.keys(GUARDS).sort();
export const ROUTE_ACTIONS = Object.keys(ACTIONS).sort();

/**
 * A route draft on lake `lakeId`, starting at `launch` (the club's launch point). `state` is a path
 * such as ["planning", "pointSelected"] for the screenshot switches; by default the chart's initial state.
 */
export function routeDraft(chart, { lakeId, launch = null, points = [], outAndBack = false, saved = null, rowed = null, state = null, selected = null } = {}) {
  const machine = statechart(chart);
  const d = {
    lakeId, launch, points, outAndBack, saved, rowed, selected, history: [],
    state: state ?? machine.initial(),
    snapshot() { return { points: this.points, outAndBack: this.outAndBack, rowed: this.rowed }; },
    get planning() { return this.state[0] === "planning"; },
    get stateName() { return this.state.join("."); },
    /** "new" (not saved yet), "saved" (as saved) or "changed": compared, so undoing back to the saved route is Saved again. */
    get status() {
      if (!this.saved) return "new";
      return samePoints(this.points, this.saved.points) && this.outAndBack === this.saved.outAndBack ? "saved" : "changed";
    },
    get canUndo() { return this.history.length > 0; },
    /** Whether `type` would do anything now, for a button's disabled state. */
    can(event) {
      return machine.transition(this.state, event.type, (g) => GUARDS[g](this, event)) != null;
    },
    /** Runs the event through the chart; false when nothing takes it. */
    send(event) {
      const step = machine.transition(this.state, event.type, (g) => {
        if (!GUARDS[g]) throw new Error(`route editor: no guard ${g}`);
        return GUARDS[g](this, event);
      });
      if (!step) return false;
      for (const a of step.actions) {
        if (!ACTIONS[a]) throw new Error(`route editor: no action ${a}`);
        ACTIONS[a](this, event);
      }
      // An edit that changed nothing (a point added to a closed loop) leaves no step to undo.
      const last = this.history.at(-1);
      if (step.actions.includes("record") && last && samePoints(last.points, this.points) && last.outAndBack === this.outAndBack && last.rowed === this.rowed) this.history.pop();
      this.state = step.state;
      return true;
    },
  };
  return d;
}
