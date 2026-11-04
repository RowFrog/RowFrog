// html`` escapes every value unless it is html`` or raw() markup (shared.js).
import { test } from "node:test";
import assert from "node:assert/strict";
import { html, raw } from "../public/app/shared.js";

test("values are escaped", () => {
  const name = `<img src=x onerror="alert(1)"> & 'Co'`;
  assert.equal(String(html`<strong>${name}</strong>`), "<strong>&lt;img src=x onerror=&quot;alert(1)&quot;&gt; &amp; &#39;Co&#39;</strong>");
  assert.equal(String(html`<a data-id="${'" onclick="x'}">`), '<a data-id="&quot; onclick=&quot;x">');
});

test("nested markup, raw markup and lists stay as they are", () => {
  const rows = ["A<", "B"].map((x) => html`<li>${x}</li>`);
  assert.equal(String(html`<ul>${rows}</ul>`), "<ul><li>A&lt;</li><li>B</li></ul>");
  assert.equal(String(html`${raw("<svg></svg>")} ${"<svg>"}`), "<svg></svg> &lt;svg&gt;");
});

test("nothing for null, undefined and false; numbers as text", () => {
  assert.equal(String(html`[${null}${undefined}${false}${0}${3}]`), "[03]");
  assert.equal(`${html`<b>${"x"}</b>`}`, "<b>x</b>", "works where a string does");
});
