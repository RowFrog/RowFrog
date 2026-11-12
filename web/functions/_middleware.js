// Runs in front of every page of the website (Cloudflare Pages Functions).
//
// While the site is in testing, only the owner gets in, with the user name and
// password in the Pages secrets SITE_USER and SITE_PASSWORD (set by
// .github/workflows/website.yml). Without them the site stays shut.
//
// The site shows its own login page (owner OK 2026-11-04): iOS forgets a
// Basic Auth login whenever a Home Screen web app closes, and Keychain cannot
// fill that box. After a login the browser keeps a signed cookie for 90 days
// (HttpOnly, Secure, SameSite=Lax). Its signature is keyed on the user name
// and password, so a new password logs every device out. A wrong password
// waits a second before the answer. /__logout forgets the cookie. Basic Auth
// still works too, for scripts and the deploy check.
// robots.txt is served without a password, so well-behaved
// crawlers read that they are not welcome. So are the home-screen icons (owner
// OK 2026-11-04): Safari fetches them without the password, and "Add to Home
// Screen" then shows a plain letter. They are the app icon, already in the
// public repository. Only these exact file names open; everything else asks.
//
// Every answer, the password prompt included, tells search engines and AI
// crawlers not to index, follow, keep or train on anything.

/**
 * What the pages may load, and from where (Content Security Policy). Scripts only
 * from the site itself; styles from the site plus inline style attributes (the
 * pages build their HTML with them); pictures and data from the forecast server
 * and the map, radar and satellite services the pages use. Sent as
 * "Report-Only" for now: the browser only reports what it would block (in the
 * console), so nothing on the site can break. Once a few days show no reports,
 * CSP_ENFORCED turns it on. The browser test enforces it already
 * (web/tests/browser/smoke.test.mjs). A new outside service goes here too.
 */
export const CSP_SOURCES = {
  "default-src": ["'self'"],
  "script-src": ["'self'"],
  "style-src": ["'self'", "'unsafe-inline'"],
  "img-src": ["'self'", "data:", "blob:", "https://api.rowfrog.com", "https://tile.openstreetmap.org", "https://api.maptiler.com",
    "https://maps.dwd.de", "https://view.eumetsat.int"],
  "connect-src": ["'self'", "https://api.rowfrog.com", "https://maps.dwd.de", "https://view.eumetsat.int", "https://api.open-meteo.com",
    "https://api.maptiler.com"],
  "font-src": ["'self'"],
  "manifest-src": ["'self'"],
  "worker-src": ["'self'"],
  "object-src": ["'none'"],
  "base-uri": ["'self'"],
  "form-action": ["'self'"],
  "frame-ancestors": ["'none'"],
};
export const CSP = Object.entries(CSP_SOURCES).map(([k, v]) => `${k} ${v.join(" ")}`).join("; ");
export const CSP_ENFORCED = false;
/** Browser features the pages may use: location for "Suggest the launch point", nothing else. */
export const PERMISSIONS = "geolocation=(self), camera=(), microphone=(), payment=(), usb=(), interest-cohort=()";

export const NO_ROBOTS = "noindex, nofollow, noarchive, nosnippet, noimageindex, notranslate, noai, noimageai";

/** The only files served without the password. */
export const OPEN_FILES = new Set(["/robots.txt", "/icon-180.png", "/icon-192.png", "/icon-512.png", "/apple-touch-icon.png", "/favicon.ico"]);

export const COOKIE = "rf_login";
export const LOGIN_DAYS = 90;
export const LOGIN_PATH = "/__login";
export const LOGOUT_PATH = "/__logout";
const WRONG_PASSWORD_WAIT_MS = 1000;

export async function onRequest(context, now = Date.now()) {
  const { request, env } = context;
  const url = new URL(request.url);
  if (OPEN_FILES.has(url.pathname)) {
    return guarded(await context.next());
  }
  if (!env.SITE_USER || !env.SITE_PASSWORD) {
    return guarded(new Response("Closed.", { status: 503 }));
  }
  if (url.pathname === LOGOUT_PATH) {
    return guarded(new Response(null, { status: 303, headers: { Location: "/", "Set-Cookie": `${COOKIE}=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Lax` } }));
  }
  if (url.pathname === LOGIN_PATH && request.method === "POST") {
    return guarded(await logIn(request, env, now));
  }
  if (
    (await allowed(request.headers.get("Authorization"), env.SITE_USER, env.SITE_PASSWORD)) ||
    (await validCookie(readCookie(request.headers.get("Cookie"), COOKIE), env, now))
  ) {
    return guarded(await context.next());
  }
  return guarded(loginPage(request, url.pathname + url.search, false));
}

/** Checks the login form; on success sets the cookie and goes back to the page asked for. */
async function logIn(request, env, now) {
  let form;
  try {
    form = await request.formData();
  } catch {
    form = new FormData();
  }
  const user = String(form.get("user") ?? "");
  const password = String(form.get("password") ?? "");
  const next = safeNext(String(form.get("next") ?? "/"));
  if (!(await same(`${user}:${password}`, `${env.SITE_USER}:${env.SITE_PASSWORD}`))) {
    await new Promise((resolve) => setTimeout(resolve, WRONG_PASSWORD_WAIT_MS));
    return loginPage(request, next, true);
  }
  const cookie = await makeCookie(env, now);
  return new Response(null, {
    status: 303,
    headers: { Location: next, "Set-Cookie": `${COOKIE}=${cookie}; Path=/; Max-Age=${LOGIN_DAYS * 86400}; HttpOnly; Secure; SameSite=Lax` },
  });
}

/** Only paths on this site, so the login cannot send anyone elsewhere. */
export function safeNext(next) {
  return next.startsWith("/") && !next.startsWith("//") && !next.includes("\\") && !next.startsWith(LOGIN_PATH) ? next : "/";
}

/** "<expiry in ms>.<signature>", signed with a key made from the user name and password. */
export async function makeCookie(env, now) {
  const expires = String(now + LOGIN_DAYS * 86400 * 1000);
  return `${expires}.${await sign(expires, env)}`;
}

export async function validCookie(value, env, now) {
  if (!value) return false;
  const dot = value.indexOf(".");
  if (dot < 0) return false;
  const expires = value.slice(0, dot);
  if (!/^\d{1,16}$/.test(expires) || Number(expires) <= now) return false;
  return same(value.slice(dot + 1), await sign(expires, env));
}

async function sign(text, env) {
  const key = await crypto.subtle.importKey("raw", await digest(`rf-login:${env.SITE_USER}:${env.SITE_PASSWORD}`), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(text)));
  return btoa(String.fromCharCode(...mac)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function readCookie(header, name) {
  for (const part of (header ?? "").split(";")) {
    const eq = part.indexOf("=");
    if (eq > 0 && part.slice(0, eq).trim() === name) return part.slice(eq + 1).trim();
  }
  return null;
}

const PAGE_TEXT = {
  en: { title: "Row Frog (testing)", lead: "This site is in testing. Please log in.", user: "User name", password: "Password", button: "Log in", wrong: "Wrong user name or password." },
  de: { title: "Row Frog (Test)", lead: "Diese Seite wird gerade getestet. Bitte anmelden.", user: "Benutzername", password: "Passwort", button: "Anmelden", wrong: "Benutzername oder Passwort falsch." },
};

const escape = (text) => text.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

/** The login form, answered with 401 so the site still reads as closed. */
export function loginPage(request, next, wrong) {
  const lang = /^de\b/i.test(request.headers.get("Accept-Language") ?? "") ? "de" : "en";
  const x = PAGE_TEXT[lang];
  const html = `<!doctype html>
<html lang="${lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="${NO_ROBOTS}"><title>${x.title}</title>
<link rel="apple-touch-icon" sizes="180x180" href="/icon-180.png"><link rel="icon" href="/icon-192.png">
<style>
:root { color-scheme: light dark; --bg: #f2f2f7; --card: #fff; --text: #000; --sub: #6e6e73; --accent: #0a84ff; --line: #d1d1d6; }
@media (prefers-color-scheme: dark) { :root { --bg: #000; --card: #1c1c1e; --text: #fff; --sub: #98989f; --line: #38383a; } }
body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: var(--bg); color: var(--text); font: 17px -apple-system, system-ui, sans-serif; }
form { width: min(340px, calc(100vw - 32px)); background: var(--card); border-radius: 16px; padding: 24px; box-sizing: border-box; display: grid; gap: 12px; }
img { width: 64px; height: 64px; border-radius: 14px; justify-self: center; }
h1 { font-size: 22px; margin: 0; text-align: center; } p { margin: 0; color: var(--sub); text-align: center; }
label { display: grid; gap: 4px; font-size: 15px; color: var(--sub); }
input { font: inherit; color: var(--text); background: transparent; border: 1px solid var(--line); border-radius: 10px; padding: 10px 12px; }
button { font: inherit; font-weight: 600; color: #fff; background: var(--accent); border: 0; border-radius: 12px; padding: 12px; cursor: pointer; }
.wrong { color: #ff3b30; }
</style></head>
<body><form method="post" action="${LOGIN_PATH}">
<img src="/icon-180.png" alt=""><h1>${x.title}</h1><p>${x.lead}</p>
${wrong ? `<p class="wrong" role="alert">${x.wrong}</p>` : ""}
<label>${x.user}<input name="user" autocomplete="username" autocapitalize="none" autocorrect="off" spellcheck="false" required autofocus></label>
<label>${x.password}<input name="password" type="password" autocomplete="current-password" required></label>
<input type="hidden" name="next" value="${escape(safeNext(next))}">
<button type="submit">${x.button}</button>
</form></body></html>`;
  return new Response(html, { status: 401, headers: { "Content-Type": "text/html; charset=utf-8" } });
}

/** True when the Basic Auth header carries the right user and password. */
export async function allowed(header, user, password) {
  if (!header || !header.startsWith("Basic ")) return false;
  let given;
  try {
    given = new TextDecoder().decode(Uint8Array.from(atob(header.slice(6).trim()), (c) => c.charCodeAt(0)));
  } catch {
    return false;
  }
  const colon = given.indexOf(":");
  if (colon < 0) return false;
  return same(given, `${user}:${password}`);
}

/** Compares hashes, which takes the same time however much of a guess is right. */
async function same(given, expected) {
  const [a, b] = await Promise.all([digest(given), digest(expected)]);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

async function digest(text) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
}

function guarded(response) {
  const out = new Response(response.body, response);
  out.headers.set("X-Robots-Tag", NO_ROBOTS);
  out.headers.set("Cache-Control", "private, no-store");
  out.headers.set("Referrer-Policy", "no-referrer");
  out.headers.set("X-Content-Type-Options", "nosniff");
  out.headers.set("X-Frame-Options", "DENY");
  out.headers.set(CSP_ENFORCED ? "Content-Security-Policy" : "Content-Security-Policy-Report-Only", CSP);
  out.headers.set("Permissions-Policy", PERMISSIONS);
  out.headers.set("Cross-Origin-Opener-Policy", "same-origin");
  out.headers.set("Strict-Transport-Security", "max-age=31536000");
  // Every reply depends on the login cookie or header, so no cache shares it.
  out.headers.append("Vary", "Cookie, Authorization");
  return out;
}
