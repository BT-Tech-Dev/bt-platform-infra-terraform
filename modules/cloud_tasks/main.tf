# =============================================================================
# modules/cloud_tasks/main.tf - MS-05 OCR pilot queue
#
# Cloud Tasks dispatches OCR extraction work from production-ingestion-service
# to the private OCR worker. Automatic enqueue remains disabled in Cloud Run
# for the first rollout.
# =============================================================================

resource "google_cloud_tasks_queue" "ocr_extraction" {
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

resource "google_cloud_tasks_queue_iam_member" "ocr_ingest_enqueuer" {
  project  = var.project_id
  location = google_cloud_tasks_queue.ocr_extraction.location
  name     = google_cloud_tasks_queue.ocr_extraction.name
  role     = "roles/cloudtasks.enqueuer"
  member   = "serviceAccount:${var.ocr_ingest_service_account_email}"
}
