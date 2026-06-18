-- DRAFT ONLY. DO NOT APPLY UNTIL REVIEWED.
-- Drops deprecated BIM Layer 0 catalog tables after successful catalog refactor.
-- Does not use DROP CASCADE and does not touch Layer 3 or progress data.

BEGIN;

DO $$
DECLARE
    missing_tables TEXT[];
    dependency_count INTEGER;
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

    SELECT COUNT(*)
    INTO dependency_count
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
      );

    IF dependency_count > 0 THEN
        RAISE EXCEPTION
            'Refusing to drop deprecated BIM catalog tables. % foreign key dependencies still reference them.',
            dependency_count;
    END IF;
END $$;

DROP TABLE IF EXISTS bim.deprecated_bt_element_type_document_requirement;
DROP TABLE IF EXISTS bim.deprecated_bt_element_type_quality_requirement;
DROP TABLE IF EXISTS bim.deprecated_bt_element_type_activity_template;
DROP TABLE IF EXISTS bim.deprecated_bt_element_type_catalog;

COMMIT;

