# =============================================================================
# modules/artifact_registry/main.tf — Registro Docker per le immagini dei microservizi
#
# Artifact Registry sostituisce il vecchio Container Registry (gcr.io).
# Le immagini Docker dei microservizi (bim-parser, etl, sal-engine, ecc.)
# vengono pushate qui da Cloud Build e poi pullate da Cloud Run al deploy.
#
# URL immagine: europe-west8-docker.pkg.dev/bt-platform-prod/bt-platform/SERVICE:TAG
#
# NOTA: il vecchio registro in bt-bim (europe-west8-docker.pkg.dev/bt-bim-po-levante-prod/bt-bim/)
#       rimane invariato — questo è un registro NUOVO per la nuova piattaforma.
# =============================================================================

resource "google_artifact_registry_repository" "bt_platform" {
  repository_id = "bt-platform"
  project       = var.project_id
  location      = var.region
  format        = "DOCKER"
  description   = "Registro Docker per tutti i microservizi della piattaforma BuildTrust"

  labels = {
    environment = var.environment
    component   = "ci-cd"
  }
}

# ─── IAM: Cloud Build può pushare le immagini ────────────────────────────────
resource "google_artifact_registry_repository_iam_member" "cloudbuild_writer" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.bt_platform.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${var.sa_cloudbuild_email}"
}

# ─── IAM: Cloud Run può pullare le immagini ──────────────────────────────────
# Il compute default SA (usato da Cloud Run) deve poter leggere le immagini

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_artifact_registry_repository_iam_member" "cloudrun_reader" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.bt_platform.name
  role       = "roles/artifactregistry.reader"
  # Il Compute Engine default SA viene usato da Cloud Run per pullare le immagini
  member = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}
