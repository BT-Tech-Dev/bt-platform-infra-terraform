output "trigger_staging_parser_name" {
  description = "Nome del trigger EventArc staging → bim-parser"
  value       = google_eventarc_trigger.staging_to_bim_parser.name
}

output "trigger_staging_parser_id" {
  value = google_eventarc_trigger.staging_to_bim_parser.id
}
