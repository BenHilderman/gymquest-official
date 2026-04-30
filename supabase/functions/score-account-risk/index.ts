// Edge Function: score-account-risk
// Trigger: AFTER INSERT on public.posts / comments / dm_messages /
//          friends -> POST { user_id, action } here.
// Increments the user's rate-limit counter for the action and re-runs
// the risk heuristics. Updates account_risk_score.tier when crossings
// occur (standard -> throttled -> paused).
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// Mirrors AbuseThresholds.swift on the Swift side. Keep these in sync
// when tuning either side.
const POINTS = {
  young_account_high_activity: 30,
  zero_workouts_high_social: 25,
  repeated_content_text: 40,
  follow_unfollow_churn: 35,
  repeated_signup_same_device: 50,
  user_reports_spike: 60,
  mention_flood: 30,
  identical_voice_note_durations: 20,
};

type Tier = "probationary" | "standard" | "trusted" | "throttled" | "paused";

function tierForScore(score: number): Tier {
  if (score < 26) return "standard";
  if (score < 61) return "throttled";
  return "paused";
}

interface RequestBody {
  user_id: string;
  action: string;
  target_key?: string;
}

async function rollHourWindow(now: Date): Promise<string> {
  // Window starts on the hour boundary.
  const d = new Date(now);
  d.setUTCMinutes(0, 0, 0);
  return d.toISOString();
}

async function rollDayWindow(now: Date): Promise<string> {
  const d = new Date(now);
  d.setUTCHours(0, 0, 0, 0);
  return d.toISOString();
}

async function increment(userId: string, action: string, targetKey: string | null) {
  const now = new Date();
  const hour = await rollHourWindow(now);
  const day = await rollDayWindow(now);

  await supabase.rpc("incr_rate_limit_counter", {
    p_user_id: userId,
    p_action: action,
    p_target_key: targetKey,
    p_window_kind: "hour",
    p_window_started_at: hour,
  });
  await supabase.rpc("incr_rate_limit_counter", {
    p_user_id: userId,
    p_action: action,
    p_target_key: null,
    p_window_kind: "day",
    p_window_started_at: day,
  });
}

async function evaluateRisk(userId: string): Promise<{ score: number; tier: Tier; signals: string[] }> {
  let score = 0;
  const signals: string[] = [];

  // Pull recent posts for repeated-content + mention-flood checks.
  const { data: recentPosts } = await supabase
    .from("posts")
    .select("caption, tagged_usernames, created_at, voice_note_duration")
    .eq("author_id", userId)
    .gte("created_at", new Date(Date.now() - 24 * 3600 * 1000).toISOString());

  if (recentPosts && recentPosts.length > 0) {
    const captionCounts = new Map<string, number>();
    let mentionFloods = 0;
    const voiceDurations: number[] = [];
    for (const p of recentPosts) {
      const cap = (p.caption ?? "").toLowerCase().trim();
      if (cap.length > 0) {
        captionCounts.set(cap, (captionCounts.get(cap) ?? 0) + 1);
      }
      const tagged = (p.tagged_usernames ?? []) as string[];
      if (tagged.length >= 10) mentionFloods++;
      if (typeof p.voice_note_duration === "number") {
        voiceDurations.push(p.voice_note_duration);
      }
    }
    for (const [, count] of captionCounts) {
      if (count >= 3) {
        score += POINTS.repeated_content_text;
        signals.push("repeated_content_text");
        break;
      }
    }
    if (mentionFloods >= 3) {
      score += POINTS.mention_flood;
      signals.push("mention_flood");
    }
    // Identical voice-note durations bucketed at 0.5s.
    const buckets = new Map<number, number>();
    for (const d of voiceDurations) {
      const b = Math.floor(d * 2);
      buckets.set(b, (buckets.get(b) ?? 0) + 1);
    }
    for (const [, c] of buckets) {
      if (c >= 5) {
        score += POINTS.identical_voice_note_durations;
        signals.push("identical_voice_note_durations");
        break;
      }
    }
  }

  // Reports against this user in 24h (≥ 5 distinct reporters).
  const { data: postIds } = await supabase
    .from("posts")
    .select("id")
    .eq("author_id", userId)
    .gte("created_at", new Date(Date.now() - 24 * 3600 * 1000).toISOString());
  const { data: commentIds } = await supabase
    .from("comments")
    .select("id")
    .eq("author_id", userId)
    .gte("created_at", new Date(Date.now() - 24 * 3600 * 1000).toISOString());
  const ids = [
    ...(postIds ?? []).map((r: { id: string }) => r.id),
    ...(commentIds ?? []).map((r: { id: string }) => r.id),
  ];
  if (ids.length > 0) {
    const { data: reports } = await supabase
      .from("content_reports")
      .select("reporter_id")
      .in("content_id", ids)
      .gte("created_at", new Date(Date.now() - 24 * 3600 * 1000).toISOString());
    const distinctReporters = new Set((reports ?? []).map((r: { reporter_id: string }) => r.reporter_id));
    if (distinctReporters.size >= 5) {
      score += POINTS.user_reports_spike;
      signals.push("user_reports_spike");
    }
  }

  // Follow→unfollow churn (5+ on the same target within 1 hour).
  const { data: friendChurn } = await supabase
    .from("friends")
    .select("od_id, created_at, deleted_at")
    .eq("user_id", userId)
    .gte("created_at", new Date(Date.now() - 3600 * 1000).toISOString());
  if (friendChurn) {
    const targetCounts = new Map<string, number>();
    for (const f of friendChurn) {
      if (f.deleted_at != null) {
        targetCounts.set(f.od_id, (targetCounts.get(f.od_id) ?? 0) + 1);
      }
    }
    for (const [, c] of targetCounts) {
      if (c >= 5) {
        score += POINTS.follow_unfollow_churn;
        signals.push("follow_unfollow_churn");
        break;
      }
    }
  }

  return { score, tier: tierForScore(score), signals };
}

async function persistRisk(userId: string, score: number, tier: Tier, signals: string[]) {
  await supabase
    .from("account_risk_score")
    .upsert({
      user_id: userId,
      score,
      tier,
      last_evaluated_at: new Date().toISOString(),
      recent_signals: signals,
    }, { onConflict: "user_id" });

  // Append audit rows for every signal that fired this evaluation.
  if (signals.length > 0) {
    const rows = signals.map((s) => ({
      user_id: userId,
      signal: s,
      points: POINTS[s as keyof typeof POINTS] ?? 0,
      score_after: score,
      fired_at: new Date().toISOString(),
    }));
    await supabase.from("risk_signals_audit").insert(rows);
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }
  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return new Response("bad request", { status: 400 });
  }
  if (!body.user_id || !body.action) {
    return new Response("user_id + action required", { status: 400 });
  }

  await increment(body.user_id, body.action, body.target_key ?? null);
  const result = await evaluateRisk(body.user_id);
  await persistRisk(body.user_id, result.score, result.tier, result.signals);

  return new Response(JSON.stringify({
    ok: true,
    score: result.score,
    tier: result.tier,
    signals: result.signals,
  }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
