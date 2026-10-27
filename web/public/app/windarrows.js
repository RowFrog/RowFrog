// Wind arrows on an even grid, as the lake map and the satellite picture draw
// them (WindArrows in LakeView.swift): worked out between the lake's forecast
// points, more of them as the view zooms in, the same size on screen, and on
// land the weather map's own wind, faded in from the lake's near the shore.

/** Screen pixels between arrows: more arrows as the view zooms in, fewer out. */
export const SPACING = 60;
/** Over this much land past the shore the lake's wind fades into the land's, so the two forecasts meet without a step. */
export const BLEND_M = 1000;

/** Arrow length on screen: longer in stronger wind. */
export const arrowLength = (speedMs) => 14 + Math.min(Math.max(speedMs, 0), 15) * 1.6;

/**
 * The wind at `p` from the forecast points `samples` ({x, y, towardDeg,
 * speedMs}), weighted by distance (nearer counts more), averaged as east and
 * north parts so opposite directions don't add up to a wrong one.
 */
export function windFrom(samples, [x, y]) {
  if (!samples.length) return null;
  let east = 0;
  let north = 0;
  let speed = 0;
  let total = 0;
  for (const s of samples) {
    const w = 1 / Math.max((s.x - x) ** 2 + (s.y - y) ** 2, 1);
    const r = (s.towardDeg * Math.PI) / 180;
    east += Math.sin(r) * w;
    north += Math.cos(r) * w;
    speed += s.speedMs * w;
    total += w;
  }
  return { towardDeg: ((Math.atan2(east, north) * 180) / Math.PI + 360) % 360, speedMs: speed / total };
}

/** `a` and `b` mixed, `t` of the way to `b`: directions as east and north parts, speeds in between. */
export function mix(a, b, t) {
  const ra = (a.towardDeg * Math.PI) / 180;
  const rb = (b.towardDeg * Math.PI) / 180;
  const east = Math.sin(ra) * (1 - t) + Math.sin(rb) * t;
  const north = Math.cos(ra) * (1 - t) + Math.cos(rb) * t;
  const toward = east === 0 && north === 0 ? b.towardDeg : (Math.atan2(east, north) * 180) / Math.PI;
  return { towardDeg: (toward + 360) % 360, speedMs: a.speedMs * (1 - t) + b.speedMs * t };
}

/** The shore as line pieces, to tell how far a point on land lies from it. */
export function shoreOf(rings) {
  const segments = [];
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const ring of rings) {
    ring.forEach((a, i) => {
      segments.push([a, ring[(i + 1) % ring.length]]);
      minX = Math.min(minX, a[0]);
      minY = Math.min(minY, a[1]);
      maxX = Math.max(maxX, a[0]);
      maxY = Math.max(maxY, a[1]);
    });
  }
  return { segments, bounds: [minX, minY, maxX, maxY] };
}

/** How far `p` is from the shore, or null when farther than `limit`. */
export function shoreDistance(shore, [x, y], limit) {
  const [x0, y0, x1, y1] = shore.bounds;
  if (x < x0 - limit || x > x1 + limit || y < y0 - limit || y > y1 + limit) return null;
  let best = limit * limit;
  let found = false;
  for (const [a, b] of shore.segments) {
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const length = dx * dx + dy * dy;
    const t = length > 0 ? Math.min(Math.max(((x - a[0]) * dx + (y - a[1]) * dy) / length, 0), 1) : 0;
    const d = (a[0] + t * dx - x) ** 2 + (a[1] + t * dy - y) ** 2;
    if (d <= best) {
      best = d;
      found = true;
    }
  }
  return found ? Math.sqrt(best) : null;
}

/** Even-odd test of a point against rings in the same coordinates. */
export function inside(rings, [x, y]) {
  let within = false;
  for (const ring of rings) {
    for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      const [xi, yi] = ring[i];
      const [xj, yj] = ring[j];
      if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) within = !within;
    }
  }
  return within;
}

/**
 * The arrows in `area` ([x0, y0, x1, y1]), `spacing` apart and fixed to the
 * drawing's coordinates, so redraws agree; every other row is shifted by
 * half, so the arrows don't line up in columns. On the water (`rings`) the
 * wind comes from the lake's forecast points, on land from `land` (the
 * weather map's forecast); without it, land gets no arrows. Within `blend` of
 * the shore the land's wind fades in from the lake's.
 */
export function windArrows({ area, spacing, rings, samples, land = null, blend = 0 }) {
  const [x0, y0, x1, y1] = area;
  if (!samples.length || !(spacing > 0) || !(x1 > x0) || !(y1 > y0)) return [];
  const shore = land && blend > 0 ? shoreOf(rings) : null;
  const out = [];
  for (let y = Math.floor(y0 / spacing) * spacing + spacing / 2; y < y1; y += spacing) {
    const shift = Math.floor(y / spacing) % 2 === 0 ? 0 : spacing / 2;
    for (let x = Math.floor((x0 - shift) / spacing) * spacing + shift + spacing / 2; x < x1; x += spacing) {
      const p = [x, y];
      const water = inside(rings, p);
      let wind;
      if (water) wind = windFrom(samples, p);
      else {
        wind = land?.(p) ?? null;
        const d = wind && shore ? shoreDistance(shore, p, blend) : null;
        if (d != null) wind = mix(windFrom(samples, p), wind, d / blend);
      }
      if (wind) out.push({ x, y, towardDeg: wind.towardDeg, speedMs: wind.speedMs, ashore: !water });
    }
  }
  return out;
}

/** The arrow's line and head as [from, to] pieces in screen pixels. */
export function arrowLines(x, y, towardDeg, length) {
  const r = (towardDeg * Math.PI) / 180;
  const dx = Math.sin(r);
  const dy = -Math.cos(r);
  const tip = [x + (dx * length) / 2, y + (dy * length) / 2];
  const lines = [[[x - (dx * length) / 2, y - (dy * length) / 2], tip]];
  for (const side of [-1, 1]) {
    const a = r + Math.PI + side * 0.5;
    lines.push([tip, [tip[0] + Math.sin(a) * length * 0.35, tip[1] - Math.cos(a) * length * 0.35]]);
  }
  return lines;
}
