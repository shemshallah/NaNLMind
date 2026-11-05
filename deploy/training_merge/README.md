# Koyeb training merge

This is the small training-delta merger. It is **not** the 2 GiB map and **not**
a macrocluster.

The bootstrap runner owns the 2 GiB map. Android/peer runners submit head
vectors, strengths, routes, a base generation, and a nanclock tick. Koyeb merges
the small deltas and returns a generation + digest. The bootstrap ring applies
the returned manifest to its map.

## Live service

```text
https://deeprepo-qtcl-9c8fea15.apps.mistral.run
```

Service `training-merge-v2` is running on the `nano` instance type. Koyeb
rejected `free`. No persistent volume is attached, so merged JSON state is
ephemeral until one is added. `NANLM_MERGE_TOKEN` is a Koyeb secret.

## Deploy

1. Build from this repository with Dockerfile
   `deploy/training_merge/Dockerfile`.
2. Attach a persistent volume at `/data` (free Koyeb instances are ephemeral).
3. Set `NANLM_MERGE_TOKEN` to a scoped, revocable service credential. Do **not**
   set or use `DEEPREPO_PAT`.
4. Expose port `8080` over HTTPS.
5. Point the bootstrap/Android merge client at
   `https://<service>.koyeb.app/v1/training/merge`.

## API

```http
POST /v1/training/merge
Authorization: Bearer <scoped token>
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

Stale `base_generation` or a backwards nanclock tick is rejected with 409.
Repeating an idempotency key returns the same response.

## Boundary

- Koyeb: small JSON state, merged head/route deltas.
- Bootstrap runner: 2 GiB map, 8 MiB live image, 256 head arena.
- Android: 8 MiB universe; no 2 GiB map.
- No PAT enters this service.
