-- ============================================================
-- v4.3 Phase 1.1 — Presence + Alive Layer foundation
-- Tables: presence, ghost_mode (4 levels), trusted_friends_per_gym
-- Extensions: reactions (voice/photo refs, expiry), notifications (granular categories)
-- ============================================================

-- Presence: live state per user
create table if not exists public.presence (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  state text not null check (state in ('live','recently_finished','inactive','ghost')),
  gym_id uuid,
  workout_type text,
  set_count integer default 0,
  started_at timestamptz,
  last_ping_at timestamptz default now(),
  expires_at timestamptz,
  updated_at timestamptz default now()
);

create index if not exists presence_state_idx on public.presence (state) where state in ('live','recently_finished');
create index if not exists presence_gym_idx on public.presence (gym_id) where gym_id is not null;

alter table public.presence enable row level security;

create policy presence_read_self_or_followed on public.presence for select using (
  user_id = auth.uid()
  or exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.following_id = presence.user_id)
);

create policy presence_write_self on public.presence for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Ghost Mode (4 levels)
create table if not exists public.ghost_mode (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  level text not null default 'friends' check (level in ('public','friends','squad','ghost')),
  updated_at timestamptz default now()
);

alter table public.ghost_mode enable row level security;
create policy ghost_mode_self on public.ghost_mode for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Trusted-friends-per-gym (asymmetric per design §8A)
create table if not exists public.trusted_friends_per_gym (
  user_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  gym_id uuid not null,
  created_at timestamptz default now(),
  primary key (user_id, friend_id, gym_id)
);

alter table public.trusted_friends_per_gym enable row level security;
create policy trusted_friends_self on public.trusted_friends_per_gym for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy trusted_friends_visible_to_friend on public.trusted_friends_per_gym for select
  using (friend_id = auth.uid());

-- Close friends list
create table if not exists public.close_friends (
  user_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  added_at timestamptz default now(),
  primary key (user_id, friend_id)
);

alter table public.close_friends enable row level security;
create policy close_friends_self on public.close_friends for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Reactions: granular kind + voice/photo refs + photo expiry
alter table public.reactions add column if not exists kind text default 'emoji'
  check (kind in ('emoji','voice','photo'));
alter table public.reactions add column if not exists voice_data_ref text;
alter table public.reactions add column if not exists photo_data_ref text;
alter table public.reactions add column if not exists photo_expires_at timestamptz;

create index if not exists reactions_target_idx on public.reactions (target_type, target_id);
create index if not exists reactions_photo_expiry_idx on public.reactions (photo_expires_at) where photo_expires_at is not null;

-- Notifications: granular category column
-- v1 schema had `is_read boolean` + `type` text; v4.3 redesigns with `read_at timestamptz` + `category` enum
drop table if exists public.notifications cascade;
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  category text not null check (category in (
    'friend_starts','friend_finishes','reaction_emoji','reaction_voice','reaction_photo',
    'comment','dm','story_view','tag_mention','crew_event','squad_chat','squad_reminder',
    'partner_invite','streak_nudge','ai_coach_prompt','system'
  )),
  title text,
  body text,
  payload jsonb default '{}'::jsonb,
  deep_link text,
  read_at timestamptz,
  created_at timestamptz default now()
);

create index if not exists notifications_user_unread_idx on public.notifications (user_id, read_at);

alter table public.notifications enable row level security;
create policy notifications_read_self on public.notifications for select using (user_id = auth.uid());
create policy notifications_write_self on public.notifications for update using (user_id = auth.uid());

-- Per-user notification preferences (granular toggles)
create table if not exists public.notification_preferences (
  user_id uuid not null references public.profiles(id) on delete cascade,
  category text not null,
  enabled boolean not null default true,
  primary key (user_id, category)
);

alter table public.notification_preferences enable row level security;
create policy notification_preferences_self on public.notification_preferences for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Device push tokens for APNs
create table if not exists public.device_tokens (
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null,
  platform text not null default 'ios' check (platform in ('ios','watchos')),
  bundle_id text,
  created_at timestamptz default now(),
  last_seen_at timestamptz default now(),
  primary key (user_id, token)
);

alter table public.device_tokens enable row level security;
create policy device_tokens_self on public.device_tokens for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
