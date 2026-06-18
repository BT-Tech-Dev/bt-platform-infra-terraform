-- READ-ONLY VALIDATION. Safe to run after reviewed clean catalog migrations.
-- This file does not create, alter, truncate, or drop database objects.

-- ---------------------------------------------------------------------------
-- 1. Migration-order prerequisites and canonical tables
-- ---------------------------------------------------------------------------
SELECT validation_target, to_regclass(validation_target) IS NOT NULL AS exists
FROM (
    VALUES
        ('tenant.company'),
        ('tenant.project'),
        ('raw.import_file'),
        ('raw.ingestion_run'),
        ('catalog.element_type'),
        ('catalog.element_type_property_template'),
        ('catalog.element_type_activity_template'),
        ('catalog.element_type_quality_requirement'),
        ('catalog.element_type_document_requirement'),
        ('catalog.element_type_classification_mapping'),
        ('bim.project_element_registry'),
        ('bim.project_element_identifier'),
        ('document.document_ref'),
        ('production.mix_recipe'),
        ('production.mix_recipe_component'),
        ('production.production_record'),
        ('quality.quality_test_result'),
        ('progress.evidence_link'),
        ('progress.progress_derivation_rule')
) AS expected(validation_target)
ORDER BY 1;

SELECT schema_name AS target_schema, schema_name IS NOT NULL AS exists
FROM information_schema.schemata
WHERE schema_name IN ('catalog', 'bim')
ORDER BY 1;

-- ---------------------------------------------------------------------------
-- 2. Legacy tables must be absent
-- ---------------------------------------------------------------------------
SELECT validation_target, to_regclass(validation_target) IS NULL AS is_absent
FROM (
    VALUES
        ('production.prefab_manufactured_element'),
        ('quality.prefab_compression_test_result'),
        ('bim.bt_element_type_catalog'),
        ('bim.bt_element_type_activity_template'),
        ('bim.bt_element_type_quality_requirement'),
        ('bim.bt_element_type_document_requirement')
) AS legacy(validation_target)
ORDER BY 1;

SELECT validation_target, to_regclass(validation_target) IS NULL AS is_absent
FROM (
    VALUES
        ('bim.deprecated_bt_element_type_catalog'),
        ('bim.deprecated_bt_element_type_activity_template'),
        ('bim.deprecated_bt_element_type_quality_requirement'),
        ('bim.deprecated_bt_element_type_document_requirement')
) AS deprecated(validation_target)
ORDER BY 1;

-- Expected result is zero rows. Rows here are external active-schema blockers
-- for dropping deprecated BIM catalog tables.
WITH deprecated_tables AS (
    SELECT deprecated_target::regclass AS table_oid
    FROM (
        VALUES
            ('bim.deprecated_bt_element_type_catalog'),
            ('bim.deprecated_bt_element_type_activity_template'),
            ('bim.deprecated_bt_element_type_quality_requirement'),
            ('bim.deprecated_bt_element_type_document_requirement')
    ) AS deprecated(deprecated_target)
    WHERE to_regclass(deprecated_target) IS NOT NULL
)
SELECT nsp_ref.nspname AS referencing_schema,
       cls_ref.relname AS referencing_table,
       con.conname AS constraint_name,
       nsp_tgt.nspname AS referenced_schema,
       cls_tgt.relname AS referenced_table,
       pg_get_constraintdef(con.oid) AS constraint_definition
FROM pg_constraint AS con
JOIN pg_class AS cls_ref
  ON cls_ref.oid = con.conrelid
JOIN pg_namespace AS nsp_ref
  ON nsp_ref.oid = cls_ref.relnamespace
JOIN pg_class AS cls_tgt
  ON cls_tgt.oid = con.confrelid
JOIN pg_namespace AS nsp_tgt
  ON nsp_tgt.oid = cls_tgt.relnamespace
WHERE con.contype = 'f'
  AND con.confrelid IN (SELECT table_oid FROM deprecated_tables)
  AND con.conrelid NOT IN (SELECT table_oid FROM deprecated_tables)
ORDER BY nsp_ref.nspname,
         cls_ref.relname,
         con.conname,
         nsp_tgt.nspname,
         cls_tgt.relname;

-- ---------------------------------------------------------------------------
-- 3. Stale canonical columns must be absent; expected result is zero rows
-- ---------------------------------------------------------------------------
SELECT table_schema, table_name, column_name
FROM information_schema.columns
WHERE (table_schema, table_name, column_name) IN (
    ('production', 'production_record', 'id'),
    ('production', 'production_record', 'element_progress_id'),
    ('document', 'document_ref', 'id'),
    ('production', 'mix_recipe', 'id')
)
ORDER BY table_schema, table_name, column_name;

-- ---------------------------------------------------------------------------
-- 4. evidence_link contract
-- ---------------------------------------------------------------------------
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'progress'
  AND table_name = 'evidence_link'
  AND column_name IN (
      'evidence_link_id',
      'tenant_id',
      'project_code',
      'project_element_id',
      'evidence_kind',
      'evidence_id',
      'matched_identifier_id',
      'match_method',
      'link_status',
      'is_effective',
      'reason'
  )
ORDER BY ordinal_position;

SELECT conname, pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'progress.evidence_link'::regclass
  AND contype = 'c'
ORDER BY conname;

-- ---------------------------------------------------------------------------
-- 5. Required idempotency/current-state indexes
-- ---------------------------------------------------------------------------
SELECT expected.index_name,
       actual.indexname IS NOT NULL AS exists,
       actual.indexdef
FROM (
    VALUES
        ('uq_production_record_source_row'),
        ('uq_quality_test_result_source_row'),
        ('uq_evidence_link_effective'),
        ('uq_evidence_link_current_unresolved'),
        ('uq_catalog_element_type_global_code_version'),
        ('uq_catalog_element_type_project_code_version'),
        ('uq_catalog_classification_mapping_global'),
        ('uq_catalog_classification_mapping_project')
) AS expected(index_name)
LEFT JOIN pg_indexes AS actual
  ON actual.indexname = expected.index_name
ORDER BY expected.index_name;

-- ---------------------------------------------------------------------------
-- 6. Primary-key shape
-- ---------------------------------------------------------------------------
SELECT conrelid::regclass AS validation_target,
       conname,
       pg_get_constraintdef(oid) AS primary_key_definition
FROM pg_constraint
WHERE conrelid IN (
    'production.production_record'::regclass,
    'quality.quality_test_result'::regclass,
    'document.document_ref'::regclass,
    'progress.evidence_link'::regclass
)
  AND contype = 'p'
ORDER BY 1, 2;

-- ---------------------------------------------------------------------------
-- 6b. Cross-schema FK target for BIM registry and progress rules
-- ---------------------------------------------------------------------------
SELECT conrelid::regclass AS validation_target,
       conname,
       confrelid::regclass AS referenced_target,
       pg_get_constraintdef(oid) AS foreign_key_definition
FROM pg_constraint
WHERE conrelid IN (
    'bim.project_element_registry'::regclass,
    'progress.progress_derivation_rule'::regclass
)
  AND contype = 'f'
  AND conkey = ARRAY[
      (
          SELECT attnum
          FROM pg_attribute
          WHERE attrelid = conrelid
            AND attname = 'element_type_id'
      )::smallint
  ]
ORDER BY 1, 2;

-- ---------------------------------------------------------------------------
-- 6c. Layer 3 and progress data-bearing tables remain present
-- ---------------------------------------------------------------------------
SELECT validation_target, to_regclass(validation_target) IS NOT NULL AS exists
FROM (
    VALUES
        ('production.production_record'),
        ('quality.quality_test_result'),
        ('document.document_ref'),
        ('progress.evidence_link')
) AS data_tables(validation_target)
ORDER BY 1;

-- Capture these counts before and after cleanup migrations. They should not
-- change when applying migrate_15 or migrate_16.
SELECT 'production.production_record' AS validation_target, COUNT(*) AS row_count
FROM production.production_record
UNION ALL
SELECT 'quality.quality_test_result' AS validation_target, COUNT(*) AS row_count
FROM quality.quality_test_result
UNION ALL
SELECT 'progress.evidence_link' AS validation_target, COUNT(*) AS row_count
FROM progress.evidence_link
ORDER BY 1;

-- ---------------------------------------------------------------------------
-- 7. Effective evidence integrity; expected count is zero
-- ---------------------------------------------------------------------------
SELECT COUNT(*) AS invalid_effective_links
FROM progress.evidence_link
WHERE is_effective
  AND (link_status <> 'confirmed' OR project_element_id IS NULL);

-- ---------------------------------------------------------------------------
-- 8. Current unresolved uniqueness health; expected duplicate_groups is zero
-- ---------------------------------------------------------------------------
SELECT COUNT(*) AS duplicate_groups
FROM (
    SELECT tenant_id, project_code, evidence_kind, evidence_id
    FROM progress.evidence_link
    WHERE link_status IN ('unmatched', 'needs_review')
      AND is_effective = FALSE
    GROUP BY tenant_id, project_code, evidence_kind, evidence_id
    HAVING COUNT(*) > 1
) AS duplicates;
