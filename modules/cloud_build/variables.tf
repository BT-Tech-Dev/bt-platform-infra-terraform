variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }

variable "sa_cloudbuild_email" {
  description = "Email del SA Cloud Build (sa-bt-cloudbuild-prod)"
  type        = string
}

variable "github_owner" {
  description = "Owner del repository GitHub (es. 'BT-Tech-Dev')"
  type        = string
}

variable "github_repo_name" {
  description = "Nome del repository GitHub (es. 'bt-platform')"
  type        = string
}
