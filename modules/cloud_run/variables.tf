variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }
variable "sa_parser_email" { type = string }
variable "sa_ocr_worker_email" { type = string }
variable "sa_ocr_tasks_oidc_email" { type = string }
variable "bucket_staging_name" { type = string }
variable "bucket_ingest_name" { type = string }
variable "bucket_handoff_name" { type = string }
variable "db_connection_name" { type = string }
variable "db_name" { type = string }
variable "sa_eventarc_email" { type = string }
variable "ocr_tasks_project_id" { type = string }
variable "ocr_tasks_location" { type = string }
variable "ocr_tasks_queue" { type = string }
variable "ocr_tasks_service_account_email" { type = string }
variable "ocr_tasks_dispatch_deadline_seconds" { type = number }
variable "ocr_auto_profiles" { type = string }
variable "ocr_worker_timeout_seconds" { type = number }
variable "ocr_worker_max_instance_count" { type = number }
variable "ocr_worker_concurrency" { type = number }
variable "ocr_vertex_project_id" { type = string }
variable "ocr_vertex_location" { type = string }
variable "ocr_vertex_model_id" { type = string }
variable "ocr_timeout_seconds" { type = number }
variable "ocr_max_retries" { type = number }
variable "ocr_raw_response_gcs_prefix" { type = string }
variable "ocr_schema_version" { type = string }

# ─── Tenant ID per il parser ─────────────────────────────────────────────────
variable "bim_parser_tenant_id" {
  description = "UUID del tenant (company) per cui gira il bim-parser-v1 (es. UUID di PPDL)"
  type        = string
  default     = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
