-- DRAFT ONLY. DO NOT APPLY UNTIL THE CLEAN RELOAD PLAN IS APPROVED.
-- Destructively replaces Layer 4 reconciliation/rule draft tables.
-- Reconciliation writes Layer 4. MS-05 writes Layer 3 only.
-- The SAL Engine reads Layer 4/progress, not raw parser output.

BEGIN;

DROP TABLE IF EXISTS progress.evidence_link;
DROP TABLE IF EXISTS progress.progress_derivation_rule;

CREATE TABLE progress.evidence_link (
    evidence_link_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    project_code VARCHAR(50) NOT NULL,
    project_element_id UUID,
    evidence_kind VARCHAR(30) NOT NULL,
    evidence_id UUID NOT NULL,
    evidence_type VARCHAR(100) NOT NULL,
    matched_identifier_id UUID,
    match_method VARCHAR(50),
    match_value VARCHAR(200),
    confidence NUMERIC(4,3),
    link_status VARCHAR(30) NOT NULL DEFAULT 'unmatched',
    is_effective BOOLEAN NOT NULL DEFAULT FALSE,
    reason TEXT,
    matched_by VARCHAR(200),
    matched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_by VARCHAR(200),
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    FOREIGN KEY (project_element_id, tenant_id, project_code)
        REFERENCES bim.project_element_registry(project_element_id, tenant_id, project_code),
    FOREIGN KEY (matched_identifier_id, tenant_id, project_code)
        REFERENCES bim.project_element_identifier(identifier_id, tenant_id, project_code),
    CHECK (evidence_kind IN ('production_record', 'quality_test_result', 'document_ref')),
    CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
    CHECK (link_status IN ('confirmed', 'needs_review', 'unmatched', 'rejected', 'superseded')),
    CHECK (link_status <> 'confirmed' OR project_element_id IS NOT NULL),
    CHECK (
        link_status <> 'unmatched'
        OR (project_element_id IS NULL AND matched_identifier_id IS NULL)
    ),
    CHECK (
        NOT is_effective
        OR (link_status = 'confirmed' AND project_element_id IS NOT NULL)
    )
);

CREATE TABLE progress.progress_derivation_rule (
    progress_derivation_rule_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_id UUID REFERENCES bim.bt_element_type_catalog(element_type_id),
    activity_code VARCHAR(100) NOT NULL,
    rule_name VARCHAR(200) NOT NULL,
    evidence_kind VARCHAR(30) NOT NULL,
    evidence_type VARCHAR(100) NOT NULL,
    derivation_method VARCHAR(50) NOT NULL,
    progress_weight NUMERIC(8,5),
    rule_expression JSONB NOT NULL DEFAULT '{}'::jsonb,
    rule_version INTEGER NOT NULL DEFAULT 1,
    effective_from DATE,
    effective_to DATE,
    approval_status VARCHAR(30) NOT NULL DEFAULT 'draft',
    approved_by VARCHAR(200),
    approved_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)),
    CHECK (evidence_kind IN ('production_record', 'quality_test_result', 'document_ref')),
    CHECK (progress_weight IS NULL OR progress_weight BETWEEN 0 AND 1),
    CHECK (rule_version > 0),
    CHECK (effective_to IS NULL OR effective_from IS NULL OR effective_to >= effective_from),
    CHECK (approval_status IN ('draft', 'approved', 'retired')),
    CHECK (jsonb_typeof(rule_expression) = 'object')
);

COMMENT ON TABLE progress.evidence_link IS
    'Layer 4 evidence links written by reconciliation. MS-05 writes Layer 3 only; the SAL Engine reads Layer 4/progress.';
COMMENT ON COLUMN progress.evidence_link.evidence_id IS
    'Controlled polymorphic Layer 3 reference selected by evidence_kind. TODO: enforce target existence with reviewed triggers or reconciliation-service validation.';
COMMENT ON COLUMN progress.evidence_link.link_status IS
    'confirmed/effective=evidence linked to a project element and eligible for SAL/progress; unmatched/needs_review=one current unresolved review/audit outcome per evidence; rejected/superseded=non-effective history.';
COMMENT ON COLUMN progress.evidence_link.reason IS
    'Reason for unmatched, needs_review, rejected, or superseded reconciliation outcomes.';
COMMENT ON COLUMN progress.evidence_link.is_effective IS
    'Only confirmed links with a project_element_id may be effective. SAL/progress derivation must consume confirmed effective links only.';
COMMENT ON TABLE progress.progress_derivation_rule IS
    'Approved-rule model for deriving Layer 4 progress facts consumed by the SAL Engine.';

CREATE UNIQUE INDEX uq_evidence_link_effective
    ON progress.evidence_link(tenant_id, project_code, evidence_kind, evidence_id)
    WHERE is_effective
      AND link_status = 'confirmed'
      AND project_element_id IS NOT NULL;
-- Reconciliation-service ON CONFLICT must repeat this predicate exactly.
CREATE UNIQUE INDEX uq_evidence_link_current_unresolved
    ON progress.evidence_link(tenant_id, project_code, evidence_kind, evidence_id)
    WHERE link_status IN ('unmatched', 'needs_review')
      AND is_effective = FALSE;
CREATE INDEX idx_evidence_link_element_effective
    ON progress.evidence_link(tenant_id, project_code, project_element_id)
    WHERE is_effective
      AND link_status = 'confirmed'
      AND project_element_id IS NOT NULL;
CREATE INDEX idx_evidence_link_review_queue
    ON progress.evidence_link(tenant_id, project_code, link_status, confidence)
    WHERE link_status = 'needs_review';
CREATE INDEX idx_evidence_link_unmatched_reprocess
    ON progress.evidence_link(tenant_id, project_code, evidence_kind, evidence_type)
    WHERE link_status = 'unmatched';
CREATE UNIQUE INDEX uq_progress_derivation_rule_scope_version
    ON progress.progress_derivation_rule(
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(project_code, ''),
        COALESCE(element_type_id, '00000000-0000-0000-0000-000000000000'::uuid),
        activity_code,
        evidence_kind,
        evidence_type,
        rule_version
    );
CREATE INDEX idx_progress_derivation_rule_lookup
    ON progress.progress_derivation_rule(
        tenant_id,
        project_code,
        element_type_id,
        evidence_kind,
        evidence_type
    )
    WHERE is_active AND approval_status = 'approved';

COMMIT;
