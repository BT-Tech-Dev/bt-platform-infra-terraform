# =============================================================================
# modules/secret_manager/main.tf — Struttura dei segreti
#
# Secret Manager è il "cassaforte" di GCP per password e API key.
# Questo modulo crea SOLO i "contenitori" (le casseforti vuote).
# I VALORI vanno inseriti manualmente DOPO terraform apply con:
#
#   gcloud secrets versions add bt-platform-db-password-prod \
#     --data-file=<(echo -n "LA_TUA_PASSWORD")
#
# OPPURE via Console GCP → Secret Manager → seleziona secret → "Add version"
#
# Segreti creati:
#   bt-platform-db-password      → password utente PostgreSQL (bt_app)
#   bt-platform-db-password-ro   → password utente read-only (bt_readonly)
#   bt-platform-llm-api-key      → API key OpenAI/Anthropic per bim-llm-merge
#   bt-platform-cloudbuild-token → GitHub token per Cloud Build trigger
# =============================================================================

locals {
  # Prefisso comune per tutti i segreti del progetto
  secret_prefix = "bt-platform"
}

# ─── Segreto: password superutente postgres ───────────────────────────────────
# Usata SOLO dagli script di init/migrazione del DB (init_db_cloudbuild.sh).
# NON usata dall'applicazione — l'app si connette con bt_app (db_password).
# Impostare con:
#   gcloud sql users set-password postgres \
#     --instance=bt-platform-pg-prod --project=bt-platform-prod \
#     --password="LA_PASSWORD_SCELTA"
#   echo -n "LA_PASSWORD_SCELTA" | gcloud secrets versions add \
#     bt-platform-db-postgres-password-prod --data-file=- --project=bt-platform-prod
resource "google_secret_manager_secret" "db_postgres_password" {
  secret_id = "${local.secret_prefix}-db-postgres-password-${var.environment}"
  project   = var.project_id

  labels = {
    environment = var.environment
    service     = "cloud-sql"
  }

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_postgres_password_placeholder" {
  secret      = google_secret_manager_secret.db_postgres_password.id
  secret_data = "PLACEHOLDER_CHANGE_ME_IMMEDIATELY"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# Il Compute Engine default SA (usato da Cloud Build) può leggere questo secret
resource "google_secret_manager_secret_iam_member" "compute_sa_postgres_password" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.db_postgres_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.compute_default_sa}"
}

# ─── Segreto: password DB applicativo ────────────────────────────────────────
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${local.secret_prefix}-db-password-${var.environment}"
  project   = var.project_id

  labels = {
    environment = var.environment
    service     = "cloud-sql"
  }

  replication {
    # "auto" lascia a GCP la scelta della replicazione geografica ottimale
    auto {}
  }
}

# ─── Segreto: password DB read-only ──────────────────────────────────────────
resource "google_secret_manager_secret" "db_password_ro" {
  secret_id = "${local.secret_prefix}-db-password-ro-${var.environment}"
  project   = var.project_id

  labels = {
    environment = var.environment
    service     = "cloud-sql"
  }

  replication {
    auto {}
  }
}

# ─── Segreto: API key LLM ────────────────────────────────────────────────────
# Usata dal servizio bim-llm-merge (attualmente disabilitato, ma struttura pronta)
resource "google_secret_manager_secret" "llm_api_key" {
  secret_id = "${local.secret_prefix}-llm-api-key-${var.environment}"
  project   = var.project_id

  labels = {
    environment = var.environment
    service     = "llm-merge"
  }

  replication {
    auto {}
  }
}

# ─── Segreto: GitHub token per Cloud Build ───────────────────────────────────
resource "google_secret_manager_secret" "cloudbuild_github_token" {
  secret_id = "${local.secret_prefix}-github-token-${var.environment}"
  project   = var.project_id

  labels = {
    environment = var.environment
    service     = "cloud-build"
  }

  replication {
    auto {}
  }
}

# ─── Versioni placeholder per db_password e llm_api_key ─────────────────────
# Cloud Run richiede che il segreto abbia almeno una versione per poter fare
# riferimento a "latest". Creiamo versioni placeholder che Terraform NON
# sovrascriverà mai (ignore_changes), così il valore reale può essere impostato
# manualmente senza che Terraform lo resetti al prossimo apply.
#
# Per impostare il valore reale:
#   gcloud secrets versions add bt-platform-db-password-prod \
#     --data-file=<(echo -n "LA_TUA_PASSWORD_SICURA")
#
# Dopo aver impostato il valore reale, la versione placeholder (v1)
# può essere disabilitata dalla Console GCP: Secret Manager → secret → Versions.

resource "google_secret_manager_secret_version" "db_password_placeholder" {
  secret = google_secret_manager_secret.db_password.id
  # Valore placeholder — NON è la password reale.
  # Sostituire immediatamente con: gcloud secrets versions add ...
  secret_data = "PLACEHOLDER_CHANGE_ME_IMMEDIATELY"

  lifecycle {
    # CRITICO: non sovrascrivere mai questo campo dopo il primo apply.
    # Una volta impostato il valore reale, Terraform non deve toccarlo.
    ignore_changes = [secret_data]
  }
}

resource "google_secret_manager_secret_version" "llm_api_key_placeholder" {
  secret      = google_secret_manager_secret.llm_api_key.id
  secret_data = "PLACEHOLDER_CHANGE_ME_IMMEDIATELY"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# ─── IAM: chi può LEGGERE i segreti ─────────────────────────────────────────
# Il service account parser può leggere db_password e llm_api_key

resource "google_secret_manager_secret_iam_member" "parser_db_password" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.sa_parser_email}"
}

resource "google_secret_manager_secret_iam_member" "parser_llm_key" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.llm_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.sa_parser_email}"
}

# Il service account ETL può leggere db_password e db_password_ro
resource "google_secret_manager_secret_iam_member" "etl_db_password" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.sa_etl_email}"
}

resource "google_secret_manager_secret_iam_member" "etl_db_password_ro" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.db_password_ro.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.sa_etl_email}"
}

resource "google_secret_manager_secret_iam_member" "ocr_worker_db_password" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.sa_ocr_worker_email}"
}
