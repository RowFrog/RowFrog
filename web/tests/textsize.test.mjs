import { test } from "node:test";
import assert from "node:assert/strict";
import { textScale, RANGE } from "../public/app/textsize.js";

test("the text scale follows the reader's body size, 17 px standard, within 85–120 % (owner's pick, 16 Nov 2026)", () => {
  assert.equal(textScale(17), 1);
  assert.equal(textScale(16), 16 / 17, "one step smaller (Medium)");
  assert.equal(textScale(19), 19 / 17, "one step larger");
  assert.equal(textScale(14), RANGE[0], "the smallest sizes stop at 85 %");
  assert.equal(textScale(28), RANGE[1], "the accessibility sizes stop at 120 %");
  assert.equal(textScale(null), 1, "no setting known: unchanged");
  assert.equal(textScale(NaN), 1);
});
