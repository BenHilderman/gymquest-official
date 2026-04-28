-- ============================================================
-- v4.3 Phase 1.5 — Discover Streak + view audit + misc
-- ============================================================

-- Discover Streak counters (per design §3A — synced with Identity)
create table if not exists public.discover_streak_counters (
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in (
    'workout_saved','tip_applied','clip_reacted','creator_followed','workout_tried'
  )),
  week_starting date not null,
  count integer not null default 0,
  primary key (user_id, kind, week_starting)
);

create index if not exists discover_streak_user_week_idx on public.discover_streak_counters (user_id, week_starting desc);

alter table public.discover_streak_counters enable row level security;
create policy discover_streak_self on public.discover_streak_counters for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Discover Engine surface audit (every recommendation render is logged with surface)
-- Used by CI to enforce design §11: engine MUST NOT feed Squad Chat / DMs / Profile / Crew quiet / Friends mid-stream.
create table if not exists public.discover_engine_renders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  surface text not null check (surface in (
    'discover_watch','discover_friends','discover_tips',
    'stories_public_optin','friends_feed_empty','plus_wod','onboarding_reel'
  )),
  candidate_id uuid,
  candidate_kind text,
  rendered_at timestamptz default now()
);

create index if not exists discover_renders_user_idx on public.discover_engine_renders (user_id, rendered_at desc);

alter table public.discover_engine_renders enable row level security;
create policy discover_renders_self on public.discover_engine_renders for select
  using (user_id = auth.uid());
create policy discover_renders_insert_self on public.discover_engine_renders for insert
  with check (user_id = auth.uid());

-- Saved gym trusted-friend visibility convenience view
create or replace view public.saved_gym_trusted_friends as
  select
    tfg.user_id,
    tfg.friend_id,
    tfg.gym_id,
    p.username as friend_username,
    p.display_name as friend_display_name
  from public.trusted_friends_per_gym tfg
  join public.profiles p on p.id = tfg.friend_id;

-- Per-post audience back-fill: any pre-existing posts default to 'friends'
update public.posts set audience = 'friends' where audience is null;
