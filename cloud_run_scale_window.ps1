# ============================================================================
# cloud_run_scale_window.ps1
# Keep the n8n Cloud Run service WARM during the PH morning batch window.
# ============================================================================
# WHAT THIS DOES
#   Provisions two Cloud Scheduler jobs that flip the service's min-instances
#   via the Cloud Run Admin API v2:
#     - n8n-scale-up    05:50 Asia/Manila -> min-instances = 1  (ON)
#     - n8n-scale-down  07:05 Asia/Manila -> min-instances = 0  (OFF)
#   This guarantees a warm instance bracketing the 06:00-06:50 pg_cron webhook
#   batch (see schedule_webhooks.sql), then releases it to scale-to-zero.
#   Provisioned + verified live 2026-09-16 (ON->minScale=1, OFF->minScale=0,
#   cpu-throttling stayed false throughout).
#
# WHY THE ADMIN API (not `gcloud run services update`)
#   Cloud Scheduler can only make HTTP calls. A narrow field-mask PATCH
#   (updateMask=template.scaling.minInstanceCount) updates ONLY that field and
#   preserves everything else -- critically the always-allocated CPU
#   (--no-cpu-throttling, CLAUDE.md gotcha #1). A raw gcloud update would
#   re-specify the service and risk dropping --no-cpu-throttling.
#
# TWO WINDOWS QUIRKS THIS SCRIPT WORKS AROUND (both learned the hard way):
#   1. This gcloud build's `scheduler jobs` --http-method does NOT allow PATCH
#      (only GET/POST/PUT/DELETE/HEAD). So we POST with an
#      `X-HTTP-Method-Override: PATCH` header, which the googleapis.com frontend
#      honors and turns back into a PATCH. Verified: returns HTTP 200.
#   2. Passing inline JSON through gcloud.cmd on Windows mangles the quotes.
#      We write the body to a file and use --message-body-from-file instead.
#
# IAM the scaler SA needs (BOTH are required -- run.admin alone gives 403):
#   - roles/run.admin on the n8n SERVICE (resource-scoped, not project-wide)
#   - roles/iam.serviceAccountUser (actAs) on the service's RUNTIME SA
#     (the compute SA) -- because the PATCH deploys a new revision as that SA.
#
# COST: $0. Cloud Scheduler free tier = 3 jobs/mo (we use 2). min-instances=1
#   for ~75 min/day is within the Cloud Run free tier.
#
# RUN THIS FROM POWERSHELL (not Git Bash -- it mangles the `://` and `/` in the
# URI; CLAUDE.md gotcha #5). Requires owner / run.admin + IAM admin. Idempotent:
# safe to re-run (creates or updates the SA, bindings, and jobs).
# ============================================================================

$ErrorActionPreference = "Stop"

# --- Config (edit here) -----------------------------------------------------
$PROJECT      = "claudegwscli-502400"
$PROJECT_NUM  = "659687081407"
$REGION       = "australia-southeast1"
$SERVICE      = "n8n"
$SA_NAME      = "cloud-run-scaler"
$SA_EMAIL     = "$SA_NAME@$PROJECT.iam.gserviceaccount.com"
$SCHED_AGENT  = "service-$PROJECT_NUM@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
$RUNTIME_SA   = "$PROJECT_NUM-compute@developer.gserviceaccount.com"  # n8n runtime SA

# ON/OFF times are in Asia/Manila (no DST). cron = "min hour * * dow".
# Weekdays only (1-5 = Mon-Fri): keep the service fully idle on weekends PHT.
# NOTE: because Scheduler runs in Asia/Manila, dow 1-5 IS Mon-Fri PHT directly --
# unlike the pg_cron webhook jobs, which run at 22:xx UTC and must use dow 0-4 to
# hit Mon-Fri PHT mornings (see schedule_webhooks.sql).
$ON_SCHEDULE  = "50 5 * * 1-5"   # 05:50 Mon-Fri Manila -> min-instances = 1
$OFF_SCHEDULE = "5 7 * * 1-5"    # 07:05 Mon-Fri Manila -> min-instances = 0
$TZ           = "Asia/Manila"

$URI = "https://run.googleapis.com/v2/projects/$PROJECT/locations/$REGION/services/$SERVICE`?updateMask=template.scaling.minInstanceCount"
$HEADERS = "Content-Type=application/json,X-HTTP-Method-Override=PATCH"

# Body files (avoids Windows inline-JSON quote mangling).
$bodyOn  = Join-Path $env:TEMP "n8n_scale_on.json"
$bodyOff = Join-Path $env:TEMP "n8n_scale_off.json"
'{"template":{"scaling":{"minInstanceCount":1}}}' | Out-File -FilePath $bodyOn  -Encoding ascii -NoNewline
'{"template":{"scaling":{"minInstanceCount":0}}}' | Out-File -FilePath $bodyOff -Encoding ascii -NoNewline

# --- 1. Enable Cloud Scheduler ----------------------------------------------
gcloud services enable cloudscheduler.googleapis.com --project=$PROJECT
# NOTE: `gcloud beta services identity create` would force-create the scheduler
# P4SA, but the `beta` component isn't installed here and can't be added
# non-interactively. Not needed -- enabling the API creates the agent, and the
# token-creator binding below references its deterministic address directly.
# (Cloud Run Admin API run.googleapis.com is already enabled -- the service exists.)

# --- 2. Least-privilege service account + IAM -------------------------------
$saExists = gcloud iam service-accounts list --project=$PROJECT --filter="email=$SA_EMAIL" --format="value(email)"
if (-not $saExists) {
  gcloud iam service-accounts create $SA_NAME `
    --project=$PROJECT `
    --display-name="Cloud Scheduler -> n8n min-instances toggler"
}

# (a) run.admin scoped to the n8n SERVICE only (not project-wide).
gcloud run services add-iam-policy-binding $SERVICE `
  --region=$REGION --project=$PROJECT `
  --member="serviceAccount:$SA_EMAIL" --role="roles/run.admin"

# (b) actAs on the runtime SA -- REQUIRED, or the PATCH 403s (the new revision
#     deploys as this SA).
gcloud iam service-accounts add-iam-policy-binding $RUNTIME_SA `
  --project=$PROJECT `
  --member="serviceAccount:$SA_EMAIL" --role="roles/iam.serviceAccountUser"

# (c) let Cloud Scheduler mint OAuth tokens as the scaler SA.
gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL `
  --project=$PROJECT `
  --member="serviceAccount:$SCHED_AGENT" --role="roles/iam.serviceAccountTokenCreator"

# --- 3. The two scheduler jobs (create or update) ---------------------------
function Set-SchedulerJob($name, $schedule, $bodyFile) {
  $exists = gcloud scheduler jobs describe $name --location=$REGION --project=$PROJECT --format="value(name)" 2>$null
  $verb = if ($exists) { "update" } else { "create" }
  gcloud scheduler jobs $verb http $name `
    --project=$PROJECT --location=$REGION `
    --schedule=$schedule --time-zone=$TZ `
    --uri=$URI `
    --http-method=POST `
    --headers=$HEADERS `
    --message-body-from-file=$bodyFile `
    --oauth-service-account-email=$SA_EMAIL
}

Set-SchedulerJob "n8n-scale-up"   $ON_SCHEDULE  $bodyOn
Set-SchedulerJob "n8n-scale-down" $OFF_SCHEDULE $bodyOff

Write-Host "`nDone. Verify with:"
Write-Host "  gcloud scheduler jobs run n8n-scale-up --location=$REGION --project=$PROJECT"
Write-Host "  gcloud run services describe $SERVICE --region=$REGION --format=`"value(spec.template.metadata.annotations['autoscaling.knative.dev/minScale'])`""
Write-Host "    -> expect 1 (and cpu-throttling annotation still 'false')"
Write-Host "  # confirm the HTTP result the scheduler got (expect 200):"
Write-Host "  gcloud logging read 'resource.type=\`"cloud_scheduler_job\`" AND resource.labels.job_id=\`"n8n-scale-up\`"' --limit=1 --format='value(httpRequest.status)' --freshness=1h"

# ============================================================================
# TEARDOWN (uncomment to remove everything this script created)
# ============================================================================
# gcloud scheduler jobs delete n8n-scale-up   --location=$REGION --project=$PROJECT --quiet
# gcloud scheduler jobs delete n8n-scale-down --location=$REGION --project=$PROJECT --quiet
# gcloud run services update $SERVICE --region=$REGION --min-instances=0 --no-cpu-throttling
# gcloud iam service-accounts delete $SA_EMAIL --project=$PROJECT --quiet
#   (the manual `gcloud run services update` above MUST keep --no-cpu-throttling)
# ============================================================================
