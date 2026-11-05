// Place suggestions for the shared club list.
//
// When a user adds their own place in the app and turns on "Suggest it for
// everyone's list", the app posts it here. The Worker opens a GitHub issue
// in RowFrog/RowFrog with the label "place suggestion", so the user needs no
// GitHub account. The GitHub key stays here (Worker secret GITHUB_TOKEN, a
// fine-grained token with Issues read and write on that repository only).
// Nothing about the sender is stored or passed on.
//
// A launch point suggestion (kind "launchPoint") is the point a user moved a
// club's map to, for a club whose launch point the club has not confirmed. It
// gets its own label; the owner answers "/accept" on the issue and the
// "Accept launch point" workflow puts it into data/catalogs/hand-checked.json.
//
//   POST /v1/suggestions  {"name", "kind", "lat", "lon", "water"?, "website"?, "country"?}
//   POST /v1/suggestions  {"name", "kind": "launchPoint", "club", "lat", "lon"}

const REPO = "RowFrog/RowFrog";
const LABEL = "place suggestion";
const LAUNCH_LABEL = "launch point suggestion";
const KINDS = ["club", "boathouse", "water", "launchPoint"];

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return json({ error: "POST a place" }, 405);
    const address = request.headers.get("cf-connecting-ip") || "unknown";
    if (env.LIMITER) {
      const { success } = await env.LIMITER.limit({ key: address });
      if (!success) return json({ error: "too many suggestions, try again in a minute" }, 429);
    }
    let place;
    try {
      place = check(await request.json());
    } catch (error) {
      return json({ error: error.message || "JSON body needed" }, 400);
    }
    const response = await fetch(`https://api.github.com/repos/${REPO}/issues`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${env.GITHUB_TOKEN}`,
        accept: "application/vnd.github+json",
        "user-agent": "rowfrog-suggestions",
        "x-github-api-version": "2022-11-28",
      },
      body: JSON.stringify(place.kind === "launchPoint"
        ? { title: `Launch point suggestion: ${place.name}`, body: launchPointBody(place), labels: [LAUNCH_LABEL] }
        : { title: `Place suggestion: ${place.name}`, body: issueBody(place), labels: [LABEL] }),
    });
    if (!response.ok) return json({ error: "could not file the suggestion" }, 502);
    return json({ ok: true }, 201);
  },
};

// Plain one-line text: no line breaks, backticks or angle brackets, so it
// cannot break out of the code spans it is shown in (and @names do not ping).
function text(value, max) {
  if (value == null || value === "") return null;
  if (typeof value !== "string") throw new Error("text fields must be strings");
  const clean = value.replace(/[\u0000-\u001f\u007f`<>]/g, " ").replace(/\s+/g, " ").trim();
  if (clean.length > max) throw new Error("text too long");
  return clean || null;
}

function check(body) {
  if (!body || typeof body !== "object") throw new Error("JSON object needed");
  const name = text(body.name, 80);
  if (!name) throw new Error("name needed");
  if (!KINDS.includes(body.kind)) throw new Error("kind must be club, boathouse, water or launchPoint");
  const lat = Number(body.lat);
  const lon = Number(body.lon);
  if (!(Math.abs(lat) <= 90 && Math.abs(lon) <= 180)) throw new Error("lat and lon needed");
  if (body.kind === "launchPoint") {
    // The club's id from the list, as the accept workflow looks it up.
    if (typeof body.club !== "string" || !/^[a-z0-9][a-z0-9-]{0,99}$/.test(body.club)) throw new Error("club id needed");
    return { name, kind: body.kind, club: body.club, lat, lon };
  }
  const website = text(body.website, 200);
  if (website && !/^https?:\/\/[^\s]+$/.test(website)) throw new Error("website must start with http");
  const country = text(body.country, 2);
  return {
    name,
    kind: body.kind,
    lat,
    lon,
    water: text(body.water, 80),
    website,
    country: country && /^[a-z]{2}$/.test(country) ? country : null,
  };
}

function issueBody(p) {
  const position = `${p.lat.toFixed(5)}, ${p.lon.toFixed(5)}`;
  return [
    "Suggested from the app for the shared club list.",
    "",
    `- Name: \`${p.name}\``,
    `- Kind: ${p.kind}`,
    `- Position: ${position} ([map](https://www.openstreetmap.org/?mlat=${p.lat.toFixed(5)}&mlon=${p.lon.toFixed(5)}#map=17/${p.lat.toFixed(5)}/${p.lon.toFixed(5)}))`,
    `- Water: ${p.water ? `\`${p.water}\`` : "not known"}`,
    `- Website: ${p.website ? `\`${p.website}\`` : "none"}`,
    `- Country: ${p.country || "not known"}`,
  ].join("\n");
}

// The lines "- Club id:" and "- Launch point:" are read by
// scripts/accept_launch_point.py; keep them in step.
function launchPointBody(p) {
  const lat = p.lat.toFixed(6), lon = p.lon.toFixed(6);
  return [
    "Suggested from the app: where this club's boats go on the water.",
    "",
    `- Club: \`${p.name}\``,
    `- Club id: \`${p.club}\``,
    `- Launch point: ${lat}, ${lon} ([map](https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}#map=18/${lat}/${lon}))`,
    "",
    "Answer `/accept` to put it into the hand-checked list (the workflow opens a pull request).",
  ].join("\n");
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}
