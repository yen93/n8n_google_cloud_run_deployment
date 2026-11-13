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

-- Get linkedin_posts to be processed          | 6:30 AM  | 22:30 UTC
--   Renamed 2026-10-15 from 'n8n-linkedin-comments-enrichment' to match the real
--   n8n workflow name "Get linkedin_posts to be processed" (now jobid 40). Same
--   webhook, schedule, and always-active. Part of the LinkedIn comments-scraper
--   pipeline (see n8n-find-org-of-commentor + the comments-scraper jobs below).
select cron.schedule('n8n-get-linkedin-posts-to-be-processed', '30 22 * * 0-4', $$
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
-- AC Notes Automation: Cold Leads follow up sequence  (added 2026-09-18)
--   Five Cold Leads "AC notes tagging" webhooks (intro + 4 follow-ups),
--   staggered 6:40-7:00 AM Manila. Same n8n workflow as the Soc Med AC Notes
--   branches above (8vZG1SAYwSmcHJ2x). These share the 22:40/22:50/22:55/23:00
--   UTC minutes with existing jobs; pg_cron fires each named job independently
--   and the block is inside the 05:50-07:05 Manila keep-warm window. dow 0-4
--   (Sun-Thu UTC = Mon-Fri PHT), same rule as the blocks above.
-- ---------------------------------------------------------------------------

-- Cold Leads: email intro AC notes tagging     | 6:40 AM  | 22:40 UTC
select cron.schedule('n8n-cold-leads-notes-intro', '40 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/2dcf9990-d794-43c7-9fb4-b81f1caad619',
    timeout_milliseconds := 30000);
$$);

-- Cold Leads: 1st follow up AC notes tagging   | 6:45 AM  | 22:45 UTC
select cron.schedule('n8n-cold-leads-notes-1st-followup', '45 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/d1ab03b4-fb68-460f-8a4a-24f057c59480',
    timeout_milliseconds := 30000);
$$);

-- Cold Leads: 2nd follow up AC notes tagging   | 6:50 AM  | 22:50 UTC
select cron.schedule('n8n-cold-leads-notes-2nd-followup', '50 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/358613aa-1325-40e8-b2b2-af3ec223d579',
    timeout_milliseconds := 30000);
$$);

-- Cold Leads: 3rd follow up AC notes tagging   | 6:55 AM  | 22:55 UTC
select cron.schedule('n8n-cold-leads-notes-3rd-followup', '55 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/be7e4d56-a267-4f41-8616-c5e1be9fdab9',
    timeout_milliseconds := 30000);
$$);

-- Cold Leads: 4th follow up AC notes tagging   | 7:00 AM  | 23:00 UTC
select cron.schedule('n8n-cold-leads-notes-4th-followup', '0 23 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/2b234727-e9ac-4f3c-ab32-f010c257bed4',
    timeout_milliseconds := 30000);
$$);

-- ---------------------------------------------------------------------------
-- Find org of commentor  (added 2026-09-23; renamed + reactivated 2026-10-15)
--   Part of the LinkedIn comments-scraper pipeline. Renamed 2026-10-15 from
--   'n8n-linkedin-comment-enrichment-sheet-update' to match the real n8n workflow
--   name "Find org of commentor" (now jobid 41). Was found INACTIVE on 2026-10-15
--   (active=false, so it hadn't been firing) and REACTIVATED at user request --
--   the unschedule+reschedule recreates it active. Shares the 22:40 UTC minute
--   with existing jobs; pg_cron fires each named job independently and it's inside
--   the 05:50-07:05 Manila keep-warm window. dow 0-4 (Sun-Thu UTC = Mon-Fri PHT).
-- ---------------------------------------------------------------------------

-- Find org of commentor                        | 6:40 AM  | 22:40 UTC
select cron.schedule('n8n-find-org-of-commentor', '40 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/d13096b0-03af-400a-8f4c-1b37cdaf8a9b',
    timeout_milliseconds := 30000);
$$);

-- ---------------------------------------------------------------------------
-- Closed Threads Processing  (added 2026-09-24)
--   WEEKLY, Mondays only. Populates closed_sequence_threads with the week's
--   newly-closed/unresponsive threads. Paired with the alternate-lead-finder
--   Supabase edge function (project aivitcomiywiysrfwqxt) which runs 55 min
--   later (6:55 AM PHT) to find alternate contacts for those rows.
--   6:00 AM PHT sharp = 22:00 UTC. Monday PHT = Sunday UTC, so dow 0 (not 1).
-- ---------------------------------------------------------------------------

-- Closed Threads Processing | 6:00 AM Mon PHT | 22:00 UTC Sun
select cron.schedule('n8n-closed-threads-processing', '0 22 * * 0', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/8fe86e56-7c2f-45cd-9658-ab653f9f2559',
    timeout_milliseconds := 30000);
$$);

-- ---------------------------------------------------------------------------
-- Batch Mailers (per lead source)  (added 2026-10-09)
--   "Batch Mailer" webhooks, one per lead source. All fire together at
--   6:30 AM Manila (file "061026 new webhooks.txt"). Originally four; the 4th,
--   manually-listed-insta-leads (webhook e6ee0878), was unscheduled 2026-10-09
--   (see note below). A separate "alternate cold leads" mailer (webhook e64817f4,
--   jobid 38) was added 2026-10-09 from "091026 new webhooks.txt", and
--   ai_scraped_cold_leads (webhook d363d508, jobid 39) 2026-10-13 from
--   "131026 new webhooks.txt" -- five live.
--   They share the 22:30 UTC minute with n8n-linkedin-comments-
--   enrichment (jobid 5); pg_cron fires each named job independently and 06:30
--   AM is inside the 05:50-07:05 Manila keep-warm window, so no cold start.
--   dow 0-4 (Sun-Thu UTC = Mon-Fri PHT), same rule as the blocks above.
--   NOTE: distinct from the unscheduled n8n-batch-mailer (webhook 18166a62) below.
-- ---------------------------------------------------------------------------

-- Batch Mailer: ai_scraped_soc_med_leads      | 6:30 AM  | 22:30 UTC
select cron.schedule('n8n-batch-mailer-ai-scraped-soc-med-leads', '30 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/86d26274-f8f8-4abf-9457-e144c42d5ee1',
    timeout_milliseconds := 30000);
$$);

-- Batch Mailer: manually_found_leads          | 6:30 AM  | 22:30 UTC
select cron.schedule('n8n-batch-mailer-manually-found-leads', '30 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/49bc9abe-eaed-49ec-b749-8e051090896c',
    timeout_milliseconds := 30000);
$$);

-- Batch Mailer: AI soc med alternate leads    | 6:30 AM  | 22:30 UTC
select cron.schedule('n8n-batch-mailer-ai-soc-med-alternate-leads', '30 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/b17ac35b-0235-484b-be50-c3783ac77a8c',
    timeout_milliseconds := 30000);
$$);

-- Batch Mailer: alternate cold leads          | 6:30 AM  | 22:30 UTC
--   (added 2026-10-09, jobid 38, file "091026 new webhooks.txt")
select cron.schedule('n8n-batch-mailer-alternate-cold-leads', '30 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/e64817f4-c359-4bc2-a40f-ca9e23b92fe7',
    timeout_milliseconds := 30000);
$$);

-- Batch Mailer: ai_scraped_cold_leads         | 6:30 AM  | 22:30 UTC
--   (added 2026-10-13, jobid 39, file "131026 new webhooks.txt")
select cron.schedule('n8n-batch-mailer-ai-scraped-cold-leads', '30 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/d363d508-d222-4783-acef-35efa48240b7',
    timeout_milliseconds := 30000);
$$);

-- Batch Mailer: manually listed insta leads   | UNSCHEDULED 2026-10-09
--   (jobid 37, webhook e6ee0878-b326-4155-a9f0-fd826104b473) removed at user
--   request. To restore, re-add the cron.schedule() block below:
-- select cron.unschedule('n8n-batch-mailer-manually-listed-insta-leads');
-- select cron.schedule('n8n-batch-mailer-manually-listed-insta-leads', '30 22 * * 0-4', $$
--   select net.http_get(
--     url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/e6ee0878-b326-4155-a9f0-fd826104b473',
--     timeout_milliseconds := 30000);
-- $$);

-- ---------------------------------------------------------------------------
-- LinkedIn comments-scraper pipeline + Company Lead Finder  (added 2026-10-15)
--   Three webhooks from "151026 new webhooks.txt". The source file labelled all
--   three "Daily", but scheduled Mon-Fri (dow 0-4) at user request to match the
--   rest of the stack and stay inside the 05:50-07:05 Manila keep-warm window
--   (weekday-only; weekend runs would be cold starts). 6:00 AM shares 22:00 UTC
--   with get-all-ac-deals/insta-story-scraper, 6:30 AM shares 22:30 UTC with the
--   batch mailers -- pg_cron fires each named job independently, so collisions are
--   fine. The two comments-scraper jobs join n8n-get-linkedin-posts-to-be-processed
--   (jobid 40) and n8n-find-org-of-commentor (jobid 41) above in that pipeline.
-- ---------------------------------------------------------------------------

-- LinkedIn Company Lead Finder                 | 6:00 AM  | 22:00 UTC
select cron.schedule('n8n-linkedin-company-lead-finder', '0 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/e70fe2f8-2d48-4fca-8849-dbafcdff6164',
    timeout_milliseconds := 30000);
$$);

-- comments scraper: email finder              | 6:00 AM  | 22:00 UTC
select cron.schedule('n8n-comments-scraper-email-finder', '0 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/5ed8979a-e286-4b3a-b5f8-c9003fb2d3b5',
    timeout_milliseconds := 30000);
$$);

-- comments scraper: log email to sheet        | 6:30 AM  | 22:30 UTC
select cron.schedule('n8n-comments-scraper-log-email-to-sheet', '30 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/74242e51-395e-4086-a157-7a3977f31b58',
    timeout_milliseconds := 30000);
$$);

-- ---------------------------------------------------------------------------
-- Action Items Automation  (added 2026-10-15)
--   INTRADAY, hourly 07:00-16:00 Manila (10 runs/day), Mon-Fri. This workflow was
--   moved back onto Cloud Run (webhook 08975797...), re-introducing an intraday
--   schedule after the earlier every-15-min version was removed 2026-09-14 (see
--   NOT-SCHEDULED note below). Hourly (not every-15-min) is deliberately gentle:
--   each ping wakes the container ~15 min then it scales to zero, so ~3 h/day
--   uptime (~10 runs x 07:00-16:00) -- stays near the $0 free tier, vs the old
--   every-15-min version that kept it awake ~9 h/day (~$12-18/mo).
--   These runs are OUTSIDE the 05:50-07:05 Manila keep-warm window, so every run
--   except 07:00 is a cold start -- timeout_milliseconds := 30000 covers it.
--   Split into TWO jobs because 07:00-16:00 Manila straddles two UTC days:
--     07:00 PHT      = 23:00 UTC prior day -> dow 0-4 (Sun-Thu UTC = Mon-Fri PHT)
--     08:00-16:00 PHT = 00:00-08:00 UTC    -> dow 1-5 (Mon-Fri UTC = Mon-Fri PHT)
--   The 07:00 job shares the 0 23 UTC minute with jobid 14 + 31 (harmless).
-- ---------------------------------------------------------------------------

-- Action Items Automation: 07:00 edge | 7:00 AM PHT | 23:00 UTC prior day
select cron.schedule('n8n-action-items-automation-0700', '0 23 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/08975797-f177-4a6f-9832-238b17f6b318',
    timeout_milliseconds := 30000);
$$);

-- Action Items Automation: main block | 8:00 AM-4:00 PM PHT | 00:00-08:00 UTC
select cron.schedule('n8n-action-items-automation', '0 0-8 * * 1-5', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/08975797-f177-4a6f-9832-238b17f6b318',
    timeout_milliseconds := 30000);
$$);

-- ---------------------------------------------------------------------------
-- Gmail Samples Caching  (added 2026-11-04, jobid 47, file "041126_gmail_samples_caching.txt")
--   Daily Mon-Fri 6:00 AM Manila. Source file listed a localhost:5678 webhook URL;
--   rewritten to the Cloud Run Production URL (same /webhook/<id> path) as with every
--   other job here -- localhost would never reach the deployed container. 6:00 AM
--   shares 22:00 UTC with get-all-ac-deals / insta-story-scraper / the LinkedIn
--   6:00 jobs; pg_cron fires each named job independently, and 06:00 is inside the
--   05:50-07:05 Manila keep-warm window, so no cold start. dow 0-4 (Sun-Thu UTC =
--   Mon-Fri PHT), same rule as the blocks above.
-- ---------------------------------------------------------------------------

-- Gmail Samples Caching                        | 6:00 AM  | 22:00 UTC
select cron.schedule('n8n-gmail-samples-caching', '0 22 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/b35b875a-a6a4-4b3f-aa1f-a1976df0e74f',
    timeout_milliseconds := 30000);
$$);

-- ---------------------------------------------------------------------------
-- Education Sector Batch Mailer  (added 2026-11-13, jobid 48, file
--   "131126 education sector batch mailer.txt")
--   A "Batch Mailer" per lead source (education sector), like the batch-mailer
--   block above, but fires at 7:00 AM Manila (not 6:30). 7:00 AM PHT = 23:00 UTC
--   prior day, so dow 0-4 (Sun-Thu UTC = Mon-Fri PHT), same as the 07:00 jobs.
--   Shares the 0 23 UTC minute with jobid 14, n8n-cold-leads-notes-4th-followup,
--   and n8n-action-items-automation-0700 -- pg_cron fires each named job
--   independently, so collisions are harmless. 07:00 is at the tail of the
--   05:50-07:05 Manila keep-warm window, so no cold start.
--   NOTE: the source file first listed webhook b17ac35b (already live as jobid 36,
--   n8n-batch-mailer-ai-soc-med-alternate-leads) -- a copy-paste error; corrected
--   to the distinct dc6155e4 webhook before scheduling.
-- ---------------------------------------------------------------------------

-- Education Sector Batch Mailer                | 7:00 AM  | 23:00 UTC prior day
select cron.schedule('n8n-batch-mailer-education-sector', '0 23 * * 0-4', $$
  select net.http_get(
    url := 'https://n8n-659687081407.australia-southeast1.run.app/webhook/dc6155e4-0178-4aad-bc0e-fcb3d8f1c6c1',
    timeout_milliseconds := 30000);
$$);

-- ---------------------------------------------------------------------------
-- NOT SCHEDULED (kept here for reference, intentionally NOT live)
-- ---------------------------------------------------------------------------
-- n8n-batch-mailer (webhook 18166a62-3c79-4f66-8597-59ff30469cbe) is NOT in the
--   live cron set as of 2026-09-16. To schedule it, add a cron.schedule() block
--   above with an unused 5-minute slot (e.g. '55 22 * * *' = 6:55 AM PHT).
-- Email Handling Agent (every 5 min) was REMOVED on 2026-09-14 when it moved to a
--   local Docker n8n. Do NOT re-add it here — every few minutes keeps the container
--   awake ~9 h/day (~$12-18/mo).
-- Action Items Automation was ALSO removed 2026-09-14 (it was every 15 min) but was
--   re-added 2026-10-15 as an HOURLY 07:00-16:00 Mon-Fri schedule (see the block
--   above) after moving back onto Cloud Run — hourly is cheap enough to stay near
--   the free tier; every-15-min was not.

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
