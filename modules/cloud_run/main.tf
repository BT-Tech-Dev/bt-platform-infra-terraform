# =============================================================================
# modules/cloud_run/main.tf — Cloud Run placeholder bim-parser-v1
#
# Questo modulo crea il servizio Cloud Run "bim-parser-v1" in modalità
# placeholder: usa un'immagine "hello world" di Google finché il codice
# applicativo non è pronto.
#
# Quando Cloud Build farà il primo build della vera immagine Docker,
# aggiornerà automaticamente il deployment (il terraform non sarà più
# necessario per aggiornare l'immagine, ci pensa Cloud Build).
#
# Questo Cloud Run è il PUNTO DI INGRESSO della pipeline BIM:
#   EventArc → POST /ingest → bim-parser-v1 → valida → muove su ingest bucket
#
# (Nelle versioni future: aggiunta di bim-llm-merge, bim-etl, sal-engine, ecc.)
# =============================================================================

resource "google_cloud_run_v2_service" "bim_parser" {
  name     = "bim-parser-v1"
  location = var.region
  project  = var.project_id

  # deletion_protection = false: necessario per permettere a Terraform di
  # distruggere/ricreare il servizio (es. dopo un apply fallito).
  # Non preoccupa per la sicurezza: la protezione reale è il controllo accessi IAM.
  deletion_protection = false

  # ingress = INGRESS_TRAFFIC_INTERNAL_ONLY: solo traffico interno GCP
  # (EventArc, altri servizi GCP). Non accessibile dall'internet pubblico.
  ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    # Usa il SA del parser (non il SA di default) — least privilege
    service_account = var.sa_parser_email

    # ─── Cloud SQL Connector ───────────────────────────────────────────
    # Abilita la connessione sicura a Cloud SQL tramite il connector API.
    # NON apre una porta TCP diretta: usa il socket Unix locale /cloudsql/...
    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [var.db_connection_name]
      }
    }

    containers {
      # Immagine placeholder di Google — verrà sostituita da Cloud Build
      # al primo deploy del codice applicativo
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      # ─── Risorse ────────────────────────────────────────────────────
      resources {
        limits = {
          cpu    = "1"     # 1 vCPU
          memory = "512Mi" # 512 MiB RAM (stesso del vecchio progetto)
        }
        # cpu_idle = true: CPU allocata solo durante elaborazione richiesta (cost saving)
        cpu_idle = true
      }

      # ─── Variabili d'ambiente ───────────────────────────────────────
      # Configurazione della pipeline (stessa struttura del vecchio progetto)

      env {
        name  = "STAGING_BUCKET"
        value = var.bucket_staging_name
      }
      env {
        name  = "INGEST_BUCKET"
        value = var.bucket_ingest_name
      }
      env {
        name  = "HANDOFF_BUCKET"
        value = var.bucket_handoff_name
      }
      env {
        name  = "SOURCE_PREFIX"
        value = "uploads/"
      }
      env {
        name  = "DEST_PREFIX"
        value = "landing/incoming/"
      }
      env {
        name  = "REJECTED_PREFIX"
        value = "rejected/"
      }
      env {
        name  = "ALLOWED_EXTENSIONS"
        value = ".json"
      }
      env {
        name  = "MAX_SIZE_MB"
        value = "50"
      }
      env {
        name  = "LOG_LEVEL"
        value = "INFO"
      }

      # ─── Configurazione database ─────────────────────────────────────
      env {
        name  = "INSTANCE_CONNECTION_NAME"
        value = var.db_connection_name
      }
      env {
        name  = "DB_USER"
        value = "bt_app"
      }
      env {
        name  = "DB_NAME"
        value = var.db_name
      }
      env {
        name  = "DB_SCHEMA"
        value = "bim"
      }

      # ─── LLM (disabilitato come nel vecchio progetto) ────────────────
      env {
        name  = "LLM_ENABLED"
        value = "false"
      }

      # ─── TENANT_ID ──────────────────────────────────────────────────────
      # UUID del tenant per cui gira questo Cloud Run.
      # Il parser usa questo valore per taggare bim_model/element/quantity.
      env {
        name  = "TENANT_ID"
        value = var.bim_parser_tenant_id
      }

      # ─── Segreti da Secret Manager ───────────────────────────────────
      # Cloud Run legge i valori direttamente da Secret Manager al runtime.
      # Il SA sa-bt-parser-prod ha roles/secretmanager.secretAccessor su questi secret
      # (assegnato nel modulo secret_manager/main.tf).
      # "version = latest" → ruotare la password aggiunge solo una nuova versione,
      # nessun terraform apply necessario.
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "bt-platform-db-password-${var.environment}"
            version = "latest"
          }
        }
      }

      env {
        name = "LLM_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "bt-platform-llm-api-key-${var.environment}"
            version = "latest"
          }
        }
      }

      # ─── Mount Cloud SQL socket ──────────────────────────────────────
      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      # ─── Porte ──────────────────────────────────────────────────────
      ports {
        container_port = 8080
      }
    }

    # ─── Scaling ─────────────────────────────────────────────────────
    scaling {
      min_instance_count = 0 # Scale-to-zero: costo zero quando inattivo
      max_instance_count = 3 # Max 3 istanze parallele (concurrency = 80 ognuna)
    }

    # ─── Timeout ─────────────────────────────────────────────────────
    timeout = "300s" # 5 minuti (stesso del vecchio progetto)

    # ─── Concorrenza ─────────────────────────────────────────────────
    # NOTA: per l'ETL finale (scrittura DB) usare max_instance_count = 1
    # e concurrency = 1 come nel vecchio bim-etl-v1. Qui il parser può
    # girare in parallelo.
    max_instance_request_concurrency = 80
  }

  labels = {
    environment = var.environment
    service     = "bim-parser"
    version     = "v1"
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
      scaling
    ]
  }
}

# ─── IAM: solo EventArc può invocare bim-parser-v1 ──────────────────────────
resource "google_cloud_run_v2_service_iam_member" "eventarc_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.bim_parser.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.sa_eventarc_email}"
}


# =============================================================================
# Cloud Run: bucket-watcher
#
# Riceve eventi GCS via EventArc e smista i file sui topic Pub/Sub corretti
# in base al doc_type nel percorso: uploads/{project_code}/{doc_type}/{file}.
#
# Pubblica su:
#   bt-platform-gcs-bim-prod       → bim-parser-v1
#   bt-platform-gcs-production-prod → production-parser (futuro)
#   bt-platform-gcs-boq-prod        → boq-parser (futuro)
#   bt-platform-gcs-gantt-prod      → gantt-parser (futuro)
#
# NOTA IAM: il SA sa_parser_email deve avere roles/pubsub.publisher
# oltre ai ruoli già assegnati (Cloud SQL client, secret accessor).
# Se non è già presente, aggiungere nel modulo IAM:
#   member = "serviceAccount:${sa_parser_email}"
#   role   = "roles/pubsub.publisher"
# =============================================================================

resource "google_cloud_run_v2_service" "bucket_watcher" {
  name     = "bucket-watcher"
  location = var.region
  project  = var.project_id

  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    service_account = var.sa_parser_email

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [var.db_connection_name]
      }
    }

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
        cpu_idle = true
      }

      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "INSTANCE_CONNECTION_NAME"
        value = var.db_connection_name
      }
      env {
        name  = "DB_USER"
        value = "bt_app"
      }
      env {
        name  = "DB_NAME"
        value = var.db_name
      }
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      env {
        name  = "LOG_LEVEL"
        value = "INFO"
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "bt-platform-db-password-${var.environment}"
            version = "latest"
          }
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      ports {
        container_port = 8080
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    timeout = "60s" # routing veloce: nessuna elaborazione pesante

    max_instance_request_concurrency = 80
  }

  labels = {
    environment = var.environment
    service     = "bucket-watcher"
    version     = "v1"
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
      scaling
    ]
  }
}

# ─── IAM: solo EventArc può invocare bucket-watcher ─────────────────────────
resource "google_cloud_run_v2_service_iam_member" "eventarc_invoker_bucket_watcher" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.bucket_watcher.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.sa_eventarc_email}"
}

# =============================================================================
# Cloud Run: production-ingestion-service (MS-05)
#
# Riceve eventi production dal topic bt-platform-gcs-production-{env} via
# Eventarc e registra l'audit raw su schema raw. Il container reale verra'
# sostituito da Cloud Build/deploy applicativo.
# =============================================================================

resource "google_cloud_run_v2_service" "production_ingestion_service" {
  name     = "production-ingestion-service"
  location = var.region
  project  = var.project_id

  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    service_account = var.sa_parser_email

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [var.db_connection_name]
      }
    }

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      env {
        name  = "STAGING_BUCKET"
        value = var.bucket_staging_name
      }
      env {
        name  = "INSTANCE_CONNECTION_NAME"
        value = var.db_connection_name
      }
      env {
        name  = "DB_USER"
        value = "bt_app"
      }
      env {
        name  = "DB_NAME"
        value = var.db_name
      }
      env {
        name  = "DB_SCHEMA"
        value = "raw"
      }
      env {
        name  = "ENABLE_RAW_PERSISTENCE"
        value = "true"
      }
      env {
        name  = "RAW_PERSISTENCE_STRICT"
        value = "false"
      }
      env {
        name  = "LOG_LEVEL"
        value = "INFO"
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "bt-platform-db-password-${var.environment}"
            version = "latest"
          }
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      ports {
        container_port = 8080
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    timeout = "300s"

    max_instance_request_concurrency = 20
  }

  labels = {
    environment = var.environment
    service     = "production-ingestion-service"
    version     = "v1"
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
      scaling
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "eventarc_invoker_production_ingestion" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.production_ingestion_service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.sa_eventarc_email}"
}
