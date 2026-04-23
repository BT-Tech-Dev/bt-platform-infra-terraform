# =============================================================================
# modules/eventarc/main.tf — Trigger EventArc: Pub/Sub → Cloud Run
#
# Percorso evento:
#   1. File caricato in GCS bucket staging (prefisso uploads/)
#   2. GCS pubblica messaggio su topic Pub/Sub bt-platform-gcs-staging-uploads-prod
#      (la notifica GCS e il binding IAM sono gestiti in modules/storage/main.tf)
#   3. EventArc legge il topic e invoca Cloud Run bim-parser-v1 via POST /ingest
# =============================================================================

# ─── EventArc Trigger ────────────────────────────────────────────────────────
# Ascolta il topic staging_uploads e invoca bim-parser-v1 via POST /ingest.
# Il SA eventarc ha il ruolo run.invoker per autenticarsi con Cloud Run.
resource "google_eventarc_trigger" "staging_to_bim_parser" {
  name     = "trg-bt-staging-to-parser-${var.environment}"
  location = var.region
  project  = var.project_id

  # Tipo evento: messaggio Pub/Sub pubblicato
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.pubsub.topic.v1.messagePublished"
  }

  # Sorgente: topic staging_uploads
  transport {
    pubsub {
      topic = var.topic_staging_uploads_id
    }
  }

  # Destinazione: Cloud Run bim-parser-v1 → endpoint POST /ingest
  destination {
    cloud_run_service {
      service = var.cloud_run_bim_parser_name
      region  = var.region
      path    = "/ingest"
    }
  }

  service_account = var.sa_eventarc_email

  labels = {
    environment = var.environment
    pipeline    = "bim-ingest"
  }

}
