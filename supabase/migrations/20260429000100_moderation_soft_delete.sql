-- v4.3 content-safety phase 2B — soft-delete + notify on rejection.
--
-- When `moderate-media` writes verdict = 'rejected' onto a
-- moderation_audits row, this trigger:
--   1. Soft-hides the source content (Posts.is_hidden_by_moderation
--      / Comments.is_hidden_by_moderation / Stories.is_hidden_by_moderation
--      / DMMessages, SquadMessages similarly).
--   2. Writes a `notifications` row so the existing send-push
--      Edge Function fires an APNs alert: "your content was held — appeal".
--
-- Authors can appeal via Phase 3 UI; appeals flip `is_hidden_by_moderation`
-- false and write a `moderation_appeals` row for the human review queue.

-- =============================================================
-- Add hidden-by-moderation columns where missing
-- =============================================================
-- These mirror the SwiftData @Model field added in Phase 1B for Comment.
-- Posts / Stories / DM / Squad use the same convention.

alter table public.posts
    add column if not exists is_hidden_by_moderation boolean not null default false,
    add column if not exists moderation_verdict text;

alter table public.comments
    add column if not exists is_hidden_by_moderation boolean not null default false,
    add column if not exists moderation_verdict text;

alter table public.stories
    add column if not exists is_hidden_by_moderation boolean not null default false,
    add column if not exists moderation_verdict text;

alter table public.dm_messages
    add column if not exists is_hidden_by_moderation boolean not null default false,
    add column if not exists moderation_verdict text;

alter table public.squad_messages
    add column if not exists is_hidden_by_moderation boolean not null default false,
    add column if not exists moderation_verdict text;

-- =============================================================
-- Soft-delete + notify trigger
-- =============================================================

create or replace function public.fn_moderation_audits_handle_verdict()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_target_table text;
    v_notification_body text;
begin
    -- Only act on transitions to a final verdict.
    if new.verdict is null or new.verdict = old.verdict then
        return new;
    end if;

    -- Always-stamp the source row's verdict column so the client can
    -- read it back without joining moderation_audits.
    v_target_table := case new.content_type
        when 'post' then 'posts'
        when 'comment' then 'comments'
        when 'story' then 'stories'
        when 'dm_message' then 'dm_messages'
        when 'squad_message' then 'squad_messages'
        else null
    end;

    if v_target_table is not null then
        execute format(
            'update public.%I set moderation_verdict = $1 where id = $2',
            v_target_table
        ) using new.verdict, new.content_id;
    end if;

    if new.verdict = 'rejected' then
        -- Soft-hide the source row.
        if v_target_table is not null then
            execute format(
                'update public.%I set is_hidden_by_moderation = true where id = $1',
                v_target_table
            ) using new.content_id;
        end if;

        -- Notify the author. Body is intentionally non-specific so the
        -- author has to open the appeal sheet to see why; this avoids
        -- giving spammers free signal about which patterns we catch.
        v_notification_body := case new.content_type
            when 'post' then 'a recent post was held for review'
            when 'comment' then 'a recent comment was held for review'
            when 'story' then 'a recent story was held for review'
            when 'dm_message' then 'a recent message was held for review'
            when 'squad_message' then 'a recent squad message was held for review'
            else 'a recent post was held for review'
        end;

        insert into public.notifications
            (user_id, category, title, body, payload, created_at)
        values
            (new.author_id,
             'content_held',
             'lift ai',
             v_notification_body,
             jsonb_build_object(
                'content_id', new.content_id,
                'content_type', new.content_type,
                'audit_id', new.id,
                'reason', new.reason
             ),
             now());
    end if;

    return new;
end;
$$;

drop trigger if exists moderation_audits_handle_verdict on public.moderation_audits;
create trigger moderation_audits_handle_verdict
    after update on public.moderation_audits
    for each row execute function public.fn_moderation_audits_handle_verdict();

-- =============================================================
-- Hide soft-deleted content from RLS reads
-- =============================================================
-- Authors still see their own held content (so they can appeal) but
-- everyone else gets a filtered view. We layer this as a new policy
-- alongside whatever the table already had.

create policy "posts_hide_held_from_others"
    on public.posts
    for select
    using (
        not is_hidden_by_moderation
        or auth.uid() = author_id
    );

create policy "comments_hide_held_from_others"
    on public.comments
    for select
    using (
        not is_hidden_by_moderation
        or auth.uid() = author_id
    );

create policy "stories_hide_held_from_others"
    on public.stories
    for select
    using (
        not is_hidden_by_moderation
        or auth.uid() = author_id
    );

-- DM / squad messages: only the author + recipient(s) ever read these,
-- and the author should still see their own held message in the thread
-- so the appeal flow makes sense. Other thread participants don't see
-- a hidden message — the existing thread-membership policy + the
-- `is_hidden_by_moderation = false` clause filters them out.

create policy "dm_messages_hide_held_from_recipients"
    on public.dm_messages
    for select
    using (
        not is_hidden_by_moderation
        or auth.uid() = sender_id
    );

create policy "squad_messages_hide_held_from_recipients"
    on public.squad_messages
    for select
    using (
        not is_hidden_by_moderation
        or auth.uid() = sender_id
    );
