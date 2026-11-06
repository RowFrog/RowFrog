// Natural neighbour (Sibson) blending between a lake's forecast points, as the app
// (LakeInterpolation.swift) and the backend (backend/rowfrog/interpolate.py) do it: a
// spot's weights are the shares of its own Voronoi cell it would take from each point's
// cell. They are never negative and add up to 1, so a blended value always stays between
// the points around it (owner's pick, 6 Nov 2026). Kept free of the page so Node can test it.

const EARTH_RADIUS_M = 6371000;
/** The box the Voronoi cells are clipped to: 4.4 km around the cells and points. */
const BOX_MARGIN_M = 4400;

/** The spots at least as close to p as to q: a*x + b*y <= c. */
const closer = (p, q) => [q[0] - p[0], q[1] - p[1], (q[0] ** 2 + q[1] ** 2 - p[0] ** 2 - p[1] ** 2) / 2];

function clip(poly, [a, b, c]) {
  const out = [];
  for (let i = 0; i < poly.length; i++) {
    const p = poly[i];
    const q = poly[(i + 1) % poly.length];
    const fp = a * p[0] + b * p[1] - c;
    const fq = a * q[0] + b * q[1] - c;
    if (fp <= 0) out.push(p);
    if ((fp < 0 && fq > 0) || (fq < 0 && fp > 0)) {
      const t = fp / (fp - fq);
      out.push([p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])]);
    }
  }
  return out;
}

function cut(box, planes) {
  let poly = box;
  for (const plane of planes) {
    poly = clip(poly, plane);
    if (!poly.length) break;
  }
  return poly;
}

function area(poly) {
  if (poly.length < 3) return 0;
  let s = 0;
  for (let i = 0; i < poly.length; i++) {
    const p = poly[i];
    const q = poly[(i + poly.length - 1) % poly.length];
    s += p[0] * q[1] - q[0] * p[1];
  }
  return Math.abs(s) / 2;
}

const bounds = (poly) => {
  let [x0, y0, x1, y1] = [Infinity, Infinity, -Infinity, -Infinity];
  for (const [x, y] of poly) {
    if (x < x0) x0 = x;
    if (x > x1) x1 = x;
    if (y < y0) y0 = y;
    if (y > y1) y1 = y;
  }
  return [x0, y0, x1, y1];
};

/** Weights for spots among fixed points, in flat metres (NaturalNeighbours). */
export function naturalNeighbours(points, { west, south, east, north }) {
  const box = [[west, south], [east, south], [east, north], [west, north]];
  const planes = points.map((p) => points.filter((q) => q !== p && (q[0] !== p[0] || q[1] !== p[1])).map((q) => closer(p, q)));
  const cells = planes.map((ps) => cut(box, ps));
  const cellBounds = cells.map((c) => (c.length ? bounds(c) : null));
  const d2 = (a, b) => (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2;
  const nearest = (spot) => points.reduce((best, p, i) => (best < 0 || d2(p, spot) < d2(points[best], spot) ? i : best), -1);
  /** Point index and weight, only points with a share. */
  function weights(spot) {
    const on = points.findIndex((p) => d2(p, spot) < 1e-12);
    if (on >= 0) return [[on, 1]];
    const own = cut(box, points.map((p) => closer(spot, p)));
    const total = area(own);
    const fallback = () => {
      const i = nearest(spot);
      return i < 0 ? [] : [[i, 1]];
    };
    if (!(total > 0)) return fallback();
    const [lo, bottom, hi, top] = bounds(own);
    const out = [];
    cells.forEach((cell, i) => {
      const b = cellBounds[i];
      // Cells that cannot overlap are skipped.
      if (!b || b[2] < lo || b[0] > hi || b[3] < bottom || b[1] > top) return;
      const part = cut(own, planes[i]);
      const share = part.length >= 3 ? area(part) : 0;
      if (share > 1e-9 * total) out.push([i, share]);
    });
    const sum = out.reduce((s, [, w]) => s + w, 0);
    if (!(sum > 0)) return fallback();
    return out.map(([i, w]) => [i, w / sum]);
  }
  return { points, weights };
}

/**
 * A lake's blending (LakeInterpolation): flat metres around its middle, a box 4.4 km around the cells and
 * points, and the weights of every water cell, worked out once per grid.
 */
export function lakeInterpolation(grid, points, cellCoordinate) {
  const cells = grid.cells.map((_, i) => cellCoordinate(grid, i));
  const lats = [...cells.map((c) => c.lat), ...points.map((p) => p.lat)];
  const lons = [...cells.map((c) => c.lon), ...points.map((p) => p.lon)];
  const lat0 = (Math.min(...lats) + Math.max(...lats)) / 2;
  const lon0 = (Math.min(...lons) + Math.max(...lons)) / 2;
  const k = Math.cos((lat0 * Math.PI) / 180);
  const flat = ({ lat, lon }) => [((lon - lon0) * Math.PI) / 180 * EARTH_RADIUS_M * k, ((lat - lat0) * Math.PI) / 180 * EARTH_RADIUS_M];
  const pts = points.map(flat);
  const sq = cells.map(flat);
  const [x0, y0, x1, y1] = bounds([...pts, ...sq]);
  const m = BOX_MARGIN_M;
  const nn = naturalNeighbours(pts, { west: x0 - m, south: y0 - m, east: x1 + m, north: y1 + m });
  const one = pts.length ? [[0, 1]] : [];
  const cellWeights = pts.length < 2 ? sq.map(() => one) : sq.map((s) => nn.weights(s));
  return {
    cellWeights,
    /** Weights at any spot, such as where the water was tapped. */
    weightsAt: (c) => (pts.length < 2 ? one : nn.weights(flat(c))),
  };
}

const RANK = { green: 0, amber: 1, red: 2 };
const worse = (a, b) => (RANK[b] > RANK[a] ? b : a);

/**
 * The wind at a spot, blended from the forecast points around it (LakeWind.blended): speed, gusts and rain as
 * they are, visibility on a log scale, the direction from the wind arrows. Thunderstorms and hail are yes or no
 * and come from `near`, the nearest point; with the newer backend fields the point's other light is worked out
 * again from the blended visibility and rain.
 */
export function blendWind(weights, winds, near) {
  const used = weights.filter(([i]) => i < winds.length);
  if (used.length <= 1) return used.length ? winds[used[0][0]] : near ?? null;
  const blend = (value) => {
    let s = 0;
    for (const [i, w] of used) {
      const v = value(winds[i]);
      if (v == null) return near ? value(near) ?? null : null;
      s += w * v;
    }
    return s;
  };
  let direction = near?.fromDeg ?? null;
  if (used.every(([i]) => winds[i].fromDeg != null)) {
    let u = 0;
    let v = 0;
    for (const [i, w] of used) {
      const speed = winds[i].speedMs ?? 0;
      const rad = (winds[i].fromDeg * Math.PI) / 180;
      u += w * speed * Math.sin(rad);
      v += w * speed * Math.cos(rad);
    }
    if (Math.abs(u) > 1e-9 || Math.abs(v) > 1e-9) {
      const deg = (Math.atan2(u, v) * 180) / Math.PI;
      direction = deg < 0 ? deg + 360 : deg;
    }
  }
  const logVis = blend((x) => (x.visM == null ? null : Math.log(Math.max(x.visM, 1))));
  const visM = logVis == null ? null : Math.exp(logVis);
  const rainMm = blend((x) => x.rainMm);
  let other = near?.other ?? null;
  if (near?.storm != null) {
    let light = near.storm;
    if (near.hail === true) light = "red";
    if (rainMm != null && rainMm >= 4) light = worse(light, "amber");
    if (visM != null) light = worse(light, visM < 500 ? "red" : visM <= 1000 ? "amber" : "green");
    other = light;
  }
  return { speedMs: blend((x) => x.speedMs), gustMs: blend((x) => x.gustMs), fromDeg: direction, other, visM, storm: near?.storm ?? null, rainMm, hail: near?.hail ?? null };
}
