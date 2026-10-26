// The forecast for a place the user put on the map themselves (OwnPlaces.swift):
// the published forecasts only cover the clubs in the lists, and an own place
// must not appear in public files. The browser asks Open-Meteo itself (the same
// DWD ICON models as the backend) and applies the backend's rowing-light rules
// for wind, gusts, fog, thunderstorms and daylight (backend/rowfrog/score.py).
// Without a lake outline there are no waves, and there are no water
// temperature, ice or DWD warnings.

export const OWN_PREFIX = "own-";
export const isOwn = (id) => String(id ?? "").startsWith(OWN_PREFIX);

// The backend's own credit line, so it is translated the same way.
const ATTRIBUTION = "Weather: Deutscher Wetterdienst (DWD) via Open-Meteo, CC BY 4.0";

// score.Thresholds and forecast.py's thunderstorm signal.
const T = {
  windAmber: 5.5, windRed: 8.0, gustAmber: 8.0, gustRed: 12.8,
  visibilityAmber: 1000, visibilityRed: 500, capeAmber: 500, capeRed: 1000, convectiveRainMm: 1.0,
};

const HOURLY = [
  "temperature_2m", "wind_speed_10m", "wind_gusts_10m", "wind_direction_10m", "cloud_cover",
  "visibility", "precipitation", "weather_code", "apparent_temperature", "relative_humidity_2m",
  "dew_point_2m", "pressure_msl", "cape", "is_day",
];

export function openMeteoUrl({ lat, lon }) {
  const q = new URLSearchParams({
    latitude: lat.toFixed(4), longitude: lon.toFixed(4), hourly: HOURLY.join(","), models: "icon_seamless",
    wind_speed_unit: "ms", timezone: "GMT", forecast_hours: "48",
  });
  return `https://api.open-meteo.com/v1/forecast?${q}`;
}

export async function loadOwnForecast(club, now = new Date()) {
  const response = await fetch(openMeteoUrl(club.launchPoint));
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return ownForecast(club, await response.json(), now);
}

const RANK = { green: 0, amber: 1, red: 2 };
const rising = (v, amber, red) => (v > red ? "red" : v >= amber ? "amber" : "green");

function thunderstorm(cape, rain) {
  if ((cape ?? 0) >= T.capeRed && (rain ?? 0) >= T.convectiveRainMm) return "red";
  return (cape ?? 0) >= T.capeAmber ? "amber" : "green";
}

/** As forecast._daylight: green with the sun up all hour, amber ("twilight") with sunrise or sunset inside it, red in the dark. */
export function daylight(start, days, isDay) {
  if (!days.length) return ["daylight", isDay === false ? "red" : "green", isDay];
  const end = start + 3600e3;
  const middle = start + 1800e3;
  const sunUp = days.some((d) => d.rise <= middle && middle < d.set);
  if (days.some((d) => d.rise <= start && end <= d.set)) return ["daylight", "green", sunUp];
  if (days.some((d) => [d.rise, d.set].some((x) => start < x && x < end))) return ["twilight", "amber", sunUp];
  return ["daylight", "red", sunUp];
}

/** The hours in the backend's forecast format, so the club page shows them like any club's. */
export function ownForecast(club, payload, now = new Date()) {
  const hr = payload.hourly ?? {};
  const at = (name, i) => hr[name]?.[i] ?? null;
  const times = (hr.time ?? []).map((x) => Date.parse(`${x}Z`));
  const { lat, lon } = club.launchPoint;
  const days = times.length ? sunDays(times[0], times[times.length - 1], lat, lon) : [];
  const hours = times.map((start, i) => {
    const wind = at("wind_speed_10m", i);
    const gust = at("wind_gusts_10m", i);
    const visibility = at("visibility", i);
    const isDay = at("is_day", i) == null ? null : at("is_day", i) > 0;
    const [daylightName, daylightLight, sunUp] = daylight(start, days, isDay);
    const reasons = [];
    const add = (condition, light) => light !== "green" && reasons.push({ condition, light });
    add("wind", rising(wind ?? 0, T.windAmber, T.windRed));
    add("gusts", rising(gust ?? 0, T.gustAmber, T.gustRed));
    add("thunderstorm", thunderstorm(at("cape", i), at("precipitation", i)));
    add(daylightName, daylightLight);
    if (visibility != null) {
      if (visibility < T.visibilityRed) add("fog", "red");
      else if (visibility <= T.visibilityAmber) add("fog", "amber");
    }
    reasons.sort((a, b) => RANK[b.light] - RANK[a.light]);
    return {
      time: new Date(start).toISOString(), light: reasons[0]?.light ?? "green", reasons,
      windSpeedMs: wind, windGustMs: gust, windFromDeg: at("wind_direction_10m", i), waveHeightM: null, fetchM: null,
      visibilityM: visibility, temperatureC: at("temperature_2m", i), cloudCoverPct: at("cloud_cover", i), sunUp,
      precipitationMm: at("precipitation", i), weatherCode: at("weather_code", i),
      apparentTemperatureC: at("apparent_temperature", i), humidityPct: at("relative_humidity_2m", i),
      dewPointC: at("dew_point_2m", i), pressureHpa: at("pressure_msl", i), capeJkg: at("cape", i),
    };
  });
  return {
    clubId: club.id, lakeId: null, generatedAt: now.toISOString(), waterTemperature: null, warnings: null, ice: null,
    attribution: [ATTRIBUTION],
    daylight: days.map((d) => ({ date: new Date(d.rise).toISOString().slice(0, 10), sunrise: new Date(d.rise).toISOString(), sunset: new Date(d.set).toISOString() })),
    hours,
  };
}

// ---- Sunrise and sunset, as backend/rowfrog/sun.py (NOAA's sunrise equation) ----

const DAY = 86400e3;
const J2000 = Date.UTC(2000, 0, 1);

/** Sunrise and sunset (ms) on a UTC day, or null in polar day or night. */
export function sunDay(dayMs, lat, lon) {
  const n = Math.round((Math.floor(dayMs / DAY) * DAY - J2000) / DAY);
  const rad = Math.PI / 180;
  const meanSolar = n - lon / 360;
  const m = ((357.5291 + 0.98560028 * meanSolar) % 360) * rad;
  const centre = 1.9148 * Math.sin(m) + 0.02 * Math.sin(2 * m) + 0.0003 * Math.sin(3 * m);
  const eclipticLon = ((m / rad + centre + 180 + 102.9372) % 360) * rad;
  const transit = 2451545.0 + meanSolar + 0.0053 * Math.sin(m) - 0.0069 * Math.sin(2 * eclipticLon);
  const declination = Math.asin(Math.sin(eclipticLon) * Math.sin(23.4397 * rad));
  const phi = lat * rad;
  const cosHourAngle = (Math.sin(-0.833 * rad) - Math.sin(phi) * Math.sin(declination)) / (Math.cos(phi) * Math.cos(declination));
  if (cosHourAngle < -1 || cosHourAngle > 1) return null;
  const halfDay = Math.acos(cosHourAngle) / rad / 360;
  const date = (j) => J2000 + 12 * 3600e3 + (j - 2451545.0) * DAY;
  return { rise: date(transit - halfDay), set: date(transit + halfDay) };
}

/** Every day from the one before `start` to the one after `end` (UTC dates). */
export function sunDays(start, end, lat, lon) {
  const out = [];
  for (let d = start - DAY; d <= end + DAY; d += DAY) {
    const s = sunDay(d, lat, lon);
    if (s) out.push(s);
  }
  return out;
}
