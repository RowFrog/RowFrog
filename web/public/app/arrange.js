// "Arrange this page" (ArrangePageSheet, PageLayout): the order of the cards
// on a club page and which are switched off, for all clubs or only one. The
// rowing light and the warnings always stay on top; the forecast source and
// the credits stay at the end.

import { t } from "./i18n.js";
import { key } from "./logic.js";
import { icon } from "./icons.js";
import { h, load, save } from "./shared.js";

/** Every card, as the app names them (PageCard). */
export const CARDS = {
  radar: { title: key("Rain radar"), icon: "umbrella" },
  conditions: { title: key("Current conditions"), icon: "gauge" },
  lakeView: { title: key("Lake view"), icon: "map" },
  hourly: { title: key("Next 48 hours"), icon: "clock" },
  launchPoint: { title: key("Launch point"), icon: "map-pin" },
  satellite: { title: key("Satellite picture"), icon: "globe" },
};

/** The cards this website draws (all of the app's). */
const ON_WEBSITE = ["conditions", "radar", "lakeView", "hourly", "launchPoint", "satellite"];

// The rain radar card starts switched off: the rain tile shows the radar.
export const STANDARD = { order: ["conditions", "radar", "lakeView", "hourly", "launchPoint", "satellite"], hidden: ["radar"], radarInTile: true };

/**
 * Every card once, unknown names dropped; cards added in a later version join at the end.
 * Orders saved before the rain tile took over the radar switch its card off once
 * (`radarInTile`, as PageLayout in the app); switched on again later, it stays on.
 */
export function normalized(layout) {
  const known = (list) => (Array.isArray(list) ? list : []).filter((c) => c in CARDS);
  const order = [...new Set([...known(layout?.order), ...STANDARD.order])];
  const hidden = known(layout?.hidden ?? STANDARD.hidden);
  if (layout?.radarInTile !== true) hidden.push("radar");
  return { order, hidden: [...new Set(hidden)], radarInTile: true };
}

const clubLayouts = () => {
  const all = load("rf.clubPageLayouts", {});
  return all && typeof all === "object" ? all : {};
};

export const pageLayout = () => normalized(load("rf.pageLayout", STANDARD));

/** A club's own order, else the one for all clubs. */
export function layoutFor(clubId) {
  const own = clubLayouts()[clubId];
  return own ? normalized(own) : pageLayout();
}

/** The cards to draw, in order. */
export const visibleCards = (layout) => layout.order.filter((c) => !layout.hidden.includes(c) && ON_WEBSITE.includes(c));

/** Saves the order, for one club or for all; chosen for all on a club's page, that club follows them again. */
export function saveLayout(layout, clubId, onlyThisClub) {
  const all = clubLayouts();
  if (clubId && onlyThisClub) {
    save("rf.clubPageLayouts", { ...all, [clubId]: layout });
    return;
  }
  save("rf.pageLayout", layout);
  if (clubId && all[clubId]) {
    delete all[clubId];
    save("rf.clubPageLayouts", all);
  }
}

/** Moves one card in the order to another card's place. */
export function moved(order, card, to) {
  const rest = order.filter((c) => c !== card);
  rest.splice(Math.max(0, Math.min(to, rest.length)), 0, card);
  return rest;
}

/** The sheet, from a club page (club) or from the settings (null, always for all clubs). */
export function openArrange(club, done) {
  const clubId = club?.id ?? null;
  const own = clubId ? clubLayouts()[clubId] : null;
  let onlyThisClub = !!own;
  let layout = clubId ? layoutFor(clubId) : pageLayout();
  const name = club ? club.shortName || club.name : "";

  document.querySelector("dialog.sheet")?.remove();
  const dialog = document.createElement("dialog");
  dialog.className = "sheet arrange";
  document.body.append(dialog);

  const otherClubsNote = () => {
    const others = Object.keys(clubLayouts()).filter((id) => id !== clubId).length;
    return others ? t("Every club page uses this order, except %@ with their own.", String(others)) : t("Every club page uses this order.");
  };
  const fixedRow = (title, iconName, note) => `<li class="fixed">${icon(iconName)}<span class="grow">${h(title)}</span>
    <small class="sub">${h(note)}</small>${icon("lock")}</li>`;
  // Only the cards the website draws can be moved; the order keeps the others in place.
  const shown = () => layout.order.filter((c) => ON_WEBSITE.includes(c));
  const cardRow = (c, i, list) => {
    const off = layout.hidden.includes(c);
    return `<li class="${off ? "off" : ""}" data-card="${c}">
      <span class="handle" aria-hidden="true">${icon("grip-vertical")}</span>
      ${icon(CARDS[c].icon)}<span class="grow">${h(t(CARDS[c].title))}</span>
      <button class="step" data-step="-1" ${i === 0 ? "disabled" : ""} aria-label="${h(t("Move up"))}">${icon("chevron-up")}</button>
      <button class="step" data-step="1" ${i === list.length - 1 ? "disabled" : ""} aria-label="${h(t("Move down"))}">${icon("chevron-down")}</button>
      <input type="checkbox" class="switch" ${off ? "" : "checked"} aria-label="${h(t(CARDS[c].title))}"></li>`;
  };

  const draw = () => {
    dialog.innerHTML = `<header><button class="link" id="arrange-cancel">${h(t("Cancel"))}</button><strong>${h(t("Arrange page"))}</strong><button class="done" id="arrange-save">${h(t("Done"))}</button></header>
      <div class="sheet-body">
        ${club ? `<div class="segmented" id="apply" role="group" aria-label="${h(t("Apply to"))}">
            <button data-only="false" class="${onlyThisClub ? "" : "on"}">${h(t("All clubs"))}</button>
            <button data-only="true" class="${onlyThisClub ? "on" : ""}">${h(t("Only %@", name))}</button></div>
          <p class="footer">${h(onlyThisClub ? t("Only this club's page changes. Changes for all clubs no longer reach it until you reset it.") : otherClubsNote())}</p>` : ""}
        <h3 class="section">${h(t("Drag the handles to change the order"))}</h3>
        <ul class="card group arrange-list">
          ${fixedRow(t("Rowing light"), "circle", t("always first"))}
          ${fixedRow(t("Official warnings"), "triangle-alert", t("right under it, while one is issued"))}
          ${shown().map(cardRow).join("")}
        </ul>
        <p class="footer">${h(`${t("Switched-off cards are left out of the page. The forecast source and credits stay at the end.")} ${t("The rain radar card starts switched off: the rain tile in Current conditions shows the radar.")}`)}</p>
        ${onlyThisClub ? `<button class="quiet" id="arrange-follow">${h(t("Use the order for all clubs"))}</button>`
          : `<button class="quiet" id="arrange-reset">${h(t("Reset to the standard order"))}</button>`}
      </div>`;
    wire();
  };

  // The order of all cards with one shown card moved to another shown card's place.
  const moveTo = (card, shownIndex) => {
    const target = shown().filter((c) => c !== card)[shownIndex];
    const others = layout.order.filter((c) => c !== card);
    const at = target ? others.indexOf(target) : others.length;
    layout = { ...layout, order: moved(layout.order, card, at) };
  };

  const wire = () => {
    dialog.querySelector("#arrange-cancel").addEventListener("click", () => dialog.close());
    dialog.querySelector("#arrange-save").addEventListener("click", () => {
      saveLayout(layout, clubId, onlyThisClub);
      dialog.close();
      done?.();
    });
    dialog.querySelectorAll("#apply button").forEach((b) => b.addEventListener("click", () => {
      onlyThisClub = b.dataset.only === "true";
      // Start from what that choice shows today.
      layout = onlyThisClub ? layoutFor(clubId) : pageLayout();
      draw();
    }));
    dialog.querySelector("#arrange-follow")?.addEventListener("click", () => {
      onlyThisClub = false;
      layout = pageLayout();
      draw();
    });
    dialog.querySelector("#arrange-reset")?.addEventListener("click", () => {
      layout = normalized(STANDARD);
      draw();
    });
    const list = dialog.querySelector(".arrange-list");
    list.querySelectorAll("li[data-card]").forEach((row) => {
      const c = row.dataset.card;
      row.querySelector(".switch").addEventListener("change", (e) => {
        const hidden = layout.hidden.filter((x) => x !== c);
        layout = { ...layout, hidden: e.target.checked ? hidden : [...hidden, c] };
        row.classList.toggle("off", !e.target.checked);
      });
      row.querySelectorAll(".step").forEach((b) => b.addEventListener("click", () => {
        moveTo(c, shown().indexOf(c) + +b.dataset.step);
        draw();
        dialog.querySelector(`li[data-card="${c}"] .step[data-step="${b.dataset.step}"]:not(:disabled)`)?.focus();
      }));
      dragByHandle(list, row, (index) => {
        moveTo(c, index);
        draw();
      });
    });
  };

  dialog.addEventListener("click", (e) => e.target === dialog && dialog.close());
  dialog.addEventListener("close", () => dialog.remove());
  draw();
  dialog.showModal();
}

/** Drags a row by its handle (mouse, pen or finger); the rows make room as it passes. */
function dragByHandle(list, row, drop) {
  const handle = row.querySelector(".handle");
  handle.addEventListener("pointerdown", (e) => {
    e.preventDefault();
    handle.setPointerCapture(e.pointerId);
    const rows = () => [...list.querySelectorAll("li[data-card]")];
    const startY = e.clientY;
    row.classList.add("dragging");
    const move = (ev) => {
      row.style.transform = `translateY(${ev.clientY - startY}px)`;
      const mid = row.getBoundingClientRect().top + row.offsetHeight / 2;
      const others = rows().filter((r) => r !== row);
      // Where the row would land: before the first other row whose middle is below it.
      const before = others.find((r) => mid < r.getBoundingClientRect().top + r.offsetHeight / 2);
      const index = before ? others.indexOf(before) : others.length;
      const shift = row.offsetHeight;
      const from = rows().indexOf(row);
      others.forEach((r, i) => {
        const was = i >= from ? i + 1 : i;
        r.style.transform = was < from && i >= index ? `translateY(${shift}px)` : was > from && i < index ? `translateY(${-shift}px)` : "";
      });
      row.dataset.to = index;
    };
    const end = () => {
      handle.removeEventListener("pointermove", move);
      handle.removeEventListener("pointerup", end);
      handle.removeEventListener("pointercancel", end);
      const to = row.dataset.to;
      rows().forEach((r) => (r.style.transform = ""));
      row.classList.remove("dragging");
      if (to != null) drop(+to);
    };
    handle.addEventListener("pointermove", move);
    handle.addEventListener("pointerup", end);
    handle.addEventListener("pointercancel", end);
  });
}
