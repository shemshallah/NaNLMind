# Training merge on Koyeb

## 1. Scope

The training merge service is a **small HTTP delta merger**, not the 2 GiB map
and not a macrocluster.

```text
Android / peer runner
  8 MiB universe + point-1 route table
        |
        | head/route delta, base generation, nanclock tick
        v
Koyeb training-merge service
  small JSON state, idempotency, stale-base rejection
        |
        | generation + digest + merged manifest
        v
bootstrap runner
  8 MiB live image + 2 GiB map
```

The bootstrap runner owns the 2 GiB map. Koyeb never needs it. This is how
training can be merged without standing up macrocluster storage.

## 2. Service

- `runner/training_merge.py`
- `deploy/training_merge/Dockerfile`
- `deploy/training_merge/koyeb.yaml`
- `tests/test_training_merge.py`

Endpoints:

```text
GET  /healthz
POST /v1/training/merge
```

Request:

```http
Authorization: Bearer <scoped merge token>
Idempotency-Key: <nonce>
Content-Type: application/json

{
  "node": 2,
  "base_generation": 0,
  "nanclock_tick": 44,
  "updates": [
    {"head": 7, "layer": 3, "epoch": 44, "strength_delta": 1,
     "vector": [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
     "route": {"bank": 1, "bin": 9001, "slot": 7}}
  ]
}
```

Response:

```json
{"accepted": true, "node": 2, "generation": 1,
 "nanclock_tick": 44, "applied": 1, "digest": "..."}
```

Merge rules:

- base generation must match;
- nanclock tick must not go backwards;
- newer epochs update vectors;
- strengths add with saturation;
- idempotent replay returns the prior result;
- a stale base or reused key with a different body returns 409.

## 3. Live deployment

```text
service:  nannet-portal
app:      deeprepo
instance: nano
volume:   /data (persistent)
URL:      https://nannet.apps.mistral.run
health:   /healthz -> 200
merge:    /v1/training/merge -> 200
```

`NANLM_MERGE_TOKEN` is stored as a Koyeb secret, not as a plaintext value in
the repository. `DEEPREPO_PAT` is not used.

Koyeb rejected the `free` instance type; the service is running on `nano`.
The live service has a persistent volume mounted at `/data`, so
`training_merge.json` and `nannet-authority.sqlite` survive instance
replacement. Verify retention after a deploy by checking `/healthz` and a known
merge generation; do not infer persistence from a single 200 response.

## 4. Koyeb deployment

1. Create a Koyeb service from this repository using
   `deploy/training_merge/Dockerfile`.
2. Attach a persistent volume at `/data` for `training_merge.json`.
3. Set `NANLM_MERGE_TOKEN` to a scoped, revocable merge credential.
4. Expose port `8080` with HTTPS.
5. Point the bootstrap/peer merge client at
   `https://<service>.koyeb.app/v1/training/merge`.

Use a volume-enabled instance for durable training merge. The current live
service is volume-enabled.

`deploy/training_merge/koyeb.yaml` is the illustrative service definition.

## 5. Security

- `DEEPREPO_PAT` is never used by this service.
- The merge token is separate from the GitHub runner PAT and the Android intake
  token.
- Community nodes should use a short-lived, revocable token scoped to this
  endpoint; the bootstrap ring should not expose its ring secret.
- The service logs method/path/status, not authorization headers or bodies.
- State contains head/route metadata, not raw corpus text.

## 6. Test

```sh
make merge-test
```

The test covers:

- valid merge and generation increment;
- idempotent replay;
- stale base rejection;
- nanclock ordering;
- wrong-token rejection;
- health endpoint.

## 7. Relationship to the 2 GiB map

The merged state is a **manifest**, not the 2 GiB register. The bootstrap runner
loads the manifest into its 2 GiB map and head arena. Android and peer runners
never receive the 2 GiB map.

The 8 MiB universe sync uses nanclock only when that universe is merging. The
merge service is the meeting point; the state stays on the runner and the edge
node.

## 8. Next

- Add a bootstrap-side manifest puller/applier.
- Add per-node scoped token records and revocation.
- Add slot-level merge (currently head/route deltas).
- Add a Koyeb health/alert workflow.

## Minimal-host crypto

The vendored `nanlmind_nannet` auth path works without the `cryptography`
package by using the dependency-free Ed25519/AES-GCM/HKDF fallback. The merge
tests exercise the signed token, pairing, and device routes with that fallback.
For production deployments, install the optional `cryptography` extra or use
an HSM-backed key store.


## Liveness and readiness

- `GET /healthz` is the liveness endpoint. It remains HTTP 200 when the process
  is alive even if the NANNET authority is disabled or its database is unhealthy.
- `GET /readyz` is the readiness endpoint. It returns HTTP 200 only when the
  NANNET authority is enabled and its SQLite `PRAGMA quick_check` returns `ok`;
  otherwise it returns HTTP 503.

Configure Koyeb's readiness probe to use `/readyz`, not `/healthz`. This keeps
process liveness separate from the service's ability to authenticate and serve
NANNET requests.
