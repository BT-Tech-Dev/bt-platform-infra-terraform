variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }
variable "db_instance_name" { type = string }
variable "db_name" { type = string }
variable "db_version" { type = string }
variable "db_tier" { type = string }
variable "sa_etl_email" { type = string }
variable "revit_export_ro_password" {
  type      = string
  ephemeral = true
}
variable "revit_export_ro_password_rotation_epoch" { type = number }
