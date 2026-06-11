param(
    [string]$DbHost = $env:DEV_DB_HOST,
    [string]$DbName = $env:DEV_DB_NAME,
    [string]$DbUser = $env:DEV_DB_USER,
    [string]$DbPassword = $env:DEV_DB_PASSWORD,
    [string]$DbPort = $(if ($env:DEV_DB_PORT) { $env:DEV_DB_PORT } else { "5432" }),
    [string]$GcpProject = $env:DEV_GCP_PROJECT,
    [string]$SecretName = $env:DEV_DB_SECRET_NAME,
    [string]$Confirmation = $env:CONFIRM_DEV_DB_RESET
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-RequiredValue {
    param([string]$Name, [string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name is required."
    }
}

function Assert-NotProduction {
    param([string]$Name, [string]$Value)
    if (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -match "(?i)prod|production") {
        throw "Refusing to run: $Name appears to reference production."
    }
}

Assert-RequiredValue "DEV_DB_HOST" $DbHost
Assert-RequiredValue "DEV_DB_NAME" $DbName
Assert-RequiredValue "DEV_DB_USER" $DbUser
Assert-RequiredValue "DEV_DB_PASSWORD" $DbPassword

Assert-NotProduction "DEV_DB_HOST" $DbHost
Assert-NotProduction "DEV_DB_NAME" $DbName
Assert-NotProduction "DEV_GCP_PROJECT" $GcpProject
Assert-NotProduction "DEV_DB_SECRET_NAME" $SecretName

if ($Confirmation -cne "YES") {
    throw "Refusing to run: set CONFIRM_DEV_DB_RESET=YES."
}

if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
    throw "psql is required and was not found on PATH."
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Migrations = @(
    "scripts\migrations\migrate_12_bim_catalog_project_element_registry.sql",
    "scripts\migrations\migrate_13_layer3_canonical_evidence.sql",
    "scripts\migrations\migrate_14_progress_reconciliation_draft.sql"
)

Write-Host "DESTRUCTIVE DEV MIGRATION TARGET"
Write-Host "  Host: $DbHost"
Write-Host "  Port: $DbPort"
Write-Host "  Database: $DbName"
Write-Host "  User: $DbUser"

$env:PGPASSWORD = $DbPassword
try {
    foreach ($Migration in $Migrations) {
        $MigrationPath = Join-Path $RepoRoot $Migration
        if (-not (Test-Path -LiteralPath $MigrationPath -PathType Leaf)) {
            throw "Migration file not found: $MigrationPath"
        }

        Write-Host "Applying $Migration"
        & psql -X -h $DbHost -p $DbPort -U $DbUser -d $DbName `
            -v ON_ERROR_STOP=1 -f $MigrationPath
        if ($LASTEXITCODE -ne 0) {
            throw "psql failed while applying $Migration."
        }
    }
}
finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}

Write-Host "Clean migrations 12-14 applied to the development database."
