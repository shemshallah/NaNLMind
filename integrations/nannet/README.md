# NANNET Universal Server

One low-memory control plane for NaNLMind, NaN0S, Android, Hermes, Clocked,
and DeepRepo. It authenticates endpoint identities, publishes capability
routes, accepts evidence-only observations, stages corpus chunks on disk,
and exposes the canonical runner merge boundary.

## Architecture and resource model

- 256 bootstrap identities: bootstrap-000 through bootstrap-255.
- Named edge identities: my_android, hermes_demo, clocked_demo.
- Identity is derived from an issued token, never from request JSON.
- SQLite WAL stores metadata and bounded observation envelopes only.
- Corpus bytes stream to disk in 8 MiB chunks; no SQLite BLOBs and no 6 GiB
  in-memory buffers.
- Default aggregate staging quota is 6 GiB.
- Uploaded data stays quarantined until an independently credentialed VPS or
  GitHub runner validates it. Only validated data is visible to the training
  runner token.
- Endpoint tokens cannot assert correctness, submit head deltas, or call the
  canonical training merge.
- The canonical merge endpoint accepts only the dedicated NANLM_BOOTSTRAP_TOKEN
  and forces source_endpoint=bootstrap.
- N16T frames are relayed opaquely to one explicitly configured HTTPS peer.
- No arbitrary URL proxy, model weights, Qwen inference, or weight-page proxy.

The 256 bootstrap identities are endpoint/slot identities, not 256 separate
models. NaNLMind's six-runner ring remains the sole canonical 256-head learner.

Issue a device token once, then deliver it to that endpoint's secret store:

\`\`\`sh
curl -fsS -X POST "$NANNET_URL/admin/tokens" \
  -H "Authorization: Bearer $NANLM_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"endpoint_id":"my_android","scopes":["intake","observation"],"ttl_seconds":2592000,"max_requests":100000}'
\`\`\`

For NaN0S transport, issue a separate my_android token with only the n16t
scope. Tokens are returned once; store them securely and never paste them into
source control or logs. Bootstrap slots use endpoint IDs bootstrap-000 through
bootstrap-255.

## API

- GET /healthz
- POST /admin/tokens (NANLM_ADMIN_TOKEN)
- GET /v1/routes (endpoint bearer)
- GET /admin/keeper/status (admin-only; keeper health/action)
- GET /admin/models/status (admin-only; read-only Qwen metadata)
- POST /v1/observations (endpoint bearer; metadata-only, unverified evidence)
- POST /v1/training/merge (NANLM_BOOTSTRAP_TOKEN only; canonical runner deltas)
- POST /n16t (endpoint bearer with n16t scope; opaque binary relay)
- POST /v1/datasets/{id}/begin (declare expected chunk count)
- PUT /v1/datasets/{id}/chunks/{index} (binary chunk + X-Chunk-SHA256)
- POST /v1/datasets/{id}/seal (verify contiguous chunks, total size and SHA-256)
- GET /internal/datasets (validator lists quarantined manifests)
- GET /internal/datasets/{id}/chunks/{index} (validator reads quarantined bytes)
- PATCH /internal/datasets/{id}/validation (validator approves/rejects)
- GET /internal/datasets/validated (runner lists approved manifests)
- GET /internal/datasets/{id}/chunks/{index} (runner reads only validated bytes)
- GET /internal/observations (runner reads pending evidence)
- POST /internal/observations/ack (runner acknowledges after native fold)
- DELETE /admin/datasets/{id} (admin deletes only non-validated data)

The validator must independently check encoding, UTF-8, record boundaries,
duplicates, provenance/licensing, contamination, safety, and held-out quality.
An endpoint's own assertion is never proof. A successful upload means
quarantined, not trained. A successful validation means training-eligible,
not yet committed to the canonical mind.

## Required service secrets

Never commit these values:

- NANLM_ADMIN_TOKEN (at least 32 characters)
- NANLM_VALIDATOR_TOKEN (at least 32 characters; quarantine review only)
- NANLM_RUNNER_TOKEN (at least 32 characters; validated-data/evidence consumer)
- NANLM_TOKEN_PEPPER (at least 32 characters; endpoint token hashing)
- NANLM_BOOTSTRAP_TOKEN (canonical runner merge credential; never expose to endpoint clients)
- GH_TOKEN (existing DeepRepo keeper credential)

Optional secrets only when those integrations are active:

- NANLM_N16T_PEER_TOKEN (trusted N16T peer credential)
- DEEPREPO_MIDDLE_TOKEN (with DEEPREPO_MIDDLE_URL)
- NANLM_MERGE_TOKEN (preserve the existing Android/legacy merge credential; NANNET does not use it for canonical writes)
- NANLM_HERMES_TOKEN / NANLM_CLOCKED_TOKEN (preserve legacy endpoint merge credentials if still referenced)
- NANNET_AUTHORITY_MASTER_KEY (preserve the existing stable 32-byte master key)
- CLOCKED_GATEWAY_ADMIN_TOKEN
- CLOCKED_TOKEN_PEPPER
- CLOCKED_API_KEY (only for the separate Clocked SDK adapter)

Keep DEEPREPO_PAT as a GitHub Actions secret on deeprepo and its five CPU
repositories. It is not interchangeable with GH_TOKEN and is not required by
the Koyeb keeper.

## Non-secret service settings

- DEEPREPO_KEEPER_ENABLED=1
- KEEPER_INTERVAL=600
- KEEPER_DISPATCH=1
- DEEPREPO_MAIN=shemshallah/deeprepo
- DEEPREPO_RAM=shemshallah/reporam
- DEEPREPO_VRAM=shemshallah/repovram
- DEEPREPO_RAM_BACKEND=github
- DEEPREPO_VRAM_BACKEND=github
- NANLM_DATA_DIR=/data/nannet
- NANLM_MERGE_ROOT=/data/nannet/merge (change to the old merge state directory
  during cutover if it contains the existing training_merge.json)
- NANLM_DATASET_QUOTA_BYTES=6442450944
- NANLM_CHUNK_BYTES=8388608
- NANLM_HTTP_WORKERS=8 (bounded concurrent requests for Nano RAM)
- NANLM_N16T_PEER_URL (optional until the runner-side peer is deployed)
- Set NANLM_DATASET_QUOTA_BYTES=0 if no persistent corpus volume is attached
- PORT (Koyeb supplies this; the app defaults to 8000 locally)

The repository-root Dockerfile installs the existing DeepRepo core from its
public repository. When DEEPREPO_KEEPER_ENABLED=1, the same Python process
starts the keeper in a background thread with small metadata caches. The
keeper performs budget/lease checks, compaction, and GitHub workflow dispatch;
it does not load Qwen or proxy model bytes. Existing Qwen3-30B and Qwen1.5B
deployments and their model selectors remain untouched. Do not override
CHAT_MODEL: the keeper reads the existing DeepRepo repository variable.

## Koyeb Nano and 6 GiB storage

Koyeb documents Nano as 256 MiB RAM and 2.5 GB local SSD. That local disk
cannot hold a durable 6 GiB corpus. Koyeb Volumes are currently public preview,
1–10 GB, and limited to Washington, D.C. and Frankfurt. They support only
single-instance standard/GPU services, are local to one machine with no built-in
redundancy, and cannot be detached except by deleting the service. A 10 GB
volume can stage the 6 GiB target for testing, but it needs snapshots/backups and
should not be the only authoritative copy. Without a persistent volume, keep dataset payloads
on a separate VPS/runner-owned durable volume and let this Nano coordinate
metadata, auth, routing, and validation state.

Do not run model inference or store Qwen weights on this Nano. DeepRepo keeps
repovram weights and reporam state on their existing backends; the keeper only
uses GitHub's API for control-plane work.

## Local run

From this directory:

\`\`\`sh
python3 server.py
python3 -m unittest -v
\`\`\`

Expose only HTTPS at the platform edge. Never print bearer tokens or log
request bodies.
