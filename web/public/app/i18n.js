// The page's text in English or German. As in the app, the English text is
// the key; German comes from de.json, which scripts/build_web.py makes from
// the app's table (ios/RowFrog/Localization.swift) plus web/strings-de.json
// for the texts only the website has. A test checks that every text passed to t has German.

let german = {};
let language = "en";

const STORE = "rf.language";

export function savedLanguage() {
  try {
    return localStorage.getItem(STORE) || "auto";
  } catch {
    return "auto";
  }
}

export function resolve(choice = savedLanguage()) {
  if (choice === "en" || choice === "de") return choice;
  return (navigator.language || "en").toLowerCase().startsWith("de") ? "de" : "en";
}

export async function setLanguage(choice) {
  try {
    localStorage.setItem(STORE, choice);
  } catch {}
  language = resolve(choice);
  if (language === "de" && !Object.keys(german).length) {
    try {
      german = await (await fetch(new URL("de.json", import.meta.url))).json();
    } catch {
      german = {};
    }
  }
  document.documentElement.lang = language;
}

export function lang() {
  return language;
}

export function locale() {
  return language === "de" ? "de-DE" : "en-GB";
}

/** The text in the chosen language, with each %@ replaced by the next argument in turn. */
export function t(english, ...args) {
  const text = language === "de" ? german[english] ?? english : english;
  let i = 0;
  return text.replace(/%@/g, () => String(args[i++] ?? ""));
}

/** A number in the page's language: 12.7 or 12,7. */
export function num(value, digits = 0) {
  if (value == null || Number.isNaN(value)) return "–";
  // Rounded to the digits first, so -0.3 shows as 0, not -0.
  const rounded = Number(value.toFixed(digits)) || 0;
  return new Intl.NumberFormat(locale(), { minimumFractionDigits: digits, maximumFractionDigits: digits }).format(rounded);
}
