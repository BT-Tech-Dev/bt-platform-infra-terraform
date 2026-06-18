-- DRAFT ONLY. DO NOT APPLY UNTIL REVIEWED.
-- Drops deprecated BIM Layer 0 catalog tables after successful catalog refactor.
-- Does not use DROP CASCADE and does not touch Layer 3 or progress data.

BEGIN;

DO $$
DECLARE
    missing_tables TEXT[];
    external_dependencies TEXT[];
    internal_constraint RECORD;
BEGIN
    SELECT array_agg(required_table)
    INTO missing_tables
    FROM (
        VALUES
            ('catalog.element_type'),
            ('catalog.element_type_activity_template'),
            ('catalog.element_type_quality_requirement'),
            ('catalog.element_type_document_requirement')
    ) AS required(required_table)
    WHERE to_regclass(required_table) IS NULL;

    IF missing_tables IS NOT NULL THEN
        RAISE EXCEPTION
            'Refusing to drop deprecated BIM catalog tables. Missing required catalog tables: %',
            missing_tables;
    END IF;

    -- Diagnostic query for external blockers:
    -- SELECT conrelid::regclass AS referencing_table,
    --        conname AS constraint_name,
    --        confrelid::regclass AS referenced_table,
    --        pg_get_constraintdef(oid) AS constraint_definition
    -- FROM pg_constraint
    -- WHERE contype = 'f'
    --   AND confrelid IN (
    --       'bim.deprecated_bt_element_type_catalog'::regclass,
    --       'bim.deprecated_bt_element_type_activity_template'::regclass,
    --       'bim.deprecated_bt_element_type_quality_requirement'::regclass,
    --       'bim.deprecated_bt_element_type_document_requirement'::regclass
    --   )
    --   AND conrelid NOT IN (
    --       'bim.deprecated_bt_element_type_catalog'::regclass,
    --       'bim.deprecated_bt_element_type_activity_template'::regclass,
    --       'bim.deprecated_bt_element_type_quality_requirement'::regclass,
    --       'bim.deprecated_bt_element_type_document_requirement'::regclass
    --   );
    SELECT array_agg(
        conrelid::regclass::text || '.' || conname || ' -> ' || confrelid::regclass::text
        ORDER BY conrelid::regclass::text, conname
    )
    INTO external_dependencies
    FROM pg_constraint
    WHERE contype = 'f'
      AND confrelid IN (
          SELECT table_name::regclass
          FROM (
              VALUES
                  ('bim.deprecated_bt_element_type_catalog'),
                  ('bim.deprecated_bt_element_type_activity_template'),
                  ('bim.deprecated_bt_element_type_quality_requirement'),
                  ('bim.deprecated_bt_element_type_document_requirement')
          ) AS deprecated(table_name)
          WHERE to_regclass(table_name) IS NOT NULL
      )
      AND conrelid NOT IN (
          SELECT table_name::regclass
          FROM (
              VALUES
                  ('bim.deprecated_bt_element_type_catalog'),
                  ('bim.deprecated_bt_element_type_activity_template'),
                  ('bim.deprecated_bt_element_type_quality_requirement'),
                  ('bim.deprecated_bt_element_type_document_requirement')
          ) AS deprecated(table_name)
          WHERE to_regclass(table_name) IS NOT NULL
      );

    IF external_dependencies IS NOT NULL THEN
        RAISE EXCEPTION
            'Refusing to drop deprecated BIM catalog tables. External FK dependencies still reference them: %',
            external_dependencies;
    END IF;

    -- Internal FK constraints among deprecated tables are expected after
    -- migration 15 renames the old tables. Drop those constraints explicitly
    -- before dropping the deprecated child tables, without using DROP CASCADE.
    FOR internal_constraint IN
        SELECT conrelid::regclass AS referencing_table,
               conname
        FROM pg_constraint
        WHERE contype = 'f'
          AND confrelid IN (
              SELECT table_name::regclass
              FROM (
                  VALUES
                      ('bim.deprecated_bt_element_type_catalog'),
                      ('bim.deprecated_bt_element_type_activity_template'),
                      ('bim.deprecated_bt_element_type_quality_requirement'),
                      ('bim.deprecated_bt_element_type_document_requirement')
              ) AS deprecated(table_name)
              WHERE to_regclass(table_name) IS NOT NULL
          )
          AND conrelid IN (
              SELECT table_name::regclass
              FROM (
                  VALUES
                      ('bim.deprecated_bt_element_type_catalog'),
                      ('bim.deprecated_bt_element_type_activity_template'),
                      ('bim.deprecated_bt_element_type_quality_requirement'),
                      ('bim.deprecated_bt_element_type_document_requirement')
              ) AS deprecated(table_name)
              WHERE to_regclass(table_name) IS NOT NULL
          )
        ORDER BY conrelid::regclass::text, conname
    LOOP
        EXECUTE format(
            'ALTER TABLE %s DROP CONSTRAINT %I',
            internal_constraint.referencing_table,
            internal_constraint.conname
        );
    END LOOP;
END $$;

DROP TABLE IF EXISTS bim.deprecated_bt_element_type_document_requirement;
DROP TABLE IF EXISTS bim.deprecated_bt_element_type_quality_requirement;
DROP TABLE IF EXISTS bim.deprecated_bt_element_type_activity_template;
DROP TABLE IF EXISTS bim.deprecated_bt_element_type_catalog;

COMMIT;
