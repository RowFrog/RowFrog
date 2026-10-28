// What a value's own page shows (ConditionDetail in the app): the big value,
// the chart's lines and limits, the facts, the rowing advice and the source.

import { t, num } from "./i18n.js";
import {
  time, dayLabel, dayTime, duration, degrees, temperature, wind, windUnit, windRange, waves, rain, distance, limitText,
  pressure, pressureChangeText, inUnit, unitSymbol, unitChange, unitId,
  currentLimits, boatInSentence, selectedBoat, iceDetail, windDial, pressureGauge, sunPath,
} from "./shared.js";
import {
  beaufort, beaufortScale, compass, REASONS, lightFor, feelsLikeNote, pressureChange, pressureTrend, sky, SKY_TITLES,
  precipitationKind, iceOff, ICE_TITLES, sunState, localDay, COLD, key,
} from "./logic.js";
import { radarAhead, rainOutlook, rainingNow, forecastRain, radarGraphic, radarEnd, peak, RADAR_CREDIT } from "./radar.js";

const HOUR = 3600 * 1000;
const FREEZING_WATER_C = 4;

/** The colours of the chart's lines and limits, as in the app. */
export const COLOURS = {
  orange: "var(--orange)", blue: "var(--blue)", purple: "var(--purple)", red: "var(--red)", teal: "var(--teal)",
  cyan: "#32ade6", gray: "#8e8e93", indigo: "#5856d6", yellow: "#e6b800", kit: "var(--kit)", deep: "#1c4d8c", secondary: "var(--sub)",
};

/**
 * The forecast seen from one hour (ConditionData): the timeline from
 * yesterday to 7 days ahead, with hours counted from `now`.
 */
export function conditionData(forecast, now, radar = null) {
  const outlook = forecast.outlook ?? [];
  const timeline = (outlook.length ? outlook : forecast.hours).slice().sort((a, b) => new Date(a.time) - new Date(b.time));
  // The rowing hours have no UV index; the outlook has it for the same hour.
  const same = timeline.find((x) => x.time === now.time);
  const hour = same ? {
    ...now, uvIndex: now.uvIndex ?? same.uvIndex, cloudCoverMidPct: now.cloudCoverMidPct ?? same.cloudCoverMidPct,
    cloudCoverHighPct: now.cloudCoverHighPct ?? same.cloudCoverHighPct,
  } : now;
  const start = new Date(hour.time).getTime();
  const x = (date) => (new Date(date).getTime() - start) / HOUR;
  const isNow = start <= Date.now() && Date.now() - start < HOUR;
  return {
    forecast, now: hour, timeline, x, isNow,
    // DWD's radar at the launch point, read while the club page is open.
    radar,
    moment: isNow ? new Date() : new Date(hour.time),
    nowLabel: isNow ? t("Now") : dayTime(hour.time),
    next24: timeline.filter((x2) => x(x2.time) >= 0 && x(x2.time) < 24),
    future: timeline.filter((x2) => x(x2.time) >= 0),
    water: forecast.waterTemperature ?? null,
    points: (value) => timeline.flatMap((x2) => {
      const v = value(x2);
      return v == null ? [] : [{ x: x(x2.time), y: v }];
    }),
  };
}

/** The same forecast seen from another hour (hours from the shown one), for the big value at the chart's line. */
export function dataAt(d, x) {
  if (Math.abs(x) < 0.5 || !d.timeline.length) return d;
  const hour = d.timeline.reduce((a, b) => (Math.abs(d.x(b.time) - x) < Math.abs(d.x(a.time) - x) ? b : a));
  if (hour.time === d.now.time) return d;
  // The rowing hour, with the boat's reasons, when there is one.
  const rowing = d.forecast.hours.find((x2) => x2.time === hour.time);
  return conditionData(d.forecast, rowing ?? hour, d.radar);
}

function extreme(hours, value, highest) {
  const known = hours.filter((x) => value(x) != null);
  if (!known.length) return null;
  return known.reduce((a, b) => (highest ? (value(b) > value(a) ? b : a) : (value(b) < value(a) ? b : a)));
}

function firstRun(hours, test) {
  const i = hours.findIndex(test);
  if (i < 0) return null;
  let j = i;
  while (j + 1 < hours.length && test(hours[j + 1])) j++;
  return { start: new Date(hours[i].time), end: new Date(new Date(hours[j].time).getTime() + HOUR) };
}

const span = (run) => `${dayTime(run.start)}–${time(run.end)}`;

function warnings(d, words) {
  return (d.forecast.warnings?.items ?? []).filter((w) => !w.isLake && (w.expires == null || new Date(w.expires) > new Date(d.now.time))
    && words.some((word) => (w.event ?? "").toUpperCase().includes(word)));
}

/** The place's warnings come from DWD (Germany, older files); else labels say "official" (ConditionsCard warningsAreDWD). */
function warningsAreDWD(d) {
  return (d.forecast.warnings?.local?.source ?? "dwd") === "dwd";
}

/** False where no warning service was read: then "no warning" must not be said. */
function warningsChecked(d) {
  return d.forecast.warnings?.local?.checked !== false;
}

const warningsLabel = (d) => (warningsAreDWD(d) ? t("DWD warnings") : t("Official warnings"));

function warningNames(d, words) {
  const found = warnings(d, words);
  if (!found.length) return t("None");
  const english = document.documentElement.lang !== "de";
  return found.map((w) => (english && w.english?.event) || w.event).join(", ");
}

const pct = (v) => (v == null ? "–" : `${num(v)} %`);
// Unrounded, and Beaufort without its steps, so a line above a limit stays above it in every unit.
const windIn = (ms) => (ms == null ? null : unitId("wind") === "bft" ? beaufortScale(ms) : inUnit("wind", ms));
const degreesIn = (c) => inUnit("temperature", c);
const wavesIn = (m) => inUnit("waves", m);

/** A limit line, marked when it is the user's own. */
function limitLine(limit, colour, label, convert = (v) => v) {
  const limits = currentLimits();
  return { value: convert(limits.value(limit)), colour, label: limits.isMine(limit) ? t("%@ (your limit)", label) : label };
}

/** The limits in use, after the explanation of the app's own. */
function inUse(pairs) {
  const limits = currentLimits();
  const parts = pairs.map(([name, amber, red]) => t("%@ amber from %@, red above %@", name, limitText(amber, limits.value(amber)), limitText(red, limits.value(red))));
  return ` ${t("In use for %@: %@. You can change them under Settings, Boats and limits.", boatInSentence(selectedBoat()), parts.join("; "))}`;
}

/** Rowing advice from the light of these reasons now and in the next 24 hours. */
function advice(d, names, { red, amber, later, calm }) {
  const light = lightFor(d.now, names);
  if (light === "red") return red;
  if (light === "amber") return amber;
  if ((d.now.notes ?? []).some((n) => names.includes(n.condition))) {
    return t("Within your own limit, but above the app's usual limit for %@: take extra care.", boatInSentence(selectedBoat()));
  }
  const next = d.next24.find((x) => lightFor(x, names) != null);
  return next ? t(later, dayTime(next.time)) : calm;
}

/** Clothing advice from the feels-like temperature, the same on the air and feels-like pages. */
function clothingAdvice(feels) {
  if (feels == null) return t("Dress in layers you can take off.");
  if (feels < 5) return t("Feels colder than %@: dress in layers, wear gloves or pogies and a hat, and keep a dry set in the boathouse.", temperature(5));
  if (feels >= 25) return t("Feels %@ or more: drink before and during the outing and protect yourself from the sun.", temperature(25));
  return t("Dress in layers you can take off.");
}

const DRAG_NOTE = () => t("Drag the chart: back to yesterday, forward up to 7 days. Hold, then slide to read a value.");

function base(overrides) {
  return {
    value: "", note: "", big: "", unit: "", lines: [], limits: [], limitInfo: null, yDomain: null, logScale: false, trendStep: null,
    windArrows: false, history: false, chartNote: null, facts: [], twoColumnFacts: false, rowing: "", source: "", ...overrides,
  };
}

function temperatureLines(d) {
  return [
    { name: t("Air"), colour: COLOURS.orange, points: d.points((x) => degreesIn(x.temperatureC)) },
    { name: t("Feels like"), colour: COLOURS.blue, points: d.points((x) => degreesIn(x.apparentTemperatureC)) },
  ];
}

const BUILDERS = {
  temperature(d) {
    const x = d.now;
    const facts = [[d.nowLabel, temperature(x.temperatureC)]];
    const lo = extreme(d.next24, (y) => y.temperatureC, false);
    const hi = extreme(d.next24, (y) => y.temperatureC, true);
    if (lo) facts.push([t("Lowest next 24 h"), t("%@ · %@", temperature(lo.temperatureC), dayTime(lo.time))]);
    if (hi) facts.push([t("Highest next 24 h"), t("%@ · %@", temperature(hi.temperatureC), dayTime(hi.time))]);
    const pastHi = extreme(d.timeline.filter((y) => d.x(y.time) < 0), (y) => y.temperatureC, true);
    if (pastHi) facts.push([t("Last 24 h"), t("highest %@", temperature(pastHi.temperatureC))]);
    return base({
      value: degrees(x.temperatureC), note: t("%@ · feels like %@", t(SKY_TITLES[sky(x.weatherCode)]), degrees(x.apparentTemperatureC)),
      unit: unitSymbol("temperature"), lines: temperatureLines(d), trendStep: unitChange("temperature", 0.5), facts, rowing: clothingAdvice(x.apparentTemperatureC),
      source: t("Deutscher Wetterdienst (DWD) via Open-Meteo, 2 m above ground."),
    });
  },

  feelsLike(d) {
    const x = d.now;
    const facts = [];
    if (x.apparentTemperatureC != null && x.temperatureC != null) {
      const diff = x.apparentTemperatureC - x.temperatureC;
      facts.push([t("Compared with the air"), t("%@° %@", num(Math.abs(unitChange("temperature", diff))), diff < 0 ? t("colder") : t("warmer"))]);
    }
    facts.push([t("Wind"), windRange(x.windSpeedMs, x.windGustMs)], [t("Humidity"), pct(x.humidityPct)],
      [t("Sun"), x.sunUp === false ? t("down") : t("up")], [t("On the water"), t("the boat's speed adds wind chill")]);
    const note = feelsLikeNote(x);
    return base({
      value: degrees(x.apparentTemperatureC), note: note ? t(note) : "", unit: unitSymbol("temperature"), lines: temperatureLines(d), trendStep: unitChange("temperature", 0.5), facts,
      rowing: clothingAdvice(x.apparentTemperatureC), source: t("Apparent temperature from air temperature, wind, humidity and sun (DWD via Open-Meteo)."),
    });
  },

  humidity(d) {
    const x = d.now;
    const misty = (y) => y.temperatureC != null && y.dewPointC != null && y.temperatureC - y.dewPointC <= 1;
    const mist = firstRun(d.next24, misty);
    const gap = x.temperatureC != null && x.dewPointC != null ? x.temperatureC - x.dewPointC : null;
    return base({
      value: pct(x.humidityPct), note: t("Dew point %@", degrees(x.dewPointC)),
      unit: "%", lines: [{ name: t("Humidity"), colour: COLOURS.teal, points: d.points((y) => y.humidityPct) }], yDomain: [0, 130], trendStep: 2.5,
      facts: [
        [t("Dew point"), temperature(x.dewPointC)],
        [t("Air minus dew point"), t("%@° (mist forms near 0–1°)", gap == null ? "–" : num(unitChange("temperature", gap)))],
        [t("Mist likely"), mist ? span(mist) : t("not in the next 24 h")],
      ],
      rowing: mist ? t("When air and dew point meet, mist forms over the water: check visibility before going out early.")
        : t("No mist expected from the humidity in the next 24 hours."),
      source: t("Relative humidity and dew point, DWD via Open-Meteo."),
    });
  },

  wind(d) {
    const x = d.now;
    const gust = extreme(d.next24, (y) => y.windGustMs, true);
    const facts = [[t("Beaufort"), x.windSpeedMs == null ? "–" : String(beaufort(x.windSpeedMs))]];
    if (x.windFromDeg != null) facts.push([t("From"), `${compass(x.windFromDeg)} (${num(x.windFromDeg)}°)`]);
    if (x.fetchM != null) facts.push([t("Open water upwind"), distance(x.fetchM)]);
    if (gust) facts.push([t("Strongest gust next 24 h"), t("%@ · %@", wind(gust.windGustMs), dayTime(gust.time))]);
    return base({
      value: wind(x.windSpeedMs),
      note: t("Gusts %@", wind(x.windGustMs)) + (x.windFromDeg != null ? ` · ${t("from %@", compass(x.windFromDeg))}` : ""),
      big: windDial(x), unit: windUnit(),
      lines: [
        { name: t("Wind"), colour: COLOURS.blue, points: d.points((y) => windIn(y.windSpeedMs)) },
        { name: t("Gusts"), colour: COLOURS.purple, points: d.points((y) => windIn(y.windGustMs)) },
      ],
      limits: [limitLine("windAmber", COLOURS.orange, t("Wind: row with care"), windIn), limitLine("windRed", COLOURS.red, t("Wind: stay ashore"), windIn)],
      limitInfo: t("Amber from %@ (Beaufort 4, the first whitecaps) and red from %@ (Beaufort 5, many whitecaps): in a single or double the boat gets hard to steer and water comes over the side. Gusts have their own limits: amber from %@ and red from %@ (46 km/h), the level at which DWD issues a strong-wind warning and the lake's warning lights start flashing. These are the app's starting values for small boats.",
        limitText("windAmber", 5.5), limitText("windRed", 8), limitText("gustAmber", 8), limitText("gustRed", 12.8))
        + inUse([[t("Wind"), "windAmber", "windRed"], [t("Gusts"), "gustAmber", "gustRed"]]),
      windArrows: true,
      // The scrub label names whole forces, as the big value does.
      valueText: unitId("wind") === "bft" ? (y) => `${Math.round(y)} Bft` : null,
      chartNote: t("The arrows above the chart show where the wind blows to. Drag the chart: back to yesterday, forward up to 7 days. Hold, then slide to read a value."),
      facts,
      rowing: advice(d, REASONS.wind, {
        red: t("Too windy now: stay ashore."), amber: t("Windy now: row with care and stay near the shore."),
        later: key("Calm enough now; the wind reaches the limit from %@."), calm: t("Calm enough for the next 24 hours."),
      }),
      source: t("Wind at 10 m and gusts, DWD ICON via Open-Meteo."),
    });
  },

  waves(d) {
    const x = d.now;
    const limits = currentLimits();
    const top = extreme(d.next24, (y) => y.waveHeightM, true);
    const facts = [];
    if (x.fetchM != null) facts.push([t("Open water upwind"), x.fetchM < 50 ? t("none, the wind blows off the shore") : distance(x.fetchM)]);
    if (top) facts.push([t("Highest next 24 h"), t("%@ · %@", waves(top.waveHeightM), dayTime(top.time))]);
    const highest = Math.max(0, ...d.timeline.map((y) => y.waveHeightM ?? 0));
    return base({
      value: waves(x.waveHeightM), note: (x.fetchM ?? 100) < 50 ? t("Wind blows off the shore") : t("At the launch point"), unit: unitSymbol("waves"),
      lines: [{ name: t("Waves"), colour: COLOURS.blue, points: d.points((y) => inUnit("waves", y.waveHeightM)) }],
      limits: [limitLine("waveAmber", COLOURS.orange, t("Row with care"), wavesIn), limitLine("waveRed", COLOURS.red, t("Stay ashore"), wavesIn)],
      limitInfo: t("Amber from %@ and red from %@ wave height. A racing single sits only about 10–15 cm above the water at its side, so from about 15 cm waves start to wash in; from about 30 cm the boat fills and capsizing becomes likely. The waves are calculated from the wind and the open water upwind, not measured.",
        waves(0.15), waves(0.3)) + inUse([[t("Waves"), "waveAmber", "waveRed"]]),
      yDomain: [0, wavesIn(Math.max((limits.value("waveRed") * 4) / 3, highest * 1.3))], trendStep: unitChange("waves", 0.015), facts,
      rowing: advice(d, ["waves"], {
        red: t("Waves are too high now: stay ashore."), amber: t("Waves now: row with care; small boats take on water."),
        later: key("Flat enough now; the waves reach the limit from %@."), calm: t("Flat enough for the next 24 hours."),
      }),
      source: t("Calculated by the app from wind and the lake's shape (fetch), not measured."),
    });
  },

  waterTemperature(d) {
    const limits = currentLimits();
    const now = d.water;
    const history = now?.history ?? [];
    const facts = [];
    if (history.length > 1) {
      const change = history[history.length - 1].celsius - history[0].celsius;
      facts.push([t("Trend"), t("%@° since %@", (change >= 0 ? "+" : "−") + num(Math.abs(unitChange("temperature", change)), 1), dayLabel(history[0].time))]);
    }
    const jacket = temperature(limits.value("lifeJacket"));
    facts.push([t("Life jacket"), limits.isMine("lifeJacket") ? t("%@ (your limit)", t("advised below %@", jacket)) : t("advised below %@", jacket)]);
    const veryCold = temperature(COLD.waterC);
    const c = now?.celsius;
    let rowing;
    if (c == null) rowing = t("No lake station: check the water yourself. Below %@ we advise a life jacket.", jacket);
    else if (c < COLD.waterC) rowing = t("Below %@ wear a life jacket, stay near the shore and row with a second boat or a safety boat nearby. Wear clothes that keep you warm when wet.", veryCold);
    else if (c < limits.value("lifeJacket")) rowing = t("Below %@ a capsize can cause cold-water shock: we advise a life jacket and clothes that keep you warm when wet.", jacket);
    else if (c < 15) rowing = t("Below %@ wear clothes that keep you warm when wet. Below %@ we advise a life jacket.", temperature(15), jacket);
    else rowing = t("Warm enough that a capsize is not a cold-water danger.");
    const satellite = now ? null : d.forecast.waterEstimate?.reading ?? null;
    const estimate = now ? null : (d.forecast.waterEstimate?.celsius ?? d.forecast.waterModelC ?? null);
    // Today's water carried on with the forecast air, dashed after the measurements.
    const days = (d.forecast.waterForecast ?? []).map((day) => [new Date(`${day.date}T12:00:00`), day.celsius]);
    const ahead = days.filter(([at]) => at > new Date());
    const forecastPoints = [];
    if (ahead.length) {
      const last = history[history.length - 1];
      if (last) forecastPoints.push({ x: d.x(last.time), y: degreesIn(last.celsius) });
      else if (days[0]) forecastPoints.push({ x: d.x(new Date()), y: degreesIn(days[0][1]) });
      forecastPoints.push(...ahead.map(([at, v]) => ({ x: d.x(at), y: degreesIn(v) })));
    }
    const today = localDay(new Date().toISOString());
    const pickedDay = localDay(d.now.time);
    const picked = !d.isNow && pickedDay !== today ? (d.forecast.waterForecast ?? []).find((day) => day.date === pickedDay)?.celsius ?? null : null;
    if (picked != null) facts.unshift([t("Forecast %@", dayLabel(d.now.time)), temperature(picked, 1)]);
    if (satellite) facts.push([t("Satellite"), t("%@, %@: %@", satellite.satelliteName ?? "", satellite.when ?? "", temperature(satellite.celsius, 1))]);
    let source;
    if (satellite) {
      source = satellite.source === "landsat"
        ? t("Landsat surface temperature (U.S. Geological Survey, via Microsoft Planetary Computer), carried forward to today with the air temperatures.")
        : t("Copernicus Land Monitoring Service, Lake Surface Water Temperature (Sentinel-3), carried forward to today with the air temperatures.");
    } else if (!now && estimate != null) source = t("Calculated by the app from the air temperatures of the last weeks, not measured.");
    else if (now) source = t("%@, the nearest station on this water.", now.station?.operatorName ?? now.station?.operator ?? "");
    else source = t("No station measures the water of this lake, and no satellite has seen it clearly in the last 30 days.");
    const lines = history.length ? [{ name: t("Measurement"), colour: COLOURS.cyan, points: history.map((p) => ({ x: d.x(p.time), y: degreesIn(p.celsius) })) }] : [];
    if (forecastPoints.length > 1) lines.push({ name: t("Forecast"), colour: COLOURS.cyan, points: forecastPoints, dashed: true });
    const highest = Math.max(0, ...history.map((p) => p.celsius), ...days.map(([, v]) => v));
    const chartLimits = [
      limitLine("lifeJacket", COLOURS.kit, t("Cold-water shock: life jacket"), degreesIn),
      { value: degreesIn(COLD.waterC), colour: COLOURS.deep, label: t("Very cold") },
    ];
    const common = {
      unit: unitSymbol("temperature"), lines, limits: chartLimits, yDomain: [degreesIn(0), degreesIn(Math.max(20, highest + 2))], history: true, facts, rowing, source,
      chartNote: forecastPoints.length > 1 ? t("Measurements of the last days; dashed, the forecast from the air temperatures. Touch the chart to read a value.") : null,
    };
    if (picked != null) {
      return base({ ...common, value: `≈ ${degrees(picked, 1)}`, note: t("Forecast for %@, from today's water and the forecast air temperatures", dayLabel(d.now.time)) });
    }
    let note;
    if (now) note = t("Measured %@", dayTime(now.measuredAt));
    else if (satellite) note = t("Estimated from %@ (%@) and the air temperatures since, not measured", satellite.satelliteName ?? "", satellite.when ?? "");
    else note = estimate != null ? t("Estimated from the air temperatures of the last weeks, not measured") : t("No lake station");
    return base({
      ...common, value: estimate != null ? `≈ ${degrees(estimate)}` : degrees(c, 1), note,
      limitInfo: t("Below about %@ a fall into the water causes cold-water shock: a gasp and fast breathing in the first minute. A life jacket keeps your head above water through it, so the app advises one from %@ down. A rule of thumb says the minutes you can still help yourself in the water are about the water temperature in °C, so about 10 minutes at 10 °C. That is why the advice gets stricter below %@: stay near the shore and don't row alone. Your club's own rules come first.",
        temperature(15), jacket, veryCold)
        + " " + t("Cold water does not change the rowing light: the blue life-jacket badge under it shows what to bring. Below %@ the app's wind and gust limits are %@ lower, and below %@ small boats get an amber warning.",
          veryCold, wind(COLD.marginMs), temperature(FREEZING_WATER_C)),
    });
  },

  precipitation(d) {
    const x = d.now;
    const total = d.next24.reduce((s, y) => s + (y.precipitationMm ?? 0), 0);
    const top = extreme(d.next24, (y) => y.precipitationMm, true);
    const kinds = [...new Set(d.next24.filter((y) => (y.precipitationMm ?? 0) >= 0.1).map((y) => precipitationKind(sky(y.weatherCode))).filter(Boolean).map((k) => t(k)))].sort();
    const light = lightFor(x, REASONS.precipitation);
    const lightText = light === "red" ? t("red: hail") : light === "amber" ? t("amber: heavy rain") : t("green: under %@ per hour", rain(4));
    const facts = [[t("Next 24 h"), t("%@ in total", rain(total))], [t("Kind"), kinds.length ? kinds.join(", ") : t("dry")]];
    if (top && (top.precipitationMm ?? 0) >= 0.1) facts.push([t("Heaviest"), t("%@ · %@", rain(top.precipitationMm), dayTime(top.time))]);
    facts.push([warningsLabel(d), warningNames(d, ["REGEN", "HAGEL", "GEWITTER", "SCHNEE"])], [t("Rowing light now"), lightText]);
    const wet = (x.precipitationMm ?? 0) >= 0.1;
    const first = forecastRain(d);
    const kind = precipitationKind(sky(x.weatherCode));
    let value = wet ? rain(x.precipitationMm) : t("Dry");
    let note = wet ? (kind ? t(kind) : "") : first ? t("Expected from %@", dayTime(first.time)) : t("Dry next 24 h");
    let big = "";
    const lines = [{ name: t("Precipitation"), colour: COLOURS.blue, kind: "bars", points: d.points((y) => inUnit("rain", y.precipitationMm)) }];
    let source = t("Precipitation per hour and weather code, DWD via Open-Meteo. Official warnings appear under the warnings.");
    // The next two hours from DWD's radar, in quarter hours, in front of the forecast's hours.
    const ahead = radarAhead(d);
    if (ahead) {
      const outlook = rainOutlook(ahead, d.timeline);
      value = rainingNow(ahead) ? rain(ahead.steps[0].mm) : t("Dry");
      if (outlook.now && outlook.next) {
        note = outlook.next.fromRadar ? t("Radar: %@ · %@", outlook.now, outlook.next.text) : `${t("Radar: %@", outlook.now)} · ${outlook.next.text}`;
      } else {
        note = t("Radar: %@", outlook.summary);
      }
      facts.unshift([t("Radar, next 2 h"), outlook.summary]);
      big = radarGraphic(d);
    }
    if (d.radar?.steps.length) {
      lines[0].name = t("Forecast");
      lines.push({
        name: t("Radar"), colour: COLOURS.indigo, kind: "bars", barWidth: 2.5,
        points: d.radar.steps.map((s) => ({ x: d.x(s.time), y: inUnit("rain", s.mm) })),
        covers: [d.x(d.radar.steps[0].time) - 0.5, d.x(radarEnd(d.radar))],
      });
      source += ` ${t(RADAR_CREDIT)}`;
    }
    const highest = Math.max(0, ...d.timeline.map((y) => y.precipitationMm ?? 0), d.radar ? peak(d.radar) : 0);
    return base({
      value, note, big,
      unit: unitSymbol("rain"), lines,
      limits: [{ value: inUnit("rain", 4), colour: COLOURS.orange, label: t("Heavy rain") }],
      limitInfo: t("%@ per hour is a common line for heavy rain (the UK Met Office uses it; DWD only warns from 15 mm per hour). From there you are soaked within minutes, visibility drops and a long outing takes on water: amber. Hail always counts as red. Official warnings for heavy rain or hail always make the light red or amber as well.", rain(4)),
      yDomain: [0, inUnit("rain", Math.max(6, highest * 1.2))], facts,
      rowing: advice(d, REASONS.precipitation, {
        red: t("Hail is forecast: stay ashore."), amber: t("Heavy rain now: you are soaked quickly and see less; keep the outing short."),
        later: key("Heavy rain or hail from %@: plan to be back before then."), calm: t("No heavy rain or hail in the next 24 hours."),
      }),
      source,
    });
  },

  visibility(d) {
    const x = d.now;
    const fogHour = (y) => (y.visibilityM ?? Infinity) < 1000;
    const fog = firstRun(d.next24, fogHour);
    const thickest = extreme(d.next24.filter(fogHour), (y) => y.visibilityM, false);
    const mist = firstRun(d.next24, (y) => (y.visibilityM ?? Infinity) >= 1000 && (y.visibilityM ?? Infinity) < 5000);
    const facts = [];
    if (fog) {
      facts.push([t("Fog"), span(fog) + (thickest ? ` · ${t("thickest %@", distance(thickest.visibilityM))}` : "")]);
      const clear = d.future.find((y) => new Date(y.time) >= fog.end && (y.visibilityM ?? Infinity) >= 1000 && y.sunUp !== false);
      facts.push([t("Rowing possible"), clear ? t("from about %@ by visibility", dayTime(clear.time)) : t("not in the forecast")]);
    } else facts.push([t("Fog"), t("not in the next 24 h")]);
    facts.push([t("Mist"), mist ? span(mist) : t("not in the next 24 h")], [warningsAreDWD(d) ? t("DWD fog warning") : t("Official fog warning"), warningNames(d, ["NEBEL"])],
      [t("Lake view"), t("fog shows as a banner over the whole lake")]);
    return base({
      value: distance(x.visibilityM), note: fogHour(x) ? t("Fog now") : fog ? t("Fog expected %@", span(fog)) : t("No fog in the next 24 h"), unit: unitSymbol("distance"),
      lines: [{ name: t("Visibility"), colour: COLOURS.gray, points: d.points((y) => (y.visibilityM == null ? null : inUnit("distance", Math.max(y.visibilityM, 50)))) }],
      limits: [
        { value: inUnit("distance", 5000), colour: COLOURS.secondary, label: t("Mist") },
        { value: inUnit("distance", 1000), colour: COLOURS.orange, label: t("Fog: row with care") },
        { value: inUnit("distance", 500), colour: COLOURS.red, label: t("Stay ashore") },
      ],
      limitInfo: t("Fog means visibility under %@ (the WMO definition): amber. Under %@ you see another boat or a passenger ship only about 2 minutes ahead at rowing speed, and you lose sight of the shore: red. Mist (up to %@) has no limit, but the app mentions it because it often thickens into fog. The scale is stretched at the bottom so short distances are easy to read.",
        distance(1000), distance(500), distance(5000)),
      yDomain: [inUnit("distance", 50), inUnit("distance", 80000)], logScale: true, trendStep: unitChange("distance", 1000), facts,
      rowing: advice(d, ["fog"], {
        red: t("Thick fog now: stay ashore."), amber: t("Fog now: row with care, close to the shore, and carry a light."),
        later: key("Clear now; fog from %@."), calm: t("No fog in the next 24 hours."),
      }),
      source: t("Visibility, DWD via Open-Meteo."),
    });
  },

  cloudCover(d) {
    const x = d.now;
    const sunny = firstRun(d.next24, (y) => (y.cloudCoverPct ?? 100) < 40 && y.sunUp === true);
    return base({
      value: pct(x.cloudCoverPct), note: t("Low cloud %@ %%", num(x.cloudCoverLowPct)), unit: "%",
      lines: [
        { name: t("All cloud"), colour: COLOURS.gray, points: d.points((y) => y.cloudCoverPct) },
        { name: t("High cloud"), colour: COLOURS.cyan, points: d.points((y) => y.cloudCoverHighPct) },
        { name: t("Middle cloud"), colour: COLOURS.teal, points: d.points((y) => y.cloudCoverMidPct) },
        { name: t("Low cloud"), colour: COLOURS.indigo, points: d.points((y) => y.cloudCoverLowPct) },
      ].filter((l) => l.points.length),
      yDomain: [0, 130], trendStep: 5,
      facts: [
        [t("Sunny spells"), sunny ? span(sunny) : t("not in the next 24 h")], [t("High cloud"), pct(x.cloudCoverHighPct)],
        [t("Middle cloud"), pct(x.cloudCoverMidPct)], [t("Low cloud"), pct(x.cloudCoverLowPct)],
      ],
      rowing: t("No effect on the rowing light; low cloud often comes with poor visibility."), source: t("Cloud cover, DWD via Open-Meteo."),
    });
  },

  pressure(d) {
    const x = d.now;
    const change = pressureChange(d.timeline, x);
    const trend = change == null ? null : pressureTrend(change);
    const values = d.timeline.map((y) => y.pressureHpa).filter((v) => v != null);
    const lo = values.length ? Math.min(...values) : 1000;
    const hi = values.length ? Math.max(...values) : 1030;
    const facts = [];
    const next = x.pressureHpa == null ? null : pressureNext24(x.pressureHpa, d.next24);
    if (next) facts.push([t("Next 24 h"), next]);
    const low = extreme(d.future, (y) => y.pressureHpa, false);
    if (low) facts.push([t("Lowest next 7 days"), t("%@ · %@", pressure(low.pressureHpa), dayTime(low.time))]);
    const high = (x.pressureHpa ?? 1013) >= 1013;
    let state;
    if (change != null && change <= -1) state = high ? t("high pressure, but falling: the weather is changing") : t("low pressure and falling: unsettled");
    else if (change != null && change >= 1) state = high ? t("high pressure and rising: settled") : t("low pressure, but rising: improving");
    else state = high ? t("high pressure: mostly settled") : t("low pressure: changeable");
    facts.push([d.nowLabel, state]);
    let rowing;
    if (change != null && change <= -3) rowing = t("Falling fast: wind is likely soon.");
    else if (change != null && change <= -1) rowing = t("Falling: wind and rain more likely in the next day or two.");
    else if (change != null && change >= 1) rowing = t("Rising: the weather is settling.");
    else rowing = t("Steady: no change in the weather expected from the pressure.");
    return base({
      value: pressure(x.pressureHpa),
      note: change == null ? "" : trend === "Steady" ? t("Steady next 3 h") : t("%@ %@ in 3 h", t(trend), pressureChangeText(Math.abs(change))),
      big: pressureGauge(x.pressureHpa, trend), unit: unitSymbol("pressure"),
      lines: [{ name: t("Air pressure"), colour: COLOURS.purple, points: d.points((y) => inUnit("pressure", y.pressureHpa)) }],
      yDomain: [inUnit("pressure", Math.floor(lo - 4)), inUnit("pressure", Math.ceil(hi + 6))], trendStep: unitChange("pressure", 0.25), facts,
      rowing: (change ?? 0) <= -3 ? rowing : `${rowing} ${t("Falling %@ or more in 3 hours often means wind soon.", pressureChangeText(3))}`,
      source: t("Air pressure at sea level, DWD via Open-Meteo."),
    });
  },

  thunderstorm(d) {
    const top = extreme(d.next24, (y) => y.capeJkg, true);
    const facts = [];
    if (top && (top.capeJkg ?? 0) > 0) facts.push([t("Most energy next 24 h"), t("%@ J/kg · %@", num(top.capeJkg), dayTime(top.time))]);
    facts.push([warningsLabel(d), warningNames(d, ["GEWITTER"])]);
    const light = lightFor(d.now, REASONS.thunderstorm);
    return base({
      value: light === "red" ? t("High") : light === "amber" ? t("Possible") : t("Low"),
      note: !warningsChecked(d) ? t("Warnings not checked")
        : !warningsAreDWD(d) ? (warnings(d, ["GEWITTER"]).length ? t("Official thunderstorm warning") : t("No official thunderstorm warning"))
        : warnings(d, ["GEWITTER"]).length ? t("DWD thunderstorm warning") : t("No DWD thunderstorm warning"),
      unit: "J/kg",
      lines: [{ name: t("Energy for storms (CAPE)"), colour: COLOURS.yellow, kind: "bars", points: d.points((y) => y.capeJkg) }],
      limits: [{ value: 500, colour: COLOURS.orange, label: t("Possible") }, { value: 1000, colour: COLOURS.red, label: t("Likely") }],
      limitInfo: t("CAPE is the energy the air has for rising, in J/kg. From 500 J/kg thunderstorms are possible if something sets them off (amber); from 1000 J/kg together with rain they are likely (red). This is the app's own estimate; an official thunderstorm warning always makes the light red."),
      yDomain: [0, Math.max(1300, Math.max(0, ...d.timeline.map((y) => y.capeJkg ?? 0)) * 1.1)], facts,
      rowing: t("If you hear thunder, head for the shore at once: lightning can strike 10 km ahead of a storm."),
      source: t("Estimated from the forecast (CAPE); official warnings appear under the warnings."),
    });
  },

  uvIndex(d) {
    const x = d.now;
    const top = extreme(d.next24, (y) => y.uvIndex, true);
    const protect = firstRun(d.next24, (y) => Math.round(y.uvIndex ?? 0) >= 3);
    const hot = d.future.find((y) => (y.apparentTemperatureC ?? 0) >= 25);
    const facts = [[d.nowLabel, x.uvIndex == null ? "–" : `${num(x.uvIndex)} (${uvBand(x.uvIndex)})`]];
    if (top?.uvIndex != null) facts.push([t("Highest next 24 h"), t("%@ (%@) · %@", num(top.uvIndex), uvBand(top.uvIndex), dayTime(top.time))]);
    facts.push([t("Protection needed"), protect ? span(protect) : t("not in the next 24 h")]);
    const day = (d.forecast.daylight ?? []).map((y) => ({ sunrise: new Date(y.sunrise), sunset: new Date(y.sunset) }))
      .sort((a, b) => a.sunrise - b.sunrise).find((y) => y.sunset > new Date());
    if (day) {
      const plus = (date, ms) => new Date(date.getTime() + ms);
      facts.push([t("Low sun, glare"), `${time(day.sunrise)}–${time(plus(day.sunrise, HOUR))}, ${time(plus(day.sunset, -HOUR))}–${time(day.sunset)}`]);
    }
    facts.push([t("Feels %@ or more", temperature(25)), hot ? dayTime(hot.time) : t("not this week")]);
    return base({
      value: x.uvIndex == null ? "–" : num(x.uvIndex), note: x.uvIndex == null ? t("No UV forecast") : uvBand(x.uvIndex), unit: t("UV"),
      lines: [{ name: t("UV index"), colour: COLOURS.orange, kind: "bars", points: d.points((y) => y.uvIndex) }],
      limits: [
        { value: 3, colour: COLOURS.orange, label: t("Moderate: protect") }, { value: 6, colour: COLOURS.red, label: t("High") },
        { value: 8, colour: COLOURS.purple, label: t("Very high") },
      ],
      limitInfo: t("These are the WHO UV bands: 0–2 low, 3–5 moderate, 6–7 high, 8–10 very high, 11 and more extreme. From 3 the WHO advises sun protection. On the water the surface reflects extra UV and outings are long, so the app gives its advice from 3. UV does not change the rowing light."),
      yDomain: [0, Math.max(10, Math.max(0, ...d.timeline.map((y) => y.uvIndex ?? 0)) + 1)], facts, twoColumnFacts: true,
      rowing: protect
        ? t("From UV 3: sunscreen SPF 30 or more, also on neck, ears and the backs of the knees, a cap and sunglasses. When it feels %@ or more, drink before and during the outing.", temperature(25))
        : t("No sun protection needed for UV in the next 24 hours; sunglasses still help against glare."),
      source: t("UV index forecast via Open-Meteo; bands from the WHO. Glare times calculated by the app from sunrise and sunset."),
    });
  },

  ice(d) {
    const ice = d.forecast.ice;
    const rowing = t("Never go onto the ice because of this app. Never row between ice floes; thin ice cuts hulls.");
    const explanation = t("Estimated from the last weeks' frost and the water temperature, and on larger lakes checked against the Copernicus satellite ice map when clouds allow. Likely ice turns the light red, possible ice at the shore or drift ice amber. Never go onto the ice because of this app.");
    const water = temperature(ice?.waterTemperatureC ?? d.water?.celsius, 1);
    if (iceOff(ice)) {
      return base({ value: t("Off season"), note: t("Ice estimates run from November to April. There is no ice estimate at this time of year."), facts: [[t("Water"), water]], rowing, source: explanation });
    }
    if (ice && ice.status !== "unavailable") {
      const facts = [[t("Water"), water]];
      if (ice.thicknessCm > 0) facts.push([t("Ice"), t("About %@ cm, estimated", num(ice.thicknessCm))]);
      if (ice.satellite?.summary) facts.push([t("Satellite"), ice.satellite.summary]);
      return base({ value: t(ICE_TITLES[ice.status] ?? "No data"), note: iceDetail(ice), facts, rowing, source: explanation });
    }
    const warm = (d.water?.celsius ?? 0) >= 8;
    return base({
      value: warm ? t("No ice") : t("No data yet"),
      note: warm ? t("Water %@, too warm for ice", temperature(d.water?.celsius, 1)) : t("Check the lake yourself"),
      facts: [[t("Water"), temperature(d.water?.celsius, 1)], [t("Basis"), t("measured water temperature")]], rowing,
      source: t("An ice estimate from water temperature and frost is being built; until then check the lake yourself in winter."),
    });
  },

  daylight(d) {
    const days = (d.forecast.daylight ?? []).map((y) => ({ sunrise: new Date(y.sunrise), sunset: new Date(y.sunset) })).sort((a, b) => a.sunrise - b.sunrise);
    const moment = d.moment;
    const sameDay = (a, b) => localDay(a.toISOString()) === localDay(b.toISOString());
    const today = days.find((y) => sameDay(y.sunrise, moment)) ?? days[0];
    const tomorrow = days.find((y) => sameDay(y.sunrise, new Date(moment.getTime() + 24 * HOUR)));
    const facts = [];
    if (today) {
      facts.push([t("Sunrise"), time(today.sunrise)], [t("Sunset"), time(today.sunset)], [t("Daylight"), duration(today.sunrise, today.sunset)]);
      if (tomorrow) {
        const change = Math.trunc(((tomorrow.sunset - tomorrow.sunrise) - (today.sunset - today.sunrise)) / 60000);
        facts.push([t("Tomorrow"), change < 0 ? t("%@ min shorter", String(-change)) : t("%@ min longer", String(change))],
          [t("Tomorrow sunrise"), time(tomorrow.sunrise)], [t("Tomorrow sunset"), time(tomorrow.sunset)]);
      }
    }
    const sun = sunState(d.forecast, moment);
    let value = "–";
    let note = "";
    if (sun?.up) {
      value = t("Sunset %@", time(sun.sunset));
      note = t("Sun is up. Rowing advised for %@ until sunset.", duration(moment, sun.sunset));
    } else if (sun) {
      value = t("Sunrise %@", time(sun.sunrise));
      note = t("Sun is down. Rowing is advised again from sunrise at %@.", time(sun.sunrise));
    }
    return base({
      value, note, big: today ? sunPath(today.sunrise, today.sunset, moment, 120, 60) : "", facts, twoColumnFacts: true,
      rowing: t("Rowing is advised from sunrise to sunset; in twilight carry lights."), source: t("Calculated by the app from the launch point's position."),
    });
  },
};


function uvBand(uv) {
  const r = Math.round(uv);
  if (r < 3) return t("low");
  if (r < 6) return t("moderate");
  if (r < 8) return t("high");
  if (r < 11) return t("very high");
  return t("extreme");
}

/** The pressure over the next 24 hours by its biggest move, so a dip that recovers is not called steady. */
export function pressureNext24(now, hours) {
  const known = hours.filter((x) => x.pressureHpa != null);
  if (!known.length) return null;
  const lo = known.reduce((a, b) => (b.pressureHpa < a.pressureHpa ? b : a));
  const hi = known.reduce((a, b) => (b.pressureHpa > a.pressureHpa ? b : a));
  const last = known[known.length - 1].pressureHpa;
  const fall = now - lo.pressureHpa;
  const rise = hi.pressureHpa - now;
  if (Math.max(fall, rise) < 1) return t("steady");
  if (fall >= rise) {
    return last - lo.pressureHpa >= 1 ? t("falls to %@ by %@, then rises", pressure(lo.pressureHpa), dayTime(lo.time)) : t("falls to %@ by %@", pressure(lo.pressureHpa), dayTime(lo.time));
  }
  return hi.pressureHpa - last >= 1 ? t("rises to %@ by %@, then falls", pressure(hi.pressureHpa), dayTime(hi.time)) : t("rises to %@ by %@", pressure(hi.pressureHpa), dayTime(hi.time));
}

/** What a value's page shows for the data. */
export function conditionDetail(condition, d) {
  return BUILDERS[condition](d);
}

export const dragNote = DRAG_NOTE;
