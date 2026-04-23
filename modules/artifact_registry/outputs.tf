output "registry_url" {
  description = "URL base del registro: REGION-docker.pkg.dev/PROJECT/REPO"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.bt_platform.repository_id}"
}

output "repository_id" {
  value = google_artifact_registry_repository.bt_platform.repository_id
}
