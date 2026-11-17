// The Home Screen menu of an installed website (manifest shortcuts), as the app's long-press menu
// (QuickActions.swift, decision 0048): the home base, its lake view, its rain radar and the club
// opened last. A manifest's list is fixed, so its links name no club: #/home, #/home/lake,
// #/home/radar and #/last pick the club here.

import { load, save } from "./shared.js";

const LAST = "rf.lastOpened";

/** The club a menu link opens: the first saved club, or the one shown last besides it (else the next one). */
export function quickClub(which, ids, last) {
  if (!ids.length) return null;
  if (which === "home") return ids[0];
  return last !== ids[0] && ids.includes(last) ? last : ids[1] ?? ids[0];
}

/** "#/home/lake" -> { which: "home", part: "lake" }; null for other pages. */
export function quickLink(hash) {
  const m = hash.match(/^\/(home|last)(?:\/(lake|radar))?$/);
  return m ? { which: m[1], part: m[2] ?? null } : null;
}

/** Notes the club on screen for #/last; the first saved club doesn't count (QuickActions.noteShown). */
export function noteShown(id, ids) {
  if (id && ids.includes(id) && id !== ids[0]) save(LAST, id);
}

export const lastShown = () => load(LAST, null);
