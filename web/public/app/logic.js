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

/**
 * What a club page says about its forecast, one state at a time (ForecastStatus.of in the app).
 * The list is testdata/states/forecast-status.json, which the app's tests read too; change both
 * with it. `failure` is refreshFailure()'s [short, why] or null. The website has no "updating":
 * it reloads the whole page, so it passes loading: false.
 */
export function forecastStatus({ hasForecast, outOfDate, loading = false, failure = null }) {
  if (!hasForecast) return failure ? { name: "noForecast", failure } : { name: "loading" };
  if (failure) return { name: outOfDate ? "outOfDateAndUpdateFailed" : "updateFailed", failure, outOfDate };
  if (outOfDate) return { name: "outOfDate", outOfDate };
  return { name: loading ? "updating" : "current" };
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

/**
 * The forecast hour as it stands at `now` (Forecast.current(at:)). The hour's daylight light is
 * the strictest of its minutes, so it is replaced by the light of this minute (daylightAt):
 * green, amber in the last hour before sunset ("sunset_soon"), red ("daylight") with the sun down.
 * The 48 hours and the hour view keep the hour's own light.
 */
export function nowHour(forecast, now = new Date()) {
  const first = currentHour(forecast.hours, now);
  const days = sunDaysOf(forecast);
  if (!first || !days.length || !(first.reasons ?? []).some((r) => DAYLIGHT_REASONS.includes(r.condition))) return first;
  const reasons = first.reasons.filter((r) => !DAYLIGHT_REASONS.includes(r.condition));
  const now_ = daylightAt(now.getTime(), days);
  if (now_ === "red") reasons.unshift({ condition: "daylight", light: "red" });
  if (now_ === "amber") reasons.unshift({ condition: "sunset_soon", light: "amber" });
  const light = reasons.reduce((worst, r) => (RANK[r.light] > RANK[worst] ? r.light : worst), "green");
  return { ...first, reasons, light, sunUp: now_ !== "red" };
}

// ---- Daylight to the minute (DaylightRule.swift, owner's pick D, 6 Nov 2026) ----------

/** As SUNSET_WINDOW in backend/rowfrog/forecast.py: the last hour before sunset is amber. */
export const SUNSET_WINDOW_MS = 3600e3;
/** A part of an hour shorter than this is left out of its dot, unless it is the strictest part. */
export const SHORTEST_PART_MS = 600e3;
/** The reasons the daylight gives; "sunset_soon" is the page's own, for "now" in the last hour. */
export const DAYLIGHT_REASONS = ["daylight", "twilight", "sunset_soon"];

/** The forecast's sun days as { sunrise, sunset } in milliseconds. */
export const sunDaysOf = (forecast) => (forecast?.daylight ?? []).map((d) => ({ sunrise: Date.parse(d.sunrise), sunset: Date.parse(d.sunset) }));

/** The daylight light at one moment `t` (ms): green, amber in the last hour before sunset, red with the sun down. */
export function daylightAt(t, days) {
  const day = days.find((d) => d.sunrise <= t && t < d.sunset);
  if (!day) return "red";
  return t >= day.sunset - SUNSET_WINDOW_MS ? "amber" : "green";
}

/** The hour from `start` (ms), cut where the daylight light changes: [{ light, from, to }]. */
export function daylightParts(start, days) {
  const end = start + 3600e3;
  const inside = days.flatMap((d) => [d.sunrise, d.sunset - SUNSET_WINDOW_MS, d.sunset]).filter((t) => t > start && t < end);
  const cuts = [start, ...inside].sort((a, b) => a - b);
  const parts = [];
  cuts.forEach((cut, i) => {
    const to = i + 1 < cuts.length ? cuts[i + 1] : end;
    const light = daylightAt(cut, days);
    const last = parts[parts.length - 1];
    if (last && last.light === light) last.to = to;
    else parts.push({ light, from: cut, to });
  });
  return parts;
}

const stricter = (a, b) => (RANK[a] >= RANK[b] ? a : b);

/**
 * The lights an hour's dot starts and ends with ({ start, end }), or null when it does not change.
 * `floor` is the hour's light from everything but the daylight: neither half is below it.
 * `before` and `after` are the same for the hours either side (owner's pick B, 6 Nov 2026): the
 * better half can never be better than the weather of the hour it touches, nor stricter than the
 * other half. The stricter half stays.
 */
export function daylightHalves(start, days, floor = "green", before = "green", after = "green") {
  const all = daylightParts(start, days);
  const top = all.reduce((w, p) => stricter(w, p.light), "green");
  const kept = all.filter((p) => p.to - p.from >= SHORTEST_PART_MS || p.light === top);
  if (!kept.length) return null;
  let left = stricter(kept[0].light, floor);
  let right = stricter(kept[kept.length - 1].light, floor);
  // Held to its neighbour, the better half never gets stricter than the other half.
  const milder = (a, b) => (RANK[a] <= RANK[b] ? a : b);
  if (RANK[left] < RANK[right]) left = milder(stricter(left, before), right);
  else if (RANK[right] < RANK[left]) right = milder(stricter(right, after), left);
  return left === right ? null : { start: left, end: right };
}

/** The light of an hour from everything but the daylight. */
export const weatherLight = (hour) => (hour?.reasons ?? []).filter((r) => !DAYLIGHT_REASONS.includes(r.condition)).reduce((w, r) => stricter(w, r.light), "green");

/** The half-and-half dot for an hour row or the hour view (ClubForecast.dotHalves); null for one colour. */
export function hourHalves(forecast, hour, stale = false) {
  const days = sunDaysOf(forecast);
  const reasons = hour?.reasons ?? [];
  if (stale || !days.length || !reasons.some((r) => DAYLIGHT_REASONS.includes(r.condition))) return null;
  const t = Date.parse(hour.time);
  const near = (offset) => (forecast.hours ?? []).find((x) => Date.parse(x.time) === t + offset);
  return daylightHalves(t, days, weatherLight(hour), weatherLight(near(-3600e3)), weatherLight(near(3600e3)));
}

/** The next `count` hours from the current one. */
export function nextHours(hours, now = new Date(), count = 48) {
  const current = currentHour(hours, now);
  const i = Math.max(0, hours.indexOf(current));
  return hours.slice(i, i + count);
}

/**
 * The 48 hours cut into rows and nights (NightFold in the app). Rowing is only
 * advised while the sun is up, so the dark hours of a night fold into one line.
 * The hours the sun sets or rises in keep their rows (their light changes inside them),
 * as does the first hour, even at night; a night of one hour stays a row.
 * Each part is { hour } or { night: [hours] }. `days` as sunDaysOf(forecast).
 */
export function nightParts(hours, days = []) {
  const parts = [];
  let run = [];
  const endRun = () => {
    if (run.length > 1) parts.push({ night: run });
    else run.forEach((hour) => parts.push({ hour }));
    run = [];
  };
  hours.forEach((hour, i) => {
    const dark = hour.sunUp === false && !hour.reasons?.some((r) => r.condition === "twilight")
      && (!days.length || daylightParts(Date.parse(hour.time), days).length === 1);
    if (i > 0 && dark) run.push(hour);
    else { endRun(); parts.push({ hour }); }
  });
  endRun();
  return parts;
}

/** What a night's line shows, each for its column: the worst of the night. */
export function nightSummary(hours) {
  const values = (key) => hours.map((x) => x[key]).filter((v) => v != null);
  const min = (key) => (values(key).length ? Math.min(...values(key)) : null);
  const max = (key) => (values(key).length ? Math.max(...values(key)) : null);
  const rain = values("precipitationMm");
  const lowest = min("temperatureC");
  const fogs = hours.map((x) => lightFor(x, ["fog"])).filter(Boolean);
  return {
    start: hours[0].time,
    end: new Date(new Date(hours[hours.length - 1].time).getTime() + 3600e3).toISOString(),
    lowestC: lowest, lowestFeelsLikeC: min("apparentTemperatureC"),
    windMs: max("windSpeedMs"), gustMs: max("windGustMs"), wavesM: max("waveHeightM"),
    rainMm: rain.length ? rain.reduce((a, b) => a + b, 0) : null,
    visibilityM: min("visibilityM"),
    fog: fogs.includes("red") ? "red" : fogs.includes("amber") ? "amber" : fogs[0] ?? null,
    frost: lowest != null && Math.round(lowest) <= 0,
  };
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

/** Where the wind comes from, as N, NE, E …; in German N, NO, O … (Format.compass). */
export function compass(deg, language = "en") {
  if (deg == null) return "";
  const points = language === "de" ? ["N", "NO", "O", "SO", "S", "SW", "W", "NW"] : ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
  return points[Math.round(((deg % 360) + 360) % 360 / 45) % 8];
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
  daylight: ["daylight", "twilight", "sunset_soon"],
  // River clubs: the Current tile, in the ice tile's place.
  current: ["shipping_stopped", "high_water", "current"],
  // Lakes let down for the winter (Forggensee): the Water level tile, in the ice tile's place.
  waterLevel: ["lake_lowered", "lake_drained"],
};

const RANK = { green: 0, amber: 1, red: 2 };
const worse = (a, b) => (RANK[b] > RANK[a] ? b : a);

/** The worst light among these reasons in the hour, or null when they are all fine. */
export function lightFor(hour, names) {
  let worst = null;
  for (const r of hour.reasons ?? []) {
    if (names.includes(r.condition) && (worst == null || RANK[r.light] > RANK[worst])) worst = r.light;
  }
  return worst;
}

/** Which condition's icon stands for a reason. */
export function reasonCondition(name, topic = null) {
  if (name.endsWith("_warning")) return "warning";
  // Water nearby takes the icon of what makes it worse (fog: binoculars), as Reason.symbol.
  if (name === "nearby_water") name = topic ?? "waves";
  return Object.keys(REASONS).find((c) => REASONS[c].includes(name)) ?? "wind";
}

/**
 * The value whose worst within 1 km sets the light this hour, if one does: the top tile then shows
 * that worst value, marked "Nearby" (ForecastHour.nearbyCondition, owner 6 Nov 2026), since a rower
 * at the launch point cannot see 15 km when there is fog 300 m out.
 */
export function nearbyCondition(hour) {
  if (!hour?.nearby) return null;
  const topic = hour.reasons?.find((r) => r.condition === "nearby_water")?.topic;
  return { wind: "wind", gusts: "wind", waves: "waves", fog: "visibility", heavy_rain: "precipitation", hail: "precipitation", thunderstorm: "thunderstorm" }[topic] ?? null;
}

/** Wind and gusts as the top tile shows them: the worst within 1 km while that sets the light (shownWind). */
export function shownWind(hour) {
  const n = hour.nearby;
  if (nearbyCondition(hour) !== "wind") return { speed: hour.windSpeedMs, gust: hour.windGustMs };
  return { speed: Math.max(hour.windSpeedMs ?? 0, n.windMs ?? 0), gust: Math.max(hour.windGustMs ?? 0, n.gustMs ?? 0) };
}

export function shownWaveHeightM(hour) {
  if (nearbyCondition(hour) !== "waves") return hour.waveHeightM;
  return Math.max(hour.waveHeightM ?? 0, hour.nearby.waveM ?? 0);
}

export function shownVisibilityM(hour) {
  const vis = hour.nearby?.visM;
  if (nearbyCondition(hour) !== "visibility" || vis == null) return hour.visibilityM;
  return Math.min(hour.visibilityM ?? vis, vis);
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
  "1x": key("Single (1x)"), "2x": key("Double (2x)"), "2-": key("Pair (2-)"), "2+": key("Coxed pair (2+)"), "4x": key("Quad (4x)"),
  "4x+": key("Coxed quad (4x+)"), "4-": key("Four (4-)"), "4+": key("Coxed four (4+)"), "8x": key("Octuple (8x)"),
  "8x+": key("Coxed octuple (8x+)"), "8+": key("Eight (8+)"),
};

/** Fours and eights: longer, heavier and steadier. */
export const isBigClass = (boatClass) => !["1x", "2x", "2-", "2+"].includes(boatClass);

/** The two groups every user has (Boat.small, Boat.big). */
export const GROUPS = [
  { id: "small", name: "", type: "racing", class: "1x" },
  { id: "big", name: "", type: "racing", class: "8+" },
];

/** The app's two boat groups; the backend's light is for small boats. */
export const BOATS = {
  small: { title: key("Small boats"), inSentence: key("small boats"), tag: "1–2", detail: key("Singles, doubles and pairs (1x, 2x, 2-)") },
  big: { title: key("Big boats"), inSentence: key("big boats"), tag: "4–8", detail: key("Fours and eights (4x, 4-, 4+, 8x, 8+)") },
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
  // River current mid-river, for every boat (river.py; app #182).
  currentAmber: { title: key("Current: row with care from"), condition: "current", step: 0.1, range: [0.5, 4] },
  currentRed: { title: key("Current: stay ashore above"), condition: "current", step: 0.1, range: [0.5, 4] },
  lifeJacket: { title: key("Life jacket below"), condition: "waterTemperature", step: 1, range: [4, 20] },
};

/** How long the gauge's reading counts in the forecast (river.py GAUGE_HOURS). */
export const GAUGE_HOURS = 24;

const WIND_LIMITS = ["windAmber", "windRed", "gustAmber", "gustRed"];
const BOAT_DEPENDENT = [...WIND_LIMITS, "waveAmber", "waveRed"];

// The app's limits by type and size (RowingLimit.standard): wind amber, wind red,
// gust amber, gust red, wave amber, wave red. From the research approved on 2026-10-23.
// testdata/limits.json checks these against the app and the backend.
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
  if (limit === "currentAmber") return 1.5;
  if (limit === "currentRed") return 2.5;
  const size = isBigClass(boat.class) ? "big" : "small";
  const row = STANDARD[`${boat.type} ${size}`] ?? STANDARD[boat.type] ?? STANDARD["racing small"];
  return row[BOAT_DEPENDENT.indexOf(limit)];
}

const COLD_WATER_C = 10;
const COLD_WIND_MARGIN_MS = 1;
const FREEZING_WATER_C = 4;
export const COLD = { waterC: COLD_WATER_C, marginMs: COLD_WIND_MARGIN_MS };
const LIMIT_REASONS = new Set(["wind", "gusts", "waves", "cold_water", "cool_water", "single_cold", "freezing_water", "nearby_water"]);

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
 * app, and on rivers the gauge's current (`currentMs`, null where it does not
 * count). Where the user's own limit is looser than the app's, a note says the
 * value is above the app's usual limit, so the advice is never lost.
 */
export function applyLimitsToHour(hour, chosen, waterC, currentMs = null) {
  const limits = limitsFor(chosen.boat, chosen.custom, waterC);
  const usual = limitsFor(chosen.boat, {}, waterC);
  const reasons = [];
  const notes = [];
  for (const r of hour.reasons ?? []) {
    if (LIMIT_REASONS.has(r.condition) || (currentMs != null && r.condition === "current")) continue;
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
  if (currentMs != null) add("current", currentMs, "currentAmber", "currentRed");
  // Cold water shows as the life-jacket badge (coldWaterKit), not in the
  // light; only near-freezing water stays amber, as in score.py.
  if (waterC != null && waterC < COLD_WATER_C) {
    // The user's own wind limits do not drop with the water; say so.
    if (WIND_LIMITS.some((l) => limits.isMine(l))) notes.push({ condition: "cold_margin", light: "amber" });
    if (waterC < FREEZING_WATER_C) reasons.push({ condition: "freezing_water", light: "amber" });
  }
  // The water within 1 km counts where it is worse than the launch point, with this boat's limits (app #395).
  const near = nearbyReason(hour.nearby, limits);
  if (near && RANK[near.light] > RANK[reasons.reduce((w, r) => worse(w, r.light), "green")]) reasons.unshift(near);
  reasons.sort((a, b) => RANK[b.light] - RANK[a.light]);
  const light = reasons.reduce((worst, r) => (RANK[r.light] > RANK[worst] ? r.light : worst), "green");
  return { ...hour, reasons, light, notes: notes.length ? notes : undefined };
}

/**
 * The "nearby_water" reason for the water within 1 km of the launch point (on rivers, 1 km along the stretch)
 * with a boat's limits (NearbyWater.reason(with:), app #395): the worst of wind, gusts, waves and the rest
 * (fog, thunderstorm, heavy rain, hail), named after what sets it, wind first as in score.py; null while green.
 */
export function nearbyReason(nearby, limits) {
  if (!nearby) return null;
  const cause = nearby.otherCause ?? "fog";
  const checks = [
    ["wind", check(nearby.windMs, limits.value("windAmber"), limits.value("windRed")), nearby.windMs],
    ["gusts", check(nearby.gustMs, limits.value("gustAmber"), limits.value("gustRed")), nearby.gustMs],
    ["waves", check(nearby.waveM, limits.value("waveAmber"), limits.value("waveRed")), nearby.waveM],
    [cause, nearby.other ?? "green", nearby.otherCause === "fog" ? nearby.visM ?? null : nearby.otherCause === "heavy_rain" ? nearby.rainMm ?? null : null],
  ];
  const worst = checks.reduce((w, [, l]) => worse(w, l), "green");
  if (worst === "green") return null;
  const [topic, , value] = checks.find(([, l]) => l === worst);
  return { condition: "nearby_water", light: worst, topic, value: value ?? null };
}

/** The water the server judges an hour by: that day's water forecast, else the reading or estimate. */
export function waterForHour(forecast, hour, zone = ZONE) {
  const day = (forecast.waterForecast ?? []).find((d) => d.date === localDay(hour.time, zone));
  return day?.celsius ?? forecast.waterTemperature?.celsius ?? estimatedWater(forecast);
}

/** The forecast with a boat's limits; unchanged with the backend's own. */
export function applyLimits(forecast, limits, zone = ZONE) {
  if (matchesStandard(limits)) return forecast;
  // The gauge's current counts for the first hours only, as on the server.
  const current = forecast.river?.now?.speedMs ?? null;
  const until = Date.parse(forecast.generatedAt) + GAUGE_HOURS * 3600 * 1000;
  const apply = (h) => applyLimitsToHour(h, limits, waterForHour(forecast, h, zone), Date.parse(h.time) < until ? current : null);
  return { ...forecast, hours: forecast.hours.map(apply), outlook: forecast.outlook?.map(apply), river: forecast.river && riverForBoat(forecast.river, limits) };
}

/** The river with the current limits of the user's boat: the Current tile's light and the limits it names (RiverConditions.applying). */
export function riverForBoat(river, chosen) {
  const limits = limitsFor(chosen.boat, chosen.custom);
  const [amber, red] = [limits.value("currentAmber"), limits.value("currentRed")];
  const now = river.now && {
    ...river.now,
    light: worse(river.now.state === "shipping_stopped" ? "red" : river.now.state === "high" ? "amber" : "green", check(river.now.speedMs, amber, red)),
  };
  return { ...river, limits: { ...river.limits, currentAmberMs: amber, currentRedMs: red }, now };
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
