// What the web app works out from the published forecast files, kept free of
// the page so it can be tested with Node (web/tests). The rules follow the
// iPhone app: the light comes from the backend for the default boat (small
// racing boats); the page only picks the hour and greys out green when the
// forecast is out of date.

// globalThis.RF_API lets the browser tests point the page at sample files.
export const API = globalThis.RF_API ?? "https://api.rowfrog.com/v1";

/** After this the forecast counts as out of date (as ClubForecast.staleAfter in the app). */
export const STALE_AFTER_MS = 3 * 3600 * 1000;

export const ZONE = "Europe/Berlin";

/** Marks an English text that the page shows through t(), so the build finds it and adds its German. */
export const key = (english) => english;

export function isStale(forecast, now = new Date()) {
  return now - new Date(forecast.generatedAt) > STALE_AFTER_MS;
}

/** Green turns grey on an old forecast; amber and red still show. */
export function shownLight(light, stale) {
  return stale && light === "green" ? "grey" : light;
}

/** The hour `now` falls in, else the first one. */
export function currentHour(hours, now = new Date()) {
  const t = now.getTime();
  return hours.find((h) => {
    const start = new Date(h.time).getTime();
    return start <= t && t < start + 3600 * 1000;
  }) ?? hours[0];
}

/** The next `count` hours from the current one. */
export function nextHours(hours, now = new Date(), count = 48) {
  const current = currentHour(hours, now);
  const i = Math.max(0, hours.indexOf(current));
  return hours.slice(i, i + count);
}

/** The local date (YYYY-MM-DD) of a time, in the lakes' time zone. */
export function localDay(time, zone = ZONE) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(time));
}

const BEAUFORT = [0.3, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7];

export function beaufort(ms) {
  const i = BEAUFORT.findIndex((limit) => ms < limit);
  return i < 0 ? 12 : i;
}

export const WIND_UNITS = {
  kmh: { label: "km/h", from: (ms) => ms * 3.6 },
  ms: { label: "m/s", from: (ms) => ms },
  kn: { label: "kn", from: (ms) => ms * 1.943844 },
  bft: { label: "Bft", from: (ms) => beaufort(ms) },
};

export function windValue(ms, unit = "ms") {
  if (ms == null) return null;
  return Math.round((WIND_UNITS[unit] ?? WIND_UNITS.ms).from(ms));
}

/** Where the wind comes from, as N, NE, E … */
export function compass(deg) {
  if (deg == null) return "";
  return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(((deg % 360) + 360) % 360 / 45) % 8];
}

/** Lower case, without accents and ß, for the search. */
export function fold(text) {
  return (text ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/ß/g, "ss").toLowerCase();
}

/**
 * Clubs matching every word of the query in their name, short name,
 * abbreviation, address or water, best first (name starts with the query).
 */
export function searchClubs(lakes, query, limit = 40) {
  const words = fold(query).split(/\s+/).filter(Boolean);
  if (!words.length) return [];
  const found = [];
  for (const lake of lakes) {
    for (const club of lake.clubs) {
      const name = fold([club.shortName, club.name, club.abbreviation].join(" "));
      const text = `${name} ${fold(club.address)} ${fold(lake.name)}`;
      if (words.every((w) => text.includes(w))) {
        const starts = name.startsWith(words[0]) || fold(club.shortName).startsWith(words[0]);
        found.push({ club, lake, rank: starts ? 0 : 1 });
      }
    }
  }
  found.sort((a, b) => a.rank - b.rank || (a.club.shortName ?? a.club.name).localeCompare(b.club.shortName ?? b.club.name));
  return found.slice(0, limit).map(({ club, lake }) => ({ club, lake }));
}

/** The town from an address like "Street 6, 82319 Starnberg". */
export function town(address) {
  if (!address) return null;
  const last = address.split(",").pop().trim();
  return last.replace(/^\d{4,5}\s+/, "") || null;
}

const WATER_NEAR = "Water near ";

/** The catalogs didn't name the club's water ("Water near <town>"). */
export function waterUnknown(lakeName) {
  return (lakeName ?? "").startsWith(WATER_NEAR);
}

/**
 * The water and town as the app shows them (Lake.place): "Starnberger See ·
 * Starnberg", or just the town when the water isn't known. `title` turns a
 * "Water near <town>" name into the page's language.
 */
export function place(lakeName, townName, title = (name) => name) {
  const water = waterUnknown(lakeName) && townName ? null : lakeName ? title(lakeName) : null;
  return [water, townName].filter(Boolean).join(" · ");
}

/**
 * For the "twilight" reason, whether the sun rises or sets in the hour and
 * when (ClubForecast.explanation(_:in:)): { kind: "sunrise" | "sunset", time },
 * or null when neither falls inside it.
 */
export function twilight(forecast, hour) {
  const start = new Date(hour.time).getTime();
  const inside = (t) => t >= start && t < start + 3600 * 1000;
  for (const kind of ["sunrise", "sunset"]) {
    const found = (forecast.daylight ?? []).map((d) => new Date(d[kind]).getTime()).find(inside);
    if (found != null) return { kind, time: new Date(found) };
  }
  return null;
}

/** Where the ice picture sits on the satellite picture, in percent of its width and height. */
export function overlayBox(pictureBbox, iceBbox) {
  const [w, s, e, n] = pictureBbox;
  const [iw, is, ie, inn] = iceBbox;
  return {
    left: ((iw - w) / (e - w)) * 100,
    top: ((n - inn) / (n - s)) * 100,
    width: ((ie - iw) / (e - w)) * 100,
    height: ((inn - is) / (n - s)) * 100,
  };
}

// ---- The sky (Sky.swift) -----------------------------------------------------

/** The kind of sky for a WMO weather code, as Sky in the app. */
export function sky(code) {
  switch (code) {
    case 0: return "clear";
    case 1: return "mostlyClear";
    case 2: return "partlyCloudy";
    case 3: return "cloudy";
    case 45: case 48: return "fog";
    case 51: case 53: case 55: return "drizzle";
    case 56: case 57: case 66: case 67: return "freezingRain";
    case 61: case 63: return "rain";
    case 80: case 81: return "showers";
    case 65: case 82: return "heavyRain";
    case 71: case 73: case 75: case 77: case 85: case 86: return "snow";
    case 95: return "thunderstorm";
    case 96: case 99: return "hail";
    default: return "cloudy";
  }
}

/** The English title (the key of its German text). */
export const SKY_TITLES = {
  clear: key("Clear"), mostlyClear: key("Mostly clear"), partlyCloudy: key("Partly cloudy"), cloudy: key("Cloudy"), fog: key("Fog"),
  drizzle: key("Drizzle"), rain: key("Rain"), showers: key("Showers"), heavyRain: key("Heavy rain"), freezingRain: key("Freezing rain"),
  snow: key("Snow"), thunderstorm: key("Thunderstorm"), hail: key("Thunderstorm with hail"),
};

/** What falls from this sky, or null when nothing does. */
export function precipitationKind(kind) {
  return { drizzle: key("Drizzle"), rain: key("Rain"), showers: key("Rain"), heavyRain: key("Rain"), thunderstorm: key("Rain"), freezingRain: key("Freezing rain"), snow: key("Snow"), hail: key("Hail") }[kind] ?? null;
}

/** The icon and its colour class for a sky, by day or by night. */
export function skyIcon(kind, night = false) {
  switch (kind) {
    case "clear": return night ? ["moon-star", "moon"] : ["sun", "sun"];
    case "mostlyClear": return night ? ["moon", "moon"] : ["sun", "sun"];
    case "partlyCloudy": return night ? ["cloud-moon", "moon"] : ["cloud-sun", "sun"];
    case "cloudy": return ["cloud", "cloud"];
    case "fog": return ["cloud-fog", "cloud"];
    case "drizzle": return ["cloud-drizzle", "rain"];
    case "rain": case "showers": return ["cloud-rain", "rain"];
    case "heavyRain": return ["cloud-rain", "rain"];
    case "freezingRain": return ["cloud-hail", "ice"];
    case "snow": return ["cloud-snow", "ice"];
    case "thunderstorm": return ["cloud-lightning", "storm"];
    case "hail": return ["cloud-hail", "ice"];
    default: return ["cloud", "cloud"];
  }
}

// ---- Conditions (Conditions.swift) ---------------------------------------------

/** The backend's reasons behind each condition, for the light on its tile. */
export const REASONS = {
  wind: ["wind", "gusts", "lake_warning", "lake_strong_wind"],
  waves: ["waves"],
  waterTemperature: ["cold_water", "cool_water", "single_cold", "freezing_water"],
  visibility: ["fog"],
  precipitation: ["heavy_rain", "hail"],
  thunderstorm: ["thunderstorm"],
  ice: ["ice"],
  daylight: ["daylight", "twilight"],
};

const RANK = { green: 0, amber: 1, red: 2 };

/** The worst light among these reasons in the hour, or null when they are all fine. */
export function lightFor(hour, names) {
  let worst = null;
  for (const r of hour.reasons ?? []) {
    if (names.includes(r.condition) && (worst == null || RANK[r.light] > RANK[worst])) worst = r.light;
  }
  return worst;
}

/** Which condition's icon stands for a reason. */
export function reasonCondition(name) {
  if (name.endsWith("_warning")) return "warning";
  return Object.keys(REASONS).find((c) => REASONS[c].includes(name)) ?? "wind";
}

/** Why it feels warmer or colder than the air, in English. */
export function feelsLikeNote(hour) {
  const feels = hour.apparentTemperatureC;
  const air = hour.temperatureC;
  if (feels == null || air == null) return null;
  if (feels <= air - 2) return (hour.windSpeedMs ?? 0) >= 3 ? key("Colder from wind chill") : key("Colder than the air");
  if (feels >= air + 2) return (hour.humidityPct ?? 0) >= 60 ? key("Warmer from humidity (heat index)") : key("Warmer in the sun");
  return key("About the air temperature");
}

/** How much the pressure changes in the 3 hours after `hour`, in hPa. */
export function pressureChange(hours, hour) {
  const later = hours.find((h) => new Date(h.time) - new Date(hour.time) === 3 * 3600 * 1000);
  if (later?.pressureHpa == null || hour.pressureHpa == null) return null;
  return later.pressureHpa - hour.pressureHpa;
}

export function pressureTrend(change) {
  return change >= 1 ? key("Rising") : change <= -1 ? key("Falling") : key("Steady");
}

/** Without a station: the satellite estimate, the air-based one or the ice estimate's water. */
export function estimatedWater(forecast) {
  if (forecast.waterTemperature) return null;
  if (forecast.waterEstimate) return forecast.waterEstimate.celsius;
  if (forecast.waterModelC != null) return forecast.waterModelC;
  const ice = forecast.ice;
  if (ice && (ice.basis === "model" || ice.basis === "satellite")) return ice.waterTemperatureC ?? null;
  return null;
}

const ICE_MONTHS = new Set([11, 12, 1, 2, 3, 4]);

/** The ice tile out of season: the backend said so, or sent nothing in a month without ice. */
export function iceOff(ice, now = new Date()) {
  if (ice && ice.status !== "unavailable") return ice.basis === "season";
  return !ICE_MONTHS.has(now.getMonth() + 1);
}

export const ICE_TITLES = {
  open: key("No ice"), edges: key("Shore ice possible"), forming: key("Ice forming"), frozen: key("Ice cover likely"), drift_ice: key("Drift ice possible"),
};

/** The ice for the top tile, only when it matters (English key), else null. */
export function iceValue(forecast) {
  const ice = forecast.ice;
  if (ice && ice.status !== "unavailable" && ice.status !== "open") return ICE_TITLES[ice.status] ?? key("No data");
  const c = forecast.waterTemperature?.celsius;
  if (c != null && c < 8) return ice ? ICE_TITLES[ice.status] ?? key("No data") : key("No data yet");
  return null;
}

/**
 * Whether the sun is up at `at`: { up: true, sunrise, sunset } for today's
 * sun, or { up: false, sunrise } with the next sunrise.
 */
export function sunState(forecast, at = new Date()) {
  const days = (forecast.daylight ?? []).map((d) => ({ sunrise: new Date(d.sunrise), sunset: new Date(d.sunset) }));
  const today = days.find((d) => d.sunrise <= at && at < d.sunset);
  if (today) return { up: true, ...today };
  const next = days.find((d) => d.sunrise > at);
  return next ? { up: false, ...next } : null;
}

// ---- Boats and limits (Limits.swift) ----------------------------------------------

/** The app's two boat groups; the backend's light is for small boats. */
export const BOATS = {
  small: { title: key("Small boats"), inSentence: key("small boats"), detail: key("Singles, doubles and pairs (1x, 2x, 2-)") },
  big: { title: key("Big boats"), inSentence: key("big boats"), detail: key("Fours and eights (4x, 4-, 4+, 8x, 8+)") },
};

/** The app's limits for racing boats, small and big (RowingLimit.standard). */
const LIMITS = {
  big: { windAmber: 8.0, windRed: 10.8, gustAmber: 10.8, gustRed: 12.8, waveAmber: 0.25, waveRed: 0.40 },
};

const COLD_WATER_C = 10;
/** Below this the app advises a life jacket (RowingLimit.lifeJacket). */
const LIFE_JACKET_C = 15;
const COLD_WIND_MARGIN_MS = 1;
const FREEZING_WATER_C = 4;
const LIMIT_REASONS = new Set(["wind", "gusts", "waves", "cold_water", "cool_water", "single_cold", "freezing_water"]);

function check(value, amber, red) {
  if (value == null) return "green";
  return value > red ? "red" : value >= amber ? "amber" : "green";
}

/** One hour checked again for big boats, as ForecastHour.applying in the app. */
export function applyBoatToHour(hour, boat, waterC) {
  const base = LIMITS[boat];
  if (!base) return hour;
  const margin = (waterC ?? 99) < COLD_WATER_C ? COLD_WIND_MARGIN_MS : 0;
  const reasons = [];
  for (const r of hour.reasons ?? []) {
    if (LIMIT_REASONS.has(r.condition)) continue;
    // The lake's strong-wind light is amber for big boats.
    reasons.push(r.condition === "lake_strong_wind" ? { ...r, light: "amber" } : r);
  }
  const add = (name, light) => light !== "green" && reasons.push({ condition: name, light });
  add("wind", check(hour.windSpeedMs, base.windAmber - margin, base.windRed - margin));
  add("gusts", check(hour.windGustMs, base.gustAmber - margin, base.gustRed - margin));
  add("waves", check(hour.waveHeightM, base.waveAmber, base.waveRed));
  // Cold water shows as the life-jacket badge (coldWaterKit), not in the
  // light; only near-freezing water stays amber, as in score.py.
  if (waterC != null && waterC < FREEZING_WATER_C) reasons.push({ condition: "freezing_water", light: "amber" });
  reasons.sort((a, b) => RANK[b.light] - RANK[a.light]);
  const light = reasons.reduce((worst, r) => (RANK[r.light] > RANK[worst] ? r.light : worst), "green");
  return { ...hour, reasons, light };
}

/** The forecast with the boat's limits; unchanged for small boats. */
export function applyBoat(forecast, boat, zone = ZONE) {
  if (!LIMITS[boat]) return forecast;
  const water = forecast.waterTemperature?.celsius ?? estimatedWater(forecast);
  const byDay = new Map((forecast.waterForecast ?? []).map((d) => [d.date, d.celsius]));
  const apply = (h) => applyBoatToHour(h, boat, byDay.get(localDay(h.time, zone)) ?? water);
  return { ...forecast, hours: forecast.hours.map(apply), outlook: forecast.outlook?.map(apply) };
}

/**
 * What cold water calls for, as ColdWaterKit in the app: a life jacket below
 * 15 °C, and below 10 °C also a partner boat (boats that may be singles) or
 * staying near the shore (the others). Null in warmer water.
 */
export function coldWaterKit(waterC, boat = "small") {
  if (waterC == null || waterC >= LIFE_JACKET_C) return null;
  if (waterC >= COLD_WATER_C) return "lifeJacket";
  return boat === "small" ? "partnerBoat" : "nearShore";
}
