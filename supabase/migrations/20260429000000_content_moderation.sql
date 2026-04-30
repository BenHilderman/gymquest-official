-- v4.3 content-safety phase 2 — server canonical audit pipeline.
--
-- Local Vision/Speech audits (phase 1) handle most cases on-device.
-- This migration introduces the server-of-record audit so public-audience
-- content gets a second-opinion check, and so we have a durable audit
-- trail for appeals.
--
-- Tables:
--   moderation_audits   — one row per asset audited
--   moderation_queue    — pending audits the Edge Function consumes
--
-- Triggers:
--   posts_enqueue_moderation        — auto-enqueue public-audience posts
--   comments_enqueue_moderation     — auto-enqueue all comments with media
--   dm_messages_enqueue_moderation  — auto-enqueue DMs with media
--   squad_messages_enqueue_moderation — auto-enqueue squad msgs with media
--
-- Soft-delete on rejection happens in a separate migration (phase 2B);
-- this one only stands up the audit infra.

-- =============================================================
-- moderation_audits
-- =============================================================

create table if not exists public.moderation_audits (
    id uuid primary key default gen_random_uuid(),
    content_id uuid not null,
    -- 'post' | 'comment' | 'dm_message' | 'squad_message' | 'story'
    content_type text not null check (content_type in
        ('post', 'comment', 'dm_message', 'squad_message', 'story')),
    -- 'image' | 'video' | 'audio' | 'text'
    asset_kind text not null check (asset_kind in
        ('image', 'video', 'audio', 'text')),
    -- Storage URL for image/video/audio. Null for text (the body itself
    -- is read directly from the source row).
    asset_url text,
    -- Author of the content — denormalized so we can rate-limit by
    -- author without a join when scoring abuse signals.
    author_id uuid not null,
    -- Audience at submission time. Helps the function pick the
    -- strictness threshold (public stricter than friends/squad).
    audience text not null check (audience in ('friends', 'squad', 'public')),
    -- 'allowed' | 'held' | 'rejected'
    verdict text,
    reason text,
    -- Confidence score 0–1 from the moderation API.
    confidence real,
    -- Provider that returned the verdict.
    -- 'aws_rekognition' | 'sightengine' | 'hive' | 'manual_review'
    provider text,
    created_at timestamptz not null default now(),
    completed_at timestamptz
);

create index if not exists moderation_audits_content_idx
    on public.moderation_audits (content_id, content_type);
create index if not exists moderation_audits_author_idx
    on public.moderation_audits (author_id, created_at desc);
create index if not exists moderation_audits_verdict_idx
    on public.moderation_audits (verdict)
    where verdict is not null;

-- RLS: an author reads only their own audit rows; service-role writes.
alter table public.moderation_audits enable row level security;

create policy "moderation_audits_self_read"
    on public.moderation_audits
    for select
    using (auth.uid() = author_id);

-- (No insert/update policy for end users — only service-role can write.)

-- =============================================================
-- moderation_queue
-- =============================================================
-- Pending work for the `moderate-media` Edge Function. Idempotent:
-- duplicate enqueues collapse via the unique index. The function pulls
-- batches, processes, and writes back the verdict on the audit row.

create table if not exists public.moderation_queue (
    id uuid primary key default gen_random_uuid(),
    audit_id uuid not null references public.moderation_audits(id) on delete cascade,
    enqueued_at timestamptz not null default now(),
    started_at timestamptz,
    completed_at timestamptz,
    attempt_count int not null default 0,
    constraint moderation_queue_audit_unique unique (audit_id)
);

create index if not exists moderation_queue_pending_idx
    on public.moderation_queue (enqueued_at)
    where started_at is null;

alter table public.moderation_queue enable row level security;
-- No public access; service-role only.

-- =============================================================
-- Helper: enqueue an audit + queue row in one shot
-- =============================================================

create or replace function public.enqueue_moderation(
    p_content_id uuid,
    p_content_type text,
    p_asset_kind text,
    p_asset_url text,
    p_author_id uuid,
    p_audience text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_audit_id uuid;
begin
    insert into public.moderation_audits
        (content_id, content_type, asset_kind, asset_url, author_id, audience)
    values
        (p_content_id, p_content_type, p_asset_kind, p_asset_url, p_author_id, p_audience)
    returning id into v_audit_id;

    insert into public.moderation_queue (audit_id)
    values (v_audit_id)
    on conflict (audit_id) do nothing;

    return v_audit_id;
end;
$$;

grant execute on function public.enqueue_moderation(uuid, text, text, text, uuid, text)
    to service_role;

-- =============================================================
-- Triggers — auto-enqueue the moderation work
-- =============================================================

-- Posts: enqueue any post tagged audience='public'. Friends/squad rely on
-- on-device audit only (the social trust gate is real). Image + video
-- enqueue separately so the function audits each asset.

create or replace function public.fn_posts_enqueue_moderation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_audience text;
begin
    v_audience := coalesce(new.audience, 'friends');
    if v_audience != 'public' then
        return new;
    end if;

    if new.photo_url is not null then
        perform public.enqueue_moderation(
            new.id, 'post', 'image', new.photo_url, new.author_id, v_audience);
    end if;
    if new.video_url is not null then
        perform public.enqueue_moderation(
            new.id, 'post', 'video', new.video_url, new.author_id, v_audience);
    end if;
    if new.caption is not null and length(new.caption) > 0 then
        perform public.enqueue_moderation(
            new.id, 'post', 'text', null, new.author_id, v_audience);
    end if;

    return new;
end;
$$;

drop trigger if exists posts_enqueue_moderation on public.posts;
create trigger posts_enqueue_moderation
    after insert on public.posts
    for each row execute function public.fn_posts_enqueue_moderation();

-- Comments: enqueue every media comment regardless of audience because
-- comments inherit the post's reach but can be authored by anyone.

create or replace function public.fn_comments_enqueue_moderation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    -- Audio-kind comments are server-audited because Speech transcripts
    -- can be bypassed locally on jailbroken devices. Photo same reason.
    -- Text comments only enqueue for public-audience posts to save spend.
    if coalesce(new.media_kind, 'text') = 'audio' and new.audio_url is not null then
        perform public.enqueue_moderation(
            new.id, 'comment', 'audio', new.audio_url, new.author_id,
            coalesce((select audience from public.posts where id = new.post_id), 'friends'));
    end if;
    if coalesce(new.media_kind, 'text') = 'photo' and new.photo_url is not null then
        perform public.enqueue_moderation(
            new.id, 'comment', 'image', new.photo_url, new.author_id,
            coalesce((select audience from public.posts where id = new.post_id), 'friends'));
    end if;
    return new;
end;
$$;

drop trigger if exists comments_enqueue_moderation on public.comments;
create trigger comments_enqueue_moderation
    after insert on public.comments
    for each row execute function public.fn_comments_enqueue_moderation();

-- Stories: every story carries author + audience and the table already has
-- an audience column. Enqueue all public stories.

create or replace function public.fn_stories_enqueue_moderation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if coalesce(new.audience, 'friends') != 'public' then
        return new;
    end if;
    if new.media_url is not null then
        -- We don't know image vs video at this layer; the function handles
        -- both via mime-type sniff on the asset URL.
        perform public.enqueue_moderation(
            new.id, 'story', 'image', new.media_url, new.author_id, 'public');
    end if;
    if new.text_body is not null and length(new.text_body) > 0 then
        perform public.enqueue_moderation(
            new.id, 'story', 'text', null, new.author_id, 'public');
    end if;
    return new;
end;
$$;

drop trigger if exists stories_enqueue_moderation on public.stories;
create trigger stories_enqueue_moderation
    after insert on public.stories
    for each row execute function public.fn_stories_enqueue_moderation();

-- DM + Squad messages: only enqueue media (image / video / voice). Text
-- DM/squad text is in-private; we trust the local audit + the report
-- pathway (phase 3) to surface abuse.

create or replace function public.fn_dm_messages_enqueue_moderation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.media_url is null then return new; end if;
    perform public.enqueue_moderation(
        new.id, 'dm_message',
        case
            when new.kind = 'voice' then 'audio'
            when new.kind = 'video' then 'video'
            else 'image'
        end,
        new.media_url, new.sender_id, 'friends');
    return new;
end;
$$;

drop trigger if exists dm_messages_enqueue_moderation on public.dm_messages;
create trigger dm_messages_enqueue_moderation
    after insert on public.dm_messages
    for each row execute function public.fn_dm_messages_enqueue_moderation();

create or replace function public.fn_squad_messages_enqueue_moderation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.media_url is null then return new; end if;
    perform public.enqueue_moderation(
        new.id, 'squad_message',
        case
            when new.kind = 'voice' then 'audio'
            when new.kind = 'video' then 'video'
            else 'image'
        end,
        new.media_url, new.sender_id, 'squad');
    return new;
end;
$$;

drop trigger if exists squad_messages_enqueue_moderation on public.squad_messages;
create trigger squad_messages_enqueue_moderation
    after insert on public.squad_messages
    for each row execute function public.fn_squad_messages_enqueue_moderation();
