# =============================================================================
# modules/eventarc/main.tf — Trigger EventArc: Pub/Sub → Cloud Run
#
# Flusso dopo l'introduzione di bucket-watcher:
#
#   1. File caricato in GCS staging (uploads/{project_code}/{doc_type}/{file})
#   2. GCS notifica → topic bt-platform-gcs-staging-uploads-prod
#   3. EventArc (trg-bt-staging-to-parser-prod) → bucket-watcher POST /route
#   4. bucket-watcher risolve tenant_id e instrada per doc_type:
#        bim        → bt-platform-gcs-bim-prod
#        production → Cloud Tasks MS-05
#        boq        → bt-platform-gcs-boq-prod
#        gantt      → bt-platform-gcs-gantt-prod
#   5. EventArc (trg-bt-gcs-bim-to-parser-prod) → bim-parser-v1 POST /ingest
# =============================================================================

# ─── Trigger 1: GCS staging → bucket-watcher ─────────────────────────────────
# MODIFICATO (2026-05-06): destinazione cambiata da bim-parser-v1 a bucket-watcher.
# bucket-watcher smista il file al parser corretto in base al doc_type nel path.
resource "google_eventarc_trigger" "staging_to_bucket_watcher" {
  name     = "trg-bt-staging-to-parser-${var.environment}"
  location = var.region
  project  = var.project_id

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.pubsub.topic.v1.messagePublished"
  }

  transport {
    pubsub {
      topic = var.topic_staging_uploads_id
    }
  }

  destination {
    cloud_run_service {
      service = var.cloud_run_bucket_watcher_name
      region  = var.region
      path    = "/route"
    }
  }

  service_account = var.sa_eventarc_email

  labels = {
    environment = var.environment
    pipeline    = "bim-ingest"
    step        = "1-routing"
  }
}

# ─── Trigger 2: topic BIM → bim-parser-v1 ────────────────────────────────────
# Nuovo trigger: ascolta il topic bt-platform-gcs-bim-{env} pubblicato da
# bucket-watcher e invoca bim-parser-v1 POST /ingest.
# Il payload contiene {bucket, file_path, project_code, tenant_id, doc_type}.
resource "google_eventarc_trigger" "gcs_bim_to_bim_parser" {
  name     = "trg-bt-gcs-bim-to-parser-${var.environment}"
  location = var.region
  project  = var.project_id

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.pubsub.topic.v1.messagePublished"
  }

  transport {
    pubsub {
      topic = var.topic_gcs_bim_id
    }
  }

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
    step        = "2-parse"
  }
}
