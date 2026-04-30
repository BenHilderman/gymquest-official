// Edge Function: moderate-media
// Trigger: cron every minute (recommended) OR direct invocation from
//          a Postgres cron worker. Pulls pending rows from
//          `moderation_queue`, calls the configured moderation provider,
//          writes the verdict back to `moderation_audits`, and triggers
//          the soft-delete pathway when the verdict is `rejected`.
//
// Required env vars:
//   MODERATION_PROVIDER     "aws_rekognition" | "sightengine" | "hive" | "stub"
//   MODERATION_API_KEY      provider API key (not used by stub)
//   MODERATION_API_SECRET   provider secret (sightengine only)
//   MODERATION_BATCH_SIZE   max queue rows to process per invocation (default 25)
//   MODERATION_MAX_ATTEMPTS retry cap before marking failed (default 3)
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const PROVIDER = Deno.env.get("MODERATION_PROVIDER") ?? "stub";
const BATCH_SIZE = parseInt(Deno.env.get("MODERATION_BATCH_SIZE") ?? "25", 10);
const MAX_ATTEMPTS = parseInt(Deno.env.get("MODERATION_MAX_ATTEMPTS") ?? "3", 10);

interface QueueRow {
  id: string;
  audit_id: string;
  attempt_count: number;
}

interface AuditRow {
  id: string;
  content_id: string;
  content_type: string;
  asset_kind: string;
  asset_url: string | null;
  author_id: string;
  audience: string;
}

type Verdict = "allowed" | "held" | "rejected";

interface ModerationResult {
  verdict: Verdict;
  reason: string;
  confidence: number;
  provider: string;
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// ---------------------------------------------------------------------------
// Provider implementations
// ---------------------------------------------------------------------------

async function moderateAsset(audit: AuditRow): Promise<ModerationResult> {
  switch (PROVIDER) {
    case "aws_rekognition":
      return await moderateWithRekognition(audit);
    case "sightengine":
      return await moderateWithSightengine(audit);
    case "hive":
      return await moderateWithHive(audit);
    default:
      return moderateStub(audit);
  }
}

/// Stub provider — always allowed. Lets the pipeline run end-to-end in
/// dev without any moderation API spend. Switch via MODERATION_PROVIDER.
function moderateStub(audit: AuditRow): ModerationResult {
  return {
    verdict: "allowed",
    reason: "stub provider — no real check performed",
    confidence: 0,
    provider: "stub",
  };
}

async function moderateWithRekognition(_audit: AuditRow): Promise<ModerationResult> {
  // Wire Rekognition's DetectModerationLabels here. Returns an array of
  // labels with confidence — collapse via threshold to a Verdict.
  // Threshold: confidence >= rejectionThresholdFor(audience) → rejected.
  // Skeleton intentionally returns held so the row stays in the appeal
  // path until the real client is set.
  return {
    verdict: "held",
    reason: "Rekognition client not configured",
    confidence: 0,
    provider: "aws_rekognition",
  };
}

async function moderateWithSightengine(_audit: AuditRow): Promise<ModerationResult> {
  return {
    verdict: "held",
    reason: "Sightengine client not configured",
    confidence: 0,
    provider: "sightengine",
  };
}

async function moderateWithHive(_audit: AuditRow): Promise<ModerationResult> {
  return {
    verdict: "held",
    reason: "Hive client not configured",
    confidence: 0,
    provider: "hive",
  };
}

// ---------------------------------------------------------------------------
// Queue processor
// ---------------------------------------------------------------------------

async function processBatch(): Promise<{ processed: number; failed: number }> {
  // Pull pending rows. `started_at is null` filter is enforced by the
  // partial index `moderation_queue_pending_idx`.
  const { data: queueRows, error: queueError } = await supabase
    .from("moderation_queue")
    .select("id, audit_id, attempt_count")
    .is("started_at", null)
    .order("enqueued_at", { ascending: true })
    .limit(BATCH_SIZE);

  if (queueError) {
    console.error("[moderate-media] queue fetch failed", queueError);
    return { processed: 0, failed: 0 };
  }
  if (!queueRows || queueRows.length === 0) {
    return { processed: 0, failed: 0 };
  }

  let processed = 0;
  let failed = 0;

  for (const queueRow of queueRows as QueueRow[]) {
    // Mark queue row started.
    await supabase
      .from("moderation_queue")
      .update({
        started_at: new Date().toISOString(),
        attempt_count: queueRow.attempt_count + 1,
      })
      .eq("id", queueRow.id);

    // Pull the audit row.
    const { data: auditRow, error: auditError } = await supabase
      .from("moderation_audits")
      .select("*")
      .eq("id", queueRow.audit_id)
      .maybeSingle();

    if (auditError || !auditRow) {
      failed++;
      continue;
    }

    try {
      const result = await moderateAsset(auditRow as AuditRow);

      await supabase
        .from("moderation_audits")
        .update({
          verdict: result.verdict,
          reason: result.reason,
          confidence: result.confidence,
          provider: result.provider,
          completed_at: new Date().toISOString(),
        })
        .eq("id", queueRow.audit_id);

      await supabase
        .from("moderation_queue")
        .update({ completed_at: new Date().toISOString() })
        .eq("id", queueRow.id);

      processed++;
    } catch (e) {
      console.error("[moderate-media] provider call failed", e);
      // Retry up to MAX_ATTEMPTS — clear started_at so the next run
      // picks it back up. After max attempts, leave it marked failed.
      const shouldRetry = queueRow.attempt_count + 1 < MAX_ATTEMPTS;
      if (shouldRetry) {
        await supabase
          .from("moderation_queue")
          .update({ started_at: null })
          .eq("id", queueRow.id);
      } else {
        await supabase
          .from("moderation_audits")
          .update({
            verdict: "held",
            reason: "moderation pipeline retry exhausted",
            provider: PROVIDER,
            completed_at: new Date().toISOString(),
          })
          .eq("id", queueRow.audit_id);
      }
      failed++;
    }
  }

  return { processed, failed };
}

// ---------------------------------------------------------------------------
// HTTP entry point
// ---------------------------------------------------------------------------

Deno.serve(async (_req) => {
  const result = await processBatch();
  return new Response(JSON.stringify({ ok: true, ...result }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
