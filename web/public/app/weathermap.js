// The weather maps (WeatherMap.swift, DetailMapCard.swift): DWD's ICON-D2
// model cut into tiles by the publish job (maps/index, maps/<tile>/<value>),
// and lightning, UV and fog live from DWD's and EUMETSAT's map servers.

import { t, num } from "./i18n.js";
import { API, key } from "./logic.js";
import { store, h, dayTime, dayLabel, wind, windNumber, windUnit, temperature, degrees, distance, distanceNumber, rain, rainNumber, loadLeaflet } from "./shared.js";

const HOUR = 3600 * 1000;
const DWD_WMS = "https://maps.dwd.de/geoserver/dwd/wms";
const EUMETSAT_WMS = "https://view.eumetsat.int/geoserver/ows";

const ramp = (stops) => stops.map(([value, rgb, a]) => ({ value, r: (rgb >> 16) & 255, g: (rgb >> 8) & 255, b: rgb & 255, a }));

/** The values the weather map can show, as WeatherMapLayer in the app. */
export const LAYERS = {
  wind: {
    title: key("Wind"), icon: "wind", model: "wind", span: 50, links: "hour",
    palette: ramp([[0, 0xBFE6F5, 0.15], [2, 0x9FD9E8, 0.35], [4, 0x7FD3A2, 0.5], [6, 0xD8E05A, 0.6], [8, 0xF5B341, 0.65], [10, 0xF07C2E, 0.7], [13, 0xE0442B, 0.75], [17, 0xB0306E, 0.8], [24, 0x6A2C8F, 0.85]]),
    legend: [0, 4, 8, 13, 17, 24],
  },
  gust: { title: key("Gusts"), icon: "wind", model: "gust", span: 50, links: "hour" },
  temperature: {
    title: key("Air temperature"), icon: "thermometer", model: "temperature", span: 50, links: "hour",
    palette: ramp([[-20, 0x5B2A86, 0.75], [-10, 0x2F5DD8, 0.7], [0, 0x8EC5F2, 0.6], [5, 0x7FD3B8, 0.55], [10, 0x9BD565, 0.55], [15, 0xE8E05A, 0.6], [20, 0xF5B341, 0.62], [25, 0xF07C2E, 0.66], [30, 0xE0442B, 0.7], [38, 0x9E1B3B, 0.75]]),
    legend: [-10, 0, 10, 20, 30],
  },
  feelsLike: { title: key("Feels like"), icon: "person-standing", model: "feelsLike", span: 50, links: "hour" },
  humidity: {
    title: key("Humidity"), icon: "droplets", model: "humidity", span: 50, links: "hour",
    palette: ramp([[20, 0xD9A55B, 0.6], [40, 0xEBD9A0, 0.45], [60, 0xBFE0D8, 0.4], [80, 0x6FB7E0, 0.55], [100, 0x2F6FC9, 0.65]]),
    legend: [20, 40, 60, 80, 100],
  },
  pressure: {
    title: key("Air pressure"), icon: "gauge", model: "pressure", span: 50, links: "hour",
    palette: ramp([[975, 0x6A2C8F, 0.65], [990, 0x3D5FD0, 0.6], [1005, 0x7FC3E8, 0.5], [1013, 0xBFE6C8, 0.45], [1020, 0xE8E05A, 0.5], [1030, 0xF5A341, 0.6], [1040, 0xE0602B, 0.65]]),
    legend: [990, 1005, 1013, 1020, 1030],
  },
  visibility: {
    title: key("Visibility"), icon: "binoculars", model: "visibility", span: 50, links: "hour",
    // Fog stands out; good visibility leaves the map clear.
    palette: ramp([[0, 0xF2F2F2, 0.9], [0.5, 0xE0E0E6, 0.85], [1, 0xC8C8D4, 0.75], [3, 0xB4B8C8, 0.5], [6, 0xA8B4C8, 0.25], [10, 0xA8B4C8, 0]]),
    legend: [0, 1, 3, 6, 10], note: key("Grey where fog or low cloud brings the visibility down."),
  },
  rain: {
    title: key("Rain forecast"), icon: "cloud-rain", model: "rain", span: 120, links: "hour",
    palette: ramp([[0, 0x9FD9F5, 0], [0.1, 0x9FD9F5, 0.35], [0.5, 0x5DB6EC, 0.55], [1, 0x2F7FD8, 0.65], [2, 0x2F9E5C, 0.7], [4, 0xE8D23A, 0.75], [8, 0xF07C2E, 0.8], [15, 0xD8302B, 0.85], [25, 0x9E1B6B, 0.9]]),
    legend: [0, 5, 10, 15, 25], note: key("Rain an hour from the weather model; after the first day, the average of every 3 hours."),
  },
  uv: {
    title: key("UV index"), icon: "sun", span: 50, links: "day", live: [DWD_WMS, "dwd:UVIndex"],
    note: key("The day's highest UV index under the expected clouds."), credit: key("Deutscher Wetterdienst (DWD), CC BY 4.0"),
  },
  lightning: {
    title: key("Lightning"), icon: "cloud-lightning", span: 120, links: "none", live: [DWD_WMS, "dwd:Blitzdichte"],
    note: key("Lightning in the last 5 minutes, for the past hour."), credit: key("Deutscher Wetterdienst (DWD), CC BY 4.0"),
  },
  fog: {
    title: key("Fog and low cloud"), icon: "cloud-fog", span: 50, links: "none", live: [EUMETSAT_WMS, "msg_fes:rgb_fog"],
    note: key("Fog and low cloud from the satellite, for the past 3 hours."), credit: key("Satellite: EUMETSAT, Meteosat"),
  },
};
LAYERS.gust.palette = LAYERS.wind.palette;
LAYERS.gust.legend = LAYERS.wind.legend;
LAYERS.feelsLike.palette = LAYERS.temperature.palette;
LAYERS.feelsLike.legend = LAYERS.temperature.legend;
for (const [id, layer] of Object.entries(LAYERS)) {
  layer.id = id;
  layer.credit ??= key("Deutscher Wetterdienst (DWD), ICON-D2, CC BY 4.0");
}

/** The map a value's page opens: the rain forecast for rain, else the value's own. */
export function layerFor(condition) {
  return {
    wind: "wind", temperature: "temperature", feelsLike: "feelsLike", humidity: "humidity", pressure: "pressure", visibility: "visibility",
    cloudCover: "visibility", uvIndex: "uv", thunderstorm: "lightning", precipitation: "rain",
  }[condition] ?? null;
}

/** Settings › Club pages › Maps start: half or double the usual area. */
export const MAP_ZOOMS = { close: 0.5, normal: 1, wide: 2 };
const startKm = (layer) => layer.span * (MAP_ZOOMS[store.mapZoom] ?? 1);

/** A value in the user's units, with or without the unit. */
export function valueText(layer, value, unit = true) {
  switch (layer.id) {
    case "temperature": case "feelsLike": return unit ? temperature(value) : degrees(value);
    case "wind": case "gust": return unit ? wind(value) : windNumber(value);
    case "humidity": return unit ? `${num(value)} %` : num(value);
    case "pressure": return unit ? `${num(value)} hPa` : num(value);
    case "visibility": return unit ? distance(value * 1000) : distanceNumber(value * 1000);
    case "rain": return unit ? rain(value) + t("/h") : rainNumber(value);
    default: return num(value);
  }
}

function unitSymbol(layer) {
  return { temperature: "°C", feelsLike: "°C", wind: windUnit(), gust: windUnit(), humidity: "%", pressure: "hPa", visibility: "km", rain: `mm${t("/h")}` }[layer.id] ?? "";
}

function stopAt(palette, value) {
  const first = palette[0];
  const last = palette[palette.length - 1];
  if (value <= first.value) return first;
  if (value >= last.value) return last;
  const i = palette.findIndex((s) => s.value >= value);
  const lo = palette[i - 1];
  const hi = palette[i];
  const f = (value - lo.value) / (hi.value - lo.value);
  const mix = (a, b) => a + (b - a) * f;
  return { r: mix(lo.r, hi.r), g: mix(lo.g, hi.g), b: mix(lo.b, hi.b), a: mix(lo.a, hi.a) };
}

// ---- The model maps ------------------------------------------------------------------

const cache = { index: null, at: 0, grids: new Map(), failed: new Set(), images: new Map() };

export async function loadIndex() {
  if (cache.index && Date.now() - cache.at < 30 * 60 * 1000) return cache.index;
  const response = await fetch(`${API}/maps/index`, { cache: "no-store" });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  cache.index = await response.json();
  cache.at = Date.now();
  return cache.index;
}

const gridKey = (index, tile, value) => `${index.run}|${tile}|${value}`;

/** One value of one tile for every hour, as bytes (raw deflate, as Apple's zlib packing writes it). */
async function loadGrid(index, tile, value) {
  const key = gridKey(index, tile, value);
  if (cache.grids.has(key) || cache.failed.has(key)) return cache.grids.get(key);
  try {
    const response = await fetch(`${API}/maps/${tile}/${value}`, { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const stream = response.body.pipeThrough(new DecompressionStream("deflate-raw"));
    const bytes = new Uint8Array(await new Response(stream).arrayBuffer());
    const arrows = value === "windDirection";
    const grid = {
      columns: arrows ? index.columns / index.arrowStep : index.columns,
      rows: arrows ? index.rows / index.arrowStep : index.rows,
      encoding: index.values[value], bytes,
    };
    cache.grids.set(key, grid);
    // Older runs' files are not needed any more.
    for (const old of cache.grids.keys()) if (!old.startsWith(`${index.run}|`)) cache.grids.delete(old);
    return grid;
  } catch {
    cache.failed.add(key);
    return null;
  }
}

export function gridValue(grid, hour, row, column) {
  const i = hour * grid.columns * grid.rows + row * grid.columns + column;
  if (i >= grid.bytes.length || grid.bytes[i] === 255) return null;
  return grid.encoding.offset + grid.encoding.scale * grid.bytes[i];
}

const mercY = (lat) => Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360));

/** The pixel at a place: column from the west, row from the north (rows are even in mercator). */
export function pixel(tile, { lat, lon }, columns, rows) {
  if (!(lon > tile.west && lon < tile.east && lat > tile.south && lat < tile.north)) return null;
  const column = Math.floor(((lon - tile.west) / (tile.east - tile.west)) * columns);
  const row = Math.floor(((mercY(tile.north) - mercY(lat)) / (mercY(tile.north) - mercY(tile.south))) * rows);
  return { row: Math.min(Math.max(row, 0), rows - 1), column: Math.min(Math.max(column, 0), columns - 1) };
}

const contains = (tile, p) => p.lon > tile.west && p.lon < tile.east && p.lat > tile.south && p.lat < tile.north;
const holds = (tile, a) => tile.west <= a.west + 1e-6 && tile.east >= a.east - 1e-6 && tile.south <= a.south + 1e-6 && tile.north >= a.north - 1e-6;
const centreDistance = (tile, p) => Math.hypot((tile.west + tile.east) / 2 - p.lon, (tile.south + tile.north) / 2 - p.lat);

/** The tile a place lies most central in. */
export function tileFor(index, p) {
  const found = index.tiles.filter((x) => contains(x, p));
  return found.length ? found.reduce((a, b) => (centreDistance(b, p) < centreDistance(a, p) ? b : a)) : null;
}

/**
 * The tiles that draw a visible area, each with the 1.5° × 1° patches it
 * draws: tiles overlap by half, so each patch goes to the tile holding it
 * whole whose centre is nearest; at most `limit` tiles, nearest the middle.
 */
export function cover(index, area, limit = 9) {
  const mid = { lat: (area.south + area.north) / 2, lon: (area.west + area.east) / 2 };
  const west = Math.max(area.west, mid.lon - 7.5);
  const east = Math.min(area.east, mid.lon + 7.5);
  const south = Math.max(area.south, mid.lat - 5);
  const north = Math.min(area.north, mid.lat + 5);
  const patches = new Map();
  for (let lon = Math.floor(west / 1.5) * 1.5; lon < east; lon += 1.5) {
    for (let lat = Math.floor(south); lat < north; lat += 1) {
      const patch = { west: lon, east: lon + 1.5, south: lat, north: lat + 1 };
      const centre = { lat: lat + 0.5, lon: lon + 0.75 };
      const fits = index.tiles.filter((x) => holds(x, patch));
      if (!fits.length) continue;
      const best = fits.reduce((a, b) => (centreDistance(b, centre) < centreDistance(a, centre) ? b : a));
      if (!patches.has(best.id)) patches.set(best.id, []);
      patches.get(best.id).push(patch);
    }
  }
  return index.tiles.filter((x) => patches.has(x.id)).sort((a, b) => centreDistance(a, mid) - centreDistance(b, mid))
    .slice(0, limit).map((tile) => ({ tile, patches: patches.get(tile.id) }));
}

/** The hour coloured, one pixel per grid point; the canvas smooths it when drawn larger. */
function hourImage(layer, grid, hour, key) {
  const id = `${key}|${hour}`;
  if (cache.images.has(id)) return cache.images.get(id);
  const { columns, rows, encoding, bytes } = grid;
  const table = Array.from({ length: 256 }, (_, byte) => {
    if (byte === 255) return [0, 0, 0, 0];
    const s = stopAt(layer.palette, encoding.offset + encoding.scale * byte);
    return [s.r, s.g, s.b, s.a * 255];
  });
  const canvas = document.createElement("canvas");
  canvas.width = columns;
  canvas.height = rows;
  const ctx = canvas.getContext("2d");
  const data = ctx.createImageData(columns, rows);
  const start = hour * columns * rows;
  for (let i = 0; i < columns * rows; i++) data.data.set(table[bytes[start + i] ?? 255], i * 4);
  ctx.putImageData(data, 0, 0);
  if (cache.images.size > 400) cache.images.clear();
  cache.images.set(id, canvas);
  return canvas;
}

/** Wind at a share of a tile's width and height, blended between the grid points as east and north parts. */
function windSample(directions, speeds, hour, x, y) {
  const blend = (grid, parts) => {
    const gx = x * grid.columns - 0.5;
    const gy = y * grid.rows - 0.5;
    const c0 = Math.floor(gx);
    const r0 = Math.floor(gy);
    const tx = gx - c0;
    const ty = gy - r0;
    let s0 = 0;
    let s1 = 0;
    let total = 0;
    for (const [dr, wy] of [[0, 1 - ty], [1, ty]]) {
      for (const [dc, wx] of [[0, 1 - tx], [1, tx]]) {
        const r = Math.min(Math.max(r0 + dr, 0), grid.rows - 1);
        const c = Math.min(Math.max(c0 + dc, 0), grid.columns - 1);
        const v = gridValue(grid, hour, r, c);
        if (v == null) continue;
        const w = wx * wy;
        const p = parts(v);
        s0 += w * p[0];
        s1 += w * p[1];
        total += w;
      }
    }
    return total > 0 ? [s0 / total, s1 / total] : null;
  };
  const parts = blend(directions, (from) => {
    const r = ((from + 180) * Math.PI) / 180;
    return [Math.sin(r), Math.cos(r)];
  });
  const speed = blend(speeds, (v) => [v, 0]);
  if (!parts || (parts[0] === 0 && parts[1] === 0) || !speed) return null;
  return { towards: (Math.atan2(parts[0], parts[1]) * 180) / Math.PI, speed: speed[0] };
}

/** The times a layer has maps for: the model run's hours from the hour now on, or the live layer's pictures. */
export function frames(layer, index, now = new Date()) {
  if (layer.model) return (index?.hours ?? []).map((x) => new Date(x)).filter((x) => x > now - HOUR);
  return liveTimes(layer, now).times;
}

function liveTimes(layer, now) {
  const floored = (date, minutes) => new Date(Math.floor(date / (minutes * 60000)) * minutes * 60000);
  if (layer.id === "lightning") {
    const last = floored(now - 10 * 60000, 5);
    return { times: Array.from({ length: 12 }, (_, i) => new Date(last - (55 - i * 5) * 60000)), first: 11 };
  }
  if (layer.id === "fog") {
    const last = floored(now - 25 * 60000, 15);
    return { times: Array.from({ length: 13 }, (_, i) => new Date(last - (180 - i * 15) * 60000)), first: 12 };
  }
  // The day's highest UV index: today and the next two days, as DWD's maps are dated (midnight UTC).
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  return { times: [0, 1, 2].map((i) => new Date(today + i * 86400000)), first: 0 };
}

/** Which frame to show for a time: the nearest hour, or for UV the day the time falls in. */
export function frameIndex(layer, list, at) {
  if (!list.length) return null;
  if (layer.links === "day") {
    let found = null;
    list.forEach((x, i) => { if (x <= at) found = i; });
    if (found != null) return found;
  }
  return list.reduce((best, x, i) => (Math.abs(x - at) < Math.abs(list[best] - at) ? i : best), 0);
}

// ---- The map itself ------------------------------------------------------------------

/**
 * A Leaflet map showing one layer at one frame around the club. Model layers
 * are drawn onto a canvas over the map (tiles clipped to their patches, then
 * the wind arrows); live layers come from the map server as WMS tiles.
 */
export async function weatherMap(el, point, layerId, { interactive = true, onArea } = {}) {
  const L = await loadLeaflet();
  const map = L.map(el, {
    zoomControl: interactive, dragging: interactive, scrollWheelZoom: interactive, doubleClickZoom: interactive, touchZoom: interactive,
    boxZoom: false, keyboard: interactive, zoomAnimation: false, attributionControl: interactive, zoomSnap: 0.25,
  });
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19, referrerPolicy: "strict-origin", attribution: '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>',
  }).addTo(map);
  const canvas = L.DomUtil.create("canvas", "wm-canvas", map.getContainer());
  L.circleMarker([point.lat, point.lon], { radius: 6, color: "#fff", weight: 2, fillColor: "#007aff", fillOpacity: 1, interactive: false }).addTo(map);
  const state = { layer: LAYERS[layerId], at: null, live: null, index: null };

  const area = () => {
    const b = map.getBounds();
    return { west: b.getWest(), east: b.getEast(), south: b.getSouth(), north: b.getNorth() };
  };

  function fit(layer) {
    const km = startKm(layer);
    const dLat = km / 111 / 2;
    const dLon = km / (111 * Math.max(Math.cos((point.lat * Math.PI) / 180), 0.2)) / 2;
    map.fitBounds([[point.lat - dLat, point.lon - dLon], [point.lat + dLat, point.lon + dLon]], { animate: false });
  }

  function draw() {
    const size = map.getSize();
    const ratio = window.devicePixelRatio || 1;
    canvas.width = size.x * ratio;
    canvas.height = size.y * ratio;
    canvas.style.width = `${size.x}px`;
    canvas.style.height = `${size.y}px`;
    const ctx = canvas.getContext("2d");
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    ctx.clearRect(0, 0, size.x, size.y);
    const { layer, at, index } = state;
    if (!layer.model || !index || !at) return;
    const hour = index.hours.findIndex((x) => new Date(x).getTime() === at.getTime());
    if (hour < 0) return;
    const pt = (lat, lon) => map.latLngToContainerPoint([lat, lon]);
    const shown = cover(index, area());
    for (const { tile, patches } of shown) {
      const grid = cache.grids.get(gridKey(index, tile.id, layer.model));
      if (!grid) continue;
      const nw = pt(tile.north, tile.west);
      const se = pt(tile.south, tile.east);
      ctx.save();
      ctx.beginPath();
      for (const p of patches) {
        const a = pt(p.north, p.west);
        const b = pt(p.south, p.east);
        ctx.rect(a.x, a.y, b.x - a.x, b.y - a.y);
      }
      ctx.clip();
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = "high";
      ctx.drawImage(hourImage(layer, grid, hour, gridKey(index, tile.id, layer.model)), nw.x, nw.y, se.x - nw.x, se.y - nw.y);
      if (layer.id === "wind" || layer.id === "gust") {
        const directions = cache.grids.get(gridKey(index, tile.id, "windDirection"));
        if (directions) drawArrows(ctx, directions, grid, hour, nw, se, size);
      }
      ctx.restore();
    }
  }

  /** Arrows on an even grid over the screen, longer in stronger wind, as on the lake map. */
  function drawArrows(ctx, directions, speeds, hour, nw, se, size) {
    const spacing = 60;
    ctx.strokeStyle = "rgba(0, 0, 0, .7)";
    ctx.lineWidth = 2;
    ctx.lineCap = "round";
    ctx.beginPath();
    for (let gx = spacing / 2; gx < size.x; gx += spacing) {
      for (let gy = spacing / 2; gy < size.y; gy += spacing) {
        if (gx < nw.x || gx > se.x || gy < nw.y || gy > se.y) continue;
        const s = windSample(directions, speeds, hour, (gx - nw.x) / (se.x - nw.x), (gy - nw.y) / (se.y - nw.y));
        if (!s || s.speed < 0.5) continue;
        const length = 14 + Math.min(Math.max(s.speed, 0), 15) * 1.6;
        const r = (s.towards * Math.PI) / 180;
        const dx = (Math.sin(r) * length) / 2;
        const dy = (-Math.cos(r) * length) / 2;
        const tip = [gx + dx, gy + dy];
        ctx.moveTo(gx - dx, gy - dy);
        ctx.lineTo(...tip);
        const head = Math.min(length * 0.35, 8);
        for (const side of [-1, 1]) {
          const a = r + Math.PI + side * 0.5;
          ctx.moveTo(...tip);
          ctx.lineTo(tip[0] + Math.sin(a) * head, tip[1] - Math.cos(a) * head);
        }
      }
    }
    ctx.stroke();
  }

  /** Loads the index and each tile's file the area on screen needs, the club's tile first. */
  async function prepare() {
    const { layer } = state;
    if (!layer.model) return;
    const index = await loadIndex();
    state.index = index;
    const ids = cover(index, area()).map((x) => x.tile.id);
    const own = tileFor(index, point)?.id;
    const order = own ? [own, ...ids.filter((x) => x !== own)] : ids;
    const values = layer.id === "wind" || layer.id === "gust" ? [layer.model, "windDirection"] : [layer.model];
    for (const id of order) {
      await Promise.all(values.map((v) => loadGrid(index, id, v)));
      draw();
    }
  }

  function showLive() {
    const { layer, at } = state;
    if (!layer.live) {
      state.live?.remove();
      state.live = null;
      return;
    }
    const params = {
      layers: layer.live[1], format: layer.live[0] === DWD_WMS ? "image/png" : "image/png", transparent: true, version: "1.3.0",
      opacity: 0.75, time: at?.toISOString().replace(".000", ""), attribution: t(layer.credit),
    };
    if (state.live && state.live.wmsParams.layers === layer.live[1]) state.live.setParams({ time: params.time });
    else {
      state.live?.remove();
      state.live = L.tileLayer.wms(layer.live[0], params).addTo(map);
    }
  }

  map.on("move zoom resize", draw);
  map.on("moveend zoomend", () => {
    prepare();
    onArea?.();
  });
  fit(state.layer);
  return {
    map,
    get layer() { return state.layer; },
    get index() { return state.index; },
    async setLayer(id) {
      const changed = state.layer.id !== id;
      state.layer = LAYERS[id];
      if (changed) fit(state.layer);
      showLive();
      draw();
      await prepare();
    },
    show(at) {
      state.at = at;
      if (state.layer.live) showLive();
      draw();
    },
    /** The value at the club in the hour shown. */
    valueAtClub() {
      const { layer, index, at } = state;
      if (!layer.model || !index || !at) return null;
      const tile = tileFor(index, point);
      const grid = tile && cache.grids.get(gridKey(index, tile.id, layer.model));
      const hour = index.hours.findIndex((x) => new Date(x).getTime() === at.getTime());
      const px = tile && pixel(tile, point, index.columns, index.rows);
      if (!grid || hour < 0 || !px) return null;
      const v = gridValue(grid, hour, px.row, px.column);
      return v == null ? null : valueText(layer, v);
    },
    problem() {
      const { layer, index } = state;
      if (!layer.model) return null;
      if (!index) return null;
      const tile = tileFor(index, point);
      if (!tile) return t("No map for this place yet.");
      return cache.failed.has(gridKey(index, tile.id, layer.model)) ? t("The map could not be loaded.") : null;
    },
    prepare,
    remove: () => map.remove(),
  };
}

/** The colours and what they stand for, in the user's units. */
export function colourBar(layer) {
  if (!layer.palette) return "";
  const values = layer.legend;
  const lo = values[0];
  const hi = values[values.length - 1];
  const stops = Array.from({ length: 21 }, (_, i) => {
    const s = stopAt(layer.palette, lo + ((hi - lo) * i) / 20);
    return `rgba(${Math.round(s.r)}, ${Math.round(s.g)}, ${Math.round(s.b)}, ${Math.max(s.a, 0.35)}) ${i * 5}%`;
  });
  return `<div class="colour-bar" aria-label="${h(t("Colours from %@ to %@", valueText(layer, lo), valueText(layer, hi)))}">
    <span class="bar" style="background:linear-gradient(90deg, ${stops.join(", ")})"></span>
    <span class="labels">${values.map((v) => `<small style="left:${((v - lo) / (hi - lo)) * 100}%">${h(valueText(layer, v, false))}</small>`).join("")}</span>
    <small class="unit">${h(unitSymbol(layer))}</small></div>`;
}

/** The label of a frame: the day for UV, else the day and hour. */
export const frameLabel = (layer, at) => (layer.links === "day" ? dayLabel(at) : dayTime(at));

/** The layer menu's rows. */
export const layerOptions = (current) => Object.values(LAYERS).map((l) => `<option value="${l.id}" ${l.id === current ? "selected" : ""}>${h(t(l.title))}</option>`).join("");

