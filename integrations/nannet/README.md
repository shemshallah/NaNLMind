# NANNET Universal Server

Small standard-library-only control plane for NaNLMind, NaN0S, Android,
Hermes, Clocked, and DeepRepo. It authenticates endpoint identities, publishes
a capability-filtered route directory, accepts evidence-only observations,
and stages corpus data on disk for independent validation.

## Resource model

- No model weights, tokenizer, vector index, or training runtime.
- SQLite WAL stores metadata and bounded observation envelopes only.
- Corpus bytes stream to disk in chunks (default 8 MiB); never stored in SQLite
  or assembled in RAM.
- Default aggregate staged-data quota: 6 GiB.
- Uploads remain quarantined until a separately credentialed VPS/runner
  validator approves the sealed dataset digest.
- Only validated datasets are training-eligible.
- No arbitrary URL proxy. Routes are allowlisted capability contracts.

## Identity and routes

Bootstrap identities are bootstrap-000 through bootstrap-255. Named edge
identities are my_android, hermes_demo, and clocked_demo. Identity comes from
the issued token, never a request field.

Route contracts: training.merge, training.validate, n16t.peer,
deeprepo.keeper, and models.status.

## API

- GET /healthz
- POST /admin/tokens (admin bearer)
- GET /v1/routes (endpoint bearer)
- POST /v1/observations (metadata-only, unverified evidence)
- POST /v1/datasets/{id}/begin (declare chunk count)
- PUT /v1/datasets/{id}/chunks/{index} (binary chunk + X-Chunk-SHA256)
- POST /v1/datasets/{id}/seal (verify contiguous chunks, size and SHA-256)
- GET /internal/datasets (validator lists quarantined manifests)
- GET /internal/datasets/{id}/chunks/{index} (validator streams bytes)
- PATCH /internal/datasets/{id}/validation (validator approves or rejects)
- GET /internal/observations (validator reads pending observations)
- DELETE /admin/datasets/{id} (admin deletes only non-validated data)

The external validator must independently check encoding, UTF-8, record
boundaries, duplicates, provenance/licensing, contamination, safety, and
held-out quality before approving. Endpoint self-reports are never proof.

## Environment

Required server-side secrets (never commit):
- NANLM_ADMIN_TOKEN (at least 32 characters)
- NANLM_VALIDATOR_TOKEN (at least 32 characters)
- NANLM_TOKEN_PEPPER (at least 32 characters)

Non-secret settings:
- NANLM_DATA_DIR (default /data/nannet; mount persistent storage here)
- NANLM_DATASET_QUOTA_BYTES (default 6442450944)
- NANLM_CHUNK_BYTES (default 8388608)
- PORT (platform supplied)

Run from this directory with python3 server.py. Ephemeral container storage is
not a durable 6 GiB corpus tier. Mount a persistent volume at /data and expose
only HTTPS through the platform edge.
