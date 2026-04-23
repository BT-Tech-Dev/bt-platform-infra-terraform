-- =============================================================================
-- 12_seed_tenants.sql
-- Inserisce i 2 tenant iniziali della piattaforma BuildTrust
--
-- ESEGUIRE DOPO tutti gli altri script (dipende da 02_schema_tenant.sql).
-- Idempotente: usa ON CONFLICT DO NOTHING (sicuro da rieseguire).
--
-- Tenant 1: Ponte sul Po di Levante (migrazione dal vecchio progetto bt-bim)
-- Tenant 2: Balocco 2 (nuovo progetto)
-- =============================================================================

-- ─── Company 1: Ponte sul Po di Levante ──────────────────────────────────────
INSERT INTO tenant.company (id, code, name, description, status, config)
VALUES (
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    'PPDL',
    'Ponte sul Po di Levante',
    'Viadotto Ponte sul Po di Levante - Autostrada A21 Torino-Brescia. Committente: Autostrade per l''Italia.',
    'active',
    jsonb_build_object(
        'revit_project_code',   '0549-IDG',
        'revit_file_name',      '0549-IDG-PPDL-L00-A-INF-3D-A',
        'target_elements',      83,
        'gcs_prefix',           'ppdl/',
        'old_project_id',       'bt-bim-po-levante-prod',
        'old_db_schema',        'bt_v1',
        'concrete_supplier',    'Superbeton/Gruppo Grigolin',
        'concrete_ftp_contact', 'Mathieu Licata',
        'notes',                'Migrato da bt-bim-po-levante-prod'
    )
)
ON CONFLICT (code) DO NOTHING;

-- Progetto associato a PPDL
INSERT INTO tenant.project (tenant_id, project_code, project_name, status, started_at)
VALUES (
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    '0549-IDG',
    'Ponte Po di Levante — Strutture in acciaio e fondazioni',
    'active',
    '2025-10-01'
)
ON CONFLICT (tenant_id, project_code) DO NOTHING;

-- ─── Company 2: Balocco 2 ─────────────────────────────────────────────────────
INSERT INTO tenant.company (id, code, name, description, status, config)
VALUES (
    'b2c3d4e5-f6a7-8901-bcde-f12345678901',
    'BAL2',
    'Balocco 2',
    'Stabilimento di produzione prefabbricati in calcestruzzo Balocco 2.',
    'active',
    jsonb_build_object(
        'notes', 'Progetto in fase di avvio — configurazione BIM da completare'
    )
)
ON CONFLICT (code) DO NOTHING;

-- ─── Verifica ─────────────────────────────────────────────────────────────────
-- SELECT id, code, name, status FROM tenant.company ORDER BY created_at;
