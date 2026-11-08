# HERMES per-universe lease integration

The integration now spans three repositories without replacing the existing NANNET pairing issuer or the BS0:0 runner ring.

1. **NaNROUTER #61** owns durable SQLite lease allocation, HMAC-signed receipts, native slot/generation high-watermarks, revocation/renewal, and fail-closed POST `/v1/hermes/leases/{open,resolve,renew,release}`. Separate 32+ character delegation bearer `RIDDLE_HERMES_DELEGATION_TOKEN` and receipt key `RIDDLE_HERMES_RECEIPT_HMAC_KEY`; both live exclusively on the router.
2. **NaNLMind NANNET portal** adds separate scope `hermes:lease` (guest-eligible, not `universe:register`). It verifies the existing paired installation's bearer, its Ed25519 signed request, body digest, timestamp and nonce before delegated service-to-service calls. It obtains `installation_id` from the token (never the body), and sets server-owned HERMES node point 3 (HW2). The portal needs `NANNET_HERMES_ROUTER_URL` and `NANNET_HERMES_DELEGATION_TOKEN`, configured privately and identically to the router-side delegation token.
3. **NaNLMind_HERMES #12** adds five tools `nanlm_universe_status/open/resolve/renew/release`. Receipts are encrypted locally using existing `NANNET_MASTER_KEY`; each operation re-verifies scope online and signs its exact NANNET request. It rejects head 255, wrong issuer/port, stale revisions and route/receipt mismatches.

### Required deployment / security gates

- Do not put keys in GitHub commits, PR comments, workflow logs or user-visible tools.
- Ensure the portal's NANNET issuer state, pairing/revocation database and configured HTTPS hostname remain authoritative; **do not bring up a second public portal writer**.
- Existing HERMES paired tokens will not automatically gain the new `hermes:lease` scope; create explicitly scoped guest pairing codes and re-pair as needed.
- Do not expose router lease endpoints publicly without private-network ingress / independent delegation bearer protection. For production require HTTPS and constrain outbound NANNET-to-router networking.
- The router's HMAC lease receipt is verified **at router resolution**, not as a locally verifiable Ed25519 signature by HERMES. The HERMES client only checks its basic shape until authenticated router admission.
- **Optional actual native execution:** When the pinned NaN0S runtime is enabled, `resolve` verifies the native guest route, and the new `dispatch` and `ack` endpoints execute the existing NaN16 N16T guest and persist an at-most-once result acknowledgement. Without the native runtime configured, `resolve` remains a metadata-only admission; `dispatch` and `ack` fail closed. The native NaN16DE `nhl_open` / `nhl_nannet_route` functions remain execution-side gates awaiting a trusted loader/receipt-to-guest handoff. Fail closed rather than claim execution.
- The old Koyeb portal remains deployed from NaNLMind until staging, database/issuer continuity, DNS, and authentication/negative tests are verified. No live cutover is performed by these code changes.

### Namespaces

BS0:0 is the shared runner-ring network port, HW0:0 is a separate root hardware node, stable HERMES HW2 translates to node point 3, and each separate HERMES universe has local computable heads 0..254 plus reserved network head 255. Multiple leased universes MAY share node point 3 while preserving distinct lease/universe identities.

### Verification

`python -m unittest discover -s tests -p test_hermes_router_delegation.py -v` alongside existing `test_training_merge.py`; new `.github/workflows/hermes-router-delegation.yml` runs both. Cross-repo checks in NaNROUTER PR #61 and HERMES PR #12 guard their own boundaries. This branch does not assert that the external Koyeb service has been updated.

### Native transport and production package

The NANNET portal forwards `dispatch` and `ack` under the exact same
bearer, Ed25519 body signature, replay nonce and `hermes:lease` scope as
`open`/`renew`/`resolve`/`release`. N16T request hex is bounded to
65,572 bytes of opaque guest-owned framing. Router ACK requires a matching
lease ID, universe ID, generation, head, dispatch ID, and response SHA-256.
A crash after reservation makes that dispatch ambiguous and prevents
non-idempotent replay. No response is treated as a canonical learning commit.

`deploy/training_merge/Dockerfile` now packages the actual
`runner.hermes_router_delegate` module for Koyeb; the existing issuer and
NANNET pairing database stay in place. Portal runtime needs a verified
`NANNET_HERMES_ROUTER_URL` (HTTPS or localhost development only) and
`NANNET_HERMES_DELEGATION_TOKEN` (must match the router's delegated bearer).
Do not include either bearer in source or documentation.

The three-repository signed HTTP smoke now builds the real pinned NaN0S C core
and tests signed pairing, independent leases, native head admission, actual
N16T guest response, digest-bound ACK, retry semantics and revocation.
See `integration/hermes_cross_repo_smoke.py` and
`.github/workflows/hermes-cross-repo-smoke.yml`.

Live deployment and public ingress cutover require the private Koyeb service
account, matching secrets, persistent volume, DNS/TLS validation and existing
issuer continuity; GitHub code changes and CI are not a live deployment.
