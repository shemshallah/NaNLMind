# Koyeb NANNET portal + training merge

This is the small training-delta merger. It is **not** the 2 GiB map and **not**
a macrocluster.

The bootstrap runner owns the 2 GiB map. Android/peer runners submit head
vectors, strengths, routes, a base generation, and a nanclock tick. Koyeb merges
the small deltas and returns a generation + digest. The bootstrap ring applies
the returned manifest to its map.

## Live service

```text
https://nannet.apps.mistral.run
```

The live Koyeb service is `nannet-portal` and currently runs on a `nano`
instance. A persistent volume is attached at `/data`, so
`/data/training_merge.json` and `/data/nannet-authority.sqlite` survive service
replacement. The current main-branch image combines the merge API with NANNET
pairing authority, root-derived role-separated identities, and consent-based
device leases on the same HTTPS origin. `NANLM_MERGE_TOKEN` is a Koyeb secret;
do not put a GitHub PAT in this service.

## Deploy

1. Name the Koyeb web service `nannet-portal` and build from this repository with Dockerfile
   `deploy/training_merge/Dockerfile`.
2. Attach a persistent volume at `/data` (the live service already has one).
3. Set `NANLM_MERGE_TOKEN` to a scoped, revocable service credential and `NANNET_AUTHORITY_MASTER_KEY` to an independent random 32-byte base64url secret. Store both as Koyeb secrets. Set `NANNET_AUTHORITY_DB=/data/nannet-authority.sqlite`. Do **not** set or use `DEEPREPO_PAT`.
4. Expose port `8080` over HTTPS.
5. Configure each `nanlm-cpu-N` repository with its matching `BSR(N-1)_PORTAL_API` Actions variable set to the portal HTTPS base URL. Point N16T protocol clients at `https://<service-host>/n16t` (or the `/portal` compatibility alias), training merge clients at `https://<service-host>/v1/training/merge`, and guest clients at the `/v1/devices/*` routes. The hostname must be taken from the actual Koyeb deployment, not guessed.

## N16T transport and NANNET routes on the same service

- `POST /n16t` — bounded binary N16T v1 HELLO/CAPABILITIES handshake (`application/vnd.nan16.n16t`).
- `POST /portal` — compatibility alias for the same N16T handshake; `GET /portal` serves this service guide. This is not the training merge API.
- `GET /healthz` — health and authority status.

- `POST /v1/devices/register` — explicit-consent enrollment, next free HW4–HW255 slot; issues a signed guest bearer using a per-device key derived from the authority master.
- `POST /v1/devices/heartbeat` — renew lease, rotate the guest bearer, and revoke its predecessor.
- `POST /v1/devices/rotate` — rotate bearer without creating a duplicate slot; old bearer is revoked.
- `POST /v1/devices/release` — revoke active bearer and return slot for next participant.
- `POST /v1/devices/report` — submit device/system/network/security issue.
- `POST /v1/bootstrap/oidc` — verifies GitHub Actions OIDC for exactly `shemshallah/nanlm-cpu-1` through `nanlm-cpu-6`, on `main`, using `.github/workflows/runner.yml`; returns a 15-minute BSR admin bearer.
- `POST /v1/bootstrap/heartbeat` — rotates the current BSR bearer and revokes the prior token.
- `POST /v1/admin/identities/revoke` — admin-only, persistent identity-wide revocation.
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

`nanlm-cpu-1` through `nanlm-cpu-6` are BSR0 through BSR5 administrative/bootstrap runners. Each repository receives only its own portal base-URL variable (`BSR0_PORTAL_API` through `BSR5_PORTAL_API`). These values are URLs, not secrets. Each BSR workflow requests a GitHub OIDC token with audience `nannet-portal`; the portal verifies its signature, repository, main ref, and exact workflow path before issuing a short-lived admin bearer. Each BSR has a distinct root-derived Ed25519 identity key. Workers rotate the bearer during long-running epochs; the prior bearer is revoked on each rotation. Do not provision a static BSR secret or copy `NANNET_AUTHORITY_MASTER_KEY` to a runner. Pairing codes default to the guest role; guest scopes cannot include `snapshot:write`, `universe:register`, or `installation:admin`. HW guest enrollment remains consent-based and separate from BSR OIDC.
