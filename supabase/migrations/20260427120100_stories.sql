-- ============================================================
-- v4.3 Phase 1.2 — Stories pillar
-- Tables: stories, story_views, story_highlights
-- Audience scoping: friends / close_friends / squad / public
-- ============================================================

create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('photo','video','text','workout_share')),
  media_url text,
  text_body text,
  workout_id uuid,
  sticker_payload jsonb default '{}'::jsonb,
  audience text not null default 'friends' check (audience in ('friends','close_friends','squad','public')),
  audience_squad_id uuid,
  song_title text,
  artist_name text,
  posted_at timestamptz default now(),
  expires_at timestamptz default (now() + interval '24 hours'),
  view_count integer default 0,
  is_deleted boolean default false
);

create index if not exists stories_author_active_idx on public.stories (author_id, expires_at)
  where is_deleted = false;
create index if not exists stories_active_idx on public.stories (expires_at) where is_deleted = false;

alter table public.stories enable row level security;

create policy stories_read on public.stories for select using (
  is_deleted = false
  and expires_at > now()
  and (
    audience = 'public'
    or author_id = auth.uid()
    or (audience = 'friends' and exists (
        select 1 from public.follows f
        where f.follower_id = auth.uid() and f.following_id = stories.author_id
    ))
    or (audience = 'close_friends' and exists (
        select 1 from public.close_friends cf
        where cf.user_id = stories.author_id and cf.friend_id = auth.uid()
    ))
    or (audience = 'squad' and audience_squad_id is not null and exists (
        select 1 from public.squads s
        where s.id = stories.audience_squad_id and auth.uid() = any(s.member_ids)
    ))
  )
);

create policy stories_write_self on public.stories for all
  using (author_id = auth.uid()) with check (author_id = auth.uid());

-- Story views (per-viewer log; powers "view count visible to poster")
create table if not exists public.story_views (
  story_id uuid not null references public.stories(id) on delete cascade,
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz default now(),
  primary key (story_id, viewer_id)
);

alter table public.story_views enable row level security;
create policy story_views_write_self on public.story_views for insert
  with check (viewer_id = auth.uid());
create policy story_views_read_author_or_self on public.story_views for select using (
  viewer_id = auth.uid()
  or exists (select 1 from public.stories s where s.id = story_views.story_id and s.author_id = auth.uid())
);

-- Story Highlights (user-curated, pinned to Profile)
create table if not exists public.story_highlights (
  user_id uuid not null references public.profiles(id) on delete cascade,
  slot_index integer not null check (slot_index >= 0 and slot_index < 8),
  story_id uuid not null references public.stories(id) on delete cascade,
  title text,
  pinned_at timestamptz default now(),
  primary key (user_id, slot_index)
);

alter table public.story_highlights enable row level security;
create policy story_highlights_read on public.story_highlights for select using (true);
create policy story_highlights_write_self on public.story_highlights for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
