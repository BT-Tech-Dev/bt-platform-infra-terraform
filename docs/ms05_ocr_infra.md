# MS-05 OCR pilot infrastructure

## Topology

Initial flow:

1. `bucket-watcher` routes production uploads.
2. `production-ingestion-service` runs with `OCR_SERVICE_ROLE=ingest`.
3. OCR automatic dispatch is explicitly disabled with `OCR_AUTO_DISPATCH_ENABLED=false`.
4. When enabled later by configuration, ingest enqueues OCR extraction tasks in Cloud Tasks.
5. Cloud Tasks invokes `production-ingestion-ocr-worker` on `/internal/ocr/extractions/{extraction_run_id}:execute`.
6. The worker calls Vertex AI Gemini, stores immutable raw provider responses in GCS, and writes OCR extraction rows in the `document` schema.

## Repository responsibility

- Terraform manages desired GCP infrastructure and zero-from-scratch bootstrap definitions.
- `modules/cloud_sql/sql` is the canonical bootstrap DDL for new environments.
- `scripts/migrations` contains manually reviewed incremental migrations for existing databases.
- Terraform must not automatically execute incremental OCR or application migrations.
- Application source, Docker build, and service image deployment commands remain in the service-local `cloudbuild.yaml` in the application repository.
- The infra repo defines the Cloud Build trigger; the application repo defines how that trigger builds and deploys the service image.

## Eventarc least privilege

The historical project-wide Eventarc `roles/run.invoker` binding is intentionally removed by this OCR infra change. Existing Eventarc destinations keep explicit service-level invoker bindings:

- `bucket-watcher`: `module.cloud_run.google_cloud_run_v2_service_iam_member.eventarc_invoker_bucket_watcher`
- `bim-parser-v1`: `module.cloud_run.google_cloud_run_v2_service_iam_member.eventarc_invoker`
- `production-ingestion-service`: `module.cloud_run.google_cloud_run_v2_service_iam_member.eventarc_invoker_production_ingestion`

No Eventarc invoker binding is granted on `production-ingestion-ocr-worker`; only the Cloud Tasks OIDC service account can invoke the private worker.

## Services

`production-ingestion-service`

- Runtime service account: existing `sa-bt-parser-${environment}` identity.
- Ingress: internal only.
- Invoker: Eventarc service account.
- OCR role: ingest.
- Automatic OCR dispatch: disabled for first rollout.

`production-ingestion-ocr-worker`

- Runtime service account: `sa-bt-ocr-worker-${environment}`.
- Ingress: internal only.
- Invoker: only `sa-bt-ocr-tasks-${environment}`.
- OCR role: worker.
- Pilot scaling: min 0, max 1, concurrency 1.

## Cloud Tasks

Queue: `bt-platform-ocr-extraction-prod`

Location: `europe-west6`.

Reason: Cloud Tasks does not currently support `europe-west8`; `europe-west6`
is the nearest supported EU region to the primary application region.

Pilot defaults:

- max concurrent dispatches: 1
- max dispatch rate: 0.05/s
- max attempts: 3
- dispatch deadline: 900s
- retry duration: 3600s

## IAM responsibilities

| Principal | Resource | Role | Reason |
| --- | --- | --- | --- |
| `sa-bt-parser-${environment}` | OCR Cloud Tasks queue | `roles/cloudtasks.enqueuer` | Let the existing ingest runtime enqueue OCR work only on the OCR queue. |
| `sa-bt-ocr-tasks-${environment}` | OCR worker Cloud Run | `roles/run.invoker` | Invoke the private worker as Cloud Tasks OIDC subject. |
| Cloud Tasks service agent | OIDC caller service account | `roles/iam.serviceAccountTokenCreator` | Mint OIDC tokens for worker invocation. |
| `sa-bt-ocr-worker-${environment}` | Cloud SQL | `roles/cloudsql.client` | Persist extraction runs/candidates. |
| `sa-bt-ocr-worker-${environment}` | app DB password secret | `roles/secretmanager.secretAccessor` | Read `bt_app` DB password. |
| `sa-bt-ocr-worker-${environment}` | staging bucket | `roles/storage.objectViewer` | Read source PDFs from GCS. |
| `sa-bt-ocr-worker-${environment}` | handoff bucket OCR prefix | `roles/storage.objectUser` with IAM condition | Create/read/update raw OCR response artifacts under the OCR prefix. |
| `sa-bt-ocr-worker-${environment}` | project | `roles/aiplatform.user` | Invoke Vertex AI Gemini. |

## Environment variables

Ingest OCR env:

- `OCR_SERVICE_ROLE=ingest`
- `OCR_AUTO_DISPATCH_ENABLED=false`
- `OCR_INTERNAL_HANDLER_ENABLED=false`
- `OCR_TASKS_PROJECT_ID`
- `OCR_TASKS_LOCATION`
- `OCR_TASKS_QUEUE`
- `OCR_TASKS_TARGET_URL`
- `OCR_TASKS_SERVICE_ACCOUNT_EMAIL`
- `OCR_TASKS_DISPATCH_DEADLINE_SECONDS`
- `OCR_AUTO_PROFILES=ferroberica_steel_ddt_v1`

Worker OCR env:

- `OCR_SERVICE_ROLE=worker`
- `OCR_AUTO_DISPATCH_ENABLED=false`
- `OCR_INTERNAL_HANDLER_ENABLED=true`
- `OCR_VERTEX_PROJECT_ID`
- `OCR_VERTEX_LOCATION`
- `OCR_VERTEX_MODEL_ID`
- `OCR_TIMEOUT_SECONDS`
- `OCR_MAX_RETRIES`
- `OCR_RAW_RESPONSE_GCS_PREFIX`
- `OCR_SCHEMA_VERSION`

## GCS artifact strategy

Raw provider responses use the existing handoff bucket with a dedicated prefix:

`gs://bt-platform-handoff-${environment}/ocr/raw-responses/<project_code>/<extractor_profile>/<schema_version>/<model_id>/<document_ref_id>/<extraction_run_id>/<prompt_hash>-<response_hash>.json`

The worker does not duplicate PDFs. It reads source documents from the original
GCS URI stored on `document.document_ref` and writes only immutable provider
response artifacts.

## Vertex AI

Configured model:

- `OCR_VERTEX_MODEL_ID=gemini-2.5-flash`
- `OCR_VERTEX_LOCATION=europe-west8`

The application uses the Google Gen AI SDK with Vertex AI (`enterprise=True`),
GCS `file_uri` document input, and JSON response schema.

## Apply and deploy order

1. Review Terraform plan.
2. Apply infra only.
3. Update the application repository `services/production-ingestion-service/cloudbuild.yaml` so the existing `cb-production-ingestion-service-${environment}` trigger builds one `production-ingestion-service:$COMMIT_SHA` image and deploys that same immutable tag to both Cloud Run services.
4. Keep `OCR_AUTO_DISPATCH_ENABLED=false`.
5. Manually test the private worker with controlled internal invocation before enabling dispatch.
6. Enable automatic dispatch only after worker validation.

## Disable and rollback

Immediate disable:

- Keep or restore `OCR_AUTO_DISPATCH_ENABLED=false`.
- Pause the Cloud Tasks queue if tasks were enabled later.

Infrastructure rollback:

- Remove worker invoker binding and queue IAM enqueuer binding.
- Scale worker max instances to zero or remove the worker service in a reviewed Terraform patch.
