// Runs in front of every page of the website (Cloudflare Pages Functions).
//
// While the site is in testing, only the owner gets in: every request needs
// the user name and password in the Pages secrets SITE_USER and SITE_PASSWORD
// (HTTP Basic Auth, set by .github/workflows/website.yml). Without them the
// site stays shut. robots.txt is served without a password, so well-behaved
// crawlers read that they are not welcome. So are the home-screen icons (owner
// OK 2026-11-04): Safari fetches them without the password, and "Add to Home
// Screen" then shows a plain letter. They are the app icon, already in the
// public repository. Only these exact file names open; everything else asks.
//
// Every answer, the password prompt included, tells search engines and AI
// crawlers not to index, follow, keep or train on anything.

export const NO_ROBOTS = "noindex, nofollow, noarchive, nosnippet, noimageindex, notranslate, noai, noimageai";

/** The only files served without the password. */
export const OPEN_FILES = new Set(["/robots.txt", "/icon-180.png", "/icon-192.png", "/icon-512.png", "/apple-touch-icon.png", "/favicon.ico"]);

export async function onRequest(context) {
  const { request, env } = context;
  const url = new URL(request.url);
  if (OPEN_FILES.has(url.pathname)) {
    return guarded(await context.next());
  }
  if (!env.SITE_USER || !env.SITE_PASSWORD) {
    return guarded(new Response("Closed.", { status: 503 }));
  }
  if (!(await allowed(request.headers.get("Authorization"), env.SITE_USER, env.SITE_PASSWORD))) {
    return guarded(
      new Response("Password needed.", {
        status: 401,
        headers: { "WWW-Authenticate": 'Basic realm="Row Frog (testing)", charset="UTF-8"' },
      }),
    );
  }
  return guarded(await context.next());
}

/** True when the Basic Auth header carries the right user and password. */
export async function allowed(header, user, password) {
  if (!header || !header.startsWith("Basic ")) return false;
  let given;
  try {
    given = new TextDecoder().decode(Uint8Array.from(atob(header.slice(6).trim()), (c) => c.charCodeAt(0)));
  } catch {
    return false;
  }
  const colon = given.indexOf(":");
  if (colon < 0) return false;
  const [a, b] = await Promise.all([digest(given), digest(`${user}:${password}`)]);
  // Comparing hashes takes the same time however much of the guess is right.
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

async function digest(text) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
}

function guarded(response) {
  const out = new Response(response.body, response);
  out.headers.set("X-Robots-Tag", NO_ROBOTS);
  out.headers.set("Cache-Control", "private, no-store");
  out.headers.set("Referrer-Policy", "no-referrer");
  out.headers.set("X-Content-Type-Options", "nosniff");
  out.headers.set("X-Frame-Options", "DENY");
  return out;
}
