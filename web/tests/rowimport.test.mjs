import { test } from "node:test";
import assert from "node:assert/strict";
import { readTrack, isFIT, plannedPace, paceSecondsPer500, routeFromTrack, SHORTEST_M } from "../public/app/rowimport.js";

const close = (a, b, eps) => assert.ok(Math.abs(a - b) < eps, `${a} ≠ ${b}`);

// A row north from Starnberg at 4 m/s (2:05 per 500 m), one point every 10 s.
const START = { lat: 47.995, lon: 11.345 };
const north = (m) => START.lat + m / 111195;
function line(metres, back = false) {
  const out = [];
  const steps = Math.round(metres / 40);
  for (let k = 0; k <= steps; k++) out.push({ lat: north(k * 40), lon: START.lon, time: k * 10000 });
  if (back) for (let k = steps - 1; k >= 0; k--) out.push({ lat: north(k * 40), lon: START.lon + 0.0001, time: (2 * steps - k) * 10000 });
  return out;
}

test("GPX and TCX points are read with their times", () => {
  const gpx = `<gpx><trk><trkseg>
    <trkpt lat="47.9950" lon="11.3450"><time>2026-10-20T08:00:00Z</time></trkpt>
    <trkpt lat="47.9960" lon="11.3450"><time>2026-10-20T08:00:30Z</time></trkpt></trkseg></trk></gpx>`;
  const points = readTrack(new TextEncoder().encode(gpx).buffer);
  assert.equal(points.length, 2);
  assert.equal(points[1].lat, 47.996);
  assert.equal(points[1].time - points[0].time, 30000);
  const tcx = `<TrainingCenterDatabase><Trackpoint><Time>2026-10-20T08:00:00Z</Time><Position>
    <LatitudeDegrees>47.995</LatitudeDegrees><LongitudeDegrees>11.345</LongitudeDegrees></Position></Trackpoint>
    <Trackpoint><Time>2026-10-20T08:00:10Z</Time><Position><LatitudeDegrees>47.996</LatitudeDegrees>
    <LongitudeDegrees>11.345</LongitudeDegrees></Position></Trackpoint></TrainingCenterDatabase>`;
  assert.equal(readTrack(new TextEncoder().encode(tcx).buffer).length, 2);
  assert.throws(() => readTrack(new TextEncoder().encode("<gpx></gpx>").buffer));
});

test("FIT record messages are read", () => {
  const semi = (deg) => Math.round((deg / 180) * 2 ** 31);
  const body = [];
  const u32 = (v) => [v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255];
  // Definition of local type 0 = record (20): timestamp, lat, lon.
  body.push(0x40, 0, 0, 20, 0, 3, 253, 4, 0x86, 0, 4, 0x85, 1, 4, 0x85);
  for (let k = 0; k < 3; k++) body.push(0x00, ...u32(1_000_000_000 + k * 10), ...u32(semi(47.995 + k * 0.001)), ...u32(semi(11.345)));
  const header = [14, 0x10, 0, 0, ...u32(body.length), 46, 70, 73, 84, 0, 0];
  const bytes = new Uint8Array([...header, ...body, 0, 0]);
  assert.ok(isFIT(bytes));
  const points = readTrack(bytes.buffer);
  assert.equal(points.length, 3);
  close(points[2].lat, 47.997, 1e-6);
  close(points[2].lon, 11.345, 1e-6);
  assert.equal(points[1].time - points[0].time, 10000);
});

test("pace counts the stretches the boat moved", () => {
  const points = line(1000);
  close(paceSecondsPer500(points), 125, 1);
  // A five-minute stop does not slow the pace.
  const stopped = [...points, { ...points.at(-1), lat: points.at(-1).lat + 1e-6, time: points.at(-1).time + 300000 }];
  close(paceSecondsPer500(stopped), 125, 1);
  assert.equal(plannedPace(127), 125);
  assert.equal(plannedPace(60), 90);
  assert.equal(plannedPace(400), 240);
});

test("a row out and back becomes an out-and-back route from the launch point", () => {
  const launch = { lat: START.lat - 0.0005, lon: START.lon };
  const route = routeFromTrack(line(2000, true), [launch, { lat: 48.1, lon: 11.4 }]);
  assert.ok(route.outAndBack);
  assert.deepEqual(route.points[0], launch);
  close(route.points.at(-1).lat, north(2000), 0.001);
  close(route.distanceM, 4000, 50);
  close(route.pace, 125, 2);
  assert.ok(route.track.length >= 2);
});

test("a row one way stays one way; too short a row makes no route", () => {
  const route = routeFromTrack(line(2000), []);
  assert.equal(route.outAndBack, false);
  assert.equal(route.points.length, 2);
  assert.equal(routeFromTrack(line(SHORTEST_M / 2), []), null);
});
