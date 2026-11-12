"""The contract for the published files: one JSON Schema per file in
testdata/schema/v1, checked against the sample files in testdata/api/v1.

Installed apps keep reading /v1 for weeks after a change (a phone build lives
7 days, App Store users update late), so a field they read must not go away or
change its type. The rule:

- Adding a field is fine: add it to the schema too.
- Removing a field, renaming it or changing its type breaks installed apps.
  The fields every installed app may rely on are frozen in
  testdata/schema/v1/frozen.json; this test fails when one of them leaves a
  schema or changes type. Such a change needs a new /v2 path, published next to
  /v1 until the old apps are gone, not an edit of frozen.json.

The samples hold one club, so a field that real files carry only sometimes may
be missing from a schema. To check real files, point the test at a folder of
them: `RW_SCHEMA_FILES=~/out/v1 pytest tests/test_schema.py` (the folder holds
lakes/index, clubs/<id>/forecast, ...). Fields found there that no schema
names are printed (run with -s), so the schema can be completed.

The schemas were built on 2026-11-12 from the sample files and all 615 files
the publish run wrote then (every club, also the ones nobody uses, which carry
less). A field is required when every file had it, and may be null when one had
null. Numbers are "number" even where every value was whole, as the app reads
them as Double (Models.swift); only hour indexes, counts and weather codes are
"integer".

The website runs the same check (web/tests/schema.test.mjs). The checker below
knows only the schema keywords the files use, and refuses others, so a schema
can't ask for a check that silently doesn't run.
"""

import json
import os
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "testdata" / "schema" / "v1"
SAMPLES = ROOT / "testdata" / "api" / "v1"
KNOWN = {"$schema", "title", "description", "type", "properties", "required", "items", "enum"}
TYPES = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    "boolean": lambda v: isinstance(v, bool),
    "null": lambda v: v is None,
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
}


def problems(schema: dict, value, path: str = "$") -> list[str]:
    """What in `value` doesn't fit `schema`, one line each (empty: it fits)."""
    unknown = {k for k in schema if not k.startswith("x-")} - KNOWN
    assert not unknown, f"{path}: the checker doesn't know {sorted(unknown)}"
    found = []
    if "type" in schema:
        types = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        if not any(TYPES[t](value) for t in types):
            return [f"{path}: {type(value).__name__} where the schema says {'/'.join(types)}"]
    if "enum" in schema and value not in schema["enum"]:
        found.append(f"{path}: {value!r} is not one of {schema['enum']}")
    if isinstance(value, dict):
        found += [f"{path}.{k}: missing" for k in schema.get("required", []) if k not in value]
        for k, sub in schema.get("properties", {}).items():
            if k in value:
                found += problems(sub, value[k], f"{path}.{k}")
    if isinstance(value, list) and "items" in schema:
        for i, item in enumerate(value):
            found += problems(schema["items"], item, f"{path}[{i}]")
    return found


def required_fields(schema: dict, path: str = "$") -> dict[str, list[str]]:
    """Every field the schema requires, by path, with its types."""
    out = {}
    for k in schema.get("required", []):
        sub = schema["properties"][k]
        t = sub.get("type", [])
        out[f"{path}.{k}"] = sorted(t if isinstance(t, list) else [t])
        out.update(required_fields(sub, f"{path}.{k}"))
    if "items" in schema:
        out.update(required_fields(schema["items"], f"{path}[]"))
    return out


SCHEMA_FILES = sorted(SCHEMAS.glob("*.schema.json"))


@pytest.mark.parametrize("schema_file", SCHEMA_FILES, ids=lambda p: p.name)
def test_sample_fits_schema(schema_file):
    schema = json.loads(schema_file.read_text())
    sample = json.loads((SAMPLES / schema["x-sample"]).read_text())
    assert problems(schema, sample) == []


def test_every_sample_has_a_schema():
    covered = {json.loads(f.read_text())["x-sample"] for f in SCHEMA_FILES}
    samples = {str(p.relative_to(SAMPLES)) for p in SAMPLES.rglob("*") if p.is_file()}
    assert samples - covered == set(), "a sample file without a schema in testdata/schema/v1"


def test_frozen_fields_stay():
    frozen = json.loads((SCHEMAS / "frozen.json").read_text())["files"]
    assert set(frozen) == {f.name for f in SCHEMA_FILES}, "frozen.json lists every schema"
    for name, fields in frozen.items():
        now = required_fields(json.loads((SCHEMAS / name).read_text()))
        for path, types in fields.items():
            assert path in now, f"{name}: {path} was removed; installed apps read it (see this file's docstring)"
            assert now[path] == types, f"{name}: {path} is now {now[path]}, installed apps expect {types}"


def unnamed(schema: dict, value, path: str = "$") -> set[str]:
    """Fields in `value` the schema doesn't name (array positions as [])."""
    out = set()
    if isinstance(value, dict) and "properties" in schema:
        for k, v in value.items():
            if k in schema["properties"]:
                out |= unnamed(schema["properties"][k], v, f"{path}.{k}")
            else:
                out.add(f"{path}.{k}")
    if isinstance(value, list) and "items" in schema:
        for item in value:
            out |= unnamed(schema["items"], item, f"{path}[]")
    return out


@pytest.mark.skipif(not os.environ.get("RW_SCHEMA_FILES"), reason="set RW_SCHEMA_FILES to a folder of real /v1 files")
def test_real_files_fit_schema():
    folder = Path(os.environ["RW_SCHEMA_FILES"]).expanduser()
    checked, found, extra = 0, [], set()
    for schema_file in SCHEMA_FILES:
        schema = json.loads(schema_file.read_text())
        pattern = schema["title"].removeprefix("/v1/").replace("{code}", "*").replace("{id}", "*")
        for f in sorted(folder.glob(pattern)):
            value = json.loads(f.read_text())
            found += [f"{f.relative_to(folder)} {p}" for p in problems(schema, value)]
            extra |= {f"{schema_file.name} {p}" for p in unnamed(schema, value)}
            checked += 1
    print(f"{checked} files checked; fields no schema names:", *sorted(extra), sep="\n  ")
    assert checked, f"no /v1 files found in {folder}"
    assert found == []


def test_checker_finds_problems():
    schema = {"type": "object", "required": ["a"], "properties": {"a": {"type": "integer"}, "b": {"type": ["string", "null"]}}}
    assert problems(schema, {"a": 1, "b": None}) == []
    assert problems(schema, {"b": "x"}) == ["$.a: missing"]
    assert problems(schema, {"a": 1.5}) == ["$.a: float where the schema says integer"]
    assert problems(schema, {"a": True}) == ["$.a: bool where the schema says integer"]
    assert unnamed(schema, {"a": 1, "c": 2}) == {"$.c"}
    with pytest.raises(AssertionError):
        problems({"minimum": 3}, 1)
