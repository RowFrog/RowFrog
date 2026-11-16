// The website follows the iPhone's and iPad's text size, as the app does with Dynamic Type (owner's pick,
// 16 Nov 2026). Safari gives the reader's body size as the font "-apple-system-body": 17 px at the standard
// size. Its ratio to 17 scales all text through -webkit-text-size-adjust, kept within 85–120 %, so the fixed
// layout (44 px buttons, tile heights) still holds at the largest sizes. Computers and other browsers, which
// do not know the font, stay at 100 %.

const STANDARD = 17;
export const RANGE = [0.85, 1.2];

/** The text size as a share of the standard one, within RANGE; 1 where the device has no text size setting. */
export function textScale(bodyPx) {
  if (!Number.isFinite(bodyPx) || bodyPx <= 0) return 1;
  return Math.min(RANGE[1], Math.max(RANGE[0], bodyPx / STANDARD));
}

/** The reader's body size in px from "-apple-system-body", or null where the browser does not know it. */
function readerBody() {
  const probe = document.createElement("span");
  probe.style.font = "-apple-system-body";
  if (!probe.style.font) return null;
  probe.style.position = "absolute";
  probe.style.visibility = "hidden";
  document.documentElement.append(probe);
  const px = parseFloat(getComputedStyle(probe).fontSize);
  probe.remove();
  return px;
}

/** Sets the page's text scale; again whenever the page comes back, as the setting may have changed meanwhile. */
export function followTextSize() {
  const apply = () => {
    const scale = textScale(readerBody());
    document.documentElement.style.setProperty("-webkit-text-size-adjust", `${Math.round(scale * 100)}%`);
    document.documentElement.dataset.textScale = String(Math.round(scale * 100));
  };
  apply();
  document.addEventListener("visibilitychange", () => document.visibilityState === "visible" && apply());
}
