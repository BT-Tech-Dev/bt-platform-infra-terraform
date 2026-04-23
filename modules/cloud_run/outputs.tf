output "bim_parser_url" {
  description = "URL HTTPS del servizio Cloud Run bim-parser-v1"
  value       = google_cloud_run_v2_service.bim_parser.uri
}

output "bim_parser_name" {
  description = "Nome del servizio Cloud Run (usato da EventArc per il routing)"
  value       = google_cloud_run_v2_service.bim_parser.name
}
