-- AFTER INSERT trigger on public.notifications: async POST to send-push edge function.
-- Trigger fails soft if pg_net or the edge function aren't reachable, so notification
-- inserts never fail because of push delivery issues.

create extension if not exists pg_net;

create or replace function public.notify_send_push() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform net.http_post(
    url := 'https://sdcvbubthjavmmicoigu.supabase.co/functions/v1/send-push',
    body := jsonb_build_object('notification_id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json'),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  return new;
end$$;

drop trigger if exists trg_notifications_send_push on public.notifications;
create trigger trg_notifications_send_push
  after insert on public.notifications
  for each row execute function public.notify_send_push();
