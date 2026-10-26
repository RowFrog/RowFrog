import { test } from "node:test";
import assert from "node:assert/strict";
import { onRequest, NO_ROBOTS } from "../functions/_middleware.js";

const env = { SITE_USER: "alex", SITE_PASSWORD: "s3cret pass" };

function call(path, authorization, environment = env) {
  const headers = authorization ? { Authorization: authorization } : {};
  return onRequest({
    request: new Request(`https://rowfrog.com${path}`, { headers }),
    env: environment,
    next: async () => new Response("page", { headers: { "Content-Type": "text/html" } }),
  });
}

const basic = (user, password) => `Basic ${btoa(`${user}:${password}`)}`;

test("without a password the page asks for one, and robots are told to stay away", async () => {
  const response = await call("/app/");
  assert.equal(response.status, 401);
  assert.match(response.headers.get("WWW-Authenticate"), /^Basic /);
  assert.equal(response.headers.get("X-Robots-Tag"), NO_ROBOTS);
  assert.notEqual(await response.text(), "page");
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

test("robots.txt is the only file without a password", async () => {
  const response = await call("/robots.txt");
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("X-Robots-Tag"), NO_ROBOTS);
});

test("without the secrets the site stays shut", async () => {
  assert.equal((await call("/", basic("alex", "s3cret pass"), {})).status, 503);
  assert.equal((await call("/", basic("", ""), { SITE_USER: "", SITE_PASSWORD: "" })).status, 503);
});
