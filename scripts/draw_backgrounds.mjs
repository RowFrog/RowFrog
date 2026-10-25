// Draws the sample background pictures that come with the app, in the flat
// style of the app icon concepts, and saves them as SVG and PNG.
//   node scripts/draw_backgrounds.mjs <out-dir>
// Needs Playwright with Chromium. scripts/backgrounds_to_jpeg.py then makes the
// JPEGs in ios/RowFrog/Backgrounds.

import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";

// Playwright is found through NODE_PATH, e.g. a global install.
const { chromium } = createRequire(import.meta.url)("playwright");

const W = 393;
const H = 852;
const out = process.argv[2] ?? "backgrounds";
fs.mkdirSync(out, { recursive: true });

// Seeded random numbers, so every run draws the same pictures.
let seed = 7;
const rnd = () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646;
const between = (a, b) => a + rnd() * (b - a);

const grad = (id, stops, x2 = 0, y2 = 1) =>
  `<linearGradient id="${id}" x1="0" y1="0" x2="${x2}" y2="${y2}">${stops
    .map(([o, c, a = 1]) => `<stop offset="${o}" stop-color="${c}" stop-opacity="${a}"/>`)
    .join("")}</linearGradient>`;

const radial = (id, stops) =>
  `<radialGradient id="${id}">${stops.map(([o, c, a = 1]) => `<stop offset="${o}" stop-color="${c}" stop-opacity="${a}"/>`).join("")}</radialGradient>`;

/** A wavy line across the picture. */
function waveLine(y, { amp = 4, len = 44, color = "#fff", opacity = 0.4, width = 2.4, phase = 0 } = {}) {
  let d = `M ${-len + phase} ${y}`;
  for (let x = -len + phase; x < W + len; x += len) {
    d += ` q ${len / 4} ${-amp} ${len / 2} 0 t ${len / 2} 0`;
  }
  return `<path d="${d}" fill="none" stroke="${color}" stroke-opacity="${opacity}" stroke-width="${width}" stroke-linecap="round"/>`;
}

/** A filled band whose top edge is a wave, down to the bottom. */
function waveBand(y, { amp = 10, len = 120, fill, phase = 0 }) {
  let d = `M ${-len + phase} ${H} L ${-len + phase} ${y}`;
  for (let x = -len + phase; x < W + len; x += len) {
    d += ` q ${len / 4} ${-amp} ${len / 2} 0 t ${len / 2} 0`;
  }
  d += ` L ${W + 2 * len} ${H} Z`;
  return `<path d="${d}" fill="${fill}"/>`;
}

/** A cumulus cloud of overlapping circles on a flat base. */
function cloud(cx, cy, s, fill = "#fff", opacity = 1) {
  const puffs = [
    [-38, 0, 22], [-14, -14, 28], [16, -20, 32], [42, -4, 24], [0, 4, 24], [30, 6, 20], [-30, 8, 18],
  ];
  return `<g transform="translate(${cx} ${cy}) scale(${s})" fill="${fill}" fill-opacity="${opacity}">
    ${puffs.map(([x, y, r]) => `<circle cx="${x}" cy="${y}" r="${r}"/>`).join("")}
    <rect x="-60" y="4" width="124" height="22" rx="11"/></g>`;
}

/** A mountain range with snow caps through the given peaks. */
function mountains(base, peaks, fill, snow = "#fff") {
  let d = `M -10 ${base}`;
  for (const [x, y] of peaks) d += ` L ${x} ${y}`;
  d += ` L ${W + 10} ${base} Z`;
  const caps = snow
    ? peaks
        .filter(([, y], i) => i > 0 && i < peaks.length - 1 && base - y > 90)
        .map(([x, y]) => `<path d="M ${x - 14} ${y + 18} L ${x} ${y} L ${x + 14} ${y + 18} L ${x + 6} ${y + 14} L ${x} ${y + 20} L ${x - 6} ${y + 14} Z" fill="${snow}"/>`)
        .join("")
    : "";
  return `<path d="${d}" fill="${fill}"/>${caps}`;
}

/** A single sculler seen from the side, like the "Sunrise sculler" icon. */
function sculler(x, y, s, color) {
  return `<g transform="translate(${x} ${y}) scale(${s})" fill="${color}" stroke="${color}" stroke-linecap="round">
    <path d="M -120 0 Q 0 10 120 -4 Q 0 4 -120 0 Z" stroke-width="3"/>
    <circle cx="6" cy="-62" r="10" stroke="none"/>
    <path d="M 2 -50 L 18 -8 L -6 -8 Z" stroke-width="6" stroke-linejoin="round"/>
    <path d="M 8 -36 L -34 -14" stroke-width="6" fill="none"/>
    <path d="M -34 -14 L -90 30" stroke-width="4" fill="none"/>
    <path d="M -84 25 L -104 41" stroke-width="10" fill="none"/>
  </g>`;
}

/** A rowing shell seen from above with its oars spread, like the "Alpine lake" icon. */
function shellFromAbove(x, y, s, color) {
  return `<g transform="translate(${x} ${y}) scale(${s})" stroke="${color}" stroke-linecap="round" fill="${color}">
    <path d="M -70 0 Q 0 -6 70 0 Q 0 6 -70 0 Z" stroke-width="2"/>
    <path d="M -30 -26 L 30 26 M -30 26 L 30 -26" stroke-width="3"/>
    <ellipse cx="-34" cy="-30" rx="8" ry="4" transform="rotate(40 -34 -30)" stroke="none"/>
    <ellipse cx="34" cy="30" rx="8" ry="4" transform="rotate(40 34 30)" stroke="none"/>
    <ellipse cx="-34" cy="30" rx="8" ry="4" transform="rotate(-40 -34 30)" stroke="none"/>
    <ellipse cx="34" cy="-30" rx="8" ry="4" transform="rotate(-40 34 -30)" stroke="none"/>
    <circle cx="0" cy="0" r="6" stroke="none"/>
  </g>`;
}

/** The frog sculler of the GitHub avatar, in a boat on a cloud. */
function frogInCloudBoat(x, y, s) {
  return `<g transform="translate(${x} ${y}) scale(${s})">
    <ellipse cx="0" cy="-40" rx="46" ry="40" fill="#5cbf5f"/>
    <ellipse cx="0" cy="-20" rx="28" ry="22" fill="#a6e08f"/>
    <ellipse cx="0" cy="-92" rx="56" ry="38" fill="#5cbf5f"/>
    <circle cx="-26" cy="-122" r="20" fill="#5cbf5f"/><circle cx="26" cy="-122" r="20" fill="#5cbf5f"/>
    <circle cx="-26" cy="-122" r="13" fill="#fff"/><circle cx="26" cy="-122" r="13" fill="#fff"/>
    <circle cx="-24" cy="-121" r="7" fill="#17233a"/><circle cx="28" cy="-121" r="7" fill="#17233a"/>
    <circle cx="-21" cy="-124" r="2.5" fill="#fff"/><circle cx="31" cy="-124" r="2.5" fill="#fff"/>
    <path d="M -22 -88 Q 0 -74 22 -88" stroke="#2c6b30" stroke-width="4" fill="none" stroke-linecap="round"/>
    <ellipse cx="-38" cy="-86" rx="8" ry="5" fill="#f19a9a" opacity="0.7"/><ellipse cx="38" cy="-86" rx="8" ry="5" fill="#f19a9a" opacity="0.7"/>
    <path d="M -175 0 Q 0 30 175 -6 Q 160 24 0 34 Q -150 30 -175 0 Z" fill="#fff"/>
    <path d="M -168 6 Q 0 34 168 0" stroke="#17305a" stroke-width="3" fill="none" opacity="0.6"/>
    ${[[-120, -2, 20], [-90, -14, 26], [-55, -6, 22], [50, -10, 24], [86, -18, 28], [122, -6, 20], [150, -2, 14]]
      .map(([cx, cy, r]) => `<circle cx="${cx}" cy="${cy}" r="${r}" fill="#fff"/>`)
      .join("")}
    <path d="M -60 -30 L -160 34" stroke="#5a4a2a" stroke-width="5" stroke-linecap="round"/>
    <path d="M -160 34 L -184 50" stroke="#f6c33b" stroke-width="16" stroke-linecap="round"/>
    <path d="M 60 -30 L 160 34" stroke="#5a4a2a" stroke-width="5" stroke-linecap="round"/>
    <path d="M 160 34 L 184 50" stroke="#f6c33b" stroke-width="16" stroke-linecap="round"/>
    <path d="M -34 -50 L -62 -30 M 34 -50 L 62 -30" stroke="#5cbf5f" stroke-width="12" stroke-linecap="round"/>
  </g>`;
}

/** Sun with soft glow. */
function sun(cx, cy, r, inner = "#ffd54a", outer = "#f7a51c") {
  return `<defs>${radial("sunGlow", [[0, "#fff4c2", 0.7], [1, "#fff4c2", 0]])}${grad("sunFill", [[0, inner], [1, outer]])}</defs>
    <circle cx="${cx}" cy="${cy}" r="${r * 2}" fill="url(#sunGlow)"/>
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="url(#sunFill)"/>`;
}

/** The chosen GitHub avatar, "Cloud shell" (github-avatar/6-cloud-shell), drawn
 * on a 1024 square with the horizon at y = 636; its water runs on below. */
const CLOUD_SHELL_AVATAR = `<defs><linearGradient id="av-sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3D8FE0"/><stop offset="1" stop-color="#9CCBF5"/></linearGradient><linearGradient id="av-water" gradientUnits="userSpaceOnUse" x1="0" y1="636" x2="0" y2="2236"><stop offset="0" stop-color="#1F6FB9"/><stop offset="1" stop-color="#0C3F78"/></linearGradient><radialGradient id="av-sun" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#FFE27A"/><stop offset="1" stop-color="#FFB21E"/></radialGradient><linearGradient id="av-cloud" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E3ECF6"/></linearGradient></defs><clipPath id="av-above"><rect width="1024" height="640"/></clipPath><circle cx="512" cy="590" r="250" fill="url(#av-sun)" clip-path="url(#av-above)"/><path d="M 0 640 L 0 545 L 130 465 L 230 525 L 320 445 L 395 520 L 430 640 L 600 640 L 640 525 L 720 460 L 810 515 L 900 440 L 1024 535 L 1024 640 Z" fill="#7FA3C8"/><path d="M 130 465 L 102 482 L 150 477 Z M 320 445 L 292 468 L 342 463 Z M 900 440 L 872 458 L 920 455 Z M 720 460 L 698 474 L 740 472 Z" fill="#FFFFFF"/><rect y="636" width="1024" height="1600" fill="url(#av-water)"/><path d="M 90 700 q 30.0 -10 60.0 0 t 60.0 0" fill="none" stroke="#FFFFFF" stroke-width="12" stroke-linecap="round" opacity="0.6"/><path d="M 60 735 q 40.0 -10 80.0 0 t 80.0 0" fill="none" stroke="#FFFFFF" stroke-width="12" stroke-linecap="round" opacity="0.6"/><path d="M -40 860 q 37.5 -12 75 0 t 75 0 q 37.5 -12 75 0 t 75 0 q 37.5 -12 75 0 t 75 0 q 37.5 -12 75 0 t 75 0 q 37.5 -12 75 0 t 75 0 q 37.5 -12 75 0 t 75 0 q 37.5 -12 75 0 t 75 0 q 37.5 -12 75 0 t 75 0" fill="none" stroke="#FFFFFF" stroke-width="14" stroke-linecap="round" opacity="0.35"/><path d="M -40 940 q 37.5 -12 75 0 t 75 0 q 37.5 -12 75 0 t 75 0 q 37.5 -12 75 0 t 75 0 q 37.5 -12 75 0 t 75 0 q 37.5 -12 75 0 t 75 0 q 37.5 -12 75 0 t 75 0 q 37.5 -12 75 0 t 75 0 q 37.5 -12 75 0 t 75 0" fill="none" stroke="#FFFFFF" stroke-width="14" stroke-linecap="round" opacity="0.35"/><path d="M 508 483 L 308 703" stroke="#0B2545" stroke-width="13" stroke-linecap="round" opacity="0.55"/><ellipse cx="294" cy="720" rx="58" ry="22" fill="#FFC531" opacity="0.6" transform="rotate(-44 294 720)"/><ellipse cx="520" cy="505" rx="88" ry="92" fill="#5DC46B"/><ellipse cx="490" cy="520" rx="52" ry="58" fill="#B5E58A"/><ellipse cx="520" cy="372" rx="136.0" ry="92.0" fill="#5DC46B"/><circle cx="444.0" cy="304.0" r="49.6" fill="#5DC46B"/><circle cx="444.0" cy="304.0" r="35.711999999999996" fill="#FFFFFF"/><circle cx="444.0" cy="307.2" r="18.848000000000003" fill="#0B2545"/><circle cx="450.4" cy="300.0" r="5.952" fill="#FFFFFF"/><ellipse cx="425.6" cy="396.0" rx="20.8" ry="12.0" fill="#FF8C95" opacity="0.6"/><circle cx="502.4" cy="357.6" r="4.800000000000001" fill="#3B9A4E"/><circle cx="596.0" cy="304.0" r="49.6" fill="#5DC46B"/><circle cx="596.0" cy="304.0" r="35.711999999999996" fill="#FFFFFF"/><circle cx="596.0" cy="307.2" r="18.848000000000003" fill="#0B2545"/><circle cx="602.4" cy="300.0" r="5.952" fill="#FFFFFF"/><ellipse cx="614.4" cy="396.0" rx="20.8" ry="12.0" fill="#FF8C95" opacity="0.6"/><circle cx="537.6" cy="357.6" r="4.800000000000001" fill="#3B9A4E"/><path d="M 444.0 386.4 Q 520 434.4 596.0 386.4" fill="none" stroke="#3B9A4E" stroke-width="10.4" stroke-linecap="round"/><g fill="url(#av-cloud)"><path d="M 110 628 C 260 612 400 604 520 603 C 680 602 830 608 945 612 C 830 642 690 662 520 664 C 350 664 220 650 110 628 Z"/><circle cx="200" cy="614" r="18"/><circle cx="240" cy="606" r="26"/><circle cx="290" cy="598" r="34"/><circle cx="345" cy="592" r="42"/><circle cx="405" cy="588" r="46"/><circle cx="468" cy="586" r="48"/><circle cx="575" cy="586" r="48"/><circle cx="638" cy="588" r="46"/><circle cx="698" cy="594" r="40"/><circle cx="752" cy="600" r="32"/><circle cx="802" cy="605" r="24"/><circle cx="848" cy="609" r="16"/><ellipse cx="520" cy="590" rx="110" ry="30"/></g><path d="M 118 632 C 230 652 360 665 520 665 C 690 663 830 642 940 614" fill="none" stroke="#0B2545" stroke-width="10" stroke-linecap="round" opacity="0.85"/><circle cx="944" cy="612" r="9" fill="#FFFFFF"/><path d="M 470 600 L 392 590" stroke="#0B2545" stroke-width="8" stroke-linecap="round" opacity="0.8"/><path d="M 450 515 L 250 735" stroke="#0B2545" stroke-width="16" stroke-linecap="round"/><ellipse cx="236" cy="752" rx="64" ry="25" fill="#FFC531" transform="rotate(-44 236 752)"/><path d="M 520 495 Q 490 520 455 515" stroke="#5DC46B" stroke-width="30" stroke-linecap="round" fill="none"/><circle cx="452" cy="515" r="22" fill="#5DC46B"/>`;

const scenes = {
  "lake-waves": () => {
    const bands = ["#5aa7e6", "#3f8fd6", "#2f79c4", "#2266ae", "#1a5598", "#134682", "#0e386c", "#0a2c58"];
    return `<defs>${grad("sky", [[0, "#7fbff0"], [1, "#cfe8fb"]])}</defs>
      <rect width="${W}" height="${H}" fill="url(#sky)"/>
      ${cloud(300, 150, 0.8, "#fff", 0.9)}${cloud(90, 230, 0.55, "#fff", 0.75)}
      ${bands.map((fill, i) => waveBand(330 + i * 66, { amp: 12 + i * 2, len: 110 + i * 12, fill, phase: (i * 37) % 110 })).join("")}
      ${bands.map((_, i) => waveLine(360 + i * 66, { amp: 5, len: 46, opacity: 0.18 + i * 0.03, phase: (i * 19) % 46 })).join("")}`;
  },

  "soft-waves": () => {
    const bands = ["#7fd6d2", "#5cc3c4", "#3eadb6", "#2b96a5", "#1f7f93", "#176a80", "#11566d", "#0c445b"];
    return `<defs>${grad("sky", [[0, "#b7e4f2"], [1, "#f4e7d7"]])}<filter id="soft"><feGaussianBlur stdDeviation="9"/></filter></defs>
      <rect width="${W}" height="${H}" fill="url(#sky)"/>
      <g filter="url(#soft)">
        <circle cx="290" cy="220" r="70" fill="#ffe2a6" opacity="0.9"/>
        ${bands.map((fill, i) => waveBand(340 + i * 64, { amp: 22, len: 170, fill, phase: (i * 53) % 170 })).join("")}
        ${bands.map((_, i) => waveLine(372 + i * 64, { amp: 9, len: 85, opacity: 0.35, width: 6, phase: (i * 29) % 85 })).join("")}
      </g>`;
  },

  "sunrise-sculler": () => {
    const horizon = 450;
    return `<defs>${grad("sky", [[0, "#2f6fc9"], [0.55, "#79aee8"], [0.85, "#f8c58c"], [1, "#fbd9a4"]])}
        ${grad("water", [[0, "#1d5fa8"], [1, "#0b2f62"]])}</defs>
      <rect width="${W}" height="${horizon}" fill="url(#sky)"/>
      ${cloud(80, 160, 0.6, "#fff", 0.55)}${cloud(320, 240, 0.45, "#fff", 0.5)}
      ${sun(196, horizon, 96)}
      <rect y="${horizon}" width="${W}" height="${H - horizon}" fill="url(#water)"/>
      ${[0, 1, 2, 3, 4, 5, 6].map((i) => `<rect x="${196 - 70 + i * 6}" y="${horizon + 18 + i * 26}" width="${140 - i * 12}" height="5" rx="2.5" fill="#f6c33b" opacity="${0.75 - i * 0.09}"/>`).join("")}
      ${sculler(196, horizon + 6, 0.95, "#10213f")}
      ${[0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map((i) => waveLine(horizon + 60 + i * 36, { amp: 4, len: 40, opacity: 0.22, phase: (i * 13) % 40 })).join("")}`;
  },

  "alpine-lake": () => {
    const horizon = 470;
    return `<defs>${grad("sky", [[0, "#3f8fdd"], [1, "#a9d4f5"]])}${grad("lake", [[0, "#2aa0a8"], [1, "#0f5f72"]])}</defs>
      <rect width="${W}" height="${horizon}" fill="url(#sky)"/>
      ${sun(318, 150, 38)}
      ${cloud(110, 200, 0.5, "#fff", 0.8)}
      ${mountains(horizon, [[-10, 360], [40, 300], [95, 345], [160, 250], [225, 330], [285, 280], [345, 340], [403, 300]], "#8aa7c8")}
      ${mountains(horizon, [[-10, 420], [55, 360], [120, 410], [190, 330], [260, 400], [330, 350], [403, 410]], "#4f6f96")}
      <rect y="${horizon}" width="${W}" height="${H - horizon}" fill="url(#lake)"/>
      <path d="M 150 ${horizon} L 196 ${horizon + 40} L 240 ${horizon} Z" fill="#4f6f96" opacity="0.25"/>
      ${shellFromAbove(196, 600, 1.0, "#10213f")}
      ${[0, 1, 2, 3, 4, 5, 6].map((i) => waveLine(horizon + 30 + i * 50 + (i > 2 ? 40 : 0), { amp: 4, len: 44, opacity: 0.25, phase: (i * 17) % 44 })).join("")}`;
  },

  "cloud-sculler": () => {
    const horizon = 520;
    return `<defs>${grad("sky", [[0, "#3f8fdd"], [1, "#9fcdf3"]])}${grad("water", [[0, "#1f66b3"], [1, "#0b2f62"]])}</defs>
      <rect width="${W}" height="${horizon}" fill="url(#sky)"/>
      ${mountains(horizon, [[-10, 470], [50, 430], [110, 470], [170, 420], [230, 465], [300, 425], [403, 470]], "#8aa7c8", null)}
      ${sun(196, 420, 82)}
      ${cloud(70, 150, 0.5, "#fff", 0.8)}${cloud(330, 110, 0.6, "#fff", 0.85)}
      <rect y="${horizon}" width="${W}" height="${H - horizon}" fill="url(#water)"/>
      ${frogInCloudBoat(196, 520, 0.95)}
      ${[0, 1, 2, 3, 4, 5, 6].map((i) => waveLine(horizon + 70 + i * 40, { amp: 4, len: 44, opacity: 0.25, phase: (i * 11) % 44 })).join("")}`;
  },

  "cloud-shell": () => {
    // The avatar across the full width, its horizon a little below the middle.
    const s = W / 1024;
    const horizon = 500;
    return `<defs>${grad("sky", [[0, "#2f7fd6"], [0.6, "#5fa4ea"], [1, "#9ccbf5"]])}</defs>
      <rect width="${W}" height="${horizon}" fill="url(#sky)"/>
      ${cloud(80, 140, 0.55, "#fff", 0.85)}${cloud(320, 200, 0.45, "#fff", 0.75)}${cloud(250, 90, 0.35, "#fff", 0.7)}
      <g transform="translate(0 ${horizon - 636 * s}) scale(${s})">${CLOUD_SHELL_AVATAR}</g>
      ${[0, 1, 2, 3, 4].map((i) => waveLine(horizon + 170 + i * 38, { amp: 4, len: 48, opacity: 0.3, width: 5 * s * 2, phase: (i * 17) % 48 })).join("")}`;
  },

  "sunny-day": () => {
    const horizon = 520;
    const sparkles = Array.from({ length: 26 }, () => {
      const x = between(10, W - 10), y = between(horizon + 20, H - 20), r = between(2, 4.5);
      return `<path d="M ${x} ${y - r * 2} L ${x + r} ${y} L ${x} ${y + r * 2} L ${x - r} ${y} Z" fill="#fff" opacity="${between(0.5, 0.9).toFixed(2)}"/>`;
    }).join("");
    const trees = Array.from({ length: 30 }, (_, i) => {
      const x = i * 14 - 5, h = between(18, 34);
      return `<path d="M ${x - 8} ${horizon} L ${x} ${horizon - h} L ${x + 8} ${horizon} Z" fill="#2f7d4a"/>`;
    }).join("");
    return `<defs>${grad("sky", [[0, "#2f86e0"], [1, "#9fd2fa"]])}${grad("lake", [[0, "#2b8ad6"], [1, "#145aa6"]])}</defs>
      <rect width="${W}" height="${horizon}" fill="url(#sky)"/>
      ${sun(90, 130, 44)}
      ${[0, 1, 2, 3, 4, 5, 6, 7].map((i) => { const a = (i * Math.PI) / 4; return `<path d="M ${90 + Math.cos(a) * 60} ${130 + Math.sin(a) * 60} L ${90 + Math.cos(a) * 78} ${130 + Math.sin(a) * 78}" stroke="#ffc533" stroke-width="5" stroke-linecap="round"/>`; }).join("")}
      ${cloud(290, 170, 0.9)}${cloud(170, 300, 0.7)}${cloud(330, 380, 0.5, "#fff", 0.9)}
      <path d="M -10 ${horizon} Q 120 ${horizon - 24} 220 ${horizon - 10} T 403 ${horizon - 16} L 403 ${horizon} Z" fill="#4a9a5c"/>
      ${trees}
      <rect y="${horizon}" width="${W}" height="${H - horizon}" fill="url(#lake)"/>
      ${sparkles}
      ${[0, 1, 2, 3, 4, 5, 6].map((i) => waveLine(horizon + 40 + i * 44, { amp: 3, len: 38, opacity: 0.25, phase: (i * 9) % 38 })).join("")}`;
  },

  "morning-mist": () => {
    const horizon = 470;
    const treeLine = (base, color, opacity, step) =>
      Array.from({ length: Math.ceil(W / step) + 2 }, (_, i) => {
        const x = i * step - step, h = between(30, 70);
        return `<path d="M ${x - step * 0.7} ${base} L ${x} ${base - h} L ${x + step * 0.7} ${base} Z" fill="${color}" opacity="${opacity}"/>`;
      }).join("");
    return `<defs>${grad("sky", [[0, "#c9d6e2"], [1, "#eef1f2"]])}${grad("water", [[0, "#b9c9d6"], [1, "#6f8aa3"]])}<filter id="mist"><feGaussianBlur stdDeviation="14"/></filter><filter id="haze"><feGaussianBlur stdDeviation="2"/></filter></defs>
      <rect width="${W}" height="${H}" fill="url(#sky)"/>
      <circle cx="270" cy="260" r="40" fill="#fff6dc" opacity="0.8"/>
      <g filter="url(#haze)">${treeLine(horizon - 4, "#8fa3b5", 0.55, 26)}${treeLine(horizon, "#6d8399", 0.6, 34)}</g>
      <rect y="${horizon}" width="${W}" height="${H - horizon}" fill="url(#water)"/>
      <g filter="url(#mist)">
        ${[0, 1, 2, 3, 4].map((i) => `<rect x="${-60 + (i % 2) * 80}" y="${horizon - 70 + i * 48}" width="${W + 40}" height="34" rx="17" fill="#fff" opacity="0.65"/>`).join("")}
      </g>
      <g opacity="0.55">${sculler(130, horizon + 110, 0.55, "#3c4f63")}</g>
      ${[0, 1, 2, 3, 4, 5].map((i) => waveLine(horizon + 170 + i * 42, { amp: 2, len: 60, opacity: 0.35, phase: (i * 21) % 60 })).join("")}`;
  },

  "rain-on-the-lake": () => {
    const horizon = 430;
    const drops = Array.from({ length: 140 }, () => {
      const x = between(-40, W), y = between(120, H), l = between(16, 30);
      return `<path d="M ${x} ${y} l ${l * 0.3} ${l}" stroke="#d9e6f2" stroke-width="1.6" stroke-linecap="round" opacity="${between(0.35, 0.8).toFixed(2)}"/>`;
    }).join("");
    const ripples = Array.from({ length: 22 }, () => {
      const x = between(10, W - 10), y = between(horizon + 20, H - 10), r = between(8, 20);
      return `<ellipse cx="${x}" cy="${y}" rx="${r}" ry="${r * 0.3}" fill="none" stroke="#c8d8e6" stroke-width="1.5" opacity="0.5"/>`;
    }).join("");
    return `<defs>${grad("sky", [[0, "#56677d"], [1, "#a7b4c2"]])}${grad("water", [[0, "#5e7389"], [1, "#2c3d52"]])}</defs>
      <rect width="${W}" height="${horizon}" fill="url(#sky)"/>
      ${cloud(80, 90, 1.1, "#7d8b9c")}${cloud(280, 70, 1.3, "#6b7a8c")}${cloud(200, 170, 1.0, "#8d9aab")}${cloud(360, 200, 0.7, "#7d8b9c")}${cloud(20, 220, 0.7, "#8d9aab")}
      ${mountains(horizon, [[-10, 400], [80, 370], [170, 395], [260, 360], [403, 400]], "#6f7f90", null)}
      <rect y="${horizon}" width="${W}" height="${H - horizon}" fill="url(#water)"/>
      ${ripples}${drops}`;
  },

  thunderstorm: () => {
    const horizon = 480;
    return `<defs>${grad("sky", [[0, "#1d2340"], [1, "#4b4f72"]])}${grad("water", [[0, "#2a3657"], [1, "#0e1428"]])}${radial("flash", [[0, "#fff6c8", 0.55], [1, "#fff6c8", 0]])}</defs>
      <rect width="${W}" height="${horizon}" fill="url(#sky)"/>
      <circle cx="230" cy="260" r="170" fill="url(#flash)"/>
      ${cloud(90, 110, 1.4, "#3a3f5e")}${cloud(300, 90, 1.5, "#33385a")}${cloud(200, 200, 1.2, "#484d70")}${cloud(40, 250, 0.9, "#40456a")}${cloud(360, 260, 0.9, "#3a3f5e")}
      <path d="M 238 230 L 204 330 L 232 330 L 208 430 L 276 304 L 244 304 L 268 230 Z" fill="#ffd23f" stroke="#fff3b0" stroke-width="2" stroke-linejoin="round"/>
      <rect y="${horizon}" width="${W}" height="${H - horizon}" fill="url(#water)"/>
      ${[0, 1, 2, 3, 4, 5, 6, 7].map((i) => waveLine(horizon + 30 + i * 46, { amp: 9, len: 34, opacity: 0.35 + (i % 3) * 0.12, width: 2.6, phase: (i * 13) % 34 })).join("")}
      ${Array.from({ length: 16 }, () => { const x = between(10, W - 10), y = between(horizon + 30, H - 20); return `<path d="M ${x - 8} ${y} q 8 -8 16 0" stroke="#fff" stroke-width="2.5" fill="none" opacity="0.7" stroke-linecap="round"/>`; }).join("")}`;
  },

  "winter-ice": () => {
    const horizon = 470;
    const floes = Array.from({ length: 14 }, (_, i) => {
      const cx = between(20, W - 20), cy = horizon + 50 + i * 24 + between(0, 10), w = between(40, 110), h = w * 0.22;
      return `<path d="M ${cx - w / 2} ${cy} L ${cx - w / 3} ${cy - h} L ${cx + w / 3} ${cy - h * 0.8} L ${cx + w / 2} ${cy} L ${cx + w / 4} ${cy + h * 0.6} L ${cx - w / 3} ${cy + h * 0.5} Z" fill="#f4f9fd" opacity="0.92"/>`;
    }).join("");
    const flakes = Array.from({ length: 50 }, () => `<circle cx="${between(0, W)}" cy="${between(0, H)}" r="${between(1.5, 3.5)}" fill="#fff" opacity="${between(0.5, 0.95).toFixed(2)}"/>`).join("");
    return `<defs>${grad("sky", [[0, "#9cc3e6"], [1, "#e4f0fa"]])}${grad("water", [[0, "#6f9cc0"], [1, "#2f5f88"]])}</defs>
      <rect width="${W}" height="${horizon}" fill="url(#sky)"/>
      ${mountains(horizon, [[-10, 330], [60, 260], [130, 330], [200, 240], [270, 320], [340, 270], [403, 330]], "#e9f2fa", null)}
      ${mountains(horizon, [[-10, 420], [70, 370], [150, 410], [230, 360], [310, 405], [403, 380]], "#c3d6e8", null)}
      <rect y="${horizon}" width="${W}" height="${H - horizon}" fill="url(#water)"/>
      <rect y="${horizon}" width="${W}" height="22" fill="#eef5fb"/>
      ${floes}${flakes}`;
  },

  "night-lake": () => {
    const horizon = 500;
    const stars = Array.from({ length: 80 }, () => `<circle cx="${between(0, W)}" cy="${between(0, horizon - 80)}" r="${between(0.6, 1.8)}" fill="#fff" opacity="${between(0.4, 1).toFixed(2)}"/>`).join("");
    return `<defs>${grad("sky", [[0, "#0b1230"], [1, "#24305e"]])}${grad("water", [[0, "#17234a"], [1, "#070c1e"]])}</defs>
      <rect width="${W}" height="${horizon}" fill="url(#sky)"/>
      ${stars}
      <circle cx="300" cy="150" r="36" fill="#f6efd2"/><circle cx="316" cy="140" r="32" fill="#0f1838"/>
      ${mountains(horizon, [[-10, 440], [60, 400], [140, 445], [220, 390], [300, 430], [403, 410]], "#1b2550", null)}
      <rect y="${horizon}" width="${W}" height="${H - horizon}" fill="url(#water)"/>
      ${[0, 1, 2, 3, 4, 5].map((i) => `<rect x="${292 - 30 + i * 4}" y="${horizon + 20 + i * 24}" width="${60 - i * 8}" height="4" rx="2" fill="#f6efd2" opacity="${0.6 - i * 0.08}"/>`).join("")}
      ${[0, 1, 2, 3, 4, 5, 6, 7].map((i) => waveLine(horizon + 40 + i * 40, { amp: 3, len: 44, opacity: 0.15, phase: (i * 15) % 44 })).join("")}`;
  },
};

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 3 });
for (const [id, draw] of Object.entries(scenes)) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${draw()}</svg>`;
  fs.writeFileSync(path.join(out, `${id}.svg`), svg);
  await page.setContent(`<html><body style="margin:0">${svg}</body></html>`);
  await page.screenshot({ path: path.join(out, `${id}.png`), clip: { x: 0, y: 0, width: W, height: H } });
  console.log(id);
}
await browser.close();
