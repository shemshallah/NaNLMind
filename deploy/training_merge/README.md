# Koyeb NANNET portal + training merge

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

The intended Koyeb service name is `nannet-portal` (the live service must also be renamed in Koyeb; changing this repository manifest does not rename an already-created service). The current main-branch image now combines the merge API with NANNET pairing authority and consent-based device leases on the same HTTPS origin. Koyeb
rejected `free`. No persistent volume is attached, so merged JSON state is
ephemeral until one is added. `NANLM_MERGE_TOKEN` is a Koyeb secret.

## Deploy

1. Name the Koyeb web service `nannet-portal` and build from this repository with Dockerfile
   `deploy/training_merge/Dockerfile`.
2. Attach a persistent volume at `/data` (free Koyeb instances are ephemeral).
3. Set `NANLM_MERGE_TOKEN` to a scoped, revocable service credential and `NANNET_AUTHORITY_MASTER_KEY` to an independent random 32-byte base64url secret. Store both as Koyeb secrets. Set `NANNET_AUTHORITY_DB=/data/nannet-authority.sqlite`. Do **not** set or use `DEEPREPO_PAT`.
4. Expose port `8080` over HTTPS.
5. Configure each `nanlm-cpu-N` repository with its matching `BSR(N-1)_PORTAL_API` Actions variable set to the portal HTTPS base URL. Point training clients at `https://<service-host>/v1/training/merge` and guest clients at the `/v1/devices/*` routes. The hostname must be taken from the actual Koyeb deployment, not guessed.

## NANNET routes on the same service

- `POST /v1/devices/register` — explicit-consent enrollment, next free HW4–HW255 slot.
- `POST /v1/devices/heartbeat` — renew lease.
- `POST /v1/devices/rotate` — rotate bearer without creating a duplicate slot.
- `POST /v1/devices/release` — return slot for next participant.
- `POST /v1/devices/report` — submit device/system/network/security issue.
- `POST /v1/pair`, `/v1/authorize`, `/v1/revoke` — scoped installation pairing and authority checks.

`GET /healthz` includes `nannet_authority: ready` only when the authority key is configured. The SQLite authority database shares the `/data` persistent volume with merge state. MAC/IMEI/serial are not used as identity; copied random credentials are limited to one active lease. Replacing a credential with a fresh identity cannot be reliably linked to the same physical device without Android hardware attestation.

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


## Bootstrap runner trust

`nanlm-cpu-1` through `nanlm-cpu-6` are BSR0 through BSR5 administrative/bootstrap runners. Each repository receives only its own portal base-URL variable (`BSR0_PORTAL_API` through `BSR5_PORTAL_API`). These values are URLs, not secrets. Give each runner a separate, revocable bootstrap credential with only the administrative scopes it needs; do not copy `NANNET_AUTHORITY_MASTER_KEY` to these runners. HW0–HW255 remain guest slots and must use guest enrollment credentials and guest scopes.
