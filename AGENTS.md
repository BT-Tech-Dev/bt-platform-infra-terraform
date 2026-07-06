\# BuildTrust Platform Repository Instructions



\## Repository purpose



This repository contains BuildTrust data-platform infrastructure and ingestion components, including:



\- Google Cloud Storage ingestion entry points;

\- bucket watcher and event routing;

\- Cloud Run ingestion services;

\- Python parsing and normalization logic;

\- PostgreSQL schemas and migrations;

\- raw, normalized, BIM, process, and progress data layers;

\- Terraform and Cloud Build configuration.



Follow the global Codex working agreement in addition to this file.



\## Critical invariants



\- Preserve tenant isolation in storage paths, payloads, queries, tables, services, and background operations.

\- Preserve raw-source immutability and complete source traceability.

\- Maintain deterministic ingestion and idempotency through stable file hashes and idempotency keys.

\- Preserve the relationship between source file, project, tenant, ingestion run, issues, and persisted domain records.

\- Never silently discard, overwrite, duplicate, or reinterpret source data.

\- Treat `raw.import\_file`, `raw.ingestion\_run`, and `raw.ingestion\_issue` as audit and operational records.

\- Prefer explicit validation failures and recorded ingestion issues over silent fallback behavior.

\- Maintain backward compatibility for existing upload paths, payloads, file profiles, APIs, and deployed services unless an approved specification states otherwise.



\## Architecture awareness



For ingestion-related work, trace the complete flow before editing:



1\. GCS object and upload path.

2\. Bucket watcher event and payload.

3\. Project and tenant resolution.

4\. Target ingestion service and parser/profile selection.

5\. Raw persistence and ingestion-run lifecycle.

6\. Validation and issue persistence.

7\. Normalized or canonical persistence.

8\. Logging, correlation, response, retry, and failure behavior.



If `graphify-out/graph.json` exists, use scoped Graphify queries to locate likely components before broad searches. Verify every critical conclusion against the current source files.



\## Change rules



\- Prefer additive, deterministic, and reviewable database migrations.

\- Respect the repository's existing migration ordering and naming convention.

\- Do not edit previously applied migrations unless explicitly approved.

\- Use transactions when partial persistence could leave inconsistent state.

\- Do not introduce direct database writes that bypass established ingestion or audit paths without approval.

\- Keep infrastructure, application, and schema changes aligned.

\- Do not hardcode tenant IDs, project IDs, bucket names, credentials, environment-specific URLs, or secrets.

\- Reuse existing Terraform modules, service patterns, environment-variable conventions, and Cloud Build workflows.

\- Do not broaden IAM permissions unless explicitly required and approved.



\## Prohibited without explicit approval



Do not execute:



\- `terraform apply`;

\- production deployment or traffic changes;

\- destructive or mass-mutating SQL;

\- production backfills;

\- schema drops, truncations, or destructive renames;

\- IAM, secret, DNS, or credential changes;

\- production GCS deletions or rewrites;

\- Git commit, push, force-push, merge, or branch deletion.



Diagnostic database access is read-only by default.



\## Verification



Use commands and test infrastructure already present in the repository. Do not invent or claim nonexistent commands.



As applicable:



\- run targeted Python tests;

\- run formatting, lint, and type checks configured by the repository;

\- validate migration syntax and ordering;

\- run `terraform fmt -check` and `terraform validate` in the affected Terraform scope;

\- verify success, duplicate/idempotent, validation-failure, and persistence-failure paths;

\- inspect the final Git diff for unrelated changes;

\- report validations not executed and the reason.



\## Definition of done



A change is complete only when:



\- implementation matches the approved specification;

\- tenant isolation, idempotency, traceability, and data integrity remain intact;

\- relevant tests and validations have been executed;

\- migrations and infrastructure changes are reviewable and coordinated;

\- no secrets or environment-specific values have been introduced;

\- remaining deployment or production actions are explicitly identified.

