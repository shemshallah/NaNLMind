# NANNET Universal Server

One low-memory control plane for NaNLMind, NaN0S, Android, Hermes, Clocked,
and DeepRepo. It authenticates endpoint identities, publishes capability
routes, accepts evidence-only observations, stages corpus chunks on disk,
and exposes the canonical runner merge boundary.

## Architecture and resource model

- Canonical address form: `nan://GM0:SC0:MC0:BS0:HW0`.
- Each GM, SC, MC, BS, and HW coordinate is an unsigned integer from 0 through 255.
- Initial identities: HW0=NaNLMind runner ring; HW1=Android; HW2=Hermes; HW3=Clocked, all initially under GM0/SC0/MC0/BS0.
- Fixed HW0–HW3 identities are reserved for the runner ring, Android, Hermes, and Clocked. Community and virtual demo installations receive the next free HW8–HW254 slot in BS0, mapping to node points 9–255.
- A device installation key is generated locally and stored only as a server-side keyed hash. One active lease is allowed per installation key and one installation per active HW slot. Re-registration resumes the same lease; explicit release revokes its tokens and frees the slot only after pending work is committed or rejected.
- The issued bearer token binds the endpoint to its canonical NaN address; optional `X-NaN-Address` claims are checked against that binding.
- MAC addresses, IMEI, serial numbers, Android IDs, phone numbers, and email addresses are not collected or used for device identity. Network MAC randomization therefore does not create a second device identity.
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

Issue an endpoint token once, then deliver it to that endpoint's secret store:

\`\`\`sh
curl -fsS -X POST "$NANNET_URL/admin/tokens" \
  -H "Authorization: Bearer $NANLM_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"address":"nan://GM0:SC0:MC0:BS0:HW1","scopes":["intake","observation","n16t"],"ttl_seconds":2592000,"max_requests":100000}'
\`\`\`

For NaN0S transport, issue a separate HW1 token with only the `n16t` scope.
Tokens are returned once; store them securely and never paste them into source
control or logs. `HWn` maps to the corresponding bootstrap node point `n+1` within BS0
(HW0 -> point 1, HW1 -> point 2, HW255 -> point 256). A node point is a
registry slot, not a head number: each endpoint owns its own 256-head local
universe. Head indices are local to that endpoint. `MC` and `BS` remain
distinct hierarchy levels, not hardware aliases.

## Operator portal

The same-origin portal is served at `/` and `/portal`. It provides device registration and first-free HW allocation, lease heartbeat/release, device/system issue reports, health, authenticated identity/routes, reserved endpoint-token issuance, a separate validator queue with explicit approve/reject actions, corpus upload, and admin-only keeper/model/device status. Credentials remain in page memory only and are not written to local storage or cookies. Use HTTPS only. The portal never proxies Qwen requests.

Corpus upload uses browser SHA-256, sends bounded chunks, and seals the manifest after every chunk is acknowledged. Upload means **quarantined**, not trained. Independent validation and a runner commit receipt are required before staging bytes are released.

## API

- GET /healthz (includes Clocked gateway and enrollment readiness)
- POST /admin/tokens (NANLM_ADMIN_TOKEN; fixed HW0–HW3 only)
- POST /v1/devices/register (public HTTPS registration; explicit consent + bounded system report + client-generated 256-bit installation secret; assigns HW8–HW254)
- GET /v1/devices/me (device bearer; own registration and lease)
- POST /v1/devices/heartbeat (device bearer; renews lease)
- POST /v1/devices/release (device bearer; revokes tokens and frees slot only after no pending uploads/observations)
- POST /v1/devices/report (device bearer; device/system/network/security issue report)
- GET /admin/devices and GET /admin/device/reports (admin-only operator views)
- GET /v1/address (endpoint bearer; canonical address, registry slot, and 256-head local universe)
- GET /v1/routes (endpoint bearer; capability-filtered routes and head count)
- GET /admin/keeper/status (admin-only; keeper health/action)
- GET /admin/models/status (admin-only; read-only Qwen metadata)
- GET /admin/training/status (admin-only; canonical generations, local-head counts, corpus receipt count, digest)
- POST /v1/observations (endpoint bearer; metadata-only, unverified evidence)
- POST /v1/intake/route (Android route-diff compatibility; verifies canonical digest and address/node binding, then stores only unverified evidence)
- POST /v1/training/merge (NANLM_BOOTSTRAP_TOKEN only; canonical runner deltas)
- POST /n16t (endpoint bearer with n16t scope; opaque binary relay; accepts `application/vnd.nan16.n16t` and Android's legacy `application/x-n16t` alias, normalizes upstream)
- POST /v1/datasets/{id}/begin (declare expected chunk count)
- PUT /v1/datasets/{id}/chunks/{index} (binary chunk + X-Chunk-SHA256)
- POST /v1/datasets/{id}/seal (verify contiguous chunks, total size and SHA-256)
- GET /internal/datasets (validator lists quarantined manifests)
- GET /internal/datasets/{id}/chunks/{index} (validator reads quarantined bytes)
- PATCH /internal/datasets/{id}/validation (validator approves/rejects)
- GET /internal/datasets/validated (runner lists approved manifests)
- GET /internal/datasets/committed (runner lists durable ingest receipts)
- GET /internal/datasets/{id}/chunks/{index} (runner reads only validated bytes)
- GET /internal/observations (runner reads pending evidence)
- POST /internal/datasets/{id}/commit (runner records canonical generation + exact dataset digest; deletes staged chunk files but retains the audit manifest)
- POST /internal/observations/ack (runner acknowledges after native fold)
- DELETE /admin/datasets/{id} (admin deletes only non-validated data)

## Training fold and recovery semantics

The runner consumer is wired into the six-runner ring after a successful
head epoch and is also available as a scheduled/manual workflow. It streams
validated chunks, checks each chunk hash and the complete dataset digest,
validates UTF-8 records (including the strict `N16TXT/1` header, 4096-byte
record bound, control/noncharacter rejection, CRLF normalization, and optional
final newline), and computes deterministic 16-dimensional byte-trigram
feature vector for each of the 256 local heads at bootstrap node point 1.
Those vectors are folded through the existing idempotent `MergeStore` into
the durable `NANLM_MERGE_ROOT/training_merge.json` state. This is the first
NANNET-to-canonical-head-bank training bridge; it is a compact byte-feature
fold, not a claim that the C++ Context2 language-model snapshot is already
persisted or updated by this path.

Before folding, the runner checks for a prior idempotency receipt. If a job
crashes after the merge but before the dataset acknowledgement, the retry
recovers the same generation from that receipt instead of applying the
dataset twice. The dataset staging files are deleted only after the merge
receipt is durable and the runner posts the exact dataset digest and generation
to the commit endpoint. Keep `NANLM_MERGE_ROOT` on persistent storage.

Required GitHub repository configuration for the runner workflows:
- Variable `NANNET_URL`: public HTTPS NANNET origin.
- Secret `NANLM_RUNNER_TOKEN`: validated dataset retrieval + acknowledgement.
- Secret `NANLM_BOOTSTRAP_TOKEN`: canonical state, receipt, and merge access.

The validator must independently check encoding, UTF-8, record boundaries,
duplicates, provenance/licensing, contamination, safety, and held-out quality.
An endpoint's own assertion is never proof. A successful upload means
quarantined, not trained. A successful validation means training-eligible, not yet committed to the canonical mind. After the runner has copied, verified, encoded, and committed a dataset into a canonical generation, it posts the generation and exact SHA-256 receipt. NANNET then removes staged chunk files and chunk rows while retaining the manifest, validation report, digest, and generation receipt. A repeated identical receipt is idempotent.

## Clocked gateway in this same Koyeb service

The Clocked SDK gateway is mounted inside this NANNET HTTP process. It is not a second Koyeb service or deployment. The root Dockerfile installs `integrations/nannet/clocked-requirements.txt`; `server.py` dispatches `/auth/demo-token`, `/v1/experience`, `/v1/tasks`, and the Clocked instance administration routes to the embedded adapter. The Clocked database defaults to `/data/clocked_gateway.sqlite3`, on the same persistent Koyeb volume as NANNET state.

Set `NANNET_URL` to this service's own public HTTPS origin. The embedded adapter uses that same-origin route to ask the existing allocator to register and release demo instances; it does not contact a separate NANNET deployment. Registration is explicit-consent-only and the allocator remains authoritative for lowest-free HW8–HW254 / node-point 9–255 leases.

Required Clocked Koyeb secrets: `CLOCKED_API_KEY` (upstream master credential, server-only), `CLOCKED_DEMO_ENROLLMENT_TOKEN` (demo enrollment gate), `CLOCKED_TOKEN_PEPPER` (participant-token hashing), `CLOCKED_RESULT_ENCRYPTION_KEY` (Fernet key for encrypted stored NANNET lease credentials), and `CLOCKED_GATEWAY_ADMIN_TOKEN` (instance administration). The returned `clu_` and `nnt_` credentials are scoped/expiring participant credentials; the upstream `CLOCKED_API_KEY` is never returned. Keep the Clocked database and encryption key stable across restarts.

Endpoints added to this service:
- POST `/auth/demo-token` (enrollment bearer + explicit consent; obtains NANNET lease and issues scoped Clocked token)
- POST `/v1/experience` and POST `/v1/tasks` (scoped Clocked participant token; server-side SDK calls)
- GET `/admin/instances` and POST `/admin/instances/revoke` (Clocked admin bearer)
- POST `/clocked/admin/tokens` (optional administrative participant token issuance; avoids collision with NANNET `/admin/tokens`)
- GET `/clocked/healthz` (embedded adapter readiness)

The `CLOCKED_API_KEY` GitHub Actions secret remains for CI/live smoke tests. GitHub Actions secrets are not automatically injected into Koyeb: configure the same value as a Koyeb secret on this existing service. No client, runner, or Android app receives it.

## NaNLMROUTER in the same Koyeb process

The BS0:0 / MC0:0 NaNLMROUTER control plane is embedded in `server.py`; it is not a second Koyeb service or listener. The `nannet_router/` package is included in the existing NANNET image and shares the same `/data` persistent volume. Its durable source inbox and six-slot MC0:0 runner-ring registry live under `RIDDLE_DATA_DIR` (default `/data/nannet/router`).

Clocked processing writes a digest-only, explicitly unverified receipt to both the NANNET evidence queue and the NaNLMROUTER source inbox. The router payload contains input/response SHA-256 digests, source address, node point, and deterministic head shard; it never stores the original prompt or raw Clocked response. It is queued work, not an automatic model update. The supervised runner leases it, computes a provenance-bound trace, and ACKs only after its own work is durable.

Embedded router endpoints:
- GET `/v1/riddle/healthz` and GET `/v1/riddle/volumes`
- POST `/v1/riddle/intake` (admin-authenticated bounded source intake)
- POST `/v1/riddle/lease`, `/v1/riddle/ack`, and `/v1/riddle/retry` (runner-authenticated durable worker protocol)
- POST `/v1/riddle/ring/heartbeat` (six-slot MC0:0 ring reconciliation against the signed volume registry)
- POST `/v1/riddle/feedback` and `/v1/riddle/feedback/ack` (signed candidate-only feedback)
- POST `/v1/riddle/routes/resolve` and `/v1/riddle/plan` (read-only signed route/range planning)

The embedded adapter reuses `NANLM_ADMIN_TOKEN`, `NANLM_RUNNER_TOKEN`, and `NANLM_TOKEN_PEPPER` for its internal intake, worker, and feedback boundaries unless explicit `RIDDLE_*` values are supplied. No extra deployment or new authentication service is introduced. Set `RIDDLE_DATA_DIR=/data/nannet/router` to pin the router's SQLite state on the same persistent volume.

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
- CLOCKED_GATEWAY_ADMIN_TOKEN (embedded Clocked instance administration)
- CLOCKED_TOKEN_PEPPER (embedded Clocked participant-token hashing)
- CLOCKED_API_KEY (embedded Clocked SDK; server-side only)
- CLOCKED_DEMO_ENROLLMENT_TOKEN (explicit demo enrollment gate)
- CLOCKED_RESULT_ENCRYPTION_KEY (Fernet key; preserve across restarts)
- RIDDLE_INTAKE_TOKEN / RIDDLE_WORKER_TOKEN / RIDDLE_FEEDBACK_HMAC_KEY (optional; otherwise derived from existing NANNET admin/runner/pepper secrets)

Keep DEEPREPO_PAT as a GitHub Actions secret on deeprepo and its five CPU
repositories. It is not interchangeable with GH_TOKEN and is not required by
the Koyeb keeper.

## Non-secret service settings

- NANNET_PUBLIC_URL (public HTTPS service origin, e.g. the Koyeb service URL)
- NANNET_URL (same public HTTPS origin as this service; embedded Clocked adapter calls its own NANNET routes)
- CLOCKED_GATEWAY_DB=/data/clocked_gateway.sqlite3
- RIDDLE_DATA_DIR=/data/nannet/router
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
- NANLM_DEVICE_LEASE_SECONDS=21600 (six-hour CLOCKED demo lease; adjust for the deployment's lease policy)
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


## Device identity, leases, and good-faith registration

A clone does not receive a hard-coded identity. On first run it creates a
random 256-bit installation secret locally and registers over HTTPS with
explicit consent and a small system-capability report. The server assigns the
lowest free community slot, initially HW8, then HW9, through HW254 (node points 9–255). HW0–HW3
remain reserved for the runner ring, Android reference endpoint, Hermes, and
Clocked.

The installation secret is never stored in plaintext by NANNET; only a
pepper-HMAC digest is retained. Re-registering with the same secret resumes
the same active lease and rotates the endpoint bearer token. Heartbeats renew
the lease. After expiry, the bearer cannot use ordinary endpoint routes; only
heartbeat, release, and its own lease-status route remain available. Pending
work prevents release and therefore prevents slot reassignment. Explicit release revokes the endpoint token and returns the HW slot
to the pool only when no upload, quarantined/validated dataset, or unacknowledged
observation remains. Expired leases with pending work are retained rather than
reassigned. This is an installation identity, not a hardware identity: a
reinstall that loses its secret is a new installation. MAC addresses are
randomized/spoofable and are not used for authentication; changing Wi-Fi or
network interfaces does not change the lease.

Registration requires platform, OS version, app version, and CPU ABI. Optional
capacity fields include CPU cores, RAM, and free storage. Error reports can
describe device, system, network, or security concerns. Never submit IMEI,
serial number, Android ID, MAC address, phone number, email, or credentials.
This is a good-faith admission and scheduling mechanism, not proof of physical
device uniqueness or a substitute for the future full cryptographic package.
