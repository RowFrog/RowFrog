// Timer for the forecast run.
//
// Every half hour Cloudflare calls this Worker, which asks GitHub to start
// the "Publish forecasts" workflow for the confirmed and used clubs, the same
// run GitHub's own "*/30" timer starts. GitHub's timer stays as a backup: its
// runs skip themselves while the published files are fresh.
// Every 6 hours one of these runs is the run for all catalog clubs instead
// (it covers the used clubs too). It sits on the full hour after a 6-hourly
// model run is ready (04, 10, 16, 22 UTC), so the used clubs' own runs on the
// half hour, when a new model run comes, never wait behind it (owner, 6 Nov 2026).
//
// The GitHub key stays here (Worker secret GITHUB_TOKEN, a fine-grained token
// with Actions read and write on RowFrog/RowFrog only).

const REPO = "RowFrog/RowFrog";
const WORKFLOW = "publish-backend.yml";

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(start(env, clubsAt(new Date(event.scheduledTime))));
  },

  // No address of its own; a request gets nothing.
  async fetch() {
    return new Response("Not found", { status: 404 });
  },
};

// The full hours of the run for all clubs (UTC). Keep in step with ALL_HOURS
// in .github/workflows/publish-backend.yml (the backup timer).
const ALL_HOURS = [4, 10, 16, 22];

export function clubsAt(time) {
  return time.getUTCMinutes() < 15 && ALL_HOURS.includes(time.getUTCHours()) ? "all" : "confirmed";
}

async function start(env, clubs) {
  const response = await fetch(`https://api.github.com/repos/${REPO}/actions/workflows/${WORKFLOW}/dispatches`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.GITHUB_TOKEN}`,
      accept: "application/vnd.github+json",
      "user-agent": "rowfrog-timer",
      "x-github-api-version": "2022-11-28",
    },
    body: JSON.stringify({ ref: "main", inputs: { clubs } }),
  });
  // 204 = started. Anything else shows in the Worker's logs, and GitHub's timer covers the gap.
  if (response.status !== 204) {
    throw new Error(`GitHub answered ${response.status}: ${(await response.text()).slice(0, 300)}`);
  }
}
