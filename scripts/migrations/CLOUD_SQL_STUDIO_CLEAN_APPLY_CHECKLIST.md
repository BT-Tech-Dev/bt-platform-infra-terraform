# Cloud SQL Studio Clean Canonical Apply Checklist

## Scope and warning

This procedure intentionally performs a destructive reset of the canonical
Layer 0/1/3/4 tables in the current Cloud SQL database. Data in the dropped
tables will be lost and must be reloaded from GCS or other source systems.

Do not apply until a restorable backup exists and every database writer has
been stopped.

Migrations 10 and 11 are superseded by this transition. Do not run either of
these after migrations 12, 13, and 14:

- `migrate_10_production_prefab_manufactured_element.sql`
- `migrate_11_quality_prefab_compression_test_result.sql`

## Pre-apply checklist

- [ ] Confirm the target Cloud SQL instance, database, and PostgreSQL user.
- [ ] Confirm this reset is intentionally targeting the current production-named instance.
- [ ] Confirm canonical Layer 3 data can be reloaded from GCS/source files.
- [ ] Confirm migrations 12, 13, and 14 are the reviewed versions.
- [ ] Confirm no earlier migration will run automatically afterward.
- [ ] Record the current application/service revisions.
- [ ] Record the reset start time and responsible operator.
- [ ] Schedule a maintenance window.

## Required backup

- [ ] Create an on-demand Cloud SQL backup or export before stopping the maintenance window.
- [ ] Record the backup/export identifier and timestamp.
- [ ] Confirm the backup reports success.
- [ ] Confirm the operator knows how to restore it to a replacement instance or database.

Do not proceed without a completed, restorable backup.

## Stop writers

Stop or scale to zero every process that can write to the affected database:

- [ ] MS-05 production ingestion service
- [ ] quality/ABC ingestion writers
- [ ] document ingestion writers
- [ ] reconciliation-service
- [ ] SAL/progress derivation engine
- [ ] read-model/projector workers
- [ ] Hasura mutations or other API writers
- [ ] ACDAT/external synchronization writers
- [ ] scheduled jobs, retries, and queued workers

Verify that no writer will automatically restart during the apply window.

## Recommended Cloud SQL Studio procedure

Run the three migration files **one at a time**, in this exact order:

1. `migrate_12_bim_catalog_project_element_registry.sql`
2. `migrate_13_layer3_canonical_evidence.sql`
3. `migrate_14_progress_reconciliation_draft.sql`

The updated `migrate_12` creates Layer 0 in `catalog`, not `bim`. If the
database already has the earlier clean schema with `bim.bt_element_type_*`
tables, run `migrate_15_catalog_schema_refactor.sql` after migration 14, or run
it standalone after confirming migrations 12-14 were already applied.

Each migration contains its own `BEGIN` and `COMMIT`. Run the complete contents
of one file in a single Cloud SQL Studio execution. Confirm success before
pasting and running the next file.

The combined `apply_clean_12_14_manual.sql` bundle preserves those transaction
boundaries and may be run as-is by a SQL client that accepts a multi-statement
script. For Cloud SQL Studio, running one migration at a time is preferred:
failure after a committed section is easier to identify and recover from, and
the editor may impose session, statement, or execution-time limits.

Do not run migrations 13 or 14 if the preceding migration reports an error.

## Apply log

- [ ] Migration 12 completed successfully
- [ ] Migration 13 completed successfully
- [ ] Migration 14 completed successfully
- [ ] No unexpected errors or disconnects occurred
- [ ] Start and completion timestamps recorded

## Validate

Run the complete contents of `validate_clean_schema.sql` in Cloud SQL Studio.
Review every result set before restarting writers.

Expected results:

- All canonical-table checks report `true`.
- All prerequisite/order-assumption checks report `true`.
- Legacy-table checks report `true` for `is_absent`.
- Stale-column query returns zero rows.
- Required evidence-link columns report the expected nullability.
- Required status check and unique indexes are present.
- Invalid effective-link count is zero.

## Reload and restart

- [ ] Reload Layer 0 catalog and Layer 1 project element identifiers.
- [ ] Reload canonical Layer 3 evidence from GCS/source systems.
- [ ] Run reconciliation and confirm unresolved/confirmed writes succeed.
- [ ] Run validation again.
- [ ] Restart readers and SAL/progress derivation.
- [ ] Restart ingestion and remaining writers in a controlled order.
- [ ] Monitor database errors, reconciliation conflicts, and queue retries.

## Rollback plan

If a migration fails before its `COMMIT`, its changes should roll back. Do not
continue to the next migration.

If migration 12 or 13 commits and a later migration fails, the database is in
an intentionally incomplete transition. Keep writers stopped and choose one:

1. Fix the reviewed migration and rerun the remaining transition while the
   maintenance window remains open.
2. Restore the pre-apply Cloud SQL backup/export to a replacement instance or
   database, validate it, then redirect services according to the operational
   recovery procedure.

Do not attempt to roll back by rerunning historical migrations 10 or 11.
