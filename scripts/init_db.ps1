# =============================================================================
# scripts/init_db.ps1 — Inizializza i 10 schemi PostgreSQL (versione Windows)
#
# Uso: .\scripts\init_db.ps1
#
# Prerequisiti:
#   - gcloud autenticato (gcloud auth application-default login)
#   - cloud-sql-proxy.exe nella cartella scripts/ o nel PATH
#     Download: https://cloud.google.com/sql/docs/postgres/sql-proxy#windows-64-bit
#   - psql.exe nel PATH
#     Installa con: winget install --id PostgreSQL.PostgreSQL (oppure scarica solo il client)
#
# Lo script:
#   1. Recupera la password postgres da Secret Manager
#   2. Avvia cloud-sql-proxy in background (porta 5432 locale)
#   3. Esegue i 12 script SQL in ordine
#   4. Ferma il proxy
# =============================================================================

$ErrorActionPreference = "Stop"

$PROJECT_ID    = "bt-platform-prod"
$INSTANCE      = "bt-platform-pg-prod"
$DB_NAME       = "db_bt_platform"
$DB_USER       = "postgres"
$REGION        = "europe-west8"
$PROXY_PORT    = 5432
$SCRIPT_DIR    = Split-Path -Parent $MyInvocation.MyCommand.Path
$SQL_DIR       = Join-Path $SCRIPT_DIR "..\modules\cloud_sql\sql"
$PROXY_EXE     = Join-Path $SCRIPT_DIR "cloud-sql-proxy.exe"
$CONNECTION    = "${PROJECT_ID}:${REGION}:${INSTANCE}"

Write-Host "========================================================"  -ForegroundColor Cyan
Write-Host "  BuildTrust Platform — Inizializzazione Database"        -ForegroundColor Cyan
Write-Host "========================================================"  -ForegroundColor Cyan
Write-Host "  Progetto:   $PROJECT_ID"
Write-Host "  Istanza:    $INSTANCE"
Write-Host "  Database:   $DB_NAME"
Write-Host "========================================================"  -ForegroundColor Cyan

# ─── Verifica psql ───────────────────────────────────────────────────────────
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "ERRORE: psql non trovato nel PATH." -ForegroundColor Red
    Write-Host "Installa PostgreSQL client:" -ForegroundColor Yellow
    Write-Host "  winget install --id PostgreSQL.PostgreSQL.16" -ForegroundColor Yellow
    Write-Host "  oppure scarica solo psql da: https://www.enterprisedb.com/download-postgresql-binaries"
    exit 1
}

# ─── Verifica cloud-sql-proxy ────────────────────────────────────────────────
if (-not (Test-Path $PROXY_EXE)) {
    Write-Host ""
    Write-Host "ERRORE: cloud-sql-proxy.exe non trovato in scripts/" -ForegroundColor Red
    Write-Host "Scaricalo da:" -ForegroundColor Yellow
    Write-Host "  https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.1/cloud-sql-proxy.x64.exe"
    Write-Host "Rinomina il file in 'cloud-sql-proxy.exe' e mettilo nella cartella scripts/"
    exit 1
}

# ─── Recupera password da Secret Manager ─────────────────────────────────────
Write-Host ""
Write-Host "-> Recupero password da Secret Manager..."
try {
    $DB_PASSWORD = gcloud secrets versions access latest `
        --secret="bt-platform-db-password-prod" `
        --project=$PROJECT_ID 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Secret non trovato" }
    Write-Host "   OK password recuperata" -ForegroundColor Green
} catch {
    Write-Host "   Secret non trovato. Inserisci la password postgres manualmente:" -ForegroundColor Yellow
    $DB_PASSWORD = Read-Host -AsSecureString "Password postgres"
    $DB_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($DB_PASSWORD))
}

$env:PGPASSWORD = $DB_PASSWORD

# ─── Avvia Cloud SQL Auth Proxy ───────────────────────────────────────────────
Write-Host ""
Write-Host "-> Avvio Cloud SQL Auth Proxy sulla porta $PROXY_PORT..."
$ProxyArgs = "$CONNECTION --port $PROXY_PORT"
$ProxyProcess = Start-Process -FilePath $PROXY_EXE `
    -ArgumentList $ProxyArgs `
    -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput "$env:TEMP\cloud-sql-proxy.log" `
    -RedirectStandardError "$env:TEMP\cloud-sql-proxy-err.log"

Write-Host "   Proxy PID: $($ProxyProcess.Id)" -ForegroundColor Gray

# Aspetta che il proxy sia pronto (max 30 secondi)
Write-Host "-> Attendo che il proxy sia pronto..."
$maxWait = 30
for ($i = 1; $i -le $maxWait; $i++) {
    Start-Sleep -Seconds 1
    $test = Test-NetConnection -ComputerName "127.0.0.1" -Port $PROXY_PORT -WarningAction SilentlyContinue
    if ($test.TcpTestSucceeded) {
        Write-Host "   Proxy pronto dopo $i secondi" -ForegroundColor Green
        break
    }
    if ($i -eq $maxWait) {
        Write-Host "ERRORE: proxy non si e' avviato. Log: $env:TEMP\cloud-sql-proxy-err.log" -ForegroundColor Red
        Stop-Process -Id $ProxyProcess.Id -Force
        exit 1
    }
}

# ─── Funzione per eseguire un file SQL ────────────────────────────────────────
function Invoke-SqlFile {
    param([string]$FilePath, [string]$Description)
    Write-Host "-> $Description..."
    & psql -h 127.0.0.1 -p $PROXY_PORT -U $DB_USER -d $DB_NAME -f $FilePath -v ON_ERROR_STOP=1 -q
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   ERRORE nel file: $FilePath" -ForegroundColor Red
        throw "SQL script fallito: $FilePath"
    }
    Write-Host "   OK" -ForegroundColor Green
}

# ─── Esecuzione script SQL in ordine ─────────────────────────────────────────
Write-Host ""
Write-Host "-> Esecuzione script SQL..." -ForegroundColor Cyan

Invoke-SqlFile "$SQL_DIR\01_schemas_extensions.sql"  "Schemi + estensioni"
Invoke-SqlFile "$SQL_DIR\02_schema_tenant.sql"        "Schema tenant (master)"
Invoke-SqlFile "$SQL_DIR\14_schema_raw.sql"           "Schema raw (MS-05 ingestion)"
Invoke-SqlFile "$SQL_DIR\02b_schema_catalog.sql"      "Schema catalog (Layer 0 reference data)"
Invoke-SqlFile "$SQL_DIR\03_schema_bim.sql"           "Schema bim"
Invoke-SqlFile "$SQL_DIR\04_schema_process.sql"       "Schema process"
Invoke-SqlFile "$SQL_DIR\05_schema_boq.sql"           "Schema boq"
Invoke-SqlFile "$SQL_DIR\09_schema_document.sql"      "Schema document"
Invoke-SqlFile "$SQL_DIR\06_schema_production.sql"    "Schema production"
Invoke-SqlFile "$SQL_DIR\07_schema_progress.sql"      "Schema progress"
Invoke-SqlFile "$SQL_DIR\08_schema_quality.sql"       "Schema quality"
Invoke-SqlFile "$SQL_DIR\10_schema_read.sql"          "Schema read (CQRS)"
Invoke-SqlFile "$SQL_DIR\11_schema_external.sql"      "Schema external"
Invoke-SqlFile "$SQL_DIR\12_seed_tenants.sql"         "Seed tenant PPDL + BAL2"

# ─── Verifica finale ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "-> Verifica schemi e tenant..." -ForegroundColor Cyan

$verifySchemas = @"
SELECT schema_name FROM information_schema.schemata
WHERE schema_name IN ('bim','process','boq','production','progress','quality','tenant','document','read','external','raw')
ORDER BY schema_name;
"@
$verifySchemas | psql -h 127.0.0.1 -p $PROXY_PORT -U $DB_USER -d $DB_NAME

$verifyTenants = "SELECT code, name, status FROM tenant.tenant ORDER BY created_at;"
$verifyTenants | psql -h 127.0.0.1 -p $PROXY_PORT -U $DB_USER -d $DB_NAME

# ─── Pulizia ─────────────────────────────────────────────────────────────────
Stop-Process -Id $ProxyProcess.Id -Force
Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "========================================================"  -ForegroundColor Green
Write-Host "  Database inizializzato con successo!"                    -ForegroundColor Green
Write-Host "========================================================"  -ForegroundColor Green
