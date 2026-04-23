# =============================================================================
# Makefile — Comandi utili per gestire l'infrastruttura bt-platform
#
# Uso: make <comando>
# Es:  make plan
#      make apply
#      make init-db
# =============================================================================

PROJECT_ID   := bt-platform-prod
REGION       := europe-west8
DB_INSTANCE  := bt-platform-pg-prod
DB_NAME      := db_bt_platform
DB_USER      := postgres

.PHONY: help auth init plan apply destroy fmt validate init-db

# ─── Aiuto ───────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "Comandi disponibili:"
	@echo "  make auth       — autentica gcloud sul progetto bt-platform-prod"
	@echo "  make init       — terraform init (scarica provider e configura backend)"
	@echo "  make fmt        — formatta tutti i file .tf"
	@echo "  make validate   — valida la sintassi Terraform senza contattare GCP"
	@echo "  make plan       — mostra le modifiche che verranno applicate"
	@echo "  make apply      — applica le modifiche (chiede conferma)"
	@echo "  make destroy    — DISTRUGGE tutta l'infrastruttura (ATTENZIONE!)"
	@echo "  make init-db    — crea gli schemi SQL nel DB dopo terraform apply"
	@echo ""

# ─── Autenticazione GCP ──────────────────────────────────────────────────────
auth:
	@echo "→ Login gcloud e imposta progetto..."
	gcloud auth login
	gcloud config set project $(PROJECT_ID)
	gcloud auth application-default login
	@echo "✓ Autenticato su $(PROJECT_ID)"

# ─── Terraform workflow ──────────────────────────────────────────────────────
init:
	terraform init

fmt:
	terraform fmt -recursive

validate: fmt
	terraform validate

plan: validate
	terraform plan -out=tfplan

apply:
	terraform apply tfplan

destroy:
	@echo "ATTENZIONE: questo distruggerà TUTTA l'infrastruttura bt-platform-prod!"
	@read -p "Sei sicuro? Scrivi 'yes' per confermare: " confirm && [ "$$confirm" = "yes" ]
	terraform destroy

# ─── Inizializzazione database ───────────────────────────────────────────────
# Normalmente viene eseguito AUTOMATICAMENTE da terraform apply (null_resource).
# Usa questo comando solo per forzare una re-inizializzazione manuale.
# Invoca Cloud Build: nessun tool locale necessario tranne gcloud.
init-db:
	@echo "→ Inizializzazione schemi database via Cloud Build..."
	gcloud builds submit . \
		--config=scripts/cloudbuild-init-db.yaml \
		--project=$(PROJECT_ID) \
		--quiet
	@echo "✓ Database inizializzato"
