# =============================================================================
# main.tf — Root module: configura i provider e chiama tutti i sotto-moduli
#
# Struttura logica:
#   1. Provider GCP (google, google-beta)
#   2. Abilitazione API GCP necessarie
#   3. Chiamata ai moduli nell'ordine corretto (dipendenze)
#
# Ordine dei moduli:
#   iam → storage → cloud_sql → secret_manager → pubsub → artifact_registry
#   → cloud_run → eventarc
#   (eventarc dipende da cloud_run e pubsub, quindi va per ultimo)
# =============================================================================

# ─── Provider ────────────────────────────────────────────────────────────────

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google" {
  alias                 = "api_keys"
  project               = var.project_id
  region                = var.region
  billing_project       = var.project_id
  user_project_override = true
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# ─── API GCP ─────────────────────────────────────────────────────────────────
# Prima di creare qualsiasi risorsa GCP, bisogna abilitare le API corrispondenti.
# Se l'API non è abilitata, Terraform riceve un errore "API not enabled".
# disable_on_destroy = false: NON disabilitare l'API se facciamo terraform destroy
# (potrebbe rompere altre risorse non gestite da Terraform).

resource "google_project_service" "apis" {
  for_each = toset([
    "sqladmin.googleapis.com",             # Cloud SQL
    "storage.googleapis.com",              # Cloud Storage (GCS)
    "pubsub.googleapis.com",               # Pub/Sub (messaggistica asincrona)
    "eventarc.googleapis.com",             # EventArc (trigger basati su eventi)
    "run.googleapis.com",                  # Cloud Run (container serverless)
    "secretmanager.googleapis.com",        # Secret Manager (gestione segreti)
    "artifactregistry.googleapis.com",     # Artifact Registry (Docker images)
    "cloudbuild.googleapis.com",           # Cloud Build (CI/CD)
    "cloudscheduler.googleapis.com",       # Cloud Scheduler (MS-05 recovery Job)
    "iam.googleapis.com",                  # IAM (identity and access management)
    "cloudresourcemanager.googleapis.com", # Resource Manager (gestione progetto)
    "servicenetworking.googleapis.com",    # Service Networking (per peering VPC futuro)
  ])

  project                    = var.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "iot_api_gateway_apis" {
  for_each = toset([
    "apigateway.googleapis.com",
    "servicemanagement.googleapis.com",
    "servicecontrol.googleapis.com",
    "apikeys.googleapis.com",
  ])

  project                    = var.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "ocr_apis" {
  for_each = toset([
    "cloudtasks.googleapis.com", # Cloud Tasks (OCR async execution)
    "aiplatform.googleapis.com", # Vertex AI (Gemini OCR pilot)
  ])

  project                    = var.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}

# ─── Modulo IAM ──────────────────────────────────────────────────────────────
# Crea i service account e assegna i ruoli IAM.
# Va per primo: gli altri moduli hanno bisogno degli email dei service account.

module "iam" {
  source = "./modules/iam"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  depends_on = [google_project_service.apis]
}

# ─── Modulo Storage ──────────────────────────────────────────────────────────
# Crea i 3 bucket GCS della pipeline BIM: staging → ingest → handoff

module "storage" {
  source = "./modules/storage"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  sa_etl_email                   = module.iam.sa_etl_email
  sa_parser_email                = module.iam.sa_parser_email
  sa_ocr_worker_email            = module.iam.sa_ocr_worker_email
  sa_revit_export_email          = module.iam.sa_revit_export_email
  sa_iot_ingestion_runtime_email = module.iam.sa_iot_ingestion_runtime_email
  sa_ms05_recovery_email         = module.iam.sa_ms05_recovery_email
  ocr_raw_response_object_prefix = var.ocr_raw_response_object_prefix

  # Topic su cui GCS pubblica le notifiche di upload (notifica e binding IAM gestiti qui)
  topic_staging_uploads_id = module.pubsub.topic_staging_uploads_id

  depends_on = [module.pubsub]
}

# ─── Modulo Cloud SQL ────────────────────────────────────────────────────────
# Crea l'istanza PostgreSQL, il database e gli utenti applicativi.
# NOTA: i 10 schemi SQL vengono creati con lo script scripts/init_db.sh
#       DOPO il terraform apply (Cloud SQL deve esistere prima di poter
#       connettersi e creare gli schemi).

module "cloud_sql" {
  source = "./modules/cloud_sql"

  project_id                              = var.project_id
  region                                  = var.region
  environment                             = var.environment
  db_instance_name                        = var.db_instance_name
  db_name                                 = var.db_name
  db_version                              = var.db_version
  db_tier                                 = var.db_tier
  revit_export_ro_password                = ephemeral.random_password.revit_export_ro.result
  revit_export_ro_password_rotation_epoch = var.revit_export_ro_password_rotation_epoch

  # Il service account ETL ha bisogno del ruolo "Cloud SQL Client" per connettersi
  sa_etl_email = module.iam.sa_etl_email

}

# ─── Modulo Secret Manager ───────────────────────────────────────────────────
# Crea la struttura dei segreti (i contenitori), ma NON i valori.
# I valori (password, API key) vanno inseriti manualmente via Console GCP
# o via: gcloud secrets versions add SECRET_NAME --data-file=file.txt

module "secret_manager" {
  source = "./modules/secret_manager"

  project_id  = var.project_id
  environment = var.environment

  # Permetti ai service account di leggere i segreti rilevanti
  sa_etl_email                            = module.iam.sa_etl_email
  sa_parser_email                         = module.iam.sa_parser_email
  sa_ocr_worker_email                     = module.iam.sa_ocr_worker_email
  sa_revit_export_email                   = module.iam.sa_revit_export_email
  sa_iot_ingestion_runtime_email          = module.iam.sa_iot_ingestion_runtime_email
  sa_ms05_recovery_email                  = module.iam.sa_ms05_recovery_email
  revit_export_ro_password                = ephemeral.random_password.revit_export_ro.result
  revit_export_ro_password_rotation_epoch = var.revit_export_ro_password_rotation_epoch
  compute_default_sa                      = module.iam.compute_default_sa
}

ephemeral "random_password" "revit_export_ro" {
  length           = 32
  special          = true
  override_special = "!#$%&*+-=?@^_"
}

# ─── Modulo Pub/Sub ──────────────────────────────────────────────────────────
# Crea i topic Pub/Sub per la pipeline BIM e gli eventi SAL.
# Il GCS service account ha bisogno del ruolo Publisher sui topic
# per poter inviare notifiche quando un file viene caricato.

module "pubsub" {
  source = "./modules/pubsub"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  enable_debug_pubsub_subscriptions = var.enable_debug_pubsub_subscriptions

  depends_on = [google_project_service.apis]
}

# ─── Modulo Artifact Registry ────────────────────────────────────────────────
# Crea il registro Docker dove Cloud Build pusha le immagini dei microservizi.
# Sostituisce il vecchio registro nel progetto bt-bim (che rimane lì).

# Cloud Tasks queue for the MS-05 OCR pilot. Cloud Tasks does not currently
# support europe-west8, so the default location is europe-west6.
module "cloud_tasks" {
  source = "./modules/cloud_tasks"

  project_id  = var.project_id
  environment = var.environment
  location    = var.ocr_tasks_location

  queue_name                     = var.ocr_tasks_queue_name
  max_concurrent_dispatches      = var.ocr_tasks_max_concurrent_dispatches
  max_dispatches_per_second      = var.ocr_tasks_max_dispatches_per_second
  max_attempts                   = var.ocr_tasks_max_attempts
  min_retry_backoff_seconds      = var.ocr_tasks_min_retry_backoff_seconds
  max_retry_backoff_seconds      = var.ocr_tasks_max_retry_backoff_seconds
  max_retry_duration_seconds     = var.ocr_tasks_max_retry_duration_seconds
  logging_sampling_ratio         = var.ocr_tasks_logging_sampling_ratio
  enqueuer_service_account_email = module.iam.sa_parser_email

  depends_on = [
    google_project_service.ocr_apis,
    module.iam,
  ]
}

# Cloud Tasks queue for MS-05 asynchronous ingest dispatch (infra tranche 2
# of Bucket Watcher -> raw.ingestion_dispatch -> Cloud Tasks -> MS-05). No
# application enqueues to this queue yet; it is additive and does not touch
# the live Eventarc/Pub/Sub ingestion path.
#
# Reuses the same generic ./modules/cloud_tasks module as the OCR queue
# above -- the module's internal names are now purpose-agnostic
# (google_cloud_tasks_queue.queue, var.enqueuer_service_account_email, ...),
# so this second instantiation configures the MS-05 ingest queue with no
# awkward OCR-named passthrough.
module "cloud_tasks_ms05" {
  source = "./modules/cloud_tasks"

  project_id  = var.project_id
  environment = var.environment
  location    = var.ms05_tasks_location

  queue_name                     = var.ms05_tasks_queue_name
  max_concurrent_dispatches      = var.ms05_tasks_max_concurrent_dispatches
  max_dispatches_per_second      = var.ms05_tasks_max_dispatches_per_second
  max_attempts                   = var.ms05_tasks_max_attempts
  min_retry_backoff_seconds      = var.ms05_tasks_min_retry_backoff_seconds
  max_retry_backoff_seconds      = var.ms05_tasks_max_retry_backoff_seconds
  max_retry_duration_seconds     = var.ms05_tasks_max_retry_duration_seconds
  logging_sampling_ratio         = var.ms05_tasks_logging_sampling_ratio
  enqueuer_service_account_email = module.iam.sa_parser_email # current Bucket Watcher runtime identity

  depends_on = [
    google_project_service.ocr_apis, # enables cloudtasks.googleapis.com project-wide
    module.iam,
  ]
}

module "artifact_registry" {
  source = "./modules/artifact_registry"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  # Cloud Build deve poter pushare le immagini
  sa_cloudbuild_email = module.iam.sa_cloudbuild_email

}

# ─── Modulo Cloud Run ────────────────────────────────────────────────────────
# Deploy placeholder del servizio bim-parser-v1.
# Al momento usa un'immagine "hello world" di Google.
# Quando il codice applicativo sarà pronto, Cloud Build lo sostituirà.

module "cloud_run" {
  source = "./modules/cloud_run"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  sa_parser_email                    = module.iam.sa_parser_email
  sa_ocr_worker_email                = module.iam.sa_ocr_worker_email
  sa_ocr_tasks_oidc_email            = module.iam.sa_ocr_tasks_oidc_email
  sa_ms05_tasks_oidc_email           = module.iam.sa_ms05_tasks_oidc_email
  sa_iot_ingestion_runtime_email     = module.iam.sa_iot_ingestion_runtime_email
  sa_ug65_balocco2_iot_invoker_email = module.iam.sa_ug65_balocco2_iot_invoker_email

  bucket_staging_name = module.storage.bucket_staging_name
  bucket_ingest_name  = module.storage.bucket_ingest_name
  bucket_handoff_name = module.storage.bucket_handoff_name
  bucket_iot_raw_name = module.storage.bucket_iot_raw_name
  db_connection_name  = module.cloud_sql.connection_name
  db_name             = var.db_name

  sa_eventarc_email = module.iam.sa_eventarc_email

  production_dispatch_backend          = var.bucket_watcher_production_dispatch_backend
  ms05_tasks_location                  = var.ms05_tasks_location
  ms05_tasks_queue                     = var.ms05_tasks_queue_name
  ms05_tasks_service_account_email     = module.iam.sa_ms05_tasks_oidc_email
  ms05_worker_target_url               = var.ms05_worker_target_url
  ms05_tasks_dispatch_deadline_seconds = var.ms05_tasks_dispatch_deadline_seconds

  ocr_tasks_project_id                = var.project_id
  ocr_tasks_location                  = module.cloud_tasks.queue_location
  ocr_tasks_queue                     = module.cloud_tasks.queue_name
  ocr_tasks_service_account_email     = module.iam.sa_ocr_tasks_oidc_email
  ocr_tasks_dispatch_deadline_seconds = var.ocr_tasks_dispatch_deadline_seconds
  ocr_auto_profiles                   = var.ocr_auto_profiles
  evidence_link_handoff_mode          = var.evidence_link_handoff_mode
  ocr_worker_timeout_seconds          = var.ocr_worker_timeout_seconds
  ocr_worker_max_instance_count       = var.ocr_worker_max_instance_count
  ocr_worker_concurrency              = var.ocr_worker_concurrency
  ocr_vertex_project_id               = var.ocr_vertex_project_id != "" ? var.ocr_vertex_project_id : var.project_id
  ocr_vertex_location                 = var.ocr_vertex_location
  ocr_vertex_model_id                 = var.ocr_vertex_model_id
  ocr_timeout_seconds                 = var.ocr_timeout_seconds
  ocr_max_retries                     = var.ocr_max_retries
  ocr_raw_response_gcs_prefix         = "gs://${module.storage.bucket_handoff_name}/${trimsuffix(var.ocr_raw_response_object_prefix, "/")}"
  ocr_schema_version                  = var.ocr_schema_version
  iot_ingestion_image                 = var.iot_ingestion_image

  # ─── Tenant ID PPDL (Ponte Po di Levante) ────────────────────────────────
  bim_parser_tenant_id = var.bim_parser_tenant_id

  depends_on = [
    module.iam,
    module.storage,
    module.cloud_sql,
    module.artifact_registry,
    module.secret_manager,
    module.cloud_tasks,
  ]
}

resource "google_api_gateway_api" "iot_ingestion" {
  provider     = google-beta
  project      = var.project_id
  api_id       = "bt-iot-ingestion-api"
  display_name = "BT IoT ingestion API"

  depends_on = [google_project_service.iot_api_gateway_apis]
}

resource "google_project_service" "iot_api_gateway_managed_service" {
  project                    = var.project_id
  service                    = google_api_gateway_api.iot_ingestion.managed_service
  disable_on_destroy         = false
  disable_dependent_services = false

  depends_on = [google_api_gateway_api_config.iot_ingestion]
}

resource "google_api_gateway_api_config" "iot_ingestion" {
  provider      = google-beta
  project       = var.project_id
  api           = google_api_gateway_api.iot_ingestion.api_id
  api_config_id = "iot-ingestion-v1"
  display_name  = "IoT ingestion API config v1"

  gateway_config {
    backend_config {
      google_service_account = module.iam.sa_ug65_balocco2_iot_invoker_email
    }
  }

  openapi_documents {
    document {
      path = "iot-ingestion-openapi.yaml"
      contents = base64encode(templatefile("${path.module}/iot-ingestion-openapi.yaml.tftpl", {
        cloud_run_url = module.cloud_run.iot_ingestion_service_url
      }))
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_project_service.iot_api_gateway_apis,
    module.cloud_run,
  ]
}

resource "google_api_gateway_gateway" "iot_ingestion" {
  provider     = google-beta
  project      = var.project_id
  region       = "europe-west1"
  gateway_id   = "bt-iot-ingestion-gateway"
  display_name = "BT IoT ingestion gateway"
  api_config   = google_api_gateway_api_config.iot_ingestion.name
}

resource "google_apikeys_key" "ug65_balocco2_iot" {
  provider     = google.api_keys
  project      = var.project_id
  name         = "ug65-balocco2-iot-key"
  display_name = "UG65 Balocco2 IoT key"

  restrictions {
    api_targets {
      service = google_api_gateway_api.iot_ingestion.managed_service
    }
  }

  depends_on = [google_project_service.iot_api_gateway_managed_service]
}

module "revit_export_job" {
  source = "./modules/revit_export_job"

  project_id              = var.project_id
  region                  = var.region
  environment             = var.environment
  image                   = var.revit_export_bim_parser_image
  service_account_email   = module.iam.sa_revit_export_email
  db_connection_name      = module.cloud_sql.connection_name
  db_name                 = var.db_name
  db_user                 = "revit_export_ro"
  db_password_secret_name = module.secret_manager.secret_db_password_revit_export_ro_name
  export_bucket_name      = module.storage.bucket_exports_name

  depends_on = [
    module.cloud_run,
    module.cloud_sql,
    module.iam,
    module.secret_manager,
    module.storage,
  ]
}

module "ms05_ingestion_recovery_job" {
  source = "./modules/ms05_ingestion_recovery_job"

  project_id                       = var.project_id
  region                           = var.region
  environment                      = var.environment
  image                            = var.ms05_recovery_image
  service_account_email            = module.iam.sa_ms05_recovery_email
  db_connection_name               = module.cloud_sql.connection_name
  db_name                          = var.db_name
  db_password_secret_name          = module.secret_manager.secret_db_password_name
  staging_bucket_name              = module.storage.bucket_staging_name
  tasks_project_id                 = var.project_id
  tasks_location                   = module.cloud_tasks_ms05.queue_location
  tasks_queue                      = module.cloud_tasks_ms05.queue_name
  tasks_oidc_service_account_email = module.iam.sa_ms05_tasks_oidc_email
  worker_target_url                = "${module.cloud_run.production_ingestion_service_url}/tasks/ingest"
  scheduler_service_account_email  = module.iam.sa_ms05_recovery_scheduler_email

  depends_on = [
    module.cloud_run,
    module.cloud_sql,
    module.iam,
    module.secret_manager,
    module.storage,
    module.cloud_tasks_ms05,
  ]
}

# Recovery remains available alongside the legacy Pub/Sub/Eventarc rollback
# path and runs after the Cloud Tasks cutover canary has passed.
resource "google_cloud_scheduler_job" "ms05_ingestion_recovery" {
  name        = "ms05-ingestion-recovery-${var.environment}"
  description = "MS-05 durable Cloud Tasks dispatch recovery (enabled at cutover)"
  project     = var.project_id
  region      = var.region
  schedule    = "*/5 * * * *"
  time_zone   = "Etc/UTC"
  paused      = false

  http_target {
    http_method = "POST"
    uri         = module.ms05_ingestion_recovery_job.run_uri
    oauth_token {
      service_account_email = module.iam.sa_ms05_recovery_scheduler_email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  #  retry_config {
  #    retry_count = 0
  #  }

  depends_on = [
    google_project_service.apis,
    module.ms05_ingestion_recovery_job,
  ]
}

resource "google_cloud_tasks_queue_iam_member" "ms05_recovery_enqueuer" {
  project  = var.project_id
  location = module.cloud_tasks_ms05.queue_location
  name     = module.cloud_tasks_ms05.queue_name
  role     = "roles/cloudtasks.enqueuer"
  member   = "serviceAccount:${module.iam.sa_ms05_recovery_email}"
}

# ─── Init DB: schemi SQL via Cloud Build ─────────────────────────────────────
# Dopo che Cloud SQL esiste, questo null_resource invoca Cloud Build per
# creare i 10 schemi PostgreSQL e inserire i 2 tenant iniziali.
#
# Perché null_resource e non uno script locale?
#   - null_resource esegue un comando sulla macchina che fa terraform apply
#   - Il comando è "gcloud builds submit" → carica il repo su GCS e lo esegue
#     in un container Linux su Google Cloud Build
#   - Risultato: funziona su Windows/Mac/Linux senza installare psql o il proxy
#
# Quando viene ri-eseguito:
#   - Quando Cloud SQL viene ricreato (cambia connection_name)
#   - Quando uno dei file SQL viene modificato (cambia il suo hash)
#   - MAI da solo se non cambia nulla (Terraform è idempotente)
#
# Per forzare la riesecuzione manualmente:
#   terraform taint null_resource.init_db && terraform apply

resource "null_resource" "init_db" {
  # ─── Triggers: quando rieseguire ────────────────────────────────────────────
  # Terraform confronta questi valori tra un apply e il successivo.
  # Se uno cambia → distrugge e ricrea il null_resource → esegue il provisioner.
  triggers = {
    instance        = module.cloud_sql.connection_name
    enabled         = tostring(var.enable_db_init)
    db_init_version = var.db_init_version
  }

  # ─── Provisioner: cosa eseguire ──────────────────────────────────────────────
  # "local-exec" = eseguito sulla macchina che fa terraform apply (il tuo PC)
  # Il comando carica il repo corrente su Cloud Build e avvia il job.
  provisioner "local-exec" {
    # Nota: gcloud builds submit è sincrono per default — Terraform aspetta
    # che il build finisca prima di continuare. Se il build fallisce,
    # terraform apply fallisce e mostra l'errore.
    command = var.enable_db_init ? "gcloud builds submit . --config=scripts/cloudbuild-init-db.yaml --project=${var.project_id} --quiet" : "echo DB init disabled. Set enable_db_init=true and increment db_init_version to bootstrap explicitly."
  }

  depends_on = [
    module.cloud_sql,
    module.secret_manager,
    module.iam,
  ]
}

# ─── Modulo Cloud Build ──────────────────────────────────────────────────────
# Crea il trigger CI/CD per bim-parser-v1: push a main → build Docker → deploy Cloud Run.
# PRE-REQUISITO: la connessione GitHub deve essere già configurata manualmente in Cloud Build.

module "cloud_build" {
  source = "./modules/cloud_build"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  sa_cloudbuild_email = module.iam.sa_cloudbuild_email
  github_owner        = var.github_owner
  github_repo_name    = var.github_repo_name

  depends_on = [
    module.iam,
    module.artifact_registry,
    module.cloud_run,
  ]
}

# ─── Modulo EventArc ─────────────────────────────────────────────────────────
# Crea i trigger EventArc che collegano le notifiche GCS → Pub/Sub → Cloud Run.
# Va per ultimo perché dipende da: storage (bucket), pubsub (topics), cloud_run (servizi).

module "eventarc" {
  source = "./modules/eventarc"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  sa_eventarc_email = module.iam.sa_eventarc_email

  bucket_staging_name      = module.storage.bucket_staging_name
  topic_staging_uploads_id = module.pubsub.topic_staging_uploads_id

  # Trigger 1: staging → bucket-watcher (smista per doc_type)
  cloud_run_bucket_watcher_name = module.cloud_run.bucket_watcher_name

  # Trigger 2: topic BIM → bim-parser-v1
  cloud_run_bim_parser_name = module.cloud_run.bim_parser_name
  topic_gcs_bim_id          = module.pubsub.topic_gcs_bim_id

  # Trigger 3: topic production -> production-ingestion-service (MS-05)
  cloud_run_production_ingestion_service_name = module.cloud_run.production_ingestion_service_name
  topic_gcs_production_id                     = module.pubsub.topic_gcs_production_id

  depends_on = [
    module.storage,
    module.pubsub,
    module.cloud_run,
    module.iam,
  ]
}
