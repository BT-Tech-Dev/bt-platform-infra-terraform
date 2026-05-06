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

#provider "google-beta" {
#  project = var.project_id
#  region  = var.region
#}

# ─── API GCP ─────────────────────────────────────────────────────────────────
# Prima di creare qualsiasi risorsa GCP, bisogna abilitare le API corrispondenti.
# Se l'API non è abilitata, Terraform riceve un errore "API not enabled".
# disable_on_destroy = false: NON disabilitare l'API se facciamo terraform destroy
# (potrebbe rompere altre risorse non gestite da Terraform).

resource "google_project_service" "apis" {
  for_each = toset([
    "sqladmin.googleapis.com",              # Cloud SQL
    "storage.googleapis.com",               # Cloud Storage (GCS)
    "pubsub.googleapis.com",                # Pub/Sub (messaggistica asincrona)
    "eventarc.googleapis.com",              # EventArc (trigger basati su eventi)
    "run.googleapis.com",                   # Cloud Run (container serverless)
    "secretmanager.googleapis.com",         # Secret Manager (gestione segreti)
    "artifactregistry.googleapis.com",      # Artifact Registry (Docker images)
    "cloudbuild.googleapis.com",            # Cloud Build (CI/CD)
    "iam.googleapis.com",                   # IAM (identity and access management)
    "cloudresourcemanager.googleapis.com",  # Resource Manager (gestione progetto)
    "servicenetworking.googleapis.com",     # Service Networking (per peering VPC futuro)
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

  sa_etl_email     = module.iam.sa_etl_email
  sa_parser_email  = module.iam.sa_parser_email

  # Topic su cui GCS pubblica le notifiche di upload (notifica e binding IAM gestiti qui)
  topic_staging_uploads_id = module.pubsub.topic_staging_uploads_id

  depends_on = [module.iam, module.pubsub]
}

# ─── Modulo Cloud SQL ────────────────────────────────────────────────────────
# Crea l'istanza PostgreSQL, il database e gli utenti applicativi.
# NOTA: i 10 schemi SQL vengono creati con lo script scripts/init_db.sh
#       DOPO il terraform apply (Cloud SQL deve esistere prima di poter
#       connettersi e creare gli schemi).

module "cloud_sql" {
  source = "./modules/cloud_sql"

  project_id       = var.project_id
  region           = var.region
  environment      = var.environment
  db_instance_name = var.db_instance_name
  db_name          = var.db_name
  db_version       = var.db_version
  db_tier          = var.db_tier

  # Il service account ETL ha bisogno del ruolo "Cloud SQL Client" per connettersi
  sa_etl_email = module.iam.sa_etl_email

  depends_on = [module.iam]
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
  sa_etl_email       = module.iam.sa_etl_email
  sa_parser_email    = module.iam.sa_parser_email
  compute_default_sa = module.iam.compute_default_sa

  depends_on = [module.iam]
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

  depends_on = [google_project_service.apis]
}

# ─── Modulo Artifact Registry ────────────────────────────────────────────────
# Crea il registro Docker dove Cloud Build pusha le immagini dei microservizi.
# Sostituisce il vecchio registro nel progetto bt-bim (che rimane lì).

module "artifact_registry" {
  source = "./modules/artifact_registry"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  # Cloud Build deve poter pushare le immagini
  sa_cloudbuild_email = module.iam.sa_cloudbuild_email

  depends_on = [module.iam]
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

  sa_parser_email = module.iam.sa_parser_email

  bucket_staging_name    = module.storage.bucket_staging_name
  bucket_ingest_name     = module.storage.bucket_ingest_name
  bucket_handoff_name    = module.storage.bucket_handoff_name
  db_connection_name     = module.cloud_sql.connection_name
  db_name                = var.db_name

  sa_eventarc_email = module.iam.sa_eventarc_email

  # ─── Tenant ID PPDL (Ponte Po di Levante) ────────────────────────────────
  bim_parser_tenant_id = var.bim_parser_tenant_id

  depends_on = [
    module.iam,
    module.storage,
    module.cloud_sql,
    module.artifact_registry,
    module.secret_manager,
  ]
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
    # Riesegui se l'istanza Cloud SQL viene ricreata
    instance = module.cloud_sql.connection_name

    # Riesegui se qualsiasi file SQL viene modificato
    sql_01 = filesha256("${path.root}/modules/cloud_sql/sql/01_schemas_extensions.sql")
    sql_02 = filesha256("${path.root}/modules/cloud_sql/sql/02_schema_tenant.sql")
    sql_03 = filesha256("${path.root}/modules/cloud_sql/sql/03_schema_bim.sql")
    sql_04 = filesha256("${path.root}/modules/cloud_sql/sql/04_schema_process.sql")
    sql_05 = filesha256("${path.root}/modules/cloud_sql/sql/05_schema_boq.sql")
    sql_06 = filesha256("${path.root}/modules/cloud_sql/sql/06_schema_production.sql")
    sql_07 = filesha256("${path.root}/modules/cloud_sql/sql/07_schema_progress.sql")
    sql_08 = filesha256("${path.root}/modules/cloud_sql/sql/08_schema_quality.sql")
    sql_09 = filesha256("${path.root}/modules/cloud_sql/sql/09_schema_document.sql")
    sql_10 = filesha256("${path.root}/modules/cloud_sql/sql/10_schema_read.sql")
    sql_11 = filesha256("${path.root}/modules/cloud_sql/sql/11_schema_external.sql")
    sql_12 = filesha256("${path.root}/modules/cloud_sql/sql/12_seed_tenants.sql")
  }

  # ─── Provisioner: cosa eseguire ──────────────────────────────────────────────
  # "local-exec" = eseguito sulla macchina che fa terraform apply (il tuo PC)
  # Il comando carica il repo corrente su Cloud Build e avvia il job.
  provisioner "local-exec" {
    # Nota: gcloud builds submit è sincrono per default — Terraform aspetta
    # che il build finisca prima di continuare. Se il build fallisce,
    # terraform apply fallisce e mostra l'errore.
    command = "gcloud builds submit . --config=scripts/cloudbuild-init-db.yaml --project=${var.project_id} --quiet"
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

  depends_on = [
    module.storage,
    module.pubsub,
    module.cloud_run,
    module.iam,
  ]
}
