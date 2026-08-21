# =============================================================================
# modules/cloud_tasks/main.tf - generic single Cloud Tasks queue + enqueuer
# binding.
#
# Generic on purpose: instantiated twice from root main.tf --
#   module "cloud_tasks"      -> OCR extraction queue (production-ingestion-service -> OCR worker)
#   module "cloud_tasks_ms05" -> MS-05 ingest queue (Bucket Watcher -> production-ingestion-service)
# Internal resource/variable/output names are queue-purpose-agnostic; each
# call site's variables carry the actual purpose (queue_name, location,
# enqueuer_service_account_email, ...).
# =============================================================================

resource "google_cloud_tasks_queue" "queue" {
  project  = var.project_id
  location = var.location
  name     = var.queue_name

  rate_limits {
    max_concurrent_dispatches = var.max_concurrent_dispatches
    max_dispatches_per_second = var.max_dispatches_per_second
  }

  retry_config {
    max_attempts       = var.max_attempts
    min_backoff        = "${var.min_retry_backoff_seconds}s"
    max_backoff        = "${var.max_retry_backoff_seconds}s"
    max_retry_duration = "${var.max_retry_duration_seconds}s"
  }

  stackdriver_logging_config {
    sampling_ratio = var.logging_sampling_ratio
  }
}

resource "google_cloud_tasks_queue_iam_member" "enqueuer" {
  project  = var.project_id
  location = google_cloud_tasks_queue.queue.location
  name     = google_cloud_tasks_queue.queue.name
  role     = "roles/cloudtasks.enqueuer"
  member   = "serviceAccount:${var.enqueuer_service_account_email}"
}

# ─── State preservation: this module was OCR-pilot-only until the MS-05 ────
# ingest queue reused it. These moved blocks keep the existing OCR queue's
# state attached to the same real GCP resource under its new generic local
# name -- no destroy/recreate, no config change, address move only.

moved {
  from = google_cloud_tasks_queue.ocr_extraction
  to   = google_cloud_tasks_queue.queue
}

moved {
  from = google_cloud_tasks_queue_iam_member.ocr_ingest_enqueuer
  to   = google_cloud_tasks_queue_iam_member.enqueuer
}
