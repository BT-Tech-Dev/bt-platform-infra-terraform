variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }
variable "sa_eventarc_email" { type = string }
variable "bucket_staging_name" { type = string }
variable "topic_staging_uploads_id" { type = string }

# ─── Servizi Cloud Run destinazione ──────────────────────────────────────────
variable "cloud_run_bim_parser_name" {
  description = "Nome del Cloud Run bim-parser-v1 (destinazione trigger Pub/Sub BIM)"
  type        = string
}

variable "cloud_run_bucket_watcher_name" {
  description = "Nome del Cloud Run bucket-watcher (destinazione trigger GCS staging)"
  type        = string
}

# ─── Topic Pub/Sub sorgente per i trigger doc_type ────────────────────────────
variable "topic_gcs_bim_id" {
  description = "ID del topic bt-platform-gcs-bim-{env} (pubblicato da bucket-watcher)"
  type        = string
}

variable "cloud_run_production_ingestion_service_name" {
  description = "Nome del Cloud Run production-ingestion-service (destinazione trigger Pub/Sub production)"
  type        = string
}

variable "topic_gcs_production_id" {
  description = "ID del topic bt-platform-gcs-production-{env} (pubblicato da bucket-watcher)"
  type        = string
}
