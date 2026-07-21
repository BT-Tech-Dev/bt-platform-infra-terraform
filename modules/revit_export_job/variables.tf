variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }
variable "image" {
  type = string

  validation {
    condition     = can(regex("^.+@sha256:[a-f0-9]{64}$", var.image))
    error_message = "image must use an immutable @sha256 digest reference."
  }
}
variable "service_account_email" { type = string }
variable "db_connection_name" { type = string }
variable "db_name" { type = string }
variable "db_user" { type = string }
variable "db_password_secret_name" { type = string }
variable "export_bucket_name" { type = string }
