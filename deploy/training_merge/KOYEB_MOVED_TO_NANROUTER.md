# NaNLMind is not the Koyeb deployment owner

The old `deploy/training_merge/koyeb.yaml` has been removed. NaNROUTER is
the **only** deployment owner for the shared BS0:0 NANNET ingress, runner ring,
HERMES lease authority and bounded NaN16/N16DE network.

Use `shemshallah/NaNROUTER/deploy/koyeb/nanrouter.yaml` to stage the new
router-owned single-public-service image. It contains an internal
loopback-only copy of this NANNET portal from a source-pinned NaNLMind commit
and the exact existing issuer/merge logic. NaNLMind remains the owner of its
model/learner source, not the public router deployment.

**Important:** GitHub does not automatically migrate the live Koyeb service.
Do not delete the old Koyeb runtime or detach its stateful volume until the
new router service is explicitly verified with the SAME
`NANNET_AUTHORITY_MASTER_KEY`, `NANNET_AUTHORITY_DB`,
pairing/revocation table, and managed external TLS name. A new empty issuer
would invalidate paired HERMES installations and is forbidden for cutover.
No new public SC0/GM0 service exists: those are SQLite tables within the
NaNROUTER mounted data.

The actual router-owned Koyeb service must be started with
`RIDDLE_KOYEB_ROUTER_PORTAL_ENABLED=1` and
`RIDDLE_HERMES_NATIVE_ENABLED=1`; it exports the native public `BS0:0`
edge and keeps portal, CLOCKED and head-cortex internally on loopback.
HERMES keypairs are paired at the same NANNET issuer and the router allocates
HW2 to the first pairing and HW5..255 to additional independent keys.

This source-side manifest removal does **not** claim the old deployed Koyeb
service has been deleted, stopped or replaced.
