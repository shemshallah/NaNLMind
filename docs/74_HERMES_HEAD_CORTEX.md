# HERMES NaN Head Cortex Service

**Status:** first read-only native inference adapter implemented; deployment and Router registration pending.  
**Owner:** NaNLMind native topology and NANNET receiving side.  
**HERMES client:** `nanlmind_hermes/head_cortex.py` in NaNLMind_HERMES.

## Purpose

The head-cortex service receives a typed `nanlm.hermes-evidence-package`,
validates its content digest and trust policy, converts provenance-bound
relation atoms to a temporary N16REL/1 test-only file, and invokes the native
`relation-eval` command against an existing serialized topology.

It returns a `nanlm.head-cortex-response` with predicted Boolean relation
states, active head IDs, rule IDs, generation, state digest and provenance.

## Native command

Build the canonical native binary:

```sh
make -j2
```

Read-only inference:

```sh
./build/nanlm-universal relation-eval RECORDS.n16rel STATE.nmg
```

Input rows must all be `test` split records. The command refuses training
rows, requires an existing topology, and never serializes or changes it.
Unknown is returned for a tied 4/8 Boolean vote. The CI smoke hashes the state
before and after evaluation and requires equality.

The existing `relation-train` command remains a distinct mutation operation.
It is not called by this service.

## HTTP adapter

Run locally after building and preparing an existing state file:

```sh
export NANLM_NATIVE_BINARY="$PWD/build/nanlm-universal"
export NANLM_HEAD_STATE="$PWD/state/hermes-universe.nmg"
export NANLM_HEAD_CORTEX_TOKEN="a-long-random-local-only-token"
python3 runner/head_cortex_service.py
```

For an integrated installation, configure `NANNET_AUTH_URL` instead of the
isolated static token. The service calls NANNET `POST /v1/authorize` with
scope `universe:read` for each request. HERMES sends its scoped
`NANLM_DEVICE_TOKEN`; it does not receive a privileged runner credential.
Deploy behind HTTPS, bind to a private interface, and expose it only through
the authenticated NaNLMind Router/Koyeb route. The built-in WSGI server is a
development adapter, not a production TLS terminator.

Environment:
- `NANLM_NATIVE_BINARY`: native NaNLMind executable.
- `NANLM_HEAD_STATE`: existing serialized topology (read-only).
- `NANNET_AUTH_URL`: NANNET authorization service URL.
- `NANLM_HEAD_CORTEX_TOKEN`: optional isolated local bearer for tests only.
- `NANLM_HEAD_CORTEX_HOST`, `NANLM_HEAD_CORTEX_PORT`: bind settings.

## Trust and mutation boundary

- CLOCKED output remains teacher observation, not ground truth.
- Only evidence entries with valid SHA-256 source provenance become native query rows.
- The service uses temporary test-only records and never calls `relation-train`.
- It does not clone or own the six-runner ring, canonical checkpoint, Koyeb volume, or route generation.
- It emits no mutation proposal and cannot promote head state.
- Boolean predictions are diagnostic relation outputs, not independent fact verification or a general language-model answer.

The shared contracts are:
- `integrations/clocked/hermes-evidence-package.schema.json`
- `integrations/clocked/head-cortex-response.schema.json`
- `integrations/clocked/scratch-entry.schema.json`

HERMES owns the revisioned scratch, source reconciliation and natural-language
synthesis. NaNLMind owns the native Boolean heads, relation evaluator and
canonical state. Only the existing six-runner generation barrier may promote
future candidate mutations.
