// Timer for the forecast run.
//
// Every half hour Cloudflare calls this Worker, which asks GitHub to start
// the "Publish forecasts" workflow for the confirmed and used clubs, the same
// run GitHub's own "*/30" timer starts. GitHub's timer stays as a backup: its
// runs skip themselves while the published files are fresh. The run for all
// catalog clubs every 6 hours stays on GitHub's timer.
//
// The GitHub key stays here (Worker secret GITHUB_TOKEN, a fine-grained token
// with Actions read and write on RowFrog/RowFrog only).

const REPO = "RowFrog/RowFrog";
const WORKFLOW = "publish-backend.yml";

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(start(env));
  },

  // No address of its own; a request gets nothing.
  async fetch() {
    return new Response("Not found", { status: 404 });
  },
};

async function start(env) {
  const response = await fetch(`https://api.github.com/repos/${REPO}/actions/workflows/${WORKFLOW}/dispatches`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.GITHUB_TOKEN}`,
      accept: "application/vnd.github+json",
      "user-agent": "rowfrog-timer",
      "x-github-api-version": "2022-11-28",
    },
    body: JSON.stringify({ ref: "main", inputs: { clubs: "confirmed" } }),
  });
  // 204 = started. Anything else shows in the Worker's logs, and GitHub's timer covers the gap.
  if (response.status !== 204) {
    throw new Error(`GitHub answered ${response.status}: ${(await response.text()).slice(0, 300)}`);
  }
}
