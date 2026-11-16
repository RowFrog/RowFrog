// The chart of a value's page (ConditionChart in the app): 24 hours visible,
// scrolled sideways from yesterday to 7 days ahead, limits as dashed lines,
// one arrow per 3 hours on top, the blue line at the hour of the big value
// and the green map marker with the hours that have maps.

import { t, num, locale } from "./i18n.js";
import { h, time as clock, dayTime } from "./shared.js";
import { icon } from "./icons.js";

const START = -1;
const LABEL_H = 15;
/** Room on the right for the value scale, as Swift Charts' trailing y axis. */
const AXIS_W = 28;

/** Round steps for the value scale, as Swift Charts' automatic marks: about four intervals of 1, 2 or 5 (no 2,5 steps, owner 14 Nov 2026: web showed 7,5 / 10,0 / 12,5 where the app shows 8 / 10 / 12). */
export function yTicks(lo, hi, log = false) {
  if (!(hi > lo)) return [];
  if (log) {
    const out = [];
    for (let e = Math.floor(Math.log10(Math.max(lo, 1e-6))); 10 ** e <= hi; e++) if (10 ** e >= lo) out.push(10 ** e);
    return out;
  }
  const raw = (hi - lo) / 4;
  const mag = 10 ** Math.floor(Math.log10(raw));
  const steps = [1, 2, 5, 10, 20].map((f) => f * mag).filter((v) => v >= raw * 0.75);
  // At most five marks: the next bigger step when a smaller one gives more.
  for (const step of steps) {
    const out = [];
    for (let i = Math.ceil(lo / step - 1e-9); i * step <= hi + 1e-9; i++) out.push(Number((i * step).toPrecision(12)) + 0);
    if (out.length <= 5 || step === steps[steps.length - 1]) return out;
  }
  return [];
}
// Teal, as the app (Color(.systemTeal)), owner's pick 14 Nov 2026: green read as the rowing light, grey as "no forecast".
const MAP_GREEN = "var(--map-teal)";

/**
 * The hour shared by the chart and the map (DetailTime): `hour` is the blue
 * line, the map shows it while linked and its own `mapHour` while not.
 */
export function detailTime(linked) {
  return {
    hour: 0, mapHour: 0, linked, mapHours: null, scrollX: START, listeners: new Set(),
    get shownMapHour() { return this.linked ? this.hour : this.mapHour; },
    get mapFrameHour() {
      if (!this.mapHours?.length) return null;
      const x = this.shownMapHour;
      return this.mapHours.reduce((a, b) => (Math.abs(b - x) < Math.abs(a - x) ? b : a));
    },
    get mapOutOfRange() {
      if (!this.mapHours?.length) return false;
      const x = this.shownMapHour;
      return x < this.mapHours[0] - 0.5 || x > this.mapHours[this.mapHours.length - 1] + 0.5;
    },
    changed() { for (const f of this.listeners) f(); },
    setChart(x) {
      const r = Math.round(x);
      if (r !== this.hour) { this.hour = r; this.changed(); }
    },
    setMap(x) {
      if (this.linked) this.setChart(x);
      else if (x !== this.mapHour) { this.mapHour = x; this.changed(); }
    },
    setLinked(on) {
      if (on === this.linked) return;
      if (on) this.hour = this.mapHour;
      else this.mapHour = this.hour;
      this.linked = on;
      this.changed();
    },
    back() {
      this.scrollX = START;
      this.hour = 0;
      this.changed();
    },
  };
}

function extent(detail, data) {
  const xs = detail.lines.flatMap((l) => l.points.map((p) => p.x));
  let lo = xs.length ? Math.min(...xs) : 0;
  let hi = xs.length ? Math.max(...xs) : 24;
  if (detail.history && !data.isNow) {
    hi = Math.max(hi, 0);
    lo = Math.min(lo, 0);
  }
  return [lo, Math.max(hi, lo + 1)];
}

function domain(detail) {
  if (detail.yDomain) return detail.yDomain;
  const values = [...detail.lines.flatMap((l) => l.points.map((p) => p.y)), ...detail.limits.map((l) => l.value)];
  const lo = values.length ? Math.min(...values) : 0;
  const hi = values.length ? Math.max(...values) : 1;
  const span = Math.max(hi - lo, 0.1);
  const bottom = lo >= 0 && detail.trendStep == null ? 0 : lo - span * 0.1;
  const room = detail.trendStep == null && !detail.windArrows ? 0.1 : 0.3;
  return [bottom, hi + span * room];
}

/** The point a line has at an hour, or null where it doesn't reach (measurements end now, a forecast starts there). */
function valueAt(line, x) {
  const pts = line.points;
  if (!pts.length) return null;
  const start = line.dashed && pts.length > 1 ? pts[0].x + 0.5 : pts[0].x - 0.75;
  if (x < start || x > pts[pts.length - 1].x + 0.75) return null;
  return pts.reduce((a, b) => (Math.abs(b.x - x) < Math.abs(a.x - x) ? b : a));
}

function valueText(y, unit) {
  const digits = Math.abs(y) < 1 ? 2 : Math.abs(y) < 10 ? 1 : 0;
  return num(y, digits) + (unit ? ` ${unit}` : "");
}

function arrows(detail, data) {
  if (detail.windArrows) {
    return data.timeline.flatMap((x) => {
      const at = data.x(x.time);
      return at % 3 === 0 && x.windFromDeg != null ? [{ x: at + 1, rotate: x.windFromDeg, symbol: "↓" }] : [];
    });
  }
  const pts = detail.lines[0]?.points ?? [];
  if (detail.trendStep == null || pts.length <= 3) return [];
  const out = [];
  for (let i = 0; i < pts.length - 3; i += 3) {
    if (pts[i].x % 1 !== 0) continue;
    const change = pts[i + 3].y - pts[i].y;
    out.push({ x: pts[i].x + 1.5, rotate: 0, symbol: change > detail.trendStep ? "↑" : change < -detail.trendStep ? "↓" : "=" });
  }
  return out;
}

/**
 * A smooth path through the points: monotone cubic interpolation (Fritsch–Carlson), as Swift
 * Charts' .interpolationMethod(.monotone) in the app. The old curve was flat at every hour, so
 * lines looked stepped (owner, 14 Nov 2026: website follows the app).
 */
export function path(points, px, py) {
  if (!points.length) return "";
  const xs = points.map((p) => px(p.x));
  const ys = points.map((p) => py(p.y));
  const n = points.length;
  const f = (v) => v.toFixed(1);
  if (n < 3) return `M${f(xs[0])},${f(ys[0])}${n === 2 ? ` L${f(xs[1])},${f(ys[1])}` : ""}`;
  const slopes = [];
  for (let i = 0; i < n - 1; i++) slopes.push(xs[i + 1] === xs[i] ? 0 : (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]));
  const tangents = [slopes[0]];
  for (let i = 1; i < n - 1; i++) tangents.push(slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2);
  tangents.push(slopes[n - 2]);
  for (let i = 0; i < n - 1; i++) {
    if (slopes[i] === 0) {
      tangents[i] = 0;
      tangents[i + 1] = 0;
      continue;
    }
    const a = tangents[i] / slopes[i];
    const b = tangents[i + 1] / slopes[i];
    const r = a * a + b * b;
    if (r > 9) {
      const k = 3 / Math.sqrt(r);
      tangents[i] = k * a * slopes[i];
      tangents[i + 1] = k * b * slopes[i];
    }
  }
  let d = `M${f(xs[0])},${f(ys[0])}`;
  for (let i = 0; i < n - 1; i++) {
    const h3 = (xs[i + 1] - xs[i]) / 3;
    d += ` C${f(xs[i] + h3)},${f(ys[i] + tangents[i] * h3)} ${f(xs[i + 1] - h3)},${f(ys[i + 1] - tangents[i + 1] * h3)} ${f(xs[i + 1])},${f(ys[i + 1])}`;
  }
  return d;
}

/**
 * Draws the chart into `box` and keeps it in step with `time`. Returns a
 * function that draws it again (after a line is hidden in the legend).
 */
export function mountChart(box, detail, data, time, { hidden = new Set(), compact = false, legend = "" } = {}) {
  box.classList.add("vchart");
  // Under the chart one line of the same height on every page, so the map below never moves: the legend at the
  // left, "Back to now" at the right once dragged away (owner, 13 Nov 2026). How to drag and read the chart is
  // the one-time chartScrub tip. Past measurements (no map below) keep their note under the line.
  box.innerHTML = `<div class="vchart-wrap"><div class="vchart-scroll"></div><div class="vchart-over"></div></div>${compact ? ""
    : `<div class="vchart-row">${legend}<span class="vchart-note"></span></div>${detail.history ? `<p class="vchart-history"><small class="sub">${h(detail.chartNote ?? t("Measurements of the last days. Touch the chart to read a value."))}</small></p>` : ""}`}`;
  const scroller = box.querySelector(".vchart-scroll");
  const over = box.querySelector(".vchart-over");
  const height = compact ? 100 : 200;
  const [lo, hi] = extent(detail, data);
  const [ylo, yhi] = domain(detail);
  const marks = arrows(detail, data);
  const top = 6;
  const bottom = height - 22;
  let selected = null;
  let width = 0;
  let pxPerHour = 0;

  const ly = (v) => (detail.logScale ? Math.log(Math.max(v, 1e-6)) : v);
  const py = (v) => bottom - ((ly(v) - ly(ylo)) / (ly(yhi) - ly(ylo))) * (bottom - top);
  const px = (x) => 16 + (x - lo) * pxPerHour;
  const xAt = (clientX) => {
    const r = scroller.getBoundingClientRect();
    return lo + (clientX - r.left + scroller.scrollLeft - 16) / pxPerHour;
  };
  const date = (x) => new Date(new Date(data.now.time).getTime() + x * 3600000);
  const marker = () => (selected != null ? Math.round(selected) : detail.history ? (data.isNow ? null : 0) : time.hour);
  const shown = () => detail.lines.filter((l) => !hidden.has(l.name));

  function axisHours() {
    const step = detail.history ? 24 : 6;
    const out = [];
    for (let x = Math.floor(lo); x <= hi; x++) {
      const d = date(x);
      const hour = Number(new Intl.DateTimeFormat("en-GB", { hour: "numeric", hourCycle: "h23", timeZone: "Europe/Berlin" }).format(d));
      if (hour % step === 0 && d.getMinutes() === 0) out.push(x);
    }
    return out;
  }

  /** Past measurements show many days: only every second or third gets its name, as the app (most 7, 5 with larger text). */
  function labelled(days, i) {
    const most = parseFloat(getComputedStyle(document.documentElement).fontSize) > 17 ? 5 : 7;
    const step = Math.max(1, Math.ceil(days.length / most));
    return (days.length - 1 - i) % step === 0;
  }

  /**
   * No label is ever cut at the visible edges (owner, 14 Nov 2026): one that would stick out is
   * moved in to sit flush with the edge, and one scrolled out of view is hidden. "Now" wins
   * over an hour label it would touch.
   */
  function edgeLabels() {
    if (detail.history) return;
    const left = scroller.scrollLeft + 2;
    const right = scroller.scrollLeft + scroller.clientWidth - AXIS_W - 4;
    const placed = [];
    const els = [...scroller.querySelectorAll("text.axis")].sort((a, b) => (b.dataset.now ? 1 : 0) - (a.dataset.now ? 1 : 0));
    for (const el of els) {
      const at = px(Number(el.dataset.x));
      const half = (el.getComputedTextLength?.() || 30) / 2;
      const centre = Math.min(Math.max(at, left + half), right - half);
      const off = at < left - half || at > right + half;
      const clash = placed.some((c) => Math.abs(c - centre) < half * 2 + 6);
      el.setAttribute("x", centre);
      el.style.visibility = off || clash ? "hidden" : "";
      if (!off && !clash) placed.push(centre);
    }
  }

  function label(x) {
    const d = date(x);
    const hour = Number(new Intl.DateTimeFormat("en-GB", { hour: "numeric", hourCycle: "h23", timeZone: "Europe/Berlin" }).format(d));
    if (hour === 0) return new Intl.DateTimeFormat(locale(), { weekday: "short", timeZone: "Europe/Berlin" }).format(d);
    return clock(d);
  }

  function draw() {
    const visible = scroller.clientWidth || box.clientWidth || 320;
    const hours = detail.history ? hi - lo : 24;
    pxPerHour = (visible - 32) / hours;
    width = Math.max(visible, 32 + (hi - lo) * pxPerHour);
    const lines = shown();
    const m = marker();
    const parts = [];
    // The value scale's lines across the whole chart; its numbers stay at the right (drawOver).
    for (const v of yTicks(ylo, yhi, detail.logScale)) {
      parts.push(`<line class="ygrid" x1="0" x2="${width}" y1="${py(v)}" y2="${py(v)}"/>`);
    }
    const axisMarks = axisHours();
    axisMarks.forEach((x, i) => {
      parts.push(`<line class="grid" x1="${px(x)}" x2="${px(x)}" y1="${top}" y2="${bottom}"/>`);
      if (!detail.history || labelled(axisMarks, i)) parts.push(`<text class="axis" data-x="${x}" x="${px(x)}" y="${bottom + 14}" text-anchor="middle">${h(label(x))}</text>`);
    });
    // "Now" under the start of a forecast, on the app and the website (owner, 14 Nov 2026).
    if (!detail.history && data.isNow && lo <= 0 && hi >= 0) parts.push(`<text class="axis now" data-x="0" data-now="1" x="${px(0)}" y="${bottom + 14}" text-anchor="middle">${h(t("Now"))}</text>`);
    for (const a of marks) {
      parts.push(`<text class="trend" x="${px(a.x)}" y="${py(ylo) - (bottom - top) * 0.92 + 4}" text-anchor="middle"${a.rotate ? ` transform="rotate(${a.rotate} ${px(a.x)} ${py(ylo) - (bottom - top) * 0.92})"` : ""}>${a.symbol}</text>`);
    }
    for (const l of lines) {
      if (l.kind === "bars") {
        // Where another shown line's bars stand in (the radar's quarter hours over the forecast's hours), this line leaves them out.
        const covered = lines.filter((o) => o !== l && o.covers).map((o) => o.covers);
        const w = l.barWidth ?? 5;
        for (const p of l.points) {
          if (p.y <= 0 || covered.some(([a, b]) => p.x >= a && p.x <= b)) continue;
          // drawOffset: a rain bar stands for the hour from its time on (decision 0043), drawn in its middle (ChartLine.drawOffset).
          parts.push(`<rect x="${px(p.x + (l.drawOffset ?? 0)) - w / 2}" y="${py(p.y)}" width="${w}" height="${Math.max(0, bottom - py(p.y))}" fill="${l.colour}" opacity=".7"/>`);
        }
      } else if (l.kind === "area" && l.points.length) {
        // A soft area down to the axis (the cloud chart's "All"), as the app's AreaMark.
        const d = path(l.points, px, py);
        parts.push(`<path d="${d} L${px(l.points[l.points.length - 1].x).toFixed(1)},${py(ylo).toFixed(1)} L${px(l.points[0].x).toFixed(1)},${py(ylo).toFixed(1)} Z" fill="${l.colour}" opacity=".55"/>`);
      } else {
        parts.push(`<path d="${path(l.points, px, py)}" fill="none" stroke="${l.colour}" stroke-width="2"${l.dashed ? ' stroke-dasharray="5 4"' : ""}/>`);
      }
    }
    // From the first hour to the last, as in the app, not into the edges.
    for (const limit of detail.limits) {
      const y = py(limit.value);
      if (y < top - 1 || y > bottom + 1) continue;
      parts.push(`<line x1="${px(lo)}" x2="${px(hi)}" y1="${y}" y2="${y}" stroke="${limit.colour}" stroke-dasharray="4 3"/>`);
    }
    parts.push(`<line class="now" x1="${px(0)}" x2="${px(0)}" y1="${top}" y2="${bottom}"/>`);
    if (!detail.history) {
      for (const l of lines.filter((x) => (x.kind ?? "line") === "line")) {
        const p = l.points.reduce((a, b) => (Math.abs(b.x) < Math.abs(a.x) ? b : a), l.points[0]);
        if (p && Math.abs(p.x) < 0.75) parts.push(`<circle cx="${px(p.x)}" cy="${py(p.y)}" r="4.5" fill="${l.colour}"/><circle cx="${px(p.x)}" cy="${py(p.y)}" r="2" fill="var(--card)"/>`);
      }
    }
    // The hours that have maps, and the map's marker.
    const mapX = detail.history ? null : time.mapFrameHour;
    const joined = time.linked && mapX != null;
    if (m != null) {
      parts.push(`<line x1="${px(m)}" x2="${px(m)}" y1="${top}" y2="${joined ? bottom - 17 : bottom}" stroke="var(--blue)" stroke-width="1.5"/>`);
      for (const l of lines.filter((x) => (x.kind ?? "line") === "line")) {
        const p = valueAt(l, m);
        if (p) parts.push(`<circle cx="${px(p.x)}" cy="${py(p.y)}" r="4" fill="${l.colour}"/>`);
      }
    }
    if (mapX != null) {
      const x = px(mapX);
      if (!joined) parts.push(`<line x1="${x}" x2="${x}" y1="${top}" y2="${bottom - 17}" stroke="${MAP_GREEN}" stroke-width="2" stroke-dasharray="4 3"/>`);
    }
    const scroll = scroller.scrollLeft;
    scroller.innerHTML = `<svg width="${width}" height="${height}" role="img" aria-label="${h(t("Chart"))}">${parts.join("")}</svg>`;
    scroller.scrollLeft = scroll;
    edgeLabels();
    drawOver();
    drawNote();
  }

  /** The limits' names at the edge away from now, the unit, and while touched, the hour and values. */
  function drawOver() {
    const trailing = !detail.history;
    let next = top + LABEL_H / 2;
    const labels = detail.limits.map((l) => ({ l, y: py(l.value) - LABEL_H / 2 - 2 })).filter(({ y }) => y >= top - LABEL_H && y <= bottom)
      .sort((a, b) => a.y - b.y).map(({ l, y }) => {
        const placed = Math.max(y, next - LABEL_H / 2);
        next = placed + LABEL_H * 1.5 + 1;
        return `<span class="limit" style="top:${placed}px;${trailing ? `right:${AXIS_W + 4}px` : "left:4px"};color:${l.colour}">${h(l.label)}</span>`;
      });
    // The hours that have maps: a strip along the bottom that ends where the plot ends, never under the
    // value scale on the right (owner, 14 Nov 2026); drawn here, so it follows the scroll.
    let strip = "";
    if (!detail.history && time.mapHours?.length) {
      const a = Math.max(0, px(time.mapHours[0]) - scroller.scrollLeft);
      const b = Math.min(scroller.clientWidth - AXIS_W - 4, px(time.mapHours[time.mapHours.length - 1]) - scroller.scrollLeft);
      if (b > a) strip = `<span class="map-strip" style="left:${a}px;width:${b - a}px;top:${bottom - 3}px;background:${MAP_GREEN}"></span>`;
    }
    let callout = "";
    if (selected != null) {
      const x = Math.round(selected);
      const rows = shown().map((l) => {
        const p = valueAt(l, x);
        if (!p) return "";
        const dotMark = shown().length > 1 ? `<i style="${l.dashed ? `border:1.5px solid ${l.colour}` : `background:${l.colour}`}"></i>` : "";
        return `<span>${dotMark}${h(detail.valueText ? detail.valueText(p.y) : valueText(p.y, detail.unit))}</span>`;
      }).join("");
      const at = px(x) - scroller.scrollLeft;
      const before = at > scroller.clientWidth / 2;
      callout = `<div class="callout" style="${before ? `right:${scroller.clientWidth - at + 6 + AXIS_W}px` : `left:${at + 6}px`}"><small>${h(dayTime(date(x)))}</small>${rows}</div>`;
    }
    let badge = "";
    const mapX = detail.history ? null : time.mapFrameHour;
    if (mapX != null) {
      const at = px(mapX) - scroller.scrollLeft;
      const joined = time.linked;
      if (at > -12 && at < scroller.clientWidth + 12) {
        badge = `<span class="map-badge ${joined ? "joined" : ""}" style="left:${at - 12.5}px;top:${bottom - 17}px;opacity:${time.mapOutOfRange ? 0.5 : 1}">${joined ? icon("link") : ""}${icon("map")}</span>`;
      }
    }
    const ticks = yTicks(ylo, yhi, detail.logScale);
    const step = ticks.length > 1 ? ticks[1] - ticks[0] : 1;
    // A log scale shows every mark with the decimals its smallest needs, as Swift Charts does: 10,0 / 1,0 / 0,1.
    const digits = detail.logScale ? Math.max(0, -Math.floor(Math.log10(ticks[0] ?? 1) + 1e-9)) : step >= 1 ? 0 : step >= 0.1 ? 1 : 2;
    const scale = ticks.map((v) => `<span class="ytick" style="top:${py(v) - 7}px">${h(num(v, step % 1 && step > 1 ? 1 : digits))}</span>`).join("");
    over.innerHTML = `${detail.unit ? `<span class="unit">${h(detail.unit)}</span>` : ""}${strip}${scale}${labels.join("")}${badge}${callout}`;
  }

  function drawNote() {
    const note = box.querySelector(".vchart-note");
    if (!note) return;
    const away = !detail.history && (Math.abs(time.scrollX - START) > 0.5 || time.hour !== 0);
    if (away) {
      const label = data.isNow ? t("Back to now") : t("Back to %@", dayTime(data.now.time));
      if (note.querySelector("#chart-back")?.title === label) return;
      note.innerHTML = `<button class="link strong" id="chart-back" title="${h(label)}" aria-label="${h(label)}">${icon("undo-2")}<span>${h(label)}</span></button>`;
      note.querySelector("#chart-back").addEventListener("click", () => {
        time.back();
        scroller.scrollLeft = px(START) - 16;
      });
    } else {
      note.innerHTML = "";
    }
  }

  // Scrubbing: a mouse held down and moved, or a tap; touch scrolls the chart sideways.
  let down = null;
  scroller.addEventListener("pointerdown", (e) => {
    down = { x: e.clientX, y: e.clientY, type: e.pointerType };
    if (e.pointerType === "mouse") {
      selected = xAt(e.clientX);
      draw();
    }
  });
  scroller.addEventListener("pointermove", (e) => {
    if (down?.type === "mouse") {
      selected = xAt(e.clientX);
      drawOver();
      if (!detail.history) time.setChart(selected);
    }
  });
  const up = (e) => {
    if (!down) return;
    const tap = Math.hypot(e.clientX - down.x, e.clientY - down.y) < 8;
    if (down.type === "mouse" || tap) {
      const x = xAt(e.clientX);
      if (!detail.history) time.setChart(x);
      selected = detail.history && tap && down.type !== "mouse" ? x : null;
    }
    down = null;
    draw();
  };
  scroller.addEventListener("pointerup", up);
  scroller.addEventListener("pointercancel", () => {
    down = null;
    selected = null;
    drawOver();
  });
  scroller.addEventListener("scroll", () => {
    if (!detail.history) time.scrollX = lo + (scroller.scrollLeft) / pxPerHour;
    edgeLabels();
    drawOver();
  });

  const listener = () => {
    if (!box.isConnected) return time.listeners.delete(listener);
    draw();
    // Moved from the map: keep the line in view.
    if (!detail.history && selected == null) {
      const left = lo + scroller.scrollLeft / pxPerHour;
      if (time.hour < left + 0.5 || time.hour > left + 23.5) scroller.scrollLeft = (Math.min(Math.max(time.hour - 8, lo), hi - 24) - lo) * pxPerHour;
    }
  };
  time.listeners.add(listener);
  draw();
  scroller.scrollLeft = detail.history ? 0 : (Math.max(time.scrollX, lo) - lo) * pxPerHour;
  edgeLabels();
  return draw;
}
