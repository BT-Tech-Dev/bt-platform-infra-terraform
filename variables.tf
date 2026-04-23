# =============================================================================
# variables.tf — Definizione di tutte le variabili di input del root module
#
# I valori reali sono in terraform.tfvars (non committare se contiene segreti).
# Le variabili senza "default" DEVONO essere valorizzate in tfvars.
# =============================================================================

# ─── Progetto GCP ────────────────────────────────────────────────────────────

variable "project_id" {
  description = "ID del progetto GCP dove deployare tutta l'infrastruttura"
  type        = string
  # Esempio: "bt-platform-prod"
}

variable "region" {
  description = "Regione GCP primaria. europe-west8 = Milano (bassa latenza per clienti italiani)"
  type        = string
  default     = "europe-west8"
}

variable "billing_account" {
  description = "ID del billing account GCP (serve solo se si crea il progetto via Terraform)"
  type        = string
  default     = ""
}

# ─── Organizzazione ──────────────────────────────────────────────────────────

variable "org_id" {
  description = "ID numerico dell'organizzazione GCP (buildtrust.it)"
  type        = string
  default     = "862731545925"
}

# ─── Database ────────────────────────────────────────────────────────────────

variable "db_instance_name" {
  description = "Nome dell'istanza Cloud SQL PostgreSQL"
  type        = string
  default     = "bt-platform-pg-prod"
}

variable "db_name" {
  description = "Nome del database principale all'interno dell'istanza Cloud SQL"
  type        = string
  default     = "db_bt_platform"
}

variable "db_version" {
  description = "Versione PostgreSQL. 15 è la versione LTS attuale con supporto ottimo per UUID e JSON"
  type        = string
  default     = "POSTGRES_15"
}

variable "db_tier" {
  description = <<-EOT
    Tipo di macchina Cloud SQL.
    db-f1-micro  = 0.6 GB RAM (solo test/dev, non per produzione)
    db-g1-small  = 1.7 GB RAM (sviluppo/staging leggero)
    db-n1-standard-1 = 3.75 GB RAM (produzione minima consigliata)
    Per ora usiamo g1-small, si scala facilmente senza downtime.
  EOT
  type        = string
  default     = "db-g1-small"
}

# ─── Tenant iniziali ─────────────────────────────────────────────────────────

variable "initial_tenants" {
  description = <<-EOT
    Lista dei tenant iniziali da inserire nel seed del database.
    Ogni tenant è un cliente/progetto della piattaforma BuildTrust.
    Il tenant_id è un UUID fisso (determinístico) usato come FK in tutte le tabelle.
  EOT
  type = list(object({
    id          = string  # UUID v4
    name        = string  # Nome completo progetto
    code        = string  # Codice breve (es. "PPDL", "BAL2")
    description = string
  }))
  default = [
    {
      id          = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      name        = "Ponte sul Po di Levante"
      code        = "PPDL"
      description = "Opera: Viadotto Ponte sul Po di Levante, Codice 0549-IDG"
    },
    {
      id          = "b2c3d4e5-f6a7-8901-bcde-f12345678901"
      name        = "Balocco 2"
      code        = "BAL2"
      description = "Opera: Balocco 2 — stabilimento di produzione prefabbricati"
    }
  ]
}

# ─── Naming ──────────────────────────────────────────────────────────────────

variable "github_owner" {
  description = "Owner del repository GitHub (es. 'BT-Tech-Dev')"
  type        = string
  default     = "BT-Tech-Dev"
}

variable "github_repo_name" {
  description = "Nome del repository GitHub per bt-platform (es. 'bt-platform')"
  type        = string
  default     = "bt-bim-platform"
}

variable "bim_parser_tenant_id" {
  description = "UUID del tenant (company) per cui gira bim-parser-v1. Default: PPDL (Ponte Po di Levante)"
  type        = string
  default     = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}

variable "environment" {
  description = "Ambiente di deployment. Usato nei nomi delle risorse per distinguere prod/staging/dev"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "L'ambiente deve essere uno tra: prod, staging, dev."
  }
}
