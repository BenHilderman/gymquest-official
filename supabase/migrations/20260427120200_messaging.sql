-- ============================================================
-- v4.3 Phase 1.3 — Messaging (DMs + Squad Chat + Comment reactions)
-- Tables: dm_threads, dm_messages, dm_message_reactions
--         squad_threads, squad_messages, squad_message_reactions
-- Squad workout-finishes are real event rows, not bot speech
-- ============================================================

-- DM threads (1-on-1)
create table if not exists public.dm_threads (
  id uuid primary key default gen_random_uuid(),
  participant_a uuid not null references public.profiles(id) on delete cascade,
  participant_b uuid not null references public.profiles(id) on delete cascade,
  last_message_at timestamptz default now(),
  vanish_mode_a boolean default false,
  vanish_mode_b boolean default false,
  read_receipts_a boolean default true,
  read_receipts_b boolean default true,
  created_at timestamptz default now()
);

create unique index if not exists dm_threads_pair_idx on public.dm_threads (
  least(participant_a, participant_b),
  greatest(participant_a, participant_b)
);

create index if not exists dm_threads_a_idx on public.dm_threads (participant_a, last_message_at desc);
create index if not exists dm_threads_b_idx on public.dm_threads (participant_b, last_message_at desc);

alter table public.dm_threads enable row level security;
create policy dm_threads_read on public.dm_threads for select
  using (auth.uid() in (participant_a, participant_b));
create policy dm_threads_write on public.dm_threads for all
  using (auth.uid() in (participant_a, participant_b))
  with check (auth.uid() in (participant_a, participant_b));

-- DM messages
create table if not exists public.dm_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.dm_threads(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in (
    'text','voice','photo','video','workout_share','profile_card','story_share',
    'crew_share','partner_invite'
  )),
  body text,
  media_url text,
  voice_data_ref text,
  photo_data_ref text,
  workout_id uuid,
  shared_post_id uuid,
  partner_invite_workout_type text,
  expires_at timestamptz,
  edited_at timestamptz,
  read_at timestamptz,
  created_at timestamptz default now()
);

create index if not exists dm_messages_thread_idx on public.dm_messages (thread_id, created_at desc);
create index if not exists dm_messages_unread_idx on public.dm_messages (thread_id, read_at);

alter table public.dm_messages enable row level security;
create policy dm_messages_thread_member on public.dm_messages for all using (
  exists (select 1 from public.dm_threads t where t.id = dm_messages.thread_id
          and auth.uid() in (t.participant_a, t.participant_b))
) with check (
  sender_id = auth.uid()
  and exists (select 1 from public.dm_threads t where t.id = dm_messages.thread_id
              and auth.uid() in (t.participant_a, t.participant_b))
);

-- DM message reactions
create table if not exists public.dm_message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.dm_messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null default 'emoji' check (kind in ('emoji','voice','photo')),
  emoji text,
  voice_data_ref text,
  photo_data_ref text,
  photo_expires_at timestamptz,
  created_at timestamptz default now()
);

create unique index if not exists dm_message_reactions_uniq_idx
  on public.dm_message_reactions (message_id, user_id, kind, coalesce(emoji,''));

alter table public.dm_message_reactions enable row level security;
create policy dm_message_reactions_thread_member on public.dm_message_reactions for all using (
  exists (
    select 1 from public.dm_messages m
    join public.dm_threads t on t.id = m.thread_id
    where m.id = dm_message_reactions.message_id
      and auth.uid() in (t.participant_a, t.participant_b)
  )
) with check (user_id = auth.uid());

-- Squad chat threads (one per squad)
create table if not exists public.squad_threads (
  id uuid primary key default gen_random_uuid(),
  squad_id uuid unique references public.squads(id) on delete cascade,
  last_message_at timestamptz default now(),
  quiet_nudge_enabled boolean default false,
  created_at timestamptz default now()
);

alter table public.squad_threads enable row level security;
create policy squad_threads_member on public.squad_threads for all using (
  exists (select 1 from public.squads s where s.id = squad_threads.squad_id and auth.uid() = any(s.member_ids))
) with check (
  exists (select 1 from public.squads s where s.id = squad_threads.squad_id and auth.uid() = any(s.member_ids))
);

-- Squad messages — `system_event_kind != null` is the ONLY way auto-shared workout completions
-- are written. Real conversations have system_event_kind = null. Bots may not insert.
create table if not exists public.squad_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.squad_threads(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete cascade,
  kind text not null check (kind in (
    'text','voice','photo','video','workout_share','poll','system_event'
  )),
  body text,
  media_url text,
  voice_data_ref text,
  photo_data_ref text,
  workout_id uuid,
  poll_options jsonb,
  poll_votes jsonb,
  system_event_kind text check (system_event_kind in (
    'workout_finished','member_joined','member_left','quiet_nudge'
  )),
  edited_at timestamptz,
  created_at timestamptz default now()
);

create index if not exists squad_messages_thread_idx on public.squad_messages (thread_id, created_at desc);

alter table public.squad_messages enable row level security;
create policy squad_messages_member on public.squad_messages for all using (
  exists (
    select 1 from public.squad_threads t
    join public.squads s on s.id = t.squad_id
    where t.id = squad_messages.thread_id and auth.uid() = any(s.member_ids)
  )
) with check (
  exists (
    select 1 from public.squad_threads t
    join public.squads s on s.id = t.squad_id
    where t.id = squad_messages.thread_id and auth.uid() = any(s.member_ids)
  )
);

create table if not exists public.squad_message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.squad_messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null default 'emoji' check (kind in ('emoji','voice','photo')),
  emoji text,
  voice_data_ref text,
  photo_data_ref text,
  photo_expires_at timestamptz,
  created_at timestamptz default now()
);

create unique index if not exists squad_message_reactions_uniq_idx
  on public.squad_message_reactions (message_id, user_id, kind, coalesce(emoji,''));

alter table public.squad_message_reactions enable row level security;
create policy squad_message_reactions_member on public.squad_message_reactions for all using (
  exists (
    select 1 from public.squad_messages m
    join public.squad_threads t on t.id = m.thread_id
    join public.squads s on s.id = t.squad_id
    where m.id = squad_message_reactions.message_id and auth.uid() = any(s.member_ids)
  )
) with check (user_id = auth.uid());

-- Comment reactions (long-press emoji + voice + photo per design §6C)
create table if not exists public.comment_reactions (
  id uuid primary key default gen_random_uuid(),
  comment_id uuid not null references public.comments(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null default 'emoji' check (kind in ('emoji','voice','photo')),
  emoji text,
  voice_data_ref text,
  photo_data_ref text,
  photo_expires_at timestamptz,
  created_at timestamptz default now()
);

create unique index if not exists comment_reactions_uniq_idx
  on public.comment_reactions (comment_id, user_id, kind, coalesce(emoji,''));

alter table public.comment_reactions enable row level security;
create policy comment_reactions_read on public.comment_reactions for select using (true);
create policy comment_reactions_write on public.comment_reactions for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
