// Caching proxy for CelesTrak GP data.
//
// CelesTrak answers each query only once per IP per update window (~2 h) and returns 403 with a text
// note otherwise, so every phone behind a shared IP competes for one quota. This Worker downloads each
// group on a cron, keeps the last good copy in KV and serves that to every client.

const GROUPS = ["stations", "visual", "starlink", "active"];
const MIN_REFRESH_MS = 110 * 60 * 1000; // CelesTrak updates about every 2 h; never ask more often.
const MIN_BYTES = 100; // Smaller than any real group; catches "[]" and short error bodies.

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const match = url.pathname.match(/^\/gp\/([a-z]+)\.json$/);
    if (request.method !== "GET" && request.method !== "HEAD") {
      return text("Method not allowed", 405);
    }
    if (!match || !GROUPS.includes(match[1])) {
      return text(`Not found. Try /gp/{${GROUPS.join(",")}}.json`, 404);
    }
    const group = match[1];

    let stored = await env.GP.getWithMetadata(key(group), { type: "text", cacheTtl: 300 });
    if (stored.value === null) {
      // Nothing cached yet (fresh deploy, before the first cron run): try once now.
      await refresh(env, group);
      stored = await env.GP.getWithMetadata(key(group), "text");
    }
    if (stored.value === null) {
      return text("Satellite data is not available yet. Try again in a few minutes.", 503, { "Retry-After": "600" });
    }

    const fetchedAt = stored.metadata?.fetchedAt ?? 0;
    return new Response(request.method === "HEAD" ? null : stored.value, {
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "public, max-age=600",
        "Last-Modified": new Date(fetchedAt).toUTCString(),
        "X-Fetched-At": new Date(fetchedAt).toISOString(),
        "Access-Control-Allow-Origin": "*",
      },
    });
  },

  async scheduled(controller, env, ctx) {
    for (const group of GROUPS) {
      const result = await refresh(env, group);
      console.log(`${group}: ${result}`);
    }
  },
};

/// Downloads one group from CelesTrak and stores it if it is a JSON array. Keeps the old copy on any failure.
async function refresh(env, group) {
  const current = await env.GP.getWithMetadata(key(group), "text");
  const fetchedAt = current.metadata?.fetchedAt ?? 0;
  if (current.value !== null && Date.now() - fetchedAt < MIN_REFRESH_MS) return "fresh, skipped";

  let body;
  try {
    const response = await fetch(`https://celestrak.org/NORAD/elements/gp.php?GROUP=${group}&FORMAT=json`, {
      headers: { "User-Agent": "skyglass-proxy (+https://github.com/LoganMHawkins/sky-glass)" },
    });
    if (response.status !== 200) return `HTTP ${response.status}, kept old copy`;
    body = await response.text();
  } catch (error) {
    return `fetch failed (${error}), kept old copy`;
  }
  if (!looksLikeGP(body)) return `not a GP JSON array (${body.slice(0, 80)}), kept old copy`;

  await env.GP.put(key(group), body, { metadata: { fetchedAt: Date.now() } });
  return `stored ${body.length} bytes`;
}

/// A structural check instead of JSON.parse: the active catalogue is several MB, and parsing it would
/// blow the free plan's CPU limit. CelesTrak's refusals are plain text, so this is enough to tell them apart.
function looksLikeGP(body) {
  const trimmed = body.trim();
  return trimmed.length >= MIN_BYTES && trimmed.startsWith("[") && trimmed.endsWith("]") &&
    trimmed.includes('"NORAD_CAT_ID"');
}

function key(group) {
  return `gp:${group}`;
}

function text(message, status, headers = {}) {
  return new Response(message, { status, headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store", ...headers } });
}
