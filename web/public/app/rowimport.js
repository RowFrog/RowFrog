// Import a row (RowTrack.swift, RowImport.swift): a GPX, TCX or FIT file
// from CrewNerd, Garmin Connect, Strava and other apps becomes a route that
// plans and edits like one drawn by hand, with the track as it was rowed and
// the pace the crew really rowed. Read in the browser only. Kept free of the
// page so Node can test it.

import { distanceM, cellAt } from "./lake.js";

/** Slower than this (8:20 per 500 m) the boat is taken to stand still. */
export const STOPPED_MS = 1.0;
/** Faster than this between two points is a GPS jump, not rowing. */
export const JUMP_MS = 12.0;

// ---- Reading files --------------------------------------------------------------------

/** The file's points [{ lat, lon, time }]: FIT by its header, else GPX or TCX by their XML. */
export function readTrack(buffer) {
  const bytes = new Uint8Array(buffer);
  const points = isFIT(bytes) ? fitPoints(bytes) : xmlPoints(new TextDecoder().decode(bytes));
  if (points.length < 2) throw new Error("no points");
  return points;
}

export const isFIT = (bytes) => bytes.length >= 12 && String.fromCharCode(...bytes.slice(8, 12)) === ".FIT";

const time = (text) => {
  const ms = Date.parse(text);
  return Number.isNaN(ms) ? null : ms;
};

/** GPX `trkpt` (or `rtept` without a track) and TCX `Trackpoint`, with or without a namespace prefix. */
export function xmlPoints(xml) {
  const tag = (name) => `(?:[\\w-]+:)?${name}`;
  const attr = (attrs, name) => {
    const m = attrs.match(new RegExp(`\\b${name}\\s*=\\s*["']([^"']+)["']`));
    return m ? Number(m[1]) : NaN;
  };
  const child = (body, name) => body.match(new RegExp(`<${tag(name)}>\\s*([^<]*?)\\s*</${tag(name)}>`))?.[1];
  const ok = (lat, lon) => Number.isFinite(lat) && Number.isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180;
  const gpx = (name) => {
    const out = [];
    const re = new RegExp(`<${tag(name)}\\b([^>]*?)(?:/>|>([\\s\\S]*?)</${tag(name)}>)`, "g");
    for (const m of xml.matchAll(re)) {
      const lat = attr(m[1], "lat");
      const lon = attr(m[1], "lon");
      if (ok(lat, lon)) out.push({ lat, lon, time: m[2] ? time(child(m[2], "time")) : null });
    }
    return out;
  };
  const track = gpx("trkpt");
  if (track.length) return track;
  const tcx = [];
  for (const m of xml.matchAll(new RegExp(`<${tag("Trackpoint")}>([\\s\\S]*?)</${tag("Trackpoint")}>`, "g"))) {
    const lat = Number(child(m[1], "LatitudeDegrees"));
    const lon = Number(child(m[1], "LongitudeDegrees"));
    if (child(m[1], "LatitudeDegrees") != null && ok(lat, lon)) tcx.push({ lat, lon, time: time(child(m[1], "Time")) });
  }
  return tcx.length ? tcx : gpx("rtept");
}

/** FIT times count seconds from 1989-12-31 00:00 UTC. */
const FIT_EPOCH = Date.UTC(1989, 11, 31);
const RECORD = 20;

/** The positions and times of a FIT file's record messages (Garmin's binary activity format). */
export function fitPoints(data) {
  const headerSize = data[0];
  const dataSize = data[4] | (data[5] << 8) | (data[6] << 16) | (data[7] * 2 ** 24);
  const end = Math.min(headerSize + dataSize, data.length);
  const uint = (at, size, bigEndian) => {
    if (size > 4 || at + size > data.length) return null;
    let value = 0;
    for (let k = 0; k < size; k++) value = value * 256 + data[at + (bigEndian ? k : size - 1 - k)];
    return value;
  };
  const signed = (v) => (v >= 2 ** 31 ? v - 2 ** 32 : v);
  const definitions = new Map();
  const points = [];
  let lastTimestamp = null;
  let i = headerSize;
  while (i < end) {
    const header = data[i++];
    if ((header & 0x80) === 0 && (header & 0x40) !== 0) {
      // Definition message: which fields the data messages of this local type carry.
      if (i + 5 > end) break;
      const bigEndian = data[i + 1] === 1;
      const global = uint(i + 2, 2, bigEndian) ?? 0;
      const count = data[i + 4];
      i += 5;
      if (i + count * 3 > end) break;
      const fields = Array.from({ length: count }, (_, k) => ({ number: data[i + k * 3], size: data[i + k * 3 + 1] }));
      i += count * 3;
      let developerBytes = 0;
      if (header & 0x20) {
        if (i >= end) break;
        const devCount = data[i++];
        if (i + devCount * 3 > end) break;
        for (let k = 0; k < devCount; k++) developerBytes += data[i + k * 3 + 1];
        i += devCount * 3;
      }
      definitions.set(header & 0x0f, { global, bigEndian, fields, developerBytes });
    } else {
      // Data message, with a normal header or a compressed timestamp header.
      const compressed = (header & 0x80) !== 0;
      const definition = definitions.get(compressed ? (header >> 5) & 0x03 : header & 0x0f);
      // Without its definition the message's length is unknown: keep what was read.
      if (!definition) break;
      let lat = null;
      let lon = null;
      let timestamp = null;
      if (compressed && lastTimestamp != null) {
        const offset = header & 0x1f;
        timestamp = (lastTimestamp - (lastTimestamp % 32)) + offset;
        if (offset < lastTimestamp % 32) timestamp += 32;
      }
      for (const field of definition.fields) {
        if (i + field.size > end) break;
        if (field.number === 253 && field.size === 4) timestamp = uint(i, 4, definition.bigEndian);
        else if (definition.global === RECORD && field.size === 4 && field.number === 0) lat = signed(uint(i, 4, definition.bigEndian));
        else if (definition.global === RECORD && field.size === 4 && field.number === 1) lon = signed(uint(i, 4, definition.bigEndian));
        i += field.size;
      }
      i += definition.developerBytes;
      if (timestamp != null && timestamp !== 0xffffffff) lastTimestamp = timestamp;
      if (definition.global === RECORD && lat != null && lon != null && lat !== 0x7fffffff && lon !== 0x7fffffff) {
        points.push({ lat: semicircles(lat), lon: semicircles(lon), time: timestamp != null ? FIT_EPOCH + timestamp * 1000 : null });
      }
    }
  }
  return points;
}

/** FIT positions are in semicircles: 2^31 of them make 180°. */
export const semicircles = (v) => (v * 180) / 2 ** 31;

// ---- The track ------------------------------------------------------------------------

export function trackDistance(points) {
  let d = 0;
  for (let k = 1; k < points.length; k++) d += distanceM(points[k - 1], points[k]);
  return d;
}

/** Without GPS jumps and without points closer than 2 m to the one before. */
export function cleaned(points) {
  const out = [];
  for (const p of points) {
    const last = out[out.length - 1];
    if (!last) {
      out.push(p);
      continue;
    }
    const d = distanceM(last, p);
    if (d < 2) continue;
    if (last.time != null && p.time != null && p.time > last.time && d / ((p.time - last.time) / 1000) > JUMP_MS) continue;
    out.push(p);
  }
  return out;
}

/** Seconds per 500 m while the boat moved; stops leave out the stretches slower than STOPPED_MS. Null without times. */
export function paceSecondsPer500(points) {
  let metres = 0;
  let seconds = 0;
  for (let k = 1; k < points.length; k++) {
    const a = points[k - 1];
    const b = points[k];
    if (a.time == null || b.time == null) continue;
    const dt = (b.time - a.time) / 1000;
    const d = distanceM(a, b);
    if (dt <= 0 || d / dt < STOPPED_MS) continue;
    metres += d;
    seconds += dt;
  }
  return metres >= 200 ? (seconds / metres) * 500 : null;
}

/** The pace route planning goes on with: in 5-second steps, 1:30 to 4:00 (RouteImport.usePace). */
export const plannedPace = (secondsPer500) => Math.min(Math.max(Math.round(secondsPer500 / 5) * 5, 90), 240);

/** The share of the track's points on the lake's water cells. */
export function shareOnWater(points, grid) {
  if (!points.length) return 0;
  const step = Math.max(Math.floor(points.length / 200), 1);
  let on = 0;
  let all = 0;
  for (let k = 0; k < points.length; k += step) {
    all++;
    if (cellAt(grid, points[k]) != null) on++;
  }
  return on / all;
}

// ---- From a track to a route (RouteImport) ----------------------------------------------------

const TOLERANCE_M = 25;
const MAX_TURNING_POINTS = 25;
const POINT_SPACING_M = 100;
const TRACK_TOLERANCE_M = 4;
const MAX_TRACK_POINTS = 1500;
const LAUNCH_SNAP_M = 200;
const BACK_AT_START_M = 150;
const RETRACE_SHARE = 0.8;
const RETRACE_M = 75;
export const SHORTEST_M = 200;

/** Metres east and north of the first point. */
function local(points) {
  const origin = points[0];
  const k = Math.cos((origin.lat * Math.PI) / 180) * 111320;
  return points.map((p) => [(p.lon - origin.lon) * k, (p.lat - origin.lat) * 110540]);
}

function segmentDistance(p, a, b) {
  const ab = [b[0] - a[0], b[1] - a[1]];
  const length = ab[0] ** 2 + ab[1] ** 2;
  if (!length) return Math.hypot(p[0] - a[0], p[1] - a[1]);
  const t = Math.min(Math.max(((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / length, 0), 1);
  return Math.hypot(p[0] - (a[0] + ab[0] * t), p[1] - (a[1] + ab[1] * t));
}

/** Douglas–Peucker: keeps the points the line strays furthest from, until none of the others is more than `tolerance` away. */
export function simplify(points, tolerance) {
  if (points.length <= 2) return points;
  const xy = local(points);
  const keep = new Array(points.length).fill(false);
  keep[0] = keep[points.length - 1] = true;
  const stack = [[0, points.length - 1]];
  while (stack.length) {
    const [a, b] = stack.pop();
    if (b <= a + 1) continue;
    let worst = a;
    let worstD = 0;
    for (let k = a + 1; k < b; k++) {
      const d = segmentDistance(xy[k], xy[a], xy[b]);
      if (d > worstD) {
        worst = k;
        worstD = d;
      }
    }
    if (worstD > tolerance) {
      keep[worst] = true;
      stack.push([a, worst], [worst, b]);
    }
  }
  return points.filter((_, k) => keep[k]);
}

function thinned(points, tolerance, count) {
  let t = tolerance;
  let out = simplify(points, t);
  while (out.length > count) {
    t *= 1.5;
    out = simplify(points, t);
  }
  return out;
}

/** The turning points, fewer the longer the row, never more than 25. */
export function turningPoints(points) {
  const thin = thinned(points, TOLERANCE_M, MAX_TURNING_POINTS);
  if (thin.length <= 2) return thin;
  const last = thin[thin.length - 1];
  const out = [thin[0]];
  for (const p of thin.slice(1, -1)) {
    if (distanceM(p, out[out.length - 1]) >= POINT_SPACING_M && distanceM(p, last) >= POINT_SPACING_M) out.push(p);
  }
  out.push(last);
  return out;
}

/** The point furthest from the start, where an out-and-back row turned. */
function farthest(start, points) {
  let best = -1;
  let bestD = -1;
  points.forEach((p, k) => {
    const d = distanceM(p, start);
    if (d > bestD) {
      best = k;
      bestD = d;
    }
  });
  return best < 0 ? null : best;
}

/** Whether the way back from `turn` runs along the way out. */
function retraces(points, turn) {
  if (turn <= 0 || turn >= points.length - 1) return false;
  const xy = local(points);
  const out = xy.slice(0, turn + 1);
  const back = xy.slice(turn);
  const near = back.filter((p) => out.some((a, k) => k > 0 && segmentDistance(p, out[k - 1], a) <= RETRACE_M));
  return near.length / back.length >= RETRACE_SHARE;
}

const plain = ({ lat, lon }) => ({ lat, lon });

/**
 * The route for a rowed track: it starts at the club when the row started
 * near its launch point, rows out and back or as a loop when the row did,
 * and keeps the track for the map. Null for rows under 200 m.
 */
export function routeFromTrack(points, launchPoints) {
  const clean = cleaned(points);
  if (clean.length < 2 || trackDistance(clean) < SHORTEST_M) return null;
  const coordinates = clean.map(plain);
  const first = coordinates[0];
  const last = coordinates[coordinates.length - 1];
  const launch = launchPoints.reduce((best, l) => (!best || distanceM(l, first) < distanceM(best, first) ? l : best), null);
  if (launch && distanceM(launch, first) <= LAUNCH_SNAP_M) coordinates[0] = plain(launch);
  const start = coordinates[0];
  const backAtStart = distanceM(start, last) <= BACK_AT_START_M;
  let outAndBack = false;
  let turning;
  const far = backAtStart ? farthest(start, coordinates) : null;
  if (far != null && retraces(coordinates, far)) {
    outAndBack = true;
    turning = turningPoints(coordinates.slice(0, far + 1));
  } else {
    turning = turningPoints(coordinates);
    if (backAtStart && turning.length >= 3) {
      // A loop ends exactly at the start.
      turning[turning.length - 1] = start;
      if (turning.length < 4) {
        // Start, one point, start: that is rowing out and back.
        turning = turning.slice(0, -1);
        outAndBack = true;
      }
    }
  }
  return {
    points: turning, outAndBack, track: thinned(coordinates, TRACK_TOLERANCE_M, MAX_TRACK_POINTS),
    rowedAt: clean[0].time != null ? new Date(clean[0].time).toISOString() : null, distanceM: trackDistance(clean),
    pace: paceSecondsPer500(clean),
  };
}
