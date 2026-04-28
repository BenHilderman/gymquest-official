-- v4.3 Step 6 — Storage RLS for story-media, voice-reactions, photo-reactions.
-- post-media + profile-photos policies are in 20260321042538_storage_policies.sql.
-- Audience scoping is enforced upstream (posts.audience, story owner, dm/squad thread membership).

drop policy if exists "v43_media_read" on storage.objects;
create policy "v43_media_read" on storage.objects for select using (
  bucket_id in ('story-media','voice-reactions','photo-reactions')
  and auth.uid() is not null
);

drop policy if exists "v43_media_upload_own_folder" on storage.objects;
create policy "v43_media_upload_own_folder" on storage.objects for insert with check (
  bucket_id in ('story-media','voice-reactions','photo-reactions')
  and auth.uid() is not null
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "v43_media_delete_own" on storage.objects;
create policy "v43_media_delete_own" on storage.objects for delete using (
  bucket_id in ('story-media','voice-reactions','photo-reactions')
  and auth.uid() is not null
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- v4.3 Step 7 — Schedule expire_photo_reactions() every 15 minutes via pg_cron.
create extension if not exists pg_cron;

do $$
begin
  perform cron.unschedule('expire-photo-reactions');
exception when others then null;
end$$;

select cron.schedule(
  'expire-photo-reactions',
  '*/15 * * * *',
  $$select public.expire_photo_reactions();$$
);
