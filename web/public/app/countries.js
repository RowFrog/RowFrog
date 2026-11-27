// Browse clubs by country (ClubSearch.swift): every country the search
// covers, then its waters or towns grouped by state or first letter, then
// the clubs; and the country chips above the search results.

import { t, lang, locale } from "./i18n.js";
import { icon } from "./icons.js";
import { fold, town, place, waterUnknown } from "./logic.js";
import { store, loadCountryIndex, html, raw, flag, setTitle, footerLinks, loadCatalog, savedClub, lakeTitle, load, save } from "./shared.js";

// Markup here goes through html``, which escapes every value (shared.js).
const svg = (...args) => raw(icon(...args));
const footer = () => raw(footerLinks());

let index = null;

/** The countries with their club counts (countries/index). */
export async function loadCountries() {
  index ??= await loadCountryIndex();
  return index;
}

/** The waters with only their clubs in one country: a border lake is listed by each country with its own clubs. */
export const inCountry = (lakes, code) => lakes
  .map((l) => ({ ...l, clubs: l.clubs.filter((c) => (c.country ?? l.country ?? "de") === code) }))
  .filter((l) => l.clubs.length);

export const countryName = (c) => (lang() === "de" ? c.nameDe ?? c.name : c.name);

/** "All countries" and one chip per country above the search results (CountryChips). */
export function countryChips(countries, selected) {
  if (countries.length < 2) return "";
  const chip = (code, label) => html`<button class="chip ${selected === code ? "on" : ""}" data-country="${code ?? ""}" aria-pressed="${String(selected === code)}">${label}</button>`;
  return html`<div class="chips country-chips">${chip(null, t("All countries"))}${countries.map((c) => chip(c.code, `${flag(c.code)} ${countryName(c)}`))}</div>`;
}

/** One club to add, as in the search (SearchResultRow). */
export function resultRow(club, lake, { showFlag = true } = {}) {
  const saved = store.clubs.some((c) => c.id === club.id);
  return html`<li><button class="result" data-club="${club.id}" data-lake="${lake.id}">
      ${showFlag && html`<span class="flag">${flag(club.country ?? lake.country)}</span>`}
      <span class="result-text"><strong>${club.name}</strong>
      <small>${place(lake.name, town(club.address), lakeTitle)}</small>
      ${!club.launchPointVerified && html`<small class="orange">${t("Launch point not yet confirmed")}</small>`}</span>
      <span class="add ${saved ? "in" : ""}">${svg(saved ? "circle-check" : "plus")}</span>
    </button></li>`;
}

/** A tapped result joins the saved clubs (if not yet there) and its page opens. */
export function wireResults(list, lakes) {
  list.addEventListener("click", (e) => {
    const button = e.target.closest(".result");
    if (!button) return;
    const lake = lakes.find((l) => l.id === button.dataset.lake);
    const club = lake?.clubs.find((c) => c.id === button.dataset.club);
    if (!club) return;
    if (!store.clubs.some((c) => c.id === club.id)) store.clubs = [...store.clubs, savedClub(club, lake)];
    location.hash = `#/club/${encodeURIComponent(club.id)}`;
  });
}

// ---- The pages ------------------------------------------------------------------------

/** A page with the back button named after the page it goes back to, as the app's navigation bar does. */
function page(title, back, body, backTitle = t("Back")) {
  setTitle(title);
  return html`<header class="nav"><a class="link" href="${back}">${svg("chevron-left")} <span class="back-title">${backTitle}</span></a><strong class="nav-title">${title}</strong><span class="nav-side"></span></header>
    <main class="page">${body}${footer()}</main>`;
}

const compare = (a, b) => a.localeCompare(b, locale(), { sensitivity: "base", numeric: true });

/** Every country the search covers (CountryListView). */
export async function renderCountries(root) {
  root.innerHTML = page(t("Countries"), "#/list", html`<p class="spinner-line"><span class="spinner"></span></p>`, t("Locations"));
  let countries;
  try {
    countries = await loadCountries();
  } catch {
    root.querySelector("main").innerHTML = html`<p class="empty">${t("Could not load the club list.")}</p>${footer()}`;
    return;
  }
  root.querySelector("main").innerHTML = html`<h1 class="large">${t("Countries")}</h1>
    <ul class="results">${countries.map((c) => html`<li><a class="result" href="#/countries/${c.code}">
      <span class="flag">${flag(c.code)}</span><span class="result-text"><strong>${countryName(c)}</strong></span>
      <span class="sub">${t("%@ clubs", String(c.clubs))}</span>${svg("chevron-right")}</a></li>`)}</ul>${footer()}`;
}

/** The list title of a club's water: the town when the catalogs don't know the water; a river section adds its place, as one river has several: "Main · Offenbach" (Lake.listTitle). */
const listTitle = (lake) => (waterUnknown(lake.name) ? lake.name.slice("Water near ".length) : lake.section?.place ? `${lake.name} · ${lake.section.place}` : lake.name);

/**
 * One row per water (or per town), with its clubs: pieces of one river or
 * lake that the map data keeps apart share a row; each club keeps its own
 * lake and forecast point.
 */
export function countryRows(lakes, byTown) {
  const groups = new Map();
  for (const lake of lakes) {
    for (const club of lake.clubs) {
      const title = byTown ? town(club.address) ?? listTitle(lake) : listTitle(lake);
      if (!title) continue;
      const unknown = !byTown && waterUnknown(lake.name);
      const id = `${unknown ? "near:" : ""}${fold(title)}`;
      if (!groups.has(id)) groups.set(id, { id, title, unknown, clubs: [] });
      groups.get(id).clubs.push({ club, lake });
    }
  }
  const rows = [...groups.values()];
  for (const row of rows) row.clubs.sort((a, b) => compare(a.club.name, b.club.name));
  return rows.sort((a, b) => compare(a.title, b.title));
}

/** Whether a row matches the filter: its water or town, or one of its clubs by name or town. */
export function rowMatches(row, query) {
  const q = fold(query);
  if (!q || fold(row.title).includes(q)) return true;
  return row.clubs.some(({ club, lake }) => [club.name, club.shortName, club.abbreviation, town(club.address), listTitle(lake)]
    .some((x) => x && fold(x).includes(q)));
}

/** By water or by town, kept in the browser (RWCountryListByTown). */
const byTown = () => load("rf.countryByTown", false) === true;

/** One country's waters, grouped by state where the list names them, otherwise by first letter (CountryWatersView). */
export async function renderCountry(root, code, filter = "") {
  root.innerHTML = page(t("Countries"), "#/countries", html`<p class="spinner-line"><span class="spinner"></span></p>`, t("Countries"));
  let country;
  let lakes;
  try {
    country = (await loadCountries()).find((c) => c.code === code);
    lakes = inCountry(await loadCatalog(), code);
  } catch {
    root.querySelector("main").innerHTML = html`<p class="empty">${t("Could not load the club list.")}</p>${footer()}`;
    return;
  }
  const title = country ? `${flag(code)} ${countryName(country)}` : code;
  setTitle(title);
  root.querySelector(".nav-title").textContent = title;
  const main = root.querySelector("main");
  main.innerHTML = html`<h1 class="large">${title}</h1>
    <div class="segmented" id="by">${[[false, t("By water")], [true, t("By town")]].map(([v, label]) => html`<button data-town="${String(v)}" class="${byTown() === v ? "on" : ""}">${label}</button>`)}</div>
    <label class="search">${svg("search")}<input id="filter" type="search" autocomplete="off" value="${filter}" placeholder="${t("Lake, river, club or town")}" aria-label="${t("Lake, river, club or town")}"></label>
    <div id="waters"></div>${footer()}`;
  const input = main.querySelector("#filter");
  const draw = () => {
    const rows = countryRows(lakes, byTown()).filter((r) => rowMatches(r, input.value));
    const regions = lakes.some((l) => l.clubs.some((c) => c.region));
    const groups = new Map();
    for (const row of rows) {
      // Ä under A, Ö under O, Ü under U, as in a dictionary.
      const key = regions ? row.clubs[0].club.region ?? t("Other") : fold(row.title.slice(0, 1)).toUpperCase();
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(row);
    }
    const keys = [...groups.keys()].sort(compare);
    main.querySelector("#waters").innerHTML = keys.length
      ? html`${keys.map((key) => html`<h3 class="section">${key}</h3>
      <ul class="results">${groups.get(key).map((row) => html`<li><a class="result" href="#/countries/${code}/${encodeURIComponent(row.id)}">
        <span class="result-text"><strong>${row.title}</strong>${row.unknown && html`<small>${t("Water not yet known")}</small>`}</span>
        <span class="sub">${row.clubs.length}</span>${svg("chevron-right")}</a></li>`)}</ul>`)}`
      : html`<p class="empty">${t("No clubs found.")}</p>`;
  };
  main.querySelectorAll("#by button").forEach((b) => b.addEventListener("click", () => {
    save("rf.countryByTown", b.dataset.town === "true");
    main.querySelectorAll("#by button").forEach((x) => x.classList.toggle("on", x === b));
    draw();
  }));
  input.addEventListener("input", () => {
    draw();
    // Coming back from a water keeps the filter.
    history.replaceState(null, "", `#/countries/${code}${input.value ? `?q=${encodeURIComponent(input.value)}` : ""}`);
  });
  draw();
}

/** The clubs on one water or in one town (WaterClubsView). */
export async function renderWater(root, code, rowId) {
  root.innerHTML = page("", `#/countries/${code}`, html`<p class="spinner-line"><span class="spinner"></span></p>`);
  let lakes;
  try {
    lakes = inCountry(await loadCatalog(), code);
  } catch {
    root.querySelector("main").innerHTML = html`<p class="empty">${t("Could not load the club list.")}</p>${footer()}`;
    return;
  }
  const row = countryRows(lakes, byTown()).find((r) => r.id === rowId) ?? countryRows(lakes, !byTown()).find((r) => r.id === rowId);
  if (!row) {
    location.replace(`#/countries/${code}`);
    return;
  }
  setTitle(row.title);
  root.querySelector(".nav-title").textContent = row.title;
  // Back to the country, named as the app's back button would (short names only, else "Back").
  const country = (await loadCountries().catch(() => [])).find((c) => c.code === code);
  const name = country ? countryName(country) : "";
  if (name && name.length <= 14) root.querySelector(".back-title").textContent = name;
  const main = root.querySelector("main");
  main.innerHTML = html`<h1 class="large">${row.title}</h1><ul class="results" id="clubs">${row.clubs.map(({ club, lake }) => resultRow(club, lake, { showFlag: false }))}</ul>${footer()}`;
  wireResults(main.querySelector("#clubs"), lakes);
}
