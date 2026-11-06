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
GET  /healthz                 # liveness: process responds
GET  /readyz                  # readiness: NANNET authority + SQLite are usable
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
service:  training-merge-v2
app:      deeprepo
instance: nano
URL:      https://deeprepo-qtcl-9c8fea15.apps.mistral.run
health:   /healthz -> 200
merge:    /v1/training/merge -> 200
```

`NANLM_MERGE_TOKEN` and `NANNET_AUTHORITY_MASTER_KEY` are Koyeb secrets,
never repository values. `DEEPREPO_PAT` is not used by the service.

The service must mount a persistent volume at `/data`; both
`/data/training_merge.json` and `/data/nannet-authority.sqlite` must live there.
A restart must preserve identities, revocations, merge generations, and
idempotency records. `/healthz` is only a liveness probe. Use `/readyz` for
readiness: it returns 503 when authority is disabled or its SQLite database
cannot be checked. A 200 from `/healthz` alone does not prove NANNET works.

## 4. Koyeb deployment

1. Build from `deploy/training_merge/Dockerfile`.
2. Mount a persistent volume at `/data`.
3. Set `NANLM_MERGE_TOKEN` and `NANNET_AUTHORITY_MASTER_KEY` as Koyeb secrets.
4. Set `NANNET_AUTHORITY_DB=/data/nannet-authority.sqlite` and
   `NANLM_MERGE_ROOT=/data`.
5. Expose port `8080` with HTTPS and configure `/readyz` as the readiness probe.
6. Point bootstrap/peer clients at the deployed `/v1` routes.
7. Restart/redeploy once and verify identity + merge state survive.

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
