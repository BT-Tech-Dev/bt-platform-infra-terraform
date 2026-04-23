# =============================================================================
# versions.tf — Vincoli di versione per Terraform e i provider GCP
#
# Perché questo file esiste:
#   Terraform usa i "provider" come plugin per parlare con GCP.
#   Bloccare le versioni evita che un aggiornamento automatico rompa il codice.
#   ~> 6.0 significa "qualsiasi 6.x ma non 7.x" (minor updates OK, major no).
# =============================================================================

terraform {
  # Versione minima di Terraform CLI richiesta
  required_version = ">= 1.7.0"

  required_providers {
    # Provider principale per le risorse GCP
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    # Provider "beta" per risorse in anteprima (es. alcune funzionalità EventArc)
    #google-beta = {
    #  source  = "hashicorp/google-beta"
    #  version = "~> 6.0"
    #}
    # Provider null: usato per null_resource (azioni locali nel ciclo di vita Terraform)
    # Esempio: invocare Cloud Build dopo la creazione di Cloud SQL
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  # ---------------------------------------------------------------------
  # Backend: dove Terraform salva il suo "state" (la mappa di tutto ciò
  # che ha creato). Usiamo il bucket GCS già esistente nel progetto.
  # IMPORTANTE: non cambiare il prefix senza migrare lo state.
  # ---------------------------------------------------------------------
  backend "gcs" {
    bucket = "bt-platform-tf-state"
    prefix = "terraform/state"
  }
}
