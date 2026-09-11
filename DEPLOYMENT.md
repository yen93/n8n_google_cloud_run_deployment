# n8n on Google Cloud Run — Deployment Reference

## What runs where
- **Service URL:** https://n8n-659687081407.australia-southeast1.run.app
- **GCP project:** claudegwscli-502400 · **region:** australia-southeast1
- **Cloud Run service:** `n8n` (min-instances=0, max-instances=1, CPU always-allocated, 1Gi / 1 CPU)
- **Image:** australia-southeast1-docker.pkg.dev/claudegwscli-502400/cloud-run-source-deploy/n8n:2.22.6
  (n8n 2.22.6 + 5 community node packages baked in — see `Dockerfile` / `nodes/package.json`)
- **Backend DB:** Supabase Postgres project `n8n-production` (ref `uwsncuowtzydylfabikj`, region ap-southeast-2 / Sydney), connected via the session pooler `aws-0-ap-southeast-2.pooler.supabase.com:5432`, user `postgres.uwsncuowtzydylfabikj`, SSL verified against Supabase's CA.

## Secrets (GCP Secret Manager)
- `n8n-encryption-key` — the SAME key as the old local instance (`D:\n8n_data\config`); required for imported credentials to decrypt.
- `supabase-db-password` — Supabase DB password.
- `supabase-ca-cert` — Supabase's CA chain (intermediate+root), wired to `DB_POSTGRESDB_SSL_CA`.

## Migration done
- 52 workflows + 26 credentials imported into Supabase (execution history NOT migrated — left on `D:\n8n_data`).
- All 29 live Schedule Triggers across the 13 formerly-active workflows were DISABLED and every workflow set inactive (per request, to keep Cloud Scheduler cost at $0). Re-add triggers manually in the editor.
- Execution pruning enabled (`EXECUTIONS_DATA_PRUNE=true`, `EXECUTIONS_DATA_MAX_AGE=336h` = 14 days) so the DB won't balloon like the old 1.5GB SQLite.
- RLS enabled on all Supabase tables (closes the auto REST API; n8n's direct Postgres connection is unaffected).

## Gotchas learned (important)
- **CPU must stay always-allocated** (`--no-cpu-throttling`). With default throttling + scale-to-zero, n8n's background DB ping timer freezes between requests and its 5s ping race fires falsely → "Database is not ready!" 503s. Always-allocated CPU fixes it.
- **SSL:** `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false` does NOT work (n8n parses the string as truthy). Must provide the real CA via `DB_POSTGRESDB_SSL_CA`. Supabase uses a private CA not in Node's default trust store.
- **Editor stuck "Offline / No network connection" (THE big one):** Google Cloud Run **reserves the exact path `/healthz` at its edge** and returns its own 404 — the request never reaches the container (confirmed: the unrelated `dashboard` service 404s on it too; the container serves `/healthz` fine locally; and a `/healthz` request never shows up in Cloud Run request logs). n8n's frontend heartbeat polls the health endpoint every 10s, gets 404, and declares the backend offline, which blocks saving.
  **Fix: `N8N_ENDPOINT_HEALTH=/n8n-health`.** The frontend reads the path from `endpointHealth` in `/rest/settings` rather than hardcoding it, so this one env var moves both server and client off the reserved path. Verify: `curl <url>/n8n-health` -> `{"status":"ok"}`.
  - Dead ends (don't repeat): `N8N_PATH=/n8n/` fixes the heartbeat but leaves REST and `/static/*` at root, so the editor renders blank. `N8N_PUSH_BACKEND=sse` breaks the push (same-origin EventSource sends no `Origin` header -> `500 Invalid origin!`); the default WebSocket was always fine (`GET 101`).
- **Windows gotcha:** `gcloud` env-var values starting with `/` or containing `://` get mangled by Git Bash path conversion. Use PowerShell for those commands and read the value back with `gcloud run services describe` to confirm.

## Manual follow-ups still needed
1. **Create owner login** — open the URL; it prompts for first-run owner account setup (user accounts aren't part of workflow/credential import).
2. **Re-authorize Google OAuth2 credentials** (gmail, drive, docs, sheets, chat): add the Cloud Run URL as an authorized redirect URI on the Google OAuth client, then reconnect each credential in the n8n UI.
3. **Re-add triggers** on the workflows you want active, then toggle them Active.
4. **Old local instance** (`n8n` container + `D:\n8n_data`) left intact as backup — don't delete until Cloud Run has proven stable.

## Redeploying (after Dockerfile / node changes)
```
cd C:\Users\Cloverly\claude_code\n8n_google_cloud_run_deployment
docker build -t australia-southeast1-docker.pkg.dev/claudegwscli-502400/cloud-run-source-deploy/n8n:2.22.6 .
docker push australia-southeast1-docker.pkg.dev/claudegwscli-502400/cloud-run-source-deploy/n8n:2.22.6
gcloud run services update n8n --region=australia-southeast1 --image=australia-southeast1-docker.pkg.dev/claudegwscli-502400/cloud-run-source-deploy/n8n:2.22.6
```
Workflow/credential edits made in the UI persist to Supabase directly — no redeploy needed.
