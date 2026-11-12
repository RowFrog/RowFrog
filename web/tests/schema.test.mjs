// The contract for the published /v1 files (testdata/schema/v1), the same check
// as backend/tests/test_schema.py, whose docstring has the rule: a field may be
// added; removing a frozen field or changing its type needs a /v2 path, so
// installed apps and open browser tabs keep working.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";

const dir = new URL("../../testdata/schema/v1/", import.meta.url);
const read = (url) => JSON.parse(readFileSync(url));
const schemaNames = readdirSync(dir).filter((n) => n.endsWith(".schema.json")).sort();
const KNOWN = new Set(["$schema", "title", "description", "type", "properties", "required", "items", "enum"]);
const TYPES = {
  object: (v) => v !== null && typeof v === "object" && !Array.isArray(v),
  array: Array.isArray,
  string: (v) => typeof v === "string",
  boolean: (v) => typeof v === "boolean",
  null: (v) => v === null,
  integer: Number.isInteger,
  number: (v) => typeof v === "number",
};

// What in `value` doesn't fit `schema`, one line each (empty: it fits).
// JSON.parse reads 3.0 as 3, so "integer" can't tell 3.0 from 3 here; the
// backend's check can.
function problems(schema, value, path = "$") {
  const unknown = Object.keys(schema).filter((k) => !k.startsWith("x-") && !KNOWN.has(k));
  assert.deepEqual(unknown, [], `${path}: the checker doesn't know ${unknown}`);
  if (schema.type) {
    const types = [schema.type].flat();
    if (!types.some((t) => TYPES[t](value))) return [`${path}: ${typeof value} where the schema says ${types.join("/")}`];
  }
  const found = [];
  if (schema.enum && !schema.enum.includes(value)) found.push(`${path}: ${value} is not one of ${schema.enum}`);
  if (TYPES.object(value)) {
    for (const k of schema.required ?? []) if (!(k in value)) found.push(`${path}.${k}: missing`);
    for (const [k, sub] of Object.entries(schema.properties ?? {})) if (k in value) found.push(...problems(sub, value[k], `${path}.${k}`));
  }
  if (Array.isArray(value) && schema.items) value.forEach((item, i) => found.push(...problems(schema.items, item, `${path}[${i}]`)));
  return found;
}

function requiredFields(schema, path = "$", out = {}) {
  for (const k of schema.required ?? []) {
    out[`${path}.${k}`] = [schema.properties[k].type ?? []].flat().sort();
    requiredFields(schema.properties[k], `${path}.${k}`, out);
  }
  if (schema.items) requiredFields(schema.items, `${path}[]`, out);
  return out;
}

for (const name of schemaNames) {
  test(`the sample fits ${name}`, () => {
    const schema = read(new URL(name, dir));
    const sample = read(new URL(`../../api/v1/${schema["x-sample"]}`, dir));
    assert.deepEqual(problems(schema, sample), []);
  });
}

test("the frozen /v1 fields are still in the schemas, with the same types", () => {
  const frozen = read(new URL("frozen.json", dir)).files;
  assert.deepEqual(Object.keys(frozen).sort(), schemaNames);
  for (const [name, fields] of Object.entries(frozen)) {
    const now = requiredFields(read(new URL(name, dir)));
    for (const [path, types] of Object.entries(fields)) {
      assert.ok(path in now, `${name}: ${path} was removed; installed apps read it`);
      assert.deepEqual(now[path], types, `${name}: ${path} changed type`);
    }
  }
});

test("the checker finds problems", () => {
  const schema = { type: "object", required: ["a"], properties: { a: { type: "integer" }, b: { type: ["string", "null"] } } };
  assert.deepEqual(problems(schema, { a: 1, b: null }), []);
  assert.deepEqual(problems(schema, { b: "x" }), ["$.a: missing"]);
  assert.deepEqual(problems(schema, { a: 1.5 }), ["$.a: number where the schema says integer"]);
  assert.throws(() => problems({ minimum: 3 }, 1));
});
