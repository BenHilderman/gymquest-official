-- v4.3 content-safety phase 4F — server canonical rate-limit + risk infra.
--
-- Mirrors the local `RateLimitWindow` and `AccountRiskState` SwiftData
-- models. Edge Function `score-account-risk` reads from + writes to
-- these tables on every Posts/Comments/DMs/Friends insert.
--
-- RLS:
--   rate_limit_counters  — user reads own; service-role writes
--   account_risk_score   — user reads own; service-role writes
--   risk_signals_audit   — service-role only (sensitive)

-- =============================================================
-- rate_limit_counters
-- =============================================================
-- Compound key (user_id, action, target_key, window_kind, window_started_at)
-- so a user can have multiple concurrent windows. The auto-bumping
-- function `incr_rate_limit_counter` does atomic upsert.

create table if not exists public.rate_limit_counters (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,
    action text not null,
    target_key text,                                  -- nullable (per-target action)
    window_kind text not null check (window_kind in ('hour', 'day')),
    window_started_at timestamptz not null,
    count int not null default 0,
    updated_at timestamptz not null default now()
);

create unique index if not exists rate_limit_counters_unique
    on public.rate_limit_counters
    (user_id, action, coalesce(target_key, ''), window_kind, window_started_at);

create index if not exists rate_limit_counters_user_idx
    on public.rate_limit_counters (user_id, action, updated_at desc);

alter table public.rate_limit_counters enable row level security;

create policy "rate_limit_counters_self_read"
    on public.rate_limit_counters
    for select
    using (auth.uid() = user_id);

-- Atomic incrementer — service-role calls this from the
-- score-account-risk function instead of doing select-then-update.
create or replace function public.incr_rate_limit_counter(
    p_user_id uuid,
    p_action text,
    p_target_key text,
    p_window_kind text,
    p_window_started_at timestamptz
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
    v_count int;
begin
    insert into public.rate_limit_counters
        (user_id, action, target_key, window_kind, window_started_at, count, updated_at)
    values
        (p_user_id, p_action, p_target_key, p_window_kind, p_window_started_at, 1, now())
    on conflict (user_id, action, coalesce(target_key, ''), window_kind, window_started_at)
    do update set
        count = public.rate_limit_counters.count + 1,
        updated_at = now()
    returning count into v_count;
    return v_count;
end;
$$;

grant execute on function public.incr_rate_limit_counter(uuid, text, text, text, timestamptz)
    to service_role;

-- =============================================================
-- account_risk_score
-- =============================================================

create table if not exists public.account_risk_score (
    user_id uuid primary key,
    score int not null default 0,
    -- 'probationary' | 'standard' | 'trusted' | 'throttled' | 'paused'
    tier text not null default 'standard'
        check (tier in ('probationary', 'standard', 'trusted', 'throttled', 'paused')),
    last_evaluated_at timestamptz not null default now(),
    -- JSON array of recent signal raw values (debug aid).
    recent_signals jsonb not null default '[]'::jsonb
);

create index if not exists account_risk_score_tier_idx
    on public.account_risk_score (tier)
    where tier in ('throttled', 'paused');

alter table public.account_risk_score enable row level security;

create policy "account_risk_score_self_read"
    on public.account_risk_score
    for select
    using (auth.uid() = user_id);

-- =============================================================
-- risk_signals_audit
-- =============================================================
-- Append-only log of every signal that fired against a user. Retained
-- 90 days for human review of disputed throttles / pauses. Service-role
-- only; users don't get to see what flagged them (signal evasion risk).

create table if not exists public.risk_signals_audit (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,
    signal text not null,
    points int not null,
    score_after int not null,
    fired_at timestamptz not null default now(),
    -- Optional context — for example the post_id that triggered
    -- "repeated content text".
    context jsonb
);

create index if not exists risk_signals_audit_user_idx
    on public.risk_signals_audit (user_id, fired_at desc);

alter table public.risk_signals_audit enable row level security;
-- (no public policy — service-role only)

-- =============================================================
-- 90-day retention cron
-- =============================================================

create or replace function public.purge_old_risk_signals()
returns void
language sql
security definer
set search_path = public
as $$
    delete from public.risk_signals_audit
    where fired_at < now() - interval '90 days';
$$;

-- Cron registration is left to the deploy step (Supabase has no
-- built-in DDL for pg_cron in plain SQL across versions). Suggested
-- schedule: daily at 03:00 UTC.
