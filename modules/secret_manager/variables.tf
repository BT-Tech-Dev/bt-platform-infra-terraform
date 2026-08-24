variable "project_id" { type = string }
variable "environment" { type = string }
variable "sa_etl_email" { type = string }
variable "sa_parser_email" { type = string }
variable "sa_ocr_worker_email" { type = string }
variable "sa_revit_export_email" { type = string }
variable "sa_iot_ingestion_runtime_email" { type = string }
variable "sa_ms05_recovery_email" { type = string }
variable "revit_export_ro_password" {
  type      = string
  ephemeral = true
}
variable "revit_export_ro_password_rotation_epoch" { type = number }
variable "compute_default_sa" { type = string }
