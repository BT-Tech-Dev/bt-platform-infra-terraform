# Revit Actual Export Job

Job: `revit-actual-balocco2-zone1-piles` in `bt-platform-prod`, region
`europe-west8`.

## Execute

Console: Cloud Run > Jobs > `revit-actual-balocco2-zone1-piles` > Execute.

```powershell
$g = 'C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd'
& $g run jobs execute revit-actual-balocco2-zone1-piles `
  --project=bt-platform-prod `
  --region=europe-west8 `
  --wait
```

Expected output prefix:

```text
gs://bt-platform-exports-prod/exports/revit-actual/balocco2/balocco2_zone1_pile_installed_v1/
```

Do not execute the Job while its database password is being rotated.

## Image Update

1. Deploy and validate the new `bim-parser-v1` revision.
2. Resolve its digest from Cloud Run, not its tag:

   ```powershell
   & $g run revisions list --service=bim-parser-v1 `
     --project=bt-platform-prod --region=europe-west8 `
     --sort-by='~metadata.creationTimestamp' --limit=1 `
     --format='value(spec.containers[0].image)'
   ```

3. Set `revit_export_bim_parser_image` in `terraform.tfvars` to that exact
   `@sha256:` reference, then review a saved plan. Never use an image tag.

## Password Rotation

`revit_export_ro_password_rotation_epoch` rotates the same ephemeral password
into both `google_sql_user.revit_export_ro.password_wo` and the Revit export
Secret Manager version. Increment it once per deliberate rotation.

1. Ensure no Job execution can start.
2. Increment the epoch and review a saved plan.
3. Apply the reviewed plan. Secret Manager creates the enabled replacement
   before destroying the superseded version; the Job uses secret version
   `latest` only when a later execution starts.
4. Verify the new secret version, read-only database login, role attributes,
   and Job image before executing the Job again.

If an apply fails after either the SQL password or Secret Manager version was
updated, do not retry the same saved plan and do not attempt to recover the
ephemeral password. Keep the Job stopped, increment the epoch again, create a
new plan, and apply that coordinated rotation.

## Database Privileges

Google provider `6.50.0` does not manage `google_sql_user.database_roles`.
When this built-in PostgreSQL user is first created or recreated, remove its
default Cloud SQL membership manually before any Job execution:

```powershell
& $g sql users assign-roles revit_export_ro `
  --project=bt-platform-prod `
  --type=BUILT_IN `
  --instance=bt-platform-pg-prod `
  --database-roles= `
  --revoke-existing-roles
```

Then run the approved database-admin operation:

```sql
ALTER ROLE revit_export_ro NOCREATEDB NOCREATEROLE;
```

The export role is intentionally limited to its approved direct column-level
`SELECT` grants. Those grants are not Terraform-managed. Its query surface is
`bim.project_element_registry`, `bim.project_element_identifier`,
`bim.bim_element`, `catalog.element_type`, `progress.evidence_link`,
`process.operational_event`, and `raw.import_file`.

After `migrate_30_moretti_manufactured_unit.sql`, apply
`scripts/migrations/migrate_31_grant_revit_export_operational_event.sql` as a
database administrator. It grants `revit_export_ro` schema `USAGE` on
`process` and column-level `SELECT` only on
`process.operational_event(operational_event_id, event_date)`.

Verify the live grant inventory and role attributes after creation or rotation:

```sql
SELECT table_schema, table_name, column_name, privilege_type
FROM information_schema.column_privileges
WHERE grantee = 'revit_export_ro'
ORDER BY table_schema, table_name, column_name;

SELECT r.rolsuper, r.rolcreatedb, r.rolcreaterole, r.rolbypassrls,
       EXISTS (
         SELECT 1
         FROM pg_auth_members membership
         JOIN pg_roles granted_role ON granted_role.oid = membership.roleid
         WHERE membership.member = r.oid
           AND granted_role.rolname = 'cloudsqlsuperuser'
       ) AS has_cloudsqlsuperuser
FROM pg_roles r
WHERE r.rolname = 'revit_export_ro';
```

Expected: all four role attributes and `has_cloudsqlsuperuser` are `false`.
