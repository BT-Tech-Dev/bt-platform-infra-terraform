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
          cpu    = "1"   # 1 vCPU
          memory = "2Gi" # BIM JSON ~80 MiB is parsed non-streaming; keep >2x measured peak RSS.
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
        value = "128"
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

      # Base service URL. The parser app appends the internal retry path and
      # uses this same value as the Cloud Run OIDC audience.
      env {
        name  = "PRODUCTION_INGESTION_SERVICE_URL"
        value = google_cloud_run_v2_service.production_ingestion_service.uri
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
    timeout = "900s"

    # ─── Concorrenza ─────────────────────────────────────────────────
    # BIM parsing is non-streaming and memory-heavy for large Revit JSON exports.
    # Keep one active request per instance to avoid concurrent in-process payloads.
    max_instance_request_concurrency = 1
  }

  labels = {
    environment = var.environment
    service     = "bim-parser"
    version     = "v1"
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].revision,
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
#   bt-platform-gcs-bim-prod → bim-parser-v1
#   production               → Cloud Tasks MS-05
#   bt-platform-gcs-boq-prod → boq-parser (futuro)
#   bt-platform-gcs-gantt-prod → gantt-parser (futuro)
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
        name  = "PRODUCTION_DISPATCH_BACKEND"
        value = var.production_dispatch_backend
      }
      env {
        name  = "MS05_TASKS_SERVICE_ACCOUNT_EMAIL"
        value = var.ms05_tasks_service_account_email
      }
      env {
        name  = "MS05_WORKER_TARGET_URL"
        value = var.ms05_worker_target_url
      }
      env {
        name  = "MS05_TASKS_LOCATION"
        value = var.ms05_tasks_location
      }
      env {
        name  = "MS05_TASKS_QUEUE"
        value = var.ms05_tasks_queue
      }
      env {
        name  = "MS05_TASKS_DISPATCH_DEADLINE_SECONDS"
        value = tostring(var.ms05_tasks_dispatch_deadline_seconds)
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
      template[0].revision,
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
# Riceve comandi Cloud Tasks su /tasks/ingest e registra l'audit raw su schema
# raw. Il container reale verra' sostituito da Cloud Build/deploy applicativo.
# =============================================================================

resource "google_cloud_run_v2_service" "production_ingestion_service" {
  name     = "production-ingestion-service"
  location = var.region
  project  = var.project_id

  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

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
          memory = "1Gi"
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
        name  = "OCR_SERVICE_ROLE"
        value = "ingest"
      }
      env {
        name  = "OCR_AUTO_DISPATCH_ENABLED"
        value = "false"
      }
      env {
        name  = "EVIDENCE_LINK_HANDOFF_MODE"
        value = var.evidence_link_handoff_mode
      }
      env {
        name  = "OCR_INTERNAL_HANDLER_ENABLED"
        value = "false"
      }
      env {
        name  = "OCR_TASKS_PROJECT_ID"
        value = var.ocr_tasks_project_id
      }
      env {
        name  = "OCR_TASKS_LOCATION"
        value = var.ocr_tasks_location
      }
      env {
        name  = "OCR_TASKS_QUEUE"
        value = var.ocr_tasks_queue
      }
      env {
        name  = "OCR_TASKS_TARGET_URL"
        value = "${google_cloud_run_v2_service.production_ingestion_ocr_worker.uri}/internal/ocr/extractions/{extraction_run_id}:execute"
      }
      env {
        name  = "OCR_TASKS_SERVICE_ACCOUNT_EMAIL"
        value = var.ocr_tasks_service_account_email
      }
      env {
        name  = "OCR_TASKS_DISPATCH_DEADLINE_SECONDS"
        value = tostring(var.ocr_tasks_dispatch_deadline_seconds)
      }
      env {
        name  = "OCR_AUTO_PROFILES"
        value = var.ocr_auto_profiles
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

    max_instance_request_concurrency = 1
  }

  labels = {
    environment = var.environment
    service     = "production-ingestion-service"
    version     = "v1"
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].revision,
      client,
      client_version,
      scaling
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "bim_parser_invoker_production_ingestion" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.production_ingestion_service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.sa_parser_email}"
}

# MS-05 async ingest queue's OIDC caller.
resource "google_cloud_run_v2_service_iam_member" "ms05_tasks_invoker_production_ingestion" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.production_ingestion_service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.sa_ms05_tasks_oidc_email}"
}

# Internet-reachable only for authenticated callers. No public principal is
# bound; the dedicated UG65 identity below is the sole invoker.
resource "google_cloud_run_v2_service" "iot_ingestion_service" {
  name     = "iot-ingestion-service"
  location = var.region
  project  = var.project_id

  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.sa_iot_ingestion_runtime_email

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [var.db_connection_name]
      }
    }

    containers {
      image = var.iot_ingestion_image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true
      }

      env {
        name  = "RAW_BUCKET"
        value = var.bucket_iot_raw_name
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

    timeout                          = "300s"
    max_instance_request_concurrency = 20
  }

  labels = {
    environment = var.environment
    service     = "iot-ingestion-service"
    version     = "v1"
  }

  lifecycle {
    ignore_changes = [client, client_version, scaling]
  }
}

resource "google_cloud_run_v2_service_iam_member" "ug65_balocco2_invoker_iot_ingestion" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.iot_ingestion_service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.sa_ug65_balocco2_iot_invoker_email}"
}

# =============================================================================
# Cloud Run: production-ingestion-ocr-worker (MS-05 OCR pilot)
#
# Private worker invoked only by Cloud Tasks with a dedicated OIDC identity.
# It uses the same application container image family as production-ingestion-
# service, but runs with OCR_SERVICE_ROLE=worker.
# =============================================================================

resource "google_cloud_run_v2_service" "production_ingestion_ocr_worker" {
  name     = "production-ingestion-ocr-worker"
  location = var.region
  project  = var.project_id

  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    service_account = var.sa_ocr_worker_email

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
          memory = "1Gi"
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
        value = "document"
      }
      env {
        name  = "LOG_LEVEL"
        value = "INFO"
      }
      env {
        name  = "OCR_SERVICE_ROLE"
        value = "worker"
      }
      env {
        name  = "OCR_AUTO_DISPATCH_ENABLED"
        value = "false"
      }
      env {
        name  = "OCR_INTERNAL_HANDLER_ENABLED"
        value = "true"
      }
      env {
        name  = "OCR_VERTEX_PROJECT_ID"
        value = var.ocr_vertex_project_id
      }
      env {
        name  = "OCR_VERTEX_LOCATION"
        value = var.ocr_vertex_location
      }
      env {
        name  = "OCR_VERTEX_MODEL_ID"
        value = var.ocr_vertex_model_id
      }
      env {
        name  = "OCR_TIMEOUT_SECONDS"
        value = tostring(var.ocr_timeout_seconds)
      }
      env {
        name  = "OCR_MAX_RETRIES"
        value = tostring(var.ocr_max_retries)
      }
      env {
        name  = "OCR_RAW_RESPONSE_GCS_PREFIX"
        value = var.ocr_raw_response_gcs_prefix
      }
      env {
        name  = "OCR_SCHEMA_VERSION"
        value = var.ocr_schema_version
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
      max_instance_count = var.ocr_worker_max_instance_count
    }

    timeout                          = "${var.ocr_worker_timeout_seconds}s"
    max_instance_request_concurrency = var.ocr_worker_concurrency
  }

  labels = {
    environment = var.environment
    service     = "production-ingestion-ocr-worker"
    version     = "v1"
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].revision,
      client,
      client_version,
      scaling
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "cloud_tasks_invoker_production_ingestion_ocr_worker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.production_ingestion_ocr_worker.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.sa_ocr_tasks_oidc_email}"
}
