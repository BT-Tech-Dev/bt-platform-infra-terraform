output "trigger_id" {
  description = "ID del trigger Cloud Build per bim-parser-v1"
  value       = google_cloudbuild_trigger.bim_parser.trigger_id
}

output "trigger_name" {
  description = "Nome del trigger Cloud Build"
  value       = google_cloudbuild_trigger.bim_parser.name
}

output "production_ingestion_trigger_id" {
  description = "ID del trigger Cloud Build per production-ingestion-service"
  value       = google_cloudbuild_trigger.production_ingestion_service.trigger_id
}

output "production_ingestion_trigger_name" {
  description = "Nome del trigger Cloud Build per production-ingestion-service"
  value       = google_cloudbuild_trigger.production_ingestion_service.name
}
