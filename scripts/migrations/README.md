# Database migrations

`scripts/init_db.*` bootstraps a database from zero by executing the canonical schema DDL in `modules/cloud_sql/sql`.

`scripts/migrations` contains manual patch scripts for existing databases that were already created from an older DDL version. These scripts are not executed automatically by Terraform in the current workflow.

During the current development phase, migrations may be consolidated before an official production baseline is declared. After a baseline is published for live environments, migration files should be treated as append-only and should not be rewritten or deleted.

For MS-05 Moretti prefab elements, `migrate_10_production_prefab_manufactured_element.sql` is the consolidated migration. The temporary raw-record and raw-payload patch migrations were merged into it before the baseline.
