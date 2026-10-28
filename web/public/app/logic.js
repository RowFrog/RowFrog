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

/**
 * Beaufort without the steps, for charts: each force spans from half a force
 * below to half above, so the line and the limits keep their order in every
 * unit, and rounding gives the force that beaufort() names.
 */
export function beaufortScale(ms) {
  if (ms == null) return null;
  const i = BEAUFORT.findIndex((limit) => ms < limit);
  if (i === 0) return (ms / BEAUFORT[0]) * 0.5;
  if (i < 0) return 11.5 + Math.min(0.5, (ms - BEAUFORT[11]) / 8);
  return i - 0.5 + (ms - BEAUFORT[i - 1]) / (BEAUFORT[i] - BEAUFORT[i - 1]);
}

export const WIND_UNITS = {
  ms: { label: "m/s", title: key("Metres per second"), from: (ms) => ms },
  kmh: { label: "km/h", title: key("Kilometres per hour"), from: (ms) => ms * 3.6 },
  kn: { label: "kn", title: key("Knots"), from: (ms) => ms * 1.943844 },
  mph: { label: "mph", title: key("Miles per hour"), from: (ms) => (ms * 3600) / 1609.344 },
  bft: { label: "Bft", title: key("Beaufort"), from: (ms) => beaufort(ms) },
};

/**
 * The units the user can pick for each value (Units.swift). The backend
 * always sends metric values (°C, m/s, m, mm, m, hPa); they are converted
 * only for display. `digits` are the decimals a value is shown with.
 */
export const UNITS = {
  temperature: {
    standard: "celsius",
    options: {
      celsius: { label: "°C", title: key("Celsius"), from: (c) => c },
      fahrenheit: { label: "°F", title: key("Fahrenheit"), from: (c) => (c * 9) / 5 + 32 },
    },
  },
  wind: { standard: "ms", options: WIND_UNITS },
  waves: {
    standard: "m",
    options: {
      m: { label: "m", title: key("Metres"), digits: 2, from: (m) => m },
      cm: { label: "cm", title: key("Centimetres"), digits: 0, from: (m) => m * 100 },
      ft: { label: "ft", title: key("Feet"), digits: 1, from: (m) => m / 0.3048 },
    },
  },
  rain: {
    standard: "mm",
    options: {
      mm: { label: "mm", title: key("Millimetres"), digits: 1, from: (mm) => mm },
      in: { label: "in", title: key("Inches"), digits: 2, from: (mm) => mm / 25.4 },
    },
  },
  distance: {
    standard: "km",
    options: {
      km: { label: "km", title: key("Kilometres"), from: (m) => m / 1000 },
      mi: { label: "mi", title: key("Miles"), from: (m) => m / 1609.344 },
      nm: { label: key("NM"), title: key("Nautical miles"), from: (m) => m / 1852 },
    },
  },
  pressure: {
    standard: "hpa",
    options: {
      hpa: { label: "hPa", title: key("Hectopascals"), digits: 0, changeDigits: 1, from: (v) => v },
      mbar: { label: "mbar", title: key("Millibars"), digits: 0, changeDigits: 1, from: (v) => v },
      bar: { label: "bar", title: key("Bars"), digits: 3, changeDigits: 4, from: (v) => v / 1000 },
      inhg: { label: "inHg", title: key("Inches of mercury"), digits: 2, changeDigits: 2, from: (v) => v / 33.8639 },
      mmhg: { label: "mmHg", title: key("Millimetres of mercury"), digits: 0, changeDigits: 1, from: (v) => v * 0.750062 },
    },
  },
};

/** A change of `value` (metric) in a unit, for trend steps and differences: °C to °F scales without the 32. */
export const unitStep = (unit, value) => unit.from(value) - unit.from(0);

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

/**
 * The kind of sky for a WMO weather code, as Sky in the app; without a code,
 * from the rain and cloud cover when given (Sky(code: nil, ...)).
 */
export function sky(code, cloudCoverPct = null, precipitationMm = null) {
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
    default: {
      if (cloudCoverPct == null && precipitationMm == null) return "cloudy";
      const rain = precipitationMm ?? 0;
      const cloud = cloudCoverPct ?? 0;
      if (rain >= 4) return "heavyRain";
      if (rain >= 0.1) return "rain";
      return cloud >= 80 ? "cloudy" : cloud >= 40 ? "partlyCloudy" : cloud >= 15 ? "mostlyClear" : "clear";
    }
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
  // River clubs: the Current tile, in the ice tile's place.
  current: ["shipping_stopped", "high_water", "current"],
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

/** How a boat is built (BoatType): freeboard and width decide how much wind and wave it takes. */
export const BOAT_TYPES = {
  racing: { title: key("Racing boat"), detail: key("Narrow and low, with the least side above the water") },
  training: { title: key("Training boat"), detail: key("Wider and steadier than a racing boat") },
  gig: { title: key("Gig boat"), detail: key("Gig and touring boats, higher sides") },
  coastal: { title: key("Coastal boat"), detail: key("Coastal boats that drain themselves") },
};

/** Size and rigging (BoatClass). */
export const BOAT_CLASSES = {
  "1x": key("Single (1x)"), "2x": key("Double (2x)"), "2-": key("Pair (2-)"), "4x": key("Quad (4x)"),
  "4-": key("Four (4-)"), "4+": key("Coxed four (4+)"), "8x": key("Octuple (8x)"), "8+": key("Eight (8+)"),
};

/** Fours and eights: longer, heavier and steadier. */
export const isBigClass = (boatClass) => !["1x", "2x", "2-"].includes(boatClass);

/** The two groups every user has (Boat.small, Boat.big). */
export const GROUPS = [
  { id: "small", name: "", type: "racing", class: "1x" },
  { id: "big", name: "", type: "racing", class: "8+" },
];

/** The app's two boat groups; the backend's light is for small boats. */
export const BOATS = {
  small: { title: key("Small boats"), inSentence: key("small boats"), short: key("Small"), detail: key("Singles, doubles and pairs (1x, 2x, 2-)") },
  big: { title: key("Big boats"), inSentence: key("big boats"), short: key("Big"), detail: key("Fours and eights (4x, 4-, 4+, 8x, 8+)") },
};

export const isGroup = (boat) => boat.id === "small" || boat.id === "big";

/** The limits a user can fine-tune (RowingLimit), with their step and range; metric values. */
export const LIMITS = {
  windAmber: { title: key("Wind: row with care from"), condition: "wind", step: 0.5, range: [2, 15] },
  windRed: { title: key("Wind: stay ashore above"), condition: "wind", step: 0.5, range: [2, 15] },
  gustAmber: { title: key("Gusts: row with care from"), condition: "wind", step: 0.5, range: [4, 20] },
  gustRed: { title: key("Gusts: stay ashore above"), condition: "wind", step: 0.5, range: [4, 20] },
  waveAmber: { title: key("Waves: row with care from"), condition: "waves", step: 0.05, range: [0.05, 1.5] },
  waveRed: { title: key("Waves: stay ashore above"), condition: "waves", step: 0.05, range: [0.05, 1.5] },
  lifeJacket: { title: key("Life jacket below"), condition: "waterTemperature", step: 1, range: [4, 20] },
};

const WIND_LIMITS = ["windAmber", "windRed", "gustAmber", "gustRed"];
const BOAT_DEPENDENT = [...WIND_LIMITS, "waveAmber", "waveRed"];

// The app's limits by type and size (RowingLimit.standard): wind amber, wind red,
// gust amber, gust red, wave amber, wave red. From the research approved on 2026-10-23.
const STANDARD = {
  "racing small": [5.5, 8.0, 8.0, 10.3, 0.15, 0.25],
  "racing big": [8.0, 10.8, 10.8, 12.8, 0.25, 0.40],
  "training small": [6.5, 9.0, 9.0, 11.0, 0.20, 0.35],
  "training big": [8.0, 10.8, 10.8, 12.8, 0.25, 0.40],
  gig: [8.0, 10.8, 10.8, 12.8, 0.30, 0.50],
  coastal: [8.0, 12.0, 10.8, 12.8, 0.50, 1.0],
};

/** The app's limit for a boat. */
export function standardLimit(limit, boat) {
  if (limit === "lifeJacket") return 15;
  const size = isBigClass(boat.class) ? "big" : "small";
  const row = STANDARD[`${boat.type} ${size}`] ?? STANDARD[boat.type] ?? STANDARD["racing small"];
  return row[BOAT_DEPENDENT.indexOf(limit)];
}

const COLD_WATER_C = 10;
const COLD_WIND_MARGIN_MS = 1;
const FREEZING_WATER_C = 4;
export const COLD = { waterC: COLD_WATER_C, marginMs: COLD_WIND_MARGIN_MS };
const LIMIT_REASONS = new Set(["wind", "gusts", "waves", "cold_water", "cool_water", "single_cold", "freezing_water"]);

/**
 * The limits for one boat (RowingLimits): the app's for its type with the
 * user's own changes in `custom`, and in water below 10 °C the app's wind
 * and gust limits lowered by 1 m/s.
 */
export function limitsFor(boat, custom = {}, waterC = null) {
  const margin = (waterC ?? 99) < COLD_WATER_C ? COLD_WIND_MARGIN_MS : 0;
  const maybeSingle = boat.id === "small" || boat.class === "1x";
  return {
    boat,
    custom,
    value: (limit) => custom[limit] ?? standardLimit(limit, boat) - (WIND_LIMITS.includes(limit) ? margin : 0),
    isMine: (limit) => custom[limit] != null,
    maybeSingle,
    // The lake's strong-wind light: red for small racing and training boats, amber for the rest.
    strongWindLight: !isBigClass(boat.class) && ["racing", "training"].includes(boat.type) ? "red" : "amber",
  };
}

/** The same limits and rules as the backend's small boats, whatever the boat is called. */
export function matchesStandard(limits) {
  const usual = limitsFor(GROUPS[0]);
  return Object.keys(LIMITS).every((l) => limits.value(l) === usual.value(l)) && limits.maybeSingle && limits.strongWindLight === "red";
}

/** Whether these limits let any wind, gust or wave pass that `other` already flags. */
export function allowsMore(limits, other) {
  return BOAT_DEPENDENT.some((l) => limits.value(l) > other.value(l) + 1e-9);
}

function check(value, amber, red) {
  if (value == null) return "green";
  return value > red ? "red" : value >= amber ? "amber" : "green";
}

/**
 * One hour checked again for a boat's limits, as ForecastHour.applying in the
 * app. Where the user's own limit is looser than the app's, a note says the
 * value is above the app's usual limit, so the advice is never lost.
 */
export function applyLimitsToHour(hour, chosen, waterC) {
  const limits = limitsFor(chosen.boat, chosen.custom, waterC);
  const usual = limitsFor(chosen.boat, {}, waterC);
  const reasons = [];
  const notes = [];
  for (const r of hour.reasons ?? []) {
    if (LIMIT_REASONS.has(r.condition)) continue;
    reasons.push(r.condition === "lake_strong_wind" ? { ...r, light: limits.strongWindLight } : r);
  }
  const add = (name, value, amber, red) => {
    const light = check(value, limits.value(amber), limits.value(red));
    if (light !== "green") reasons.push({ condition: name, light, ...(limits.isMine(light === "red" ? red : amber) ? { mine: true } : {}) });
    const was = check(value, usual.value(amber), usual.value(red));
    if (RANK[was] > RANK[light]) notes.push({ condition: name, light: was });
  };
  add("wind", hour.windSpeedMs, "windAmber", "windRed");
  add("gusts", hour.windGustMs, "gustAmber", "gustRed");
  add("waves", hour.waveHeightM, "waveAmber", "waveRed");
  // Cold water shows as the life-jacket badge (coldWaterKit), not in the
  // light; only near-freezing water stays amber, as in score.py.
  if (waterC != null && waterC < COLD_WATER_C) {
    // The user's own wind limits do not drop with the water; say so.
    if (WIND_LIMITS.some((l) => limits.isMine(l))) notes.push({ condition: "cold_margin", light: "amber" });
    if (waterC < FREEZING_WATER_C) reasons.push({ condition: "freezing_water", light: "amber" });
  }
  reasons.sort((a, b) => RANK[b.light] - RANK[a.light]);
  const light = reasons.reduce((worst, r) => (RANK[r.light] > RANK[worst] ? r.light : worst), "green");
  return { ...hour, reasons, light, notes: notes.length ? notes : undefined };
}

/** The water the server judges an hour by: that day's water forecast, else the reading or estimate. */
export function waterForHour(forecast, hour, zone = ZONE) {
  const day = (forecast.waterForecast ?? []).find((d) => d.date === localDay(hour.time, zone));
  return day?.celsius ?? forecast.waterTemperature?.celsius ?? estimatedWater(forecast);
}

/** The forecast with a boat's limits; unchanged with the backend's own. */
export function applyLimits(forecast, limits, zone = ZONE) {
  if (matchesStandard(limits)) return forecast;
  const apply = (h) => applyLimitsToHour(h, limits, waterForHour(forecast, h, zone));
  return { ...forecast, hours: forecast.hours.map(apply), outlook: forecast.outlook?.map(apply) };
}

/** For a boat group id ("small" or "big"), as before own boats existed. */
export function applyBoatToHour(hour, boat, waterC) {
  const group = GROUPS.find((g) => g.id === boat);
  return group ? applyLimitsToHour(hour, limitsFor(group), waterC) : hour;
}

export function applyBoat(forecast, boat, zone = ZONE) {
  const group = GROUPS.find((g) => g.id === boat);
  return group ? applyLimits(forecast, limitsFor(group), zone) : forecast;
}

/**
 * What cold water calls for, as ColdWaterKit in the app: a life jacket below
 * the life-jacket limit (15 °C), and below 10 °C also a partner boat (boats
 * that may be singles) or staying near the shore (the others). Null in warmer water.
 */
export function coldWaterKit(waterC, limits = limitsFor(GROUPS[0])) {
  if (typeof limits === "string") limits = limitsFor(GROUPS.find((g) => g.id === limits) ?? GROUPS[0]);
  if (waterC == null || !(waterC < limits.value("lifeJacket") || waterC < COLD_WATER_C)) return null;
  if (waterC >= COLD_WATER_C) return "lifeJacket";
  return limits.maybeSingle ? "partnerBoat" : "nearShore";
}

/**
 * One of the user's own boats that would get better advice than the ticked one
 * this hour (SteadierBoat): { boat, light }, or null.
 */
export function steadierBoat(hour, waterC, boats, chosenId, limitsOf) {
  if (hour.light === "green") return null;
  let best = null;
  for (const boat of boats) {
    if (boat.id === chosenId) continue;
    const light = applyLimitsToHour(hour, limitsOf(boat), waterC).light;
    if (RANK[light] < RANK[hour.light] && (!best || RANK[light] < RANK[best.light])) best = { boat, light };
  }
  return best;
}
