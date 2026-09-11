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
2. **SSL to Supabase:** `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false` does NOT work
   — n8n parses the string as truthy, so it silently attempts a plaintext
   connection the pooler never answers (-> connection timeout). You MUST provide
   Supabase's CA via `DB_POSTGRESDB_SSL_CA` (it uses a private CA not in Node's
   trust store). n8n's connection builder only creates an SSL object when a
   ca/cert/key is set OR rejectUnauthorized is false.
3. n8n CLI export/import over the network to Supabase is slow (imports one workflow
   at a time); expect minutes, not seconds.
4. On Windows Git Bash, `docker cp`/`docker exec` with container paths mangle under
   MSYS path conversion — prefix commands with `export MSYS_NO_PATHCONV=1`.

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
