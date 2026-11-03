// The forecast timer (cloudflare/timer): every half hour it asks GitHub to
// start "Publish forecasts" for the confirmed and used clubs.
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import worker from "../timer/src/index.js";
import { fakeCtx, fakeFetch } from "./fakes.mjs";

let github;
afterEach(() => github?.restore());

test("each run starts Publish forecasts on main for the confirmed clubs", async () => {
  github = fakeFetch(() => new Response(null, { status: 204 }));
  const ctx = fakeCtx();
  await worker.scheduled({}, { GITHUB_TOKEN: "gh-test" }, ctx);
  await ctx.done();
  assert.equal(github.length, 1);
  assert.equal(github[0].url, "https://api.github.com/repos/RowFrog/RowFrog/actions/workflows/publish-backend.yml/dispatches");
  assert.equal(github[0].method, "POST");
  assert.equal(github[0].headers.get("authorization"), "Bearer gh-test");
  assert.deepEqual(JSON.parse(github[0].body), { ref: "main", inputs: { clubs: "confirmed" } });
});

test("a refused start shows in the logs with GitHub's answer", async () => {
  github = fakeFetch(() => new Response("Resource not accessible", { status: 403 }));
  const ctx = fakeCtx();
  await worker.scheduled({}, { GITHUB_TOKEN: "gh-test" }, ctx);
  await assert.rejects(ctx.done(), /GitHub answered 403: Resource not accessible/);
});

test("it has no address of its own", async () => {
  github = fakeFetch();
  const response = await worker.fetch(new Request("https://example.org/"));
  assert.equal(response.status, 404);
  assert.equal(github.length, 0);
});
