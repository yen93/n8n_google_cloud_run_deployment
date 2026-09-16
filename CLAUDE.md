# CLAUDE.md

Guidance for a future Claude session working in this repo.

## What this project is
Deployment tooling for running **n8n** (workflow automation) on **Google Cloud Run**,
backed by a **Supabase** free-tier Postgres. Migrated 2026-09-11 from a local Docker
n8n (SQLite at `D:\n8n_data`). This repo holds the image definition and docs — the
actual n8n state (workflows/credentials) lives in Supabase, not here.

See `DEPLOYMENT.md` for the full runbook and `as_built.txt` for the current inventory.

## Key facts
- GCP project `claudegwscli-502400`, region `australia-southeast1`.
- Service URL: https://n8n-659687081407.australia-southeast1.run.app
- Image: `australia-southeast1-docker.pkg.dev/claudegwscli-502400/cloud-run-source-deploy/n8n:2.22.6`
- Supabase project ref `uwsncuowtzydylfabikj` (region ap-southeast-2), via session pooler port 5432.
- Secrets in GCP Secret Manager: `n8n-encryption-key`, `supabase-db-password`, `supabase-ca-cert`. Never hardcode these; never regenerate the encryption key (imported credentials decrypt with it).

## Non-obvious gotchas (these cost real debugging time — do not relearn them)
1. **CPU must be always-allocated** (`--no-cpu-throttling`). With default CPU
   throttling + scale-to-zero, n8n's background DB ping timer freezes between
   requests and its 5s ping race fires falsely -> persistent "Database is not
   ready!" 503s even though the DB is fine. Always-allocated CPU is the fix.
   NOTE: `--no-cpu-throttling` does NOT keep the instance alive — it only stops
   CPU throttling *within* a live instance. With `min-instances=0` the container
   still scales to zero after ~15 min idle (see scheduling gotcha #6).
2. **SSL to Supabase:** `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false` does NOT work
   — n8n parses the string as truthy, so it silently attempts a plaintext
   connection the pooler never answers (-> connection timeout). You MUST provide
   Supabase's CA via `DB_POSTGRESDB_SSL_CA` (it uses a private CA not in Node's
   trust store). n8n's connection builder only creates an SSL object when a
   ca/cert/key is set OR rejectUnauthorized is false.
3. **Editor stuck "Offline / No network connection", can't save — Cloud Run
   reserves `/healthz`.** Google's edge intercepts the exact path `/healthz` and
   returns its own 404; the request never reaches the container (verified three
   ways: an unrelated Cloud Run service in this project 404s on it too; the
   container serves `/healthz` -> `{"status":"ok"}` locally; and a `/healthz`
   request never appears in Cloud Run request logs while `/healthz/readiness`
   does). n8n's frontend heartbeat (`useBackendStatus`, 10s interval) polls the
   health endpoint, gets 404, and marks the backend offline, blocking saves.
   **Fix (applied): `N8N_ENDPOINT_HEALTH=/n8n-health`.** The frontend doesn't
   hardcode the path — it reads `endpointHealth` from `/rest/settings`, and
   `resolveFrontendHealthEndpointPath()` echoes this env var when set, so backend
   and frontend agree on the new path. Verify with
   `curl <url>/n8n-health` -> `{"status":"ok"}`.
   Two dead ends, do NOT repeat them:
   - `N8N_PATH=/n8n/` "works" for the heartbeat but half-breaks the app: REST and
     `/static/*` are NOT moved under the prefix, so `/n8n/static/base-path.js`
     returns HTML and the editor renders a blank white page.
   - `N8N_PUSH_BACKEND=sse` breaks the push connection: same-origin EventSource
     sends no `Origin` header, so n8n's origin validator rejects it with
     `500 Invalid origin!`. Default WebSocket push is fine (`GET 101`) and was
     never the problem.
5. **Windows: `gcloud` env-var values starting with `/` get mangled by Git Bash.**
   `--update-env-vars="N8N_PATH=/n8n/"` in the Bash tool silently became
   `C:\Program Files\Git\n8n\`, and `https://` became `https;\\`. Use the
   PowerShell tool for any `gcloud` command whose value contains a path or URL
   (`MSYS2_ARG_CONV_EXCL="*"` breaks gcloud's own wrapper — don't use it).
   Always read the value back with `gcloud run services describe` to confirm.
4. n8n CLI export/import over the network to Supabase is slow (imports one workflow
   at a time); expect minutes, not seconds.
4. On Windows Git Bash, `docker cp`/`docker exec` with container paths mangle under
   MSYS path conversion — prefix commands with `export MSYS_NO_PATHCONV=1`.
6. **Scheduling: n8n's in-process Schedule Trigger does NOT fire on this deploy.**
   `min-instances=0` scales the container to zero after ~15 min idle, and n8n's
   cron scheduler only runs while a container is alive — so scheduled workflows
   silently stop once the editor/browser is closed (observed: a 62-hour gap where
   nothing fired). A scaled-to-zero container cannot wake itself; you need an
   EXTERNAL caller. Chosen fix (2026-09-14): per-workflow Webhook Trigger nodes
   called daily by Supabase pg_cron + pg_net (free, in-stack) — the GET both wakes
   the container and triggers the run. See `schedule_webhooks.sql` and as_built.txt.
   - Timezone trap: `GENERIC_TIMEZONE=Australia/Sydney` but the user is in Manila
     (UTC+8), so an n8n Schedule Trigger "10:05" = 10:05 Sydney = 8:05 AM Manila.
     `pg_cron` runs in UTC and does NOT do DST, so write jobs at PHT-8
     (10:05 Manila = 02:05 UTC = `'5 2 * * *'`).
   - Day-of-week trap (weekday scheduling): the daily jobs run at 22:xx UTC =
     06:xx the NEXT day Manila, so PHT weekday = UTC weekday + 1. To run Mon-Fri
     PHT (weekends idle, set 2026-09-16) the pg_cron dow must be `0-4` (Sun-Thu
     UTC), NOT `1-5`. But the Cloud Scheduler keep-warm jobs (gotcha #7) DO use
     `1-5` because they run in Asia/Manila, not UTC. Same intent, different dow.
   - `pg_net` is async fire-and-forget: cron reports success once the request is
     QUEUED, not once n8n answers. Confirm real HTTP status in `net._http_response`,
     not just `cron.job_run_details`. Cold starts are slow — set
     `timeout_milliseconds := 30000` on the calls.
7. **Keep-warm window: two Cloud Scheduler jobs toggle `min-instances` (added
   2026-09-16).** `n8n-scale-up` (05:50 Mon-Fri Manila) sets min=1,
   `n8n-scale-down` (07:05 Mon-Fri Manila) sets min=0, bracketing the 06:00–06:50
   pg_cron batch so the first run isn't a cold start. Weekday-only (dow 1-5) since
   2026-09-16 — weekends fully idle. Set up by `cloud_run_scale_window.ps1`;
   Scheduler runs jobs in `Asia/Manila` directly (no PHT-8 math). Non-obvious traps
   that cost real time — do NOT relearn them:
   - Change min-instances via a **narrow field-mask PATCH**
     (`updateMask=template.scaling.minInstanceCount`), NOT `gcloud run services
     update` — the mask preserves everything else, so it can't drop
     `--no-cpu-throttling` (gotcha #1). If you ever use gcloud by hand, re-pass it.
   - This gcloud build's `scheduler jobs --http-method` has **no PATCH** option.
     POST instead with header `X-HTTP-Method-Override: PATCH` (googleapis.com honors
     it → 200). And pass the JSON via `--message-body-from-file` (inline JSON
     mangles through `gcloud.cmd` on Windows).
   - The scaler SA needs BOTH `roles/run.admin` on the service AND
     `roles/iam.serviceAccountUser` (actAs) on the runtime SA
     `659687081407-compute@` — run.admin alone gives a silent **403** (the PATCH
     deploys a new revision as that runtime SA). Check failures in Cloud Logging
     (`resource.type="cloud_scheduler_job"`), not the job's own status.

## Build & redeploy
```
docker build -t australia-southeast1-docker.pkg.dev/claudegwscli-502400/cloud-run-source-deploy/n8n:2.22.6 .
docker push australia-southeast1-docker.pkg.dev/claudegwscli-502400/cloud-run-source-deploy/n8n:2.22.6
gcloud run services update n8n --region=australia-southeast1 --image=<that image>
```
Workflow/credential edits in the n8n UI persist to Supabase directly — no redeploy
needed. A redeploy is only for image/env/secret changes.

## Conventions
- Keep infra at $0 / free tier where possible (strong user preference). Flag any
  step that would incur recurring cost and offer the free alternative.
- The user often answers questions / supplies secrets by giving a file path to
  read, not inline. Read the file; move any secret into Secret Manager and delete
  the plaintext copy.
