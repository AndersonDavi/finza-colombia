// Lets Finza ask Gemini without each person creating a key: the key lives
// here as a secret (GEMINI_API_KEY) and never ships inside the app. Only
// the two Gemini calls the app makes are forwarded, only to "flash"
// models, and each address gets a few requests a minute.

const GEMINI = "https://generativelanguage.googleapis.com";
const MAX_BODY = 6 * 1024 * 1024; // receipts are resized in the app first

function cors(origin) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

function reply(status, body, origin) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...cors(origin) },
  });
}

// Same shape as Gemini's errors, so the app shows its usual messages
function geminiError(status, statusText, message, origin) {
  return reply(status, { error: { code: status, status: statusText, message } }, origin);
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin");
    const allowed = (env.ALLOWED_ORIGINS || "").split(",").map((o) => o.trim());
    // Browsers send an origin; the Android app sends none
    if (origin && !allowed.includes(origin)) {
      return geminiError(403, "PERMISSION_DENIED", "Origin not allowed", null);
    }
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors(origin) });
    }
    if (!env.GEMINI_API_KEY) {
      return geminiError(503, "UNAVAILABLE", "The free assistant is not set up yet", origin);
    }

    const url = new URL(request.url);
    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    if (env.LIMITER) {
      const { success } = await env.LIMITER.limit({ key: ip });
      if (!success) {
        return geminiError(429, "RESOURCE_EXHAUSTED", "Too many requests, wait a minute", origin);
      }
    }

    // The model list, filtered to the cheap fast ones
    if (request.method === "GET" && url.pathname === "/v1beta/models") {
      const upstream = await fetch(GEMINI + "/v1beta/models", {
        headers: { "x-goog-api-key": env.GEMINI_API_KEY },
      });
      const body = await upstream.json();
      if (!upstream.ok) return reply(upstream.status, body, origin);
      body.models = (body.models || []).filter((m) => String(m.name).includes("flash"));
      return reply(200, body, origin);
    }

    const match = url.pathname.match(/^\/v1beta\/(models\/[a-z0-9.\-]+):generateContent$/);
    if (request.method === "POST" && match) {
      if (!match[1].includes("flash")) {
        return geminiError(400, "INVALID_ARGUMENT", "Only flash models are available", origin);
      }
      const length = Number(request.headers.get("Content-Length") || 0);
      if (length > MAX_BODY) {
        return geminiError(413, "INVALID_ARGUMENT", "The request is too large", origin);
      }
      const upstream = await fetch(GEMINI + "/v1beta/" + match[1] + ":generateContent", {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
        body: request.body,
      });
      return new Response(upstream.body, {
        status: upstream.status,
        headers: { "Content-Type": "application/json", ...cors(origin) },
      });
    }

    return geminiError(404, "NOT_FOUND", "Not found", origin);
  },
};
