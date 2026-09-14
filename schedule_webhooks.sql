-- ============================================================================
-- Schedule n8n webhook triggers via Supabase pg_cron + pg_net
-- Target DB: Supabase project uwsncuowtzydylfabikj (n8n-production)
-- ============================================================================
-- WHAT THIS DOES
--   Creates one daily pg_cron job per n8n webhook. Each job fires an HTTP GET
--   at the webhook's Production URL, which BOTH wakes the scale-to-zero Cloud
--   Run container AND triggers the workflow. Replaces n8n's in-process Schedule
--   Trigger (which can't fire while the container is asleep).
--
-- TIMEZONE
--   pg_cron runs in UTC and does NOT adjust for DST. All times below are the
--   UTC equivalent of the requested Philippine time (PHT = UTC+8, no DST):
--       UTC = PHT - 8   (7:00-7:45 AM PHT roll back to 23:xx UTC the prior day)
--
-- ASSUMPTION
--   Every webhook node is HTTP method GET with Authentication = None (matches
--   the Soc Med Follow Up node that was inspected). If any node is set to POST,
--   swap net.http_get -> net.http_post for that job, or GET will return 404.
--   If any node later gets Header Auth, add a headers := jsonb_build_object(...)
--   argument reading the token from Supabase Vault.
--
-- IDEMPOTENT
--   cron.schedule() upserts by job name, so re-running this script just updates
--   the existing schedules. Safe to run repeatedly.
-- ============================================================================

-- One-time: enable the extensions (no-op if already enabled)
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---------------------------------------------------------------------------
-- Schedules  (job name                         | PHT      | UTC cron)
-- ---------------------------------------------------------------------------

-- LinkedIn Outbound Sales Automations          | 7:00 AM  | 23:00 UTC
select cron.schedule('n8n-linkedin-outbound-sales', '0 23 * * *', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/50798cda-7448-45bf-9168-d887756fb8c8',
    timeout_milliseconds := 30000);
$$);

-- Soc Med Follow Up Sequence                   | 7:15 AM  | 23:15 UTC
select cron.schedule('n8n-soc-med-follow-up', '15 23 * * *', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/be8d0706-4150-4358-8e0d-be4108b88615',
    timeout_milliseconds := 30000);
$$);

-- Cold Leads Follow Up Sequence                | 7:30 AM  | 23:30 UTC
select cron.schedule('n8n-cold-leads-follow-up', '30 23 * * *', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/cf04a824-5636-40ec-b75c-bb5d5ff6743c',
    timeout_milliseconds := 30000);
$$);

-- LinkedIn Comments Scraping POC Enrichment    | 7:45 AM  | 23:45 UTC
select cron.schedule('n8n-linkedin-comments-enrichment', '45 23 * * *', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/e7e0b196-e1a4-4340-8af7-c6eb93509e46',
    timeout_milliseconds := 30000);
$$);

-- Cold Leads Scraper                           | 8:00 AM  | 00:00 UTC
select cron.schedule('n8n-cold-leads-scraper', '0 0 * * *', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/f5ca40e6-06cf-42a0-a829-0a938c03bebc',
    timeout_milliseconds := 30000);
$$);

-- Get All AC Deals                             | 8:15 AM  | 00:15 UTC
select cron.schedule('n8n-get-all-ac-deals', '15 0 * * *', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/02b6362d-b828-4f40-908c-45e98a943a2b',
    timeout_milliseconds := 30000);
$$);

-- Get all AC Contacts                          | 8:30 AM  | 00:30 UTC
select cron.schedule('n8n-get-all-ac-contacts', '30 0 * * *', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/8388b39d-9c99-494e-9991-2fefb0081a87',
    timeout_milliseconds := 30000);
$$);

-- Get all AC Accounts                          | 8:45 AM  | 00:45 UTC
select cron.schedule('n8n-get-all-ac-accounts', '45 0 * * *', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/ae6f429c-99a2-428c-91f9-db2cb62c16c6',
    timeout_milliseconds := 30000);
$$);

-- Insta Story Scraper                          | 9:00 AM  | 01:00 UTC
select cron.schedule('n8n-insta-story-scraper', '0 1 * * *', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/c2fa45b3-49b1-496b-9dd0-8193897caa2f',
    timeout_milliseconds := 30000);
$$);

-- Batch Mailer                                 | 9:15 AM  | 01:15 UTC
select cron.schedule('n8n-batch-mailer', '15 1 * * *', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/18166a62-3c79-4f66-8597-59ff30469cbe',
    timeout_milliseconds := 30000);
$$);

-- Sales Daily Email Notification               | 9:30 AM  | 01:30 UTC
select cron.schedule('n8n-sales-daily-email-notification', '30 1 * * *', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/7dc5b0a7-071a-4a66-99e4-ab48cc23aeff',
    timeout_milliseconds := 30000);
$$);

-- Insta Story Scraper: Log to sheet and notify Liv | 9:30 AM | 01:30 UTC
select cron.schedule('n8n-insta-story-scraper-log-notify-liv', '30 1 * * *', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/57fe4813-a476-4f26-b27b-e011e5c17092',
    timeout_milliseconds := 30000);
$$);

-- ============================================================================
-- VERIFY  (run after the above)
-- ============================================================================
-- List all scheduled jobs:
--   select jobid, jobname, schedule, active from cron.job order by schedule;
--
-- See recent runs (did cron fire?):
--   select jobname, status, start_time, end_time
--   from cron.job_run_details order by start_time desc limit 30;
--
-- See HTTP responses from n8n (did it return 200?):
--   select id, status_code, created from net._http_response
--   order by created desc limit 30;
--
-- ============================================================================
-- REMOVE a job / all jobs (if needed)
-- ============================================================================
--   select cron.unschedule('n8n-soc-med-follow-up');
--
--   -- unschedule every job created by this script:
--   select cron.unschedule(jobname) from cron.job where jobname like 'n8n-%';
-- ============================================================================
