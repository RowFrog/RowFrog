// A small reader for statecharts written as JSON (ios/RowFrog/Charts/*.json), the same as the app's
// Statechart.swift: nested states with an initial child, entry actions, and per event a transition
// (or a list tried in order) with an optional target, guard and actions. Guards and actions are
// named in the chart and written by the caller (owner decision 12 Nov 2026, D-lite).

/** The chart's states by their path ("planning.drawing"), with their parent and initial child. */
export function statechart(chart) {
  const nodes = new Map();
  const walk = (node, path) => {
    nodes.set(path.join("."), { node, path });
    for (const [name, child] of Object.entries(node.states ?? {})) walk(child, [...path, name]);
  };
  walk(chart, []);
  /** The path and the deepest initial child below it. */
  const settle = (path) => {
    const out = [...path];
    for (let n = nodes.get(out.join(".")).node; n.initial; n = n.states[n.initial]) out.push(n.initial);
    return out;
  };
  const resolve = (from, target) => {
    const path = target.startsWith(".") ? [...from, target.slice(1)] : [...from.slice(0, -1), target];
    if (!nodes.has(path.join("."))) throw new Error(`${chart.id}: no state ${path.join(".")} (target ${target} in ${from.join(".")})`);
    return settle(path);
  };
  return {
    id: chart.id,
    initial: () => settle([]),
    /** Every guard and action the chart names, to check that the caller writes them all. */
    names() {
      const guards = new Set();
      const actions = new Set();
      for (const { node } of nodes.values()) {
        for (const a of node.entry ?? []) actions.add(a);
        for (const list of Object.values(node.on ?? {})) {
          for (const tr of [list].flat()) {
            if (tr.guard) guards.add(tr.guard);
            for (const a of tr.actions ?? []) actions.add(a);
          }
        }
      }
      return { guards: [...guards].sort(), actions: [...actions].sort() };
    },
    /** Every target, so a test can see each one leads to a state. */
    targets() {
      const out = [];
      for (const { node, path } of nodes.values()) {
        for (const list of Object.values(node.on ?? {})) for (const tr of [list].flat()) if (tr.target) out.push(resolve(path, tr.target));
      }
      return out;
    },
    /**
     * What `event` does in `state` (a path such as ["planning", "drawing"]): the new state and the actions
     * to run in order (the transition's, then the entry actions of the states it enters), or null when
     * no state on the path takes it. The deepest state goes first; one whose guards all say no passes
     * the event to its parent, as in SCXML.
     */
    transition(state, event, guard) {
      for (let depth = state.length; depth >= 0; depth--) {
        const path = state.slice(0, depth);
        const list = nodes.get(path.join("."))?.node.on?.[event];
        if (!list) continue;
        const tr = [list].flat().find((x) => !x.guard || guard(x.guard));
        if (!tr) continue;
        if (!tr.target) return { state, actions: tr.actions ?? [] };
        const next = resolve(path, tr.target);
        const actions = [...(tr.actions ?? [])];
        // The states the old and new paths share are not entered again.
        let same = 0;
        while (same < Math.min(state.length, next.length) && state[same] === next[same]) same++;
        for (let i = same + 1; i <= next.length; i++) actions.push(...(nodes.get(next.slice(0, i).join(".")).node.entry ?? []));
        return { state: next, actions };
      }
      return null;
    },
  };
}
