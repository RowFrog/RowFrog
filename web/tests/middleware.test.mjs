import { test } from "node:test";
import assert from "node:assert/strict";
import { onRequest, NO_ROBOTS, makeCookie, validCookie, safeNext, readCookie, LOGIN_DAYS, CSP, CSP_ENFORCED, PERMISSIONS } from "../functions/_middleware.js";

const env = { SITE_USER: "alex", SITE_PASSWORD: "s3cret pass" };

function call(path, authorization, environment = env, extra = {}, now = Date.now()) {
  const headers = { ...(authorization ? { Authorization: authorization } : {}), ...(extra.headers ?? {}) };
  return onRequest({
    request: new Request(`https://rowfrog.com${path}`, { method: extra.method ?? "GET", headers, body: extra.body }),
    env: environment,
    next: async () => new Response("page", { headers: { "Content-Type": "text/html" } }),
  }, now);
}

function logIn(user, password, next = "/app/", now = Date.now()) {
  const body = new URLSearchParams({ user, password, next });
  return call("/__login", null, env, { method: "POST", body, headers: { "Content-Type": "application/x-www-form-urlencoded" } }, now);
}

const basic = (user, password) => `Basic ${btoa(`${user}:${password}`)}`;

test("without a password the login page shows, and robots are told to stay away", async () => {
  const response = await call("/app/#/club/x?d=1");
  assert.equal(response.status, 401);
  assert.equal(response.headers.get("WWW-Authenticate"), null);
  assert.equal(response.headers.get("X-Robots-Tag"), NO_ROBOTS);
  const html = await response.text();
  assert.notEqual(html, "page");
  assert.match(html, /<form method="post" action="\/__login">/);
  assert.match(html, /autocomplete="current-password"/);
  assert.match(html, /name="robots" content="noindex/);
  assert.match(html, /value="\/app\/"/);
});

test("the login page speaks German to German browsers", async () => {
  const html = await (await call("/", null, env, { headers: { "Accept-Language": "de-DE,de;q=0.9" } })).text();
  assert.match(html, /Anmelden/);
});

test("logging in sets a 90-day cookie that opens the site", async () => {
  const response = await logIn("alex", "s3cret pass", "/app/?d=2");
  assert.equal(response.status, 303);
  assert.equal(response.headers.get("Location"), "/app/?d=2");
  const cookie = response.headers.get("Set-Cookie");
  assert.match(cookie, new RegExp(`^rf_login=[^;]+; Path=/; Max-Age=${LOGIN_DAYS * 86400}; HttpOnly; Secure; SameSite=Lax$`));
  assert.equal(response.headers.get("X-Robots-Tag"), NO_ROBOTS);
  const value = cookie.split(";")[0];
  const page = await call("/app/", null, env, { headers: { Cookie: `other=1; ${value}` } });
  assert.equal(page.status, 200);
  assert.equal(await page.text(), "page");
});

test("a wrong login waits, shows the form again and sets no cookie", async () => {
  const started = Date.now();
  const response = await logIn("alex", "wrong");
  assert.ok(Date.now() - started >= 900);
  assert.equal(response.status, 401);
  assert.equal(response.headers.get("Set-Cookie"), null);
  assert.match(await response.text(), /role="alert"/);
});

test("a cookie runs out after 90 days, and a new password or a changed cookie does not count", async () => {
  const now = Date.UTC(2026, 10, 4);
  const cookie = await makeCookie(env, now);
  assert.ok(await validCookie(cookie, env, now + 89 * 86400e3));
  assert.ok(!(await validCookie(cookie, env, now + 91 * 86400e3)));
  assert.ok(!(await validCookie(cookie, { ...env, SITE_PASSWORD: "new" }, now)));
  const [expires, mac] = cookie.split(".");
  assert.ok(!(await validCookie(`${Number(expires) + 1e12}.${mac}`, env, now)));
  assert.ok(!(await validCookie(`${expires}.x${mac.slice(1)}`, env, now)));
  for (const bad of [null, "", "abc", ".", "1.2.3"]) assert.ok(!(await validCookie(bad, env, now)));
  assert.equal((await call("/app/", null, env, { headers: { Cookie: `rf_login=${cookie}` } }, now + 91 * 86400e3)).status, 401);
});

test("logging out forgets the cookie", async () => {
  const response = await call("/__logout");
  assert.equal(response.status, 303);
  assert.match(response.headers.get("Set-Cookie"), /^rf_login=; Path=\/; Max-Age=0;/);
});

test("the login only goes back to pages on this site", () => {
  assert.equal(safeNext("/app/?x=1"), "/app/?x=1");
  // A route link's "#…" part, added by login.js, survives the login.
  assert.equal(safeNext("/app/#/routes/add?r=eyJ2IjoxfQ"), "/app/#/routes/add?r=eyJ2IjoxfQ");
  for (const bad of ["https://evil.example/", "//evil.example/", "/\\evil.example", "/__login", "javascript:alert(1)", ""]) assert.equal(safeNext(bad), "/", bad);
  assert.equal(readCookie("a=1; rf_login=xyz", "rf_login"), "xyz");
  assert.equal(readCookie("xrf_login=1", "rf_login"), null);
});

test("a wrong user or password is refused", async () => {
  assert.equal((await call("/", basic("alex", "wrong"))).status, 401);
  assert.equal((await call("/", basic("someone", "s3cret pass"))).status, 401);
  assert.equal((await call("/", "Basic !!!")).status, 401);
  assert.equal((await call("/", "Bearer x")).status, 401);
});

test("the right user and password open the page, still marked noindex", async () => {
  const response = await call("/app/", basic("alex", "s3cret pass"));
  assert.equal(response.status, 200);
  assert.equal(await response.text(), "page");
  assert.equal(response.headers.get("X-Robots-Tag"), NO_ROBOTS);
  assert.equal(response.headers.get("Cache-Control"), "private, no-store");
});

test("only robots.txt and the home-screen icons open without a password", async () => {
  for (const path of ["/robots.txt", "/icon-180.png", "/icon-192.png", "/icon-512.png", "/apple-touch-icon.png", "/favicon.ico"]) {
    const response = await call(path);
    assert.equal(response.status, 200, path);
    assert.equal(response.headers.get("X-Robots-Tag"), NO_ROBOTS);
  }
  for (const path of ["/", "/app/", "/app/manifest.webmanifest", "/app/app.js", "/app/icon-192.png", "/icon-192.png/x", "/icon-192.png.html"]) {
    assert.equal((await call(path)).status, 401, path);
  }
});

test("without the secrets the site stays shut", async () => {
  assert.equal((await call("/", basic("alex", "s3cret pass"), {})).status, 503);
  assert.equal((await call("/", basic("", ""), { SITE_USER: "", SITE_PASSWORD: "" })).status, 503);
});

test("every answer carries the security headers, the login page and open files too", async () => {
  for (const response of [await call("/app/", basic("alex", "s3cret pass")), await call("/app/"), await call("/robots.txt")]) {
    const csp = response.headers.get(CSP_ENFORCED ? "Content-Security-Policy" : "Content-Security-Policy-Report-Only");
    assert.equal(csp, CSP);
    assert.match(csp, /script-src 'self';/, "scripts only from the site");
    assert.match(csp, /frame-ancestors 'none'/);
    assert.equal(response.headers.get("Permissions-Policy"), PERMISSIONS);
    assert.equal(response.headers.get("X-Content-Type-Options"), "nosniff");
    assert.equal(response.headers.get("Referrer-Policy"), "no-referrer");
    assert.equal(response.headers.get("Cross-Origin-Opener-Policy"), "same-origin");
    assert.match(response.headers.get("Strict-Transport-Security"), /^max-age=\d+$/);
  }
});
