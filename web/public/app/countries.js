// Browse clubs by country (ClubSearch.swift): every country the search
// covers, then its waters or towns grouped by state or first letter, then
// the clubs; and the country chips above the search results.

import { t, lang, locale } from "./i18n.js";
import { icon } from "./icons.js";
import { fold, town, place, waterUnknown } from "./logic.js";
import { store, getJSON, h, flag, setTitle, testing, footerLinks, loadCatalog, savedClub, lakeTitle, load, save } from "./shared.js";

let index = null;

/** The countries with their club counts (countries/index). */
export async function loadCountries() {
  index ??= await getJSON("countries/index");
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
  const chip = (code, label) => `<button class="chip ${selected === code ? "on" : ""}" data-country="${code ?? ""}" aria-pressed="${selected === code}">${h(label)}</button>`;
  return `<div class="chips country-chips">${chip(null, t("All countries"))}${countries.map((c) => chip(c.code, `${flag(c.code)} ${countryName(c)}`)).join("")}</div>`;
}

/** One club to add, as in the search (SearchResultRow). */
export function resultRow(club, lake, { showFlag = true } = {}) {
  const saved = store.clubs.some((c) => c.id === club.id);
  return `<li><button class="result" data-club="${h(club.id)}" data-lake="${h(lake.id)}">
      ${showFlag ? `<span class="flag">${flag(club.country ?? lake.country)}</span>` : ""}
      <span class="result-text"><strong>${h(club.name)}</strong>
      <small>${h(place(lake.name, town(club.address), lakeTitle))}</small>
      ${club.launchPointVerified ? "" : `<small class="orange">${h(t("Launch point not yet confirmed"))}</small>`}</span>
      <span class="add ${saved ? "in" : ""}">${icon(saved ? "circle-check" : "plus")}</span>
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

function page(title, back, body) {
  setTitle(title);
  return `<header class="nav"><a class="link" href="${back}">${icon("chevron-left")} ${h(t("Back"))}</a><strong class="nav-title">${h(title)}</strong><span class="nav-side"></span></header>
    ${testing()}
    <main class="page">${body}${footerLinks()}</main>`;
}

const compare = (a, b) => a.localeCompare(b, locale(), { sensitivity: "base", numeric: true });

/** Every country the search covers (CountryListView). */
export async function renderCountries(root) {
  root.innerHTML = page(t("Countries"), "#/list", `<p class="spinner-line"><span class="spinner"></span></p>`);
  let countries;
  try {
    countries = await loadCountries();
  } catch {
    root.querySelector("main").innerHTML = `<p class="empty">${h(t("Could not load the club list."))}</p>${footerLinks()}`;
    return;
  }
  root.querySelector("main").innerHTML = `<h1 class="large">${h(t("Countries"))}</h1>
    <ul class="results">${countries.map((c) => `<li><a class="result" href="#/countries/${c.code}">
      <span class="flag">${flag(c.code)}</span><span class="result-text"><strong>${h(countryName(c))}</strong></span>
      <span class="sub">${h(t("%@ clubs", String(c.clubs)))}</span>${icon("chevron-right")}</a></li>`).join("")}</ul>${footerLinks()}`;
}

/** The list title of a club's water: the town when the catalogs don't know the water (Lake.listTitle). */
const listTitle = (lake) => (waterUnknown(lake.name) ? lake.name.slice("Water near ".length) : lake.name);

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
  root.innerHTML = page(t("Countries"), "#/countries", `<p class="spinner-line"><span class="spinner"></span></p>`);
  let country;
  let lakes;
  try {
    country = (await loadCountries()).find((c) => c.code === code);
    lakes = inCountry(await loadCatalog(), code);
  } catch {
    root.querySelector("main").innerHTML = `<p class="empty">${h(t("Could not load the club list."))}</p>${footerLinks()}`;
    return;
  }
  const title = country ? `${flag(code)} ${countryName(country)}` : code;
  setTitle(title);
  root.querySelector(".nav-title").textContent = title;
  const main = root.querySelector("main");
  main.innerHTML = `<h1 class="large">${h(title)}</h1>
    <div class="segmented" id="by">${[[false, t("By water")], [true, t("By town")]].map(([v, label]) => `<button data-town="${v}" class="${byTown() === v ? "on" : ""}">${h(label)}</button>`).join("")}</div>
    <label class="search">${icon("search")}<input id="filter" type="search" autocomplete="off" value="${h(filter)}" placeholder="${h(t("Lake, river, club or town"))}" aria-label="${h(t("Lake, river, club or town"))}"></label>
    <div id="waters"></div>${footerLinks()}`;
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
    main.querySelector("#waters").innerHTML = [...groups.keys()].sort(compare).map((key) => `<h3 class="section">${h(key)}</h3>
      <ul class="results">${groups.get(key).map((row) => `<li><a class="result" href="#/countries/${code}/${encodeURIComponent(row.id)}">
        <span class="result-text"><strong>${h(row.title)}</strong>${row.unknown ? `<small>${h(t("Water not yet known"))}</small>` : ""}</span>
        <span class="sub">${row.clubs.length}</span>${icon("chevron-right")}</a></li>`).join("")}</ul>`).join("")
      || `<p class="empty">${h(t("No clubs found."))}</p>`;
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
  root.innerHTML = page("", `#/countries/${code}`, `<p class="spinner-line"><span class="spinner"></span></p>`);
  let lakes;
  try {
    lakes = inCountry(await loadCatalog(), code);
  } catch {
    root.querySelector("main").innerHTML = `<p class="empty">${h(t("Could not load the club list."))}</p>${footerLinks()}`;
    return;
  }
  const row = countryRows(lakes, byTown()).find((r) => r.id === rowId) ?? countryRows(lakes, !byTown()).find((r) => r.id === rowId);
  if (!row) {
    location.replace(`#/countries/${code}`);
    return;
  }
  setTitle(row.title);
  root.querySelector(".nav-title").textContent = row.title;
  const main = root.querySelector("main");
  main.innerHTML = `<h1 class="large">${h(row.title)}</h1><ul class="results" id="clubs">${row.clubs.map(({ club, lake }) => resultRow(club, lake, { showFlag: false })).join("")}</ul>${footerLinks()}`;
  wireResults(main.querySelector("#clubs"), lakes);
}
