-- ============================================================
-- v4.3 Phase 1.6 — Photo reaction expiry (design §9: 7-day server expiry)
-- ============================================================

-- Sweep function: nulls out media refs (and rows) past expiry.
create or replace function public.expire_photo_reactions()
returns integer
language plpgsql
security definer
as $$
declare
  expired_count integer := 0;
  c integer;
begin
  -- Per-target tables. Keep the row but null the media so a
  -- "this reaction expired" UI state remains.
  update public.reactions
     set photo_data_ref = null
   where photo_expires_at is not null
     and photo_expires_at < now()
     and photo_data_ref is not null;
  get diagnostics c = row_count;
  expired_count := expired_count + c;

  update public.dm_message_reactions
     set photo_data_ref = null
   where photo_expires_at is not null
     and photo_expires_at < now()
     and photo_data_ref is not null;
  get diagnostics c = row_count;
  expired_count := expired_count + c;

  update public.squad_message_reactions
     set photo_data_ref = null
   where photo_expires_at is not null
     and photo_expires_at < now()
     and photo_data_ref is not null;
  get diagnostics c = row_count;
  expired_count := expired_count + c;

  update public.comment_reactions
     set photo_data_ref = null
   where photo_expires_at is not null
     and photo_expires_at < now()
     and photo_data_ref is not null;
  get diagnostics c = row_count;
  expired_count := expired_count + c;

  return expired_count;
end;
$$;

-- Helper: schedule via Supabase pg_cron from the dashboard or by running
--   select cron.schedule('photo-expiry', '*/15 * * * *', $$select public.expire_photo_reactions();$$);
-- pg_cron is enabled in newer Supabase projects. If unavailable, run the
-- function from a Supabase Edge Function on a 15-minute cadence instead.

-- Audit-test helper: count surface-violation attempts. Used by a CI check
-- to assert zero forbidden surfaces appeared in `discover_engine_renders`.
create or replace function public.discover_engine_forbidden_surface_count()
returns table(surface text, count integer)
language sql
stable
as $$
  select surface::text, count(*)::int
    from public.discover_engine_renders
   where surface not in ('discover_watch','discover_friends','discover_tips',
                          'stories_public_optin','friends_feed_empty','plus_wod','onboarding_reel')
   group by 1;
$$;
