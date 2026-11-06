# NaN Translation Fabric (NTF)

## 1. The three address domains

| domain | example | question |
|---|---|---|
| physical | `tcp://node-a.example:7401/nan` | where can I reach it? |
| universe | `nan://U-07/R-03/H-0x0180/T-108/model/a` | where does it exist in the topology? |
| semantic | `model/nanlm-head`, `corpus/alice`, `service/reason` | what am I trying to access? |

The fabric translates between them without letting the physical address become
the identity. A universe can move hosts, a head can move CPUs, and a resource
can move providers while the logical address stays stable.

---

## 2. Universe address

```text
nan://U-07/R-03/H-0x0180/T-108/model/a
      │    │    │         │
      │    │    │         └─ temporal generation
      │    │    └─────────── head / native address
      │    └──────────────── region
      └───────────────────── universe id
```

- `U-` is the universe id.
- `R-` is the region (a 256×256 chart or a deployment zone).
- `H-` is the native head address; it may be a 16-bit palindromic address.
- `T-` is the temporal generation from the logical clock/ledger.
- The trailing object is a semantic resource key.

An IPv6 address, port, or provider name never appears in the universe address.
That is the point: **network location is replaceable infrastructure**.

---

## 3. Mapping record

```text
NaNMappingRecord {
    universe_id
    topology_root          // hash of the universe page set
    interface_map          // exposed operations / capabilities
    provider_peers[]       // signed node identities
    network_locators[]     // physical routes
    temporal_generation
    mapping_version
    capabilities
    expiry
    crypto_suite
    signature
}
```

Rules:

- `mapping_version` must increase;
- `generation` must never go backwards;
- an expired mapping is not resolved;
- an unsigned mapping is rejected;
- a valid address does **not** grant permission; capabilities are separate;
- a provider can change without changing the universe id.

The `topology_root` ties the mapping to the one global digest. A provider that
claims a universe must present a matching root.

---

## 4. Resolution pipeline

```text
native address
   │
   ▼
universe registry
   │
   ▼
region resolver
   │
   ▼
head / resource resolver
   │
   ▼
peer discovery
   │
   ▼
physical route
   │
   ▼
remote NaN/0S node
```

Control plane:

- publish and verify mapping records;
- discover peers and providers;
- negotiate interfaces and capabilities;
- revoke, expire, and rotate keys.

Data plane:

- move computation, state transitions, files, and messages;
- carry the temporal handoff context;
- never expose the internal head layout to the destination.

---

## 5. Temporal handoff

A cross-universe request carries:

```text
source universe / region / head / generation
destination universe / region / head / generation
epoch, phase
payload hash
```

`validate_handoff()` rejects:

- a destination universe mismatch;
- a stale destination generation;
- an expired destination mapping;
- an invalid temporal phase;
- a missing epoch at generation zero.

This is how a universe can move or restart without accepting a replay from an
old physical route.

---

## 6. Identity and security

The code exposes a pluggable `CryptoSuite`:

| suite | role |
|---|---|
| Ed25519 | node signatures, mapping authorization |
| ML-KEM | post-quantum key establishment |
| SHA3 | hashing / domain separation |
| NSP8 | NaN-native packet/state sealing |

The current C++ implementation is a **verification hook**, not a crypto
implementation. It checks that a signature is present and that the mapping is
versioned/expiring; the actual Ed25519/ML-KEM/SHA3/NSP8 verification belongs in
NaN/0S or a small native verifier.

Separate:

1. identity — who signed this mapping;
2. address — which universe is this;
3. authorization — which capabilities are granted.

A valid universe address must not imply access.

---

## 7. Mesh layering

```text
NaN computational universes
  256 heads · scratch · clock · self-modification
        │
Universe Network Map
  universe identities · interfaces · topology
        │
NaN Translation Fabric
  address resolution · mapping · routing · temporal translation
        │
NaN/0S Mesh Network
  peer discovery · secure transport · relays · distributed registry
        │
Physical devices
  phones · laptops · servers · ARM · RISC-V · x86 · GPU/RAM/storage farms
```

A device can contribute only storage, only CPU, only GPU, only network, or a
combination. It does not need to host an entire universe. A universe can have
multiple providers and survive one provider disappearing.

---

## 8. Decentralization

Use a distributed registry rather than one permanent address server:

- nodes advertise reachable locators;
- universes advertise signed identity and interfaces;
- storage providers advertise hosted resources;
- compute providers advertise capabilities;
- bootstrap nodes are replaceable;
- a node can discover peers without a central coordinator.

The design borrows the separation of identity and location from LISP and the
peer/content discovery distinction from libp2p, without claiming compatibility.

---

## 9. Implementation status

`include/nanlm/ntf.hpp`, `src/ntf.cpp`:

- `UniverseAddress` parse/format;
- `PhysicalLocator`;
- `NodeId`;
- `MappingRecord` with version, generation, expiry, capabilities, crypto suite,
  signature field, and digest;
- `TranslationFabric` publish/resolve/route/revoke;
- `TemporalHandoff` validation;
- `MeshRegistry` advertise/find/expire.

`tests/test_ntf.cpp` verifies:

- `nan://` parse/format round-trip;
- multiple locators for one universe;
- stale version/generation rejection;
- expiry rejection;
- owner-only revoke;
- handoff generation/expiry validation;
- peer advertisement/expiry.

The crypto verifier and real peer discovery are next; the address/mapping
contract is in place.

---

## 10. Priority stages

| stage | deliverable |
|---:|---|
| 1 | native universe address format |
| 2 | translation fabric mapping record |
| 3 | signed registry (Ed25519/ML-KEM/SHA3/NSP8 hook) |
| 4 | peer discovery and routing |
| 5 | two-universe communication demo |
| 6 | NaNClock-aware handoff protocol |
| 7 | distributed storage and resource discovery |
| 8 | dynamic mesh expansion |

Stage 5 is the first meaningful demonstration: two universes on two machines,
communicating through logical addresses, with neither machine knowing the
other's internal head arrangement.

---

## 11. The principle

> The network should be subordinate to the universe topology, not the other way
> around.

IP addresses, devices, routes, and providers are replaceable infrastructure. A
universe's logical identity and topology should survive those changes.
