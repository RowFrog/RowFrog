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

/**
 * One line per day from the outlook (or the hours when there is none): the
 * light of every daylight hour, the lowest and highest temperature, the
 * strongest gust and the rain. Days before today are left out.
 */
export function days(forecast, now = new Date(), zone = ZONE) {
  const hours = forecast.outlook?.length ? forecast.outlook : forecast.hours;
  const today = localDay(now, zone);
  const byDay = new Map();
  for (const h of hours) {
    const day = localDay(h.time, zone);
    if (day < today) continue;
    if (!byDay.has(day)) byDay.set(day, []);
    byDay.get(day).push(h);
  }
  return [...byDay.entries()].map(([day, list]) => {
    const temps = list.map((h) => h.temperatureC).filter((v) => v != null);
    const gusts = list.map((h) => h.windGustMs).filter((v) => v != null);
    const daylight = list.filter((h) => h.sunUp);
    return {
      day,
      lights: daylight.map((h) => ({ time: h.time, light: h.light })),
      green: daylight.filter((h) => h.light === "green").length,
      minC: temps.length ? Math.min(...temps) : null,
      maxC: temps.length ? Math.max(...temps) : null,
      maxGustMs: gusts.length ? Math.max(...gusts) : null,
      rainMm: list.reduce((sum, h) => sum + (h.precipitationMm ?? 0), 0),
      weatherCode: dayCode(daylight.length ? daylight : list),
    };
  });
}

/** The day's weather symbol: the most common code in daylight, rain and storms first. */
function dayCode(list) {
  const codes = list.map((h) => h.weatherCode).filter((c) => c != null);
  if (!codes.length) return null;
  const worst = Math.max(...codes);
  if (worst >= 51) return worst;
  const counts = new Map();
  for (const c of codes) counts.set(c, (counts.get(c) ?? 0) + 1);
  return [...counts.entries()].sort((a, b) => b[1] - a[1] || b[0] - a[0])[0][0];
}

/** A symbol for a WMO weather code (Open-Meteo's weather_code). */
export function weatherSymbol(code, sunUp = true) {
  if (code == null) return "·";
  if (code === 0) return sunUp ? "☀️" : "🌙";
  if (code === 1) return sunUp ? "🌤️" : "🌙";
  if (code === 2) return sunUp ? "⛅" : "☁️";
  if (code === 3) return "☁️";
  if (code === 45 || code === 48) return "🌫️";
  if (code >= 51 && code <= 57) return "🌦️";
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return "🌧️";
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "🌨️";
  if (code >= 95) return "⛈️";
  return "☁️";
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

export function windValue(ms, unit = "kmh") {
  if (ms == null) return null;
  return Math.round((WIND_UNITS[unit] ?? WIND_UNITS.kmh).from(ms));
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

/** The water temperature the light used: measured, from satellite, or from the air. */
export function waterTemperature(forecast) {
  if (forecast.waterTemperature) return { celsius: forecast.waterTemperature.celsius, basis: "measured" };
  if (forecast.waterEstimate) return { celsius: forecast.waterEstimate.celsius, basis: "satellite" };
  if (forecast.waterModelC != null) return { celsius: forecast.waterModelC, basis: "air" };
  return null;
}

/** The town from an address like "Street 6, 82319 Starnberg". */
export function town(address) {
  if (!address) return null;
  const last = address.split(",").pop().trim();
  return last.replace(/^\d{4,5}\s+/, "") || null;
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
