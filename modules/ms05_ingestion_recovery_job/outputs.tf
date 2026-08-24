output "run_uri" {
  value = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${google_cloud_run_v2_job.recovery.name}:run"
}

output "name" { value = google_cloud_run_v2_job.recovery.name }
