-- v4.3 storage buckets: story-media, voice-reactions, photo-reactions (all private)
-- profile-photos and post-media already exist from earlier setup.
insert into storage.buckets (id, name, public)
values
  ('story-media', 'story-media', false),
  ('voice-reactions', 'voice-reactions', false),
  ('photo-reactions', 'photo-reactions', false)
on conflict (id) do nothing;
