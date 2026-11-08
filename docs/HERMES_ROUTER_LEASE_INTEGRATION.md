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
- **Not yet native execution:** `resolve` means lease-admitted *route metadata*, not a loaded NaN16DE guest, N16T packet execution, or a canonical NaNLMind training merge. The native NaN16DE `nhl_open` / `nhl_nannet_route` functions remain execution-side gates awaiting a trusted loader/receipt-to-guest handoff. Fail closed rather than claim execution.
- The old Koyeb portal remains deployed from NaNLMind until staging, database/issuer continuity, DNS, and authentication/negative tests are verified. No live cutover is performed by these code changes.

### Namespaces

BS0:0 is the shared runner-ring network port, HW0:0 is a separate root hardware node, stable HERMES HW2 translates to node point 3, and each separate HERMES universe has local computable heads 0..254 plus reserved network head 255. Multiple leased universes MAY share node point 3 while preserving distinct lease/universe identities.

### Verification

`python -m unittest discover -s tests -p test_hermes_router_delegation.py -v` alongside existing `test_training_merge.py`; new `.github/workflows/hermes-router-delegation.yml` runs both. Cross-repo checks in NaNROUTER PR #61 and HERMES PR #12 guard their own boundaries. This branch does not assert that the external Koyeb service has been updated.
