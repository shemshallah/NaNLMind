# Unified build contract — NaNLMind is canonical

This contract freezes the build and authority boundary between the three
repositories.

```text
NaNLMind          canonical topology, native build, canonical state
NaNROUTER         transport, point-0 ingress, routing, control plane
NaNLMind_HERMES   read-only adapter and candidate producer
```

NaNLMind is not a client of NaNROUTER for its native universe. NaNROUTER may
route requests and leases to the active runner, but it must not copy, fork, or
reinterpret the native topology. HERMES may read, chat, train candidates, and
export evidence, but it must not promote canonical state.

This contract is aligned with
[`HYPERMATRIX_V1_V2_RECONCILIATION.md`](HYPERMATRIX_V1_V2_RECONCILIATION.md):
NaNLMind v2 is the only target; v1 Python, PyTorch, float tensors, overlay
files, and the v1 runtime are not imported into the native path.

## Canonical constants

| Object | Value |
|---|---:|
| Addresses | 65,536 |
| Physical heads | 256 |
| Triad member heads | 255 (0–254) |
| Triad field head | 255 |
| Triads | 85 |
| Mirror pairs | 32,640 |
| Canonical cells | 32,896 |
| Chart bytes | 8,388,608 |
| Hypermatrix rows | 32,640 |
| Hypermatrix row bits | 256 |
| Resolution layers L0–L9 | 10 |
| Transform passes M0–M9 | 10 |
| Runner slots | 6 |
| Active runner slots | 1 |
| MP-writer-eligible heads | 255 (1–255) |
| Boolean-curriculum-eligible heads | 250 |
| NANNET root control head | 0 (role alias, not a native model head) |
| BSR control head indices | 0, 4, 5, 6, 7, 8 |

## Native command contract

The canonical binary is `build/nanlm-universal`. The required commands are:

```text
verify
relation-train RECORDS STATE
relation-eval RECORDS STATE
relation-audit RECORDS STATE
unification
```

`unification` prints a machine-readable line that must match
`spec/unified-build.v1.json`. `make unified-check` runs the native command and
the Python audit.

## Three role views, one topology

The router role contract and the native triad field are overlays on the same
256 physical heads:

- the router control-plane view reserves head 0 as the NANNET root role and
  heads 0,4,5,6,7,8 as BSR control roles, leaving 250 Boolean-curriculum heads;
- the MP writer view leaves 255 heads (1–255) eligible to originate microtable
  writes, subject to the existing authorization gates;
- the NaNLMind triad field uses heads 0–254 as triad members and head 255 as
  the field counter/readout.

These are not three universes, three head arrays, or permission grants. A role
overlay cannot reassign the native field head or create a second topology.

## Authority rules

1. One native topology exists, owned by NaNLMind.
2. NaNROUTER is the transport/control plane; it does not instantiate or fork
   the native universe.
3. HERMES is an adapter and candidate producer. Its local SQLite, resident
   store, scratch, caches, and transcripts are derived artifacts.
4. Only NaNLMind's existing generation/merge barrier can promote canonical
   state.
5. A pinned HERMES contract snapshot is a compatibility check, not a second
   source of truth; it must be refreshed from NaNLMind.
6. No live deployment is implied by this contract.

## Sync with the hypermatrix plan

This contract is the build/authority boundary for
[`HYPERMATRIX_V1_V2_RECONCILIATION.md`](HYPERMATRIX_V1_V2_RECONCILIATION.md).
P0 (mapped 32,640-row hypermatrix, projection, integer score, fixed 85-triads,
Q16.16 gains, relation audit) is implemented. P1 calibrated gains and all
later gates remain open until their own evidence exists. The contract does not
claim them.
