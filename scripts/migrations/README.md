# Database migrations

`scripts/init_db.*` bootstraps a database from zero by executing the canonical schema DDL in `modules/cloud_sql/sql`.

`scripts/migrations` contains manual patch scripts for existing databases that were already created from an older DDL version. These scripts are not executed automatically by Terraform in the current workflow.

During the current development phase, migrations may be consolidated before an official production baseline is declared. After a baseline is published for live environments, migration files should be treated as append-only and should not be rewritten or deleted.

For MS-05 Moretti prefab elements, `migrate_10_production_prefab_manufactured_element.sql` is the consolidated migration. The temporary raw-record and raw-payload patch migrations were merged into it before the baseline.

## Canonical evidence model draft sequence

The Layer 0-4 canonical evidence model is drafted in:

1. `migrate_12_bim_catalog_project_element_registry.sql`
2. `migrate_13_layer3_canonical_evidence.sql`
3. `migrate_14_progress_reconciliation_draft.sql`
4. `migrate_15_catalog_schema_refactor.sql`
5. `migrate_16_drop_deprecated_bim_catalog_tables.sql`
6. `migrate_17_catalog_definition_applicability_refactor.sql`
7. `migrate_18_seed_catalog_from_workbook.sql`
8. `migrate_19_project_element_registry_hardening.sql`
9. `migrate_20_grant_catalog_read_to_app.sql`

These files are drafts for manual review. They have not been executed.
They form one destructive transition and must be reviewed/run as a contiguous
sequence. `migrate_12` removes known Layer 3/4 dependants before replacing
Layer 0/1, `migrate_13` recreates Layer 3, and `migrate_14` recreates Layer 4.
`migrate_15` refactors the BT element type catalog out of `bim` into
`catalog` without dropping Layer 3 or progress data.
`migrate_16` drops only the deprecated BIM catalog tables after validating
that the catalog tables exist and no FK dependencies still reference the
deprecated tables.
`migrate_17` refactors the catalog from long element-type template tables to a
matrix-first normalized definition/applicability model.
`migrate_18` seeds the Layer 0 catalog from the reviewed
`BT_Element_Catalog_Master_migrate_18_source.xlsx` workbook snapshot. It is
catalog-only, uses temporary seed tables inside a single transaction, and does
not touch BIM Layer 1, production, quality result, progress, reconciliation, or
SAL tables.
`migrate_19` is a narrow additive BIM Layer 1 registry hardening draft for
MS-01. It adds registry origin flags to `bim.project_element_registry` only and
does not touch Layer 0 catalog data, BIM source elements, production, quality,
progress, reconciliation, or SAL tables.
`migrate_20` grants read-only `bt_app` access to the Layer 0 `catalog` schema
and tables so application services can resolve element type codes and validate
classifier configuration. It is grants-only and does not change catalog data or
any BIM, production, quality, progress, reconciliation, or SAL tables.

The dependency-safe bootstrap manifest is:

1. `tenant`
2. `raw`
3. `catalog`
4. `bim`
5. `process`
6. `boq`
7. `document`
8. `production`
9. `progress`
10. `quality`
11. `read` / `external`
12. seeds

The current filenames retain their historical numbers. The explicit manifests
in `scripts/init_db.ps1`, `scripts/init_db.sh`, and
`scripts/init_db_cloudbuild.sh` are authoritative and execute `raw`,
`catalog`, and `document` before their dependants.

The final Layer 0 schema name is `catalog`, not `bim` and not `library`.
`catalog` stores reusable/project-aware BT element type reference data:
`element_type`, `property_definition`,
`element_type_property_applicability`, `activity_definition`,
`element_type_activity_applicability`, `quality_requirement_definition`,
`element_type_quality_applicability`, `document_requirement_definition`,
`element_type_document_applicability`, and
`element_type_classification_mapping`. `bim` stores imported BIM model data and
project-specific BIM baseline/registry tables. `bim.project_element_registry`
has a cross-schema FK to `catalog.element_type`.

`BT_Element_Catalog_Master.xlsx` is matrix-first for human editing. Excel
definition sheets map to `*_definition` tables, matrix sheets map to
`element_type_*_applicability` tables, and `06_Classification_Table` maps to
`catalog.element_type_classification_mapping`. `source_sheet`, `source_row`,
helper notes, and reviewer notes are import/staging metadata and are not DB
domain fields in the normalized catalog schema.

`migrate_15_catalog_schema_refactor.sql` creates `catalog`, copies any existing
rows from `bim.bt_element_type_*` tables, updates the element-type FKs in
`bim.project_element_registry` and `progress.progress_derivation_rule`, and
renames old BIM catalog tables to `bim.deprecated_bt_element_type_*` when
present. It does not use `DROP CASCADE`.

`migrate_16_drop_deprecated_bim_catalog_tables.sql` is the cleanup migration
after a successful catalog refactor. It checks required `catalog.*` tables and
external FK dependencies, drops internal FK constraints among deprecated tables,
then drops:

- `bim.deprecated_bt_element_type_document_requirement`
- `bim.deprecated_bt_element_type_quality_requirement`
- `bim.deprecated_bt_element_type_activity_template`
- `bim.deprecated_bt_element_type_catalog`

It does not use `DROP CASCADE` and does not touch
`production.production_record`, `quality.quality_test_result`, or
`progress.evidence_link`.

`migrate_17_catalog_definition_applicability_refactor.sql` creates the
definition/applicability tables, backfills them from existing
`catalog.element_type_*` template tables when present, checks for external FK
dependencies, and then drops the obsolete template tables explicitly:

- `catalog.element_type_document_requirement`
- `catalog.element_type_quality_requirement`
- `catalog.element_type_activity_template`
- `catalog.element_type_property_template`

It does not use `DROP CASCADE`, does not seed from Excel, and does not touch
Layer 1, Layer 3, or progress data.

`production.prefab_manufactured_element` and
`quality.prefab_compression_test_result` are dropped by the clean Layer 3 draft.
The clean drafts assume affected data can be truncated and reloaded. They must
not be applied until the destructive reload and rollback plans are approved.

The earlier `migrate_10_production_prefab_manufactured_element.sql` and
`migrate_11_quality_prefab_compression_test_result.sql` drafts are superseded by
the clean canonical transition and must not be run after migrations 12-14.

For an intentional manual apply to the current production-named Cloud SQL
instance, use `CLOUD_SQL_STUDIO_CLEAN_APPLY_CHECKLIST.md`. The combined
`apply_clean_12_14_manual.sql` bundle is provided for review and compatible SQL
clients, but Cloud SQL Studio operators should run migrations 12, 13, and 14
one at a time. Run `validate_clean_schema.sql` after all three complete.

Layer 4 `progress.evidence_link` persists every reconciliation outcome:
`confirmed`, `needs_review`, `unmatched`, `rejected`, and `superseded`.
Unmatched rows can be reprocessed after identifiers are loaded. SAL/progress
derivation must consume only confirmed links marked effective.

Only one current unresolved outcome is allowed per evidence. Reconciliation
upserts unresolved outcomes using this exact conflict target and predicate:

```sql
ON CONFLICT (tenant_id, project_code, evidence_kind, evidence_id)
WHERE link_status IN ('unmatched', 'needs_review')
  AND is_effective = FALSE
```

Confirmed/effective rows are SAL/progress eligible. Unmatched/needs-review rows
are review/audit only. Rejected and superseded rows are unconstrained history.

## Development-only clean migration apply

Do not use `scripts/init_db.ps1` or `scripts/init_db.sh` unchanged for a
development reset: their current defaults or secret handling reference
production. Historical migrations 10 and 11 are superseded and must not be run.

The guarded development scripts require explicit connection values, reject
targets whose host, database, optional GCP project, or optional secret name
contains `prod` or `production`, and apply only migrations 12, 13, and 14.

PowerShell:

```powershell
$env:DEV_DB_HOST = "<DEV_HOST>"
$env:DEV_DB_NAME = "<DEV_DB>"
$env:DEV_DB_USER = "<DEV_USER>"
$env:DEV_DB_PASSWORD = "<DEV_PASSWORD>"
$env:CONFIRM_DEV_DB_RESET = "YES"
.\scripts\dev\apply_clean_migrations_dev.ps1
```

Bash:

```bash
DEV_DB_HOST='<DEV_HOST>' \
DEV_DB_NAME='<DEV_DB>' \
DEV_DB_USER='<DEV_USER>' \
DEV_DB_PASSWORD='<DEV_PASSWORD>' \
CONFIRM_DEV_DB_RESET=YES \
bash scripts/dev/apply_clean_migrations_dev.sh
```

Optional variables are `DEV_DB_PORT`, `DEV_GCP_PROJECT`, and
`DEV_DB_SECRET_NAME`. The scripts do not retrieve secrets, run Terraform, or
deploy services.

## Post-apply validation

Run these queries manually only after the reviewed clean migration apply:

```sql
SELECT
    to_regclass('production.production_record') AS production_record,
    to_regclass('quality.quality_test_result') AS quality_test_result,
    to_regclass('document.document_ref') AS document_ref,
    to_regclass('progress.evidence_link') AS evidence_link,
    to_regclass('production.prefab_manufactured_element') AS legacy_production,
    to_regclass('quality.prefab_compression_test_result') AS legacy_quality;

SELECT table_schema, table_name, column_name
FROM information_schema.columns
WHERE (table_schema, table_name, column_name) IN (
    ('production', 'production_record', 'id'),
    ('production', 'production_record', 'element_progress_id'),
    ('document', 'document_ref', 'id'),
    ('production', 'mix_recipe', 'id')
);

SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE indexname IN (
    'uq_production_record_source_row',
    'uq_quality_test_result_source_row',
    'uq_evidence_link_effective',
    'uq_evidence_link_current_unresolved'
)
ORDER BY schemaname, tablename, indexname;

SELECT COUNT(*) AS invalid_effective_links
FROM progress.evidence_link
WHERE is_effective
  AND (link_status <> 'confirmed' OR project_element_id IS NULL);
```
