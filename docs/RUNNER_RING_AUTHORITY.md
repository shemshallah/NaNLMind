# Atomic runner-ring authority

The six `nanrouter-runner-0..5` repositories are identical hot standbys. They
are the internal BSR0..BSR5 members of `MC0:0`. They do **not** receive
individual HW addresses. The ring as a whole is `HW5:0` for NaN routing.

## Authority

The Koyeb portal is the single atomic arbiter:

- `runner/runner_ring_authority.py` (portal process)
- SQLite WAL + `BEGIN IMMEDIATE`
- one `runner_ring_lease` row (slot, epoch, lease id, endpoint, expiry)
- monotone `nanclock_tick` in `runner_ring_meta`
- bounded checkpoint in `runner_ring_checkpoint`
- append-only `runner_ring_handoffs` evidence

## Protocol

| Method | Path | Meaning |
|---|---|---|
| `GET` | `/v1/runner-ring/clock` | allocate one monotone nanclock tick |
| `GET` | `/v1/runner-ring/status` | current active slot/epoch/checkpoint |
| `GET` | `/v1/runner-ring/checkpoint` | read the bounded handoff checkpoint |
| `POST` | `/v1/runner-ring/lease` | acquire/renew the single active lease |
| `POST` | `/v1/runner-ring/renew` | extend the current lease |
| `POST` | `/v1/runner-ring/release` | release before expiry |
| `POST` | `/v1/runner-ring/checkpoint` | publish the active HW5:0 state |

All routes require `RUNNER_RING_TOKEN` (32+ characters, Koyeb secret). The
authority stores no bearer token and performs no NaN arithmetic.

## Handoff rules

1. A live lease blocks every other slot.
2. The same slot may renew idempotently; its epoch and lease id do not change.
3. A released or expired lease advances the epoch.
4. A successful handoff writes a `runner_ring_handoffs` row.
5. The new active slot reads the checkpoint before activating `HW5:0`.
6. The checkpoint carries exact `NPF1` frames and the source/route evidence,
   so accepted NaN16DE words are not dropped.
7. If the active process dies, the lease expires; a standby takes over.

## Live evidence

See `NaNROUTER/docs/KOYEB_CUTOVER_EVIDENCE.md`. The live handoff advanced
slot 0/epoch 1 to slot 1/epoch 2 while preserving checkpoint digest
`d2fa6d5d306f15fce962096979d70ab9d6d7dc3cbd5d83e4e52ce4f71c02fc1d`.

## Boundaries

- The 7 GiB figure is a per-runner process budget, reported and soft-enforced.
- A runner does not claim an HW identity for itself.
- Koyeb remains the portal; the runners perform monitoring, translation and
  NaN routing.
