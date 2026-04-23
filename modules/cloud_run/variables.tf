variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }
variable "sa_parser_email" { type = string }
variable "bucket_staging_name" { type = string }
variable "bucket_ingest_name" { type = string }
variable "bucket_handoff_name" { type = string }
variable "db_connection_name" { type = string }
variable "db_name" { type = string }
variable "sa_eventarc_email" { type = string }

# ─── Tenant ID per il parser ─────────────────────────────────────────────────
variable "bim_parser_tenant_id" {
  description = "UUID del tenant (company) per cui gira il bim-parser-v1 (es. UUID di PPDL)"
  type        = string
  default     = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
