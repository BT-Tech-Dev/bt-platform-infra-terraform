output "trigger_staging_parser_name" {
  description = "Nome del trigger EventArc staging → bucket-watcher"
  value       = google_eventarc_trigger.staging_to_bucket_watcher.name
}

output "trigger_staging_parser_id" {
  value = google_eventarc_trigger.staging_to_bucket_watcher.id
}

output "trigger_gcs_bim_parser_name" {
  description = "Nome del trigger EventArc topic BIM → bim-parser-v1"
  value       = google_eventarc_trigger.gcs_bim_to_bim_parser.name
}

output "trigger_gcs_bim_parser_id" {
  value = google_eventarc_trigger.gcs_bim_to_bim_parser.id
}

output "trigger_gcs_production_ingestion_name" {
  description = "Nome del trigger EventArc topic production â†’ production-ingestion-service"
  value       = google_eventarc_trigger.gcs_production_to_production_ingestion.name
}

output "trigger_gcs_production_ingestion_id" {
  value = google_eventarc_trigger.gcs_production_to_production_ingestion.id
}
