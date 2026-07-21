output "sa_parser_email" {
  description = "Email service account BIM parser"
  value       = google_service_account.parser.email
}

output "sa_etl_email" {
  description = "Email service account ETL"
  value       = google_service_account.etl.email
}

output "sa_revit_export_email" {
  description = "Email service account Cloud Run Job Revit actual export"
  value       = google_service_account.revit_export.email
}

output "sa_eventarc_email" {
  description = "Email service account EventArc"
  value       = google_service_account.eventarc.email
}

output "sa_cloudbuild_email" {
  description = "Email service account Cloud Build"
  value       = google_service_account.cloudbuild.email
}

output "sa_ocr_worker_email" {
  description = "Email service account MS-05 OCR worker"
  value       = google_service_account.ocr_worker.email
}

output "sa_ocr_tasks_oidc_email" {
  description = "Email service account OIDC Cloud Tasks -> OCR worker"
  value       = google_service_account.ocr_tasks_oidc.email
}

output "gcs_service_account" {
  description = "Email del SA di sistema GCS (usato per le notifiche Pub/Sub)"
  value       = local.gcs_service_account
}

output "compute_default_sa" {
  description = "Email del Compute Engine default SA (usato da Cloud Build nei nuovi progetti GCP)"
  value       = local.compute_default_sa
}
