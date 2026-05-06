# =============================================================================
# modules/cloud_build/main.tf — Trigger CI/CD per bim-parser-v1
#
# Questo modulo crea il trigger Cloud Build che:
#   1. Si attiva su push al branch "main" del repository GitHub
#   2. Filtra solo le modifiche in "services/bim-parser-v1/**"
#      (evita build inutili se cambia solo il Terraform)
#   3. Usa cloudbuild.yaml in services/bim-parser-v1/
#   4. Builda l'immagine Docker e deploya su Cloud Run bim-parser-v1
#
# PRE-REQUISITO (manuale, non Terraform):
#   La connessione GitHub deve essere già configurata in Cloud Build.
#   Console GCP → Cloud Build → Settings → Connect Repository
#   Oppure: gcloud builds connections create github --region=europe-west8
#   NOTA: la prima autorizzazione GitHub richiede un browser (OAuth).
#         Non può essere fatta via Terraform o gcloud senza interazione.
# =============================================================================

# =============================================================================
# Trigger CI/CD: push main → build + deploy bucket-watcher
# Si attiva solo se ci sono modifiche in services/bucket-watcher/
# =============================================================================

resource "google_cloudbuild_trigger" "bucket_watcher" {
  name     = "cb-bucket-watcher-${var.environment}"
  project  = var.project_id
  location = var.region

  description = "Build e deploy automatico di bucket-watcher su push a main (services/bucket-watcher/)"

  github {
    owner = var.github_owner
    name  = var.github_repo_name

    push {
      branch = "^main$"
    }
  }

  filename = "services/bucket-watcher/cloudbuild.yaml"

  included_files = ["services/bucket-watcher/**"]

  service_account = "projects/${var.project_id}/serviceAccounts/${var.sa_cloudbuild_email}"

  tags = [
    "bucket-watcher",
    "cloud-run",
    var.environment,
  ]
}

# =============================================================================
# Trigger CI/CD: push main → build + deploy bim-parser-v1
# =============================================================================

resource "google_cloudbuild_trigger" "bim_parser" {
  name     = "cb-bim-parser-v1-${var.environment}"
  project  = var.project_id
  location = var.region

  description = "Build e deploy automatico di bim-parser-v1 su push a main (services/bim-parser-v1/)"

  # ─── Sorgente: repository GitHub ─────────────────────────────────────────
  # Il "name" della connessione GitHub è visibile in:
  # Console GCP → Cloud Build → Repositories (2nd gen)
  github {
    owner = var.github_owner
    name  = var.github_repo_name

    # Si attiva solo su push al branch main
    push {
      branch = "^main$"  # Regex: esattamente "main"
    }
  }

  # ─── File di configurazione build ────────────────────────────────────────
  # Usa il cloudbuild.yaml nella cartella del servizio (non nel root del repo).
  filename = "services/bim-parser-v1/cloudbuild.yaml"

  # ─── Filtro cartella ─────────────────────────────────────────────────────
  # Il trigger si attiva SOLO se il push include modifiche in services/bim-parser-v1/.
  # Senza questo, ogni push (anche solo infra Terraform) triggererebbe il build.
  included_files = ["services/bim-parser-v1/**"]

  # ─── Service Account per il build ────────────────────────────────────────
  # Usa il SA dedicato Cloud Build (sa-bt-cloudbuild-prod) che ha:
  #   - roles/artifactregistry.writer → push immagini
  #   - roles/run.admin → deploy su Cloud Run
  #   - roles/iam.serviceAccountUser → usare il SA del parser nel deploy
  service_account = "projects/${var.project_id}/serviceAccounts/${var.sa_cloudbuild_email}"

  # ─── Variabili di sostituzione disponibili nel cloudbuild.yaml ───────────
  # Cloud Build inietta automaticamente $PROJECT_ID e $COMMIT_SHA.
  # Aggiungiamo solo variabili extra se necessarie.
  # substitutions = {}  # Non servono variabili extra per ora

  tags = [
    "bim-parser",
    "cloud-run",
    var.environment,
  ]
}
