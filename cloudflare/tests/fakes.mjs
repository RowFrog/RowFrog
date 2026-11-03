// Stand-ins for what Cloudflare gives a Worker, so the Workers run under
// `node --test` without wrangler or an account: a D1 database on Node's own
// SQLite with the real schema, a ctx that collects waitUntil promises, and a
// fetch that records each call.
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";

export class FakeD1 {
  constructor(schemaPath) {
    this.db = new DatabaseSync(":memory:");
    if (schemaPath) this.db.exec(readFileSync(schemaPath, "utf8"));
  }
  prepare(sql) {
    return new FakeStatement(this.db, sql);
  }
  async batch(statements) {
    const out = [];
    for (const s of statements) out.push(await s.run());
    return out;
  }
  rows(sql, ...args) {
    return this.db.prepare(sql).all(...args).map((r) => ({ ...r }));
  }
}

class FakeStatement {
  constructor(db, sql) {
    this.db = db;
    this.sql = sql;
    this.args = [];
  }
  bind(...args) {
    this.args = args;
    return this;
  }
  async run() {
    this.db.prepare(this.sql).run(...this.args);
    return { success: true };
  }
  async all() {
    return { results: this.db.prepare(this.sql).all(...this.args).map((r) => ({ ...r })) };
  }
}

export function fakeCtx() {
  const pending = [];
  return { waitUntil: (p) => pending.push(p), done: () => Promise.all(pending) };
}

/** Replaces the global fetch; `answer(request)` gives the Response. Returns the calls. */
export function fakeFetch(answer = () => new Response("ok")) {
  const calls = [];
  const original = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    const request = input instanceof Request ? input : new Request(input, init);
    calls.push({ url: request.url, method: request.method, headers: request.headers, body: init?.body ?? null });
    return answer(request);
  };
  calls.restore = () => (globalThis.fetch = original);
  return calls;
}
