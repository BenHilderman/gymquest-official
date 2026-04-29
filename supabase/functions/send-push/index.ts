// Edge Function: send-push
// Trigger: AFTER INSERT on public.notifications -> POST { notification_id } here.
// Resolves user's device tokens and dispatches APNs alerts.
//
// Required env vars (set in Supabase dashboard -> Edge Functions -> send-push -> Secrets):
//   APNS_KEY_ID       10-char Key ID from Apple Developer
//   APNS_TEAM_ID      10-char Apple Developer Team ID
//   APNS_BUNDLE_ID    e.g. com.gymquest.app  (used as apns-topic if device row has no bundle_id)
//   APNS_KEY_P8       full contents of AuthKey_XXXXXXXXXX.p8 (including BEGIN/END lines)
//   APNS_HOST         (optional) "api.sandbox.push.apple.com" (dev, default) or "api.push.apple.com" (prod)
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically by the runtime.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID");
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID");
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID");
const APNS_KEY_P8 = Deno.env.get("APNS_KEY_P8");
const APNS_HOST = Deno.env.get("APNS_HOST") ?? "api.sandbox.push.apple.com";

interface NotificationRow {
  id: string;
  user_id: string;
  category: string;
  title: string | null;
  body: string | null;
  payload: Record<string, unknown> | null;
  deep_link: string | null;
}

interface DeviceTokenRow {
  token: string;
  platform: string;
  bundle_id: string | null;
}

let cachedSigningKey: CryptoKey | null = null;
let cachedJwt: { token: string; expiresAt: number } | null = null;

function base64UrlEncode(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function utf8(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}

async function importP8(pem: string): Promise<CryptoKey> {
  if (cachedSigningKey) return cachedSigningKey;
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(cleaned), (c) => c.charCodeAt(0));
  cachedSigningKey = await crypto.subtle.importKey(
    "pkcs8",
    der.buffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  return cachedSigningKey;
}

// APNs JWTs are valid up to 60 min; rotate every 50 min.
async function getApnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && cachedJwt.expiresAt > now + 300) return cachedJwt.token;

  const headerB64 = base64UrlEncode(utf8(JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID })));
  const claimsB64 = base64UrlEncode(utf8(JSON.stringify({ iss: APNS_TEAM_ID, iat: now })));
  const message = `${headerB64}.${claimsB64}`;

  const key = await importP8(APNS_KEY_P8!);
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    utf8(message),
  );

  const token = `${message}.${base64UrlEncode(new Uint8Array(sig))}`;
  cachedJwt = { token, expiresAt: now + 3000 };
  return token;
}

async function dispatchOne(
  jwt: string,
  topic: string,
  device: DeviceTokenRow,
  notif: NotificationRow,
): Promise<{ token: string; status: number; reason?: string }> {
  const aps = {
    alert: { title: notif.title ?? "", body: notif.body ?? "" },
    sound: "default",
    "thread-id": notif.category,
    "mutable-content": 1,
  };
  const payload = {
    aps,
    notification_id: notif.id,
    category: notif.category,
    deep_link: notif.deep_link,
    ...(notif.payload ?? {}),
  };

  const r = await fetch(`https://${APNS_HOST}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": device.bundle_id ?? topic,
      "apns-push-type": "alert",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (r.status >= 400) {
    const body = await r.text();
    let reason: string | undefined;
    try {
      reason = JSON.parse(body)?.reason;
    } catch { /* ignore */ }
    return { token: device.token, status: r.status, reason };
  }
  return { token: device.token, status: r.status };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  if (!APNS_KEY_ID || !APNS_TEAM_ID || !APNS_BUNDLE_ID || !APNS_KEY_P8) {
    return new Response(
      JSON.stringify({
        error: "APNs env vars not configured. Set APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_KEY_P8 in function secrets.",
      }),
      { status: 503, headers: { "content-type": "application/json" } },
    );
  }

  let body: { notification_id?: string };
  try {
    body = await req.json();
  } catch {
    return new Response("invalid json", { status: 400 });
  }
  if (!body.notification_id) {
    return new Response("missing notification_id", { status: 400 });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: notif, error: nErr } = await supabase
    .from("notifications")
    .select("id, user_id, category, title, body, payload, deep_link")
    .eq("id", body.notification_id)
    .single<NotificationRow>();

  if (nErr || !notif) {
    return new Response(`notification not found: ${nErr?.message ?? "no row"}`, { status: 404 });
  }

  const { data: tokens } = await supabase
    .from("device_tokens")
    .select("token, platform, bundle_id")
    .eq("user_id", notif.user_id)
    .returns<DeviceTokenRow[]>();

  if (!tokens || tokens.length === 0) {
    return Response.json({ sent: 0, results: [] });
  }

  const jwt = await getApnsJwt();
  const results = await Promise.all(
    tokens.map((t) => dispatchOne(jwt, APNS_BUNDLE_ID!, t, notif)),
  );

  // Reap dead tokens: 410 Gone or 400 BadDeviceToken.
  const dead = results
    .filter((r) => r.status === 410 || r.reason === "BadDeviceToken" || r.reason === "Unregistered")
    .map((r) => r.token);
  if (dead.length) {
    await supabase.from("device_tokens").delete().in("token", dead);
  }

  return Response.json({
    sent: results.filter((r) => r.status < 300).length,
    failed: results.filter((r) => r.status >= 300).length,
    pruned: dead.length,
    results,
  });
});
