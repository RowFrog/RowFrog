// Place suggestions (cloudflare/suggestions): checks a place from the app and
// files it as a GitHub issue, with nothing about the sender.
import assert from "node:assert/strict";
import { afterEach, beforeEach, test } from "node:test";
import worker from "../suggestions/src/index.js";
import { fakeFetch } from "./fakes.mjs";

let github, env;
const place = { name: "Ruderclub Musterstadt", kind: "club", lat: 47.9, lon: 11.3, water: "Starnberger See", website: "https://example.org", country: "de" };

beforeEach(() => {
  github = fakeFetch(() => new Response("{}", { status: 201 }));
  env = { GITHUB_TOKEN: "gh-test", LIMITER: { limit: async () => ({ success: true }) } };
});
afterEach(() => github.restore());

const post = (body, method = "POST") =>
  worker.fetch(new Request("https://api.rowfrog.com/v1/suggestions", {
    method, headers: { "cf-connecting-ip": "192.0.2.1" }, body: method === "POST" ? (typeof body === "string" ? body : JSON.stringify(body)) : undefined,
  }), env);

test("a place becomes an issue with the label, a map link and no sender details", async () => {
  const response = await post(place);
  assert.equal(response.status, 201);
  assert.equal(github.length, 1);
  const call = github[0];
  assert.equal(call.url, "https://api.github.com/repos/RowFrog/RowFrog/issues");
  assert.equal(call.method, "POST");
  assert.equal(call.headers.get("authorization"), "Bearer gh-test");
  const issue = JSON.parse(call.body);
  assert.equal(issue.title, "Place suggestion: Ruderclub Musterstadt");
  assert.deepEqual(issue.labels, ["place suggestion"]);
  assert.match(issue.body, /- Name: `Ruderclub Musterstadt`/);
  assert.match(issue.body, /- Position: 47\.90000, 11\.30000 \(\[map\]\(https:\/\/www\.openstreetmap\.org\/\?mlat=47\.90000&mlon=11\.30000#map=17\/47\.90000\/11\.30000\)\)/);
  assert.match(issue.body, /- Water: `Starnberger See`/);
  assert.match(issue.body, /- Country: de/);
  assert.doesNotMatch(call.body, /192\.0\.2\.1/);
});

test("text cannot break out of its code span or the line", async () => {
  await post({ ...place, name: "Club `x`\n<b>@someone</b>", water: "", website: null, country: "DE" });
  const issue = JSON.parse(github[0].body);
  assert.equal(issue.title, "Place suggestion: Club x b @someone /b");
  assert.match(issue.body, /- Name: `Club x b @someone \/b`\n/);
  assert.match(issue.body, /- Water: not known/);
  assert.match(issue.body, /- Website: none/);
  assert.match(issue.body, /- Country: not known/);
});

test("a launch point becomes an issue with its own label, the club id and the point", async () => {
  const response = await post({ name: "Ruderclub Musterstadt", kind: "launchPoint", club: "ruderclub-musterstadt", lat: 47.9123456, lon: 11.3 });
  assert.equal(response.status, 201);
  const issue = JSON.parse(github[0].body);
  assert.equal(issue.title, "Launch point suggestion: Ruderclub Musterstadt");
  assert.deepEqual(issue.labels, ["launch point suggestion"]);
  assert.match(issue.body, /- Club id: `ruderclub-musterstadt`\n/);
  assert.match(issue.body, /- Launch point: 47\.912346, 11\.300000 \(\[map\]/);
  assert.match(issue.body, /\/accept/);
  assert.doesNotMatch(github[0].body, /192\.0\.2\.1/);
});

test("a launch point needs a club id from the list", async () => {
  const launch = { name: "Ruderclub Musterstadt", kind: "launchPoint", club: "ruderclub-musterstadt", lat: 47.9, lon: 11.3 };
  for (const club of [undefined, "", "Club X", "../x", "x`y", "-x", "x".repeat(101)]) {
    assert.equal((await post({ ...launch, club })).status, 400, String(club));
  }
  assert.equal(github.length, 0);
});

test("a place that does not check out is turned away before GitHub", async () => {
  const bad = [
    "not json",
    "null",
    { ...place, name: "" },
    { ...place, name: 42 },
    { ...place, name: "x".repeat(81) },
    { ...place, kind: "pub" },
    { ...place, lat: 91 },
    { ...place, lon: "east" },
    { ...place, website: "javascript:alert(1)" },
    { ...place, country: "Germany" },
  ];
  for (const body of bad) {
    assert.equal((await post(body)).status, 400, JSON.stringify(body));
  }
  assert.equal(github.length, 0);
});

test("only POST, at most as often as the limiter allows", async () => {
  assert.equal((await post(null, "GET")).status, 405);
  env.LIMITER = { limit: async ({ key }) => ({ success: key !== "192.0.2.1" }) };
  assert.equal((await post(place)).status, 429);
  assert.equal(github.length, 0);
});

test("a GitHub failure is reported as such", async () => {
  github.restore();
  github = fakeFetch(() => new Response("bad credentials", { status: 401 }));
  const response = await post(place);
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { error: "could not file the suggestion" });
});
