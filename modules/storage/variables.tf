variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }
variable "sa_etl_email" { type = string }
variable "sa_parser_email" { type = string }
variable "sa_ocr_worker_email" { type = string }
variable "sa_revit_export_email" { type = string }
variable "sa_iot_ingestion_runtime_email" { type = string }
variable "ocr_raw_response_object_prefix" { type = string }
variable "topic_staging_uploads_id" {
  description = "ID del topic Pub/Sub per le notifiche GCS staging uploads"
  type        = string
}
