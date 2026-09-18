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
--       UTC = PHT - 8   (6:00-6:50 AM PHT roll back to 22:xx UTC the prior day)
--   Rescheduled 2026-09-16 from the earlier 7:00-9:30 AM spread to a tighter
--   06:00-06:50 AM Manila block, staggered every 5 min.
--
-- WEEKDAYS ONLY (day-of-week 0-4)
--   Jobs run Mon-Fri PHT only (service fully idle on weekends, 2026-09-16).
--   Because each job fires at 22:xx UTC = 06:xx the NEXT day Manila, the PHT
--   weekday is UTC weekday + 1. So Mon-Fri PHT = Sun-Thu UTC = dow 0-4.
--   (Do NOT write 1-5 here -- that would be Tue-Sat PHT. The Cloud Scheduler
--   keep-warm jobs DO use 1-5 because they run in Asia/Manila, not UTC.)
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

-- Get All AC Deals                             | 6:00 AM  | 22:00 UTC
select cron.schedule('n8n-get-all-ac-deals', '0 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/02b6362d-b828-4f40-908c-45e98a943a2b',
    timeout_milliseconds := 30000);
$$);

-- Get all AC Contacts                          | 6:05 AM  | 22:05 UTC
select cron.schedule('n8n-get-all-ac-contacts', '5 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/8388b39d-9c99-494e-9991-2fefb0081a87',
    timeout_milliseconds := 30000);
$$);

-- Get all AC Accounts                          | 6:10 AM  | 22:10 UTC
select cron.schedule('n8n-get-all-ac-accounts', '10 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/ae6f429c-99a2-428c-91f9-db2cb62c16c6',
    timeout_milliseconds := 30000);
$$);

-- LinkedIn Outbound Sales Automations          | 6:15 AM  | 22:15 UTC
select cron.schedule('n8n-linkedin-outbound-sales', '15 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/50798cda-7448-45bf-9168-d887756fb8c8',
    timeout_milliseconds := 30000);
$$);

-- Soc Med Follow Up Sequence                   | 6:20 AM  | 22:20 UTC
select cron.schedule('n8n-soc-med-follow-up', '20 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/be8d0706-4150-4358-8e0d-be4108b88615',
    timeout_milliseconds := 30000);
$$);

-- Cold Leads Follow Up Sequence                | 6:25 AM  | 22:25 UTC
select cron.schedule('n8n-cold-leads-follow-up', '25 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/cf04a824-5636-40ec-b75c-bb5d5ff6743c',
    timeout_milliseconds := 30000);
$$);

-- LinkedIn Comments Scraping POC Enrichment    | 6:30 AM  | 22:30 UTC
select cron.schedule('n8n-linkedin-comments-enrichment', '30 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/e7e0b196-e1a4-4340-8af7-c6eb93509e46',
    timeout_milliseconds := 30000);
$$);

-- Cold Leads Scraper                           | 6:35 AM  | 22:35 UTC
select cron.schedule('n8n-cold-leads-scraper', '35 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/f5ca40e6-06cf-42a0-a829-0a938c03bebc',
    timeout_milliseconds := 30000);
$$);

-- Insta Story Scraper                          | 6:40 AM  | 22:40 UTC
select cron.schedule('n8n-insta-story-scraper', '40 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/c2fa45b3-49b1-496b-9dd0-8193897caa2f',
    timeout_milliseconds := 30000);
$$);

-- Insta Story Scraper: Log to sheet and notify Liv | 7:00 AM | 23:00 UTC
-- NOTE: this job (jobid 14) was created via the Supabase dashboard UI, so its
--   jobname is the human-readable string below, NOT the n8n- slug convention.
--   Do NOT put a "-- comment" INSIDE the url string -- it becomes part of the URL
--   and net.http_get rejects it ("Malformed input to a URL function"). That bug
--   silently killed every run Sep 15-17 2026 before it was fixed.
select cron.schedule('Insta Story Scraper: Log to sheet and notify Liv', '0 23 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/57fe4813-a476-4f26-b27b-e011e5c17092',
    timeout_milliseconds := 30000);
$$);

-- Sales Daily Email Notification               | 6:50 AM  | 22:50 UTC
select cron.schedule('n8n-sales-daily-email-notification', '50 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/7dc5b0a7-071a-4a66-99e4-ab48cc23aeff',
    timeout_milliseconds := 30000);
$$);

-- ---------------------------------------------------------------------------
-- AC Notes Automation (Follow up sequence)  (added 2026-09-18)
--   Four Soc Med "AC notes tagging" webhooks, staggered 6:40-6:55 AM Manila.
--   These share the 22:40 and 22:50 UTC minutes with existing jobs (insta-story
--   -scraper / sales-daily-email); pg_cron fires each named job independently and
--   the whole block is inside the 05:50-07:05 Manila keep-warm window, so no cold
--   start. dow 0-4 (Sun-Thu UTC = Mon-Fri PHT), same rule as the block above.
-- ---------------------------------------------------------------------------

-- AC Notes: Soc Med email intro tagging       | 6:40 AM  | 22:40 UTC
select cron.schedule('n8n-ac-notes-intro', '40 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/3c2a741d-656f-41fe-846e-a84d4b0ae530',
    timeout_milliseconds := 30000);
$$);

-- AC Notes: Soc Med 1st follow up tagging     | 6:45 AM  | 22:45 UTC
select cron.schedule('n8n-ac-notes-1st-followup', '45 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/968fa7b5-c233-4488-b09a-8b57975dd512',
    timeout_milliseconds := 30000);
$$);

-- AC Notes: Soc Med 2nd follow up tagging     | 6:50 AM  | 22:50 UTC
select cron.schedule('n8n-ac-notes-2nd-followup', '50 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/f8e3664b-0c56-479e-8702-e4bfa6a8aeba',
    timeout_milliseconds := 30000);
$$);

-- AC Notes: Soc Med 3rd follow up tagging     | 6:55 AM  | 22:55 UTC
select cron.schedule('n8n-ac-notes-3rd-followup', '55 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/2a30ffcf-4f94-44f4-9a83-59ec3b18abf4',
    timeout_milliseconds := 30000);
$$);

-- ---------------------------------------------------------------------------
-- NOT SCHEDULED (kept here for reference, intentionally NOT live)
-- ---------------------------------------------------------------------------
-- n8n-batch-mailer (webhook 18166a62-3c79-4f66-8597-59ff30469cbe) is NOT in the
--   live cron set as of 2026-09-16. To schedule it, add a cron.schedule() block
--   above with an unused 5-minute slot (e.g. '55 22 * * *' = 6:55 AM PHT).
-- The two intraday-recurring jobs (Email Handling Agent every 5 min, Action Items
--   Automation every 15 min, 7 AM-4 PM Manila) were REMOVED on 2026-09-14 when
--   those workflows moved to a local Docker n8n. Do NOT re-add them here — running
--   them every few minutes keeps the container awake ~9 h/day (~$12-18/mo).

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
