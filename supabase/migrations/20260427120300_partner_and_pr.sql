-- ============================================================
-- v4.3 Phase 1.4 — Partner Mode + PR events + post audience
-- ============================================================

-- Partner sessions
create table if not exists public.partner_sessions (
  id uuid primary key default gen_random_uuid(),
  initiator_id uuid not null references public.profiles(id) on delete cascade,
  partner_id uuid not null references public.profiles(id) on delete cascade,
  workout_a_id uuid,
  workout_b_id uuid,
  invited_workout_type text,
  state text not null default 'pending' check (state in ('pending','accepted','declined','active','ended','expired')),
  shared_post_id uuid,
  post_together_enabled boolean default true,
  invited_at timestamptz default now(),
  accepted_at timestamptz,
  started_at timestamptz,
  ended_at timestamptz
);

create index if not exists partner_sessions_initiator_idx on public.partner_sessions (initiator_id, invited_at desc);
create index if not exists partner_sessions_partner_idx on public.partner_sessions (partner_id, invited_at desc);
create index if not exists partner_sessions_active_idx on public.partner_sessions (state) where state = 'active';

alter table public.partner_sessions enable row level security;
create policy partner_sessions_member on public.partner_sessions for all
  using (auth.uid() in (initiator_id, partner_id))
  with check (auth.uid() in (initiator_id, partner_id));

-- Partner streaks
create table if not exists public.partner_streaks (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  streak_count integer not null default 0,
  last_session_at timestamptz,
  broken_at timestamptz,
  updated_at timestamptz default now()
);

create unique index if not exists partner_streaks_pair_idx on public.partner_streaks (
  least(user_a, user_b),
  greatest(user_a, user_b)
);

alter table public.partner_streaks enable row level security;
create policy partner_streaks_member on public.partner_streaks for select
  using (auth.uid() in (user_a, user_b));

-- PR events
create table if not exists public.pr_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  workout_id uuid,
  set_id uuid,
  exercise_id uuid,
  exercise_name text,
  value numeric not null,
  value_unit text not null default 'kg' check (value_unit in ('kg','lb','reps','sec','m','km','mi')),
  previous_best numeric,
  recorded_at timestamptz default now()
);

create index if not exists pr_events_user_idx on public.pr_events (user_id, recorded_at desc);

alter table public.pr_events enable row level security;
create policy pr_events_read_self_or_followed on public.pr_events for select using (
  user_id = auth.uid()
  or exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.following_id = pr_events.user_id)
);
create policy pr_events_write_self on public.pr_events for insert
  with check (user_id = auth.uid());

-- Posts: audience scoping + partner linkage
alter table public.posts add column if not exists audience text default 'friends'
  check (audience in ('friends','close_friends','squad','public'));
alter table public.posts add column if not exists audience_squad_id uuid;
alter table public.posts add column if not exists partner_session_id uuid references public.partner_sessions(id);
alter table public.posts add column if not exists partner_user_id uuid references public.profiles(id);

create index if not exists posts_audience_idx on public.posts (audience);
create index if not exists posts_partner_idx on public.posts (partner_session_id) where partner_session_id is not null;

-- Drop the wide-open posts read policy if any older one exists, then add audience-aware policy.
drop policy if exists posts_read_all on public.posts;
drop policy if exists posts_select_all on public.posts;

create policy posts_read_audience on public.posts for select using (
  is_deleted = false
  and (
    audience = 'public'
    or author_id = auth.uid()
    or (audience = 'friends' and exists (
        select 1 from public.follows f
        where f.follower_id = auth.uid() and f.following_id = posts.author_id
    ))
    or (audience = 'close_friends' and exists (
        select 1 from public.close_friends cf
        where cf.user_id = posts.author_id and cf.friend_id = auth.uid()
    ))
    or (audience = 'squad' and audience_squad_id is not null and exists (
        select 1 from public.squads s
        where s.id = posts.audience_squad_id and auth.uid() = any(s.member_ids)
    ))
  )
);
