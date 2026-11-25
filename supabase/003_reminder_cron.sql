-- Headcount 003: run the reminder emails every 30 minutes.
-- Before running: deploy the send-reminders function and set its CRON_SECRET secret.
-- Then replace YOUR-CRON-SECRET below with that same value, and run this in the SQL Editor.
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.unschedule('headcount-reminders') where exists (select 1 from cron.job where jobname = 'headcount-reminders');
select cron.schedule('headcount-reminders', '*/30 * * * *', $$
  select net.http_post(
    url     := 'https://wkyjixmlzskiygyjgoyd.supabase.co/functions/v1/send-reminders',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', 'YOUR-CRON-SECRET'),
    body    := '{}'::jsonb
  );
$$);
