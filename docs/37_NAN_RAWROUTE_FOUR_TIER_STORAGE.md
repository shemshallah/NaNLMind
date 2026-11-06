# NaN Rawroute: four-tier storage and hierarchical address model

**Status:** architecture specification for implementation. This extends the existing NaNNet point-zero / N16B runner transport; it does not replace that transport or silently reinterpret existing route IDs.

## 1. Decision

Use four independently addressable NaN-native namespaces:

- `BS0:0::bs0db` — bootstrap authority and network entry point.
- `MC0:0::mc0db` — runner-ring and macrocluster mapping.
- `SC0:0::sc0db` — supercluster topology and aggregation.
- `GM0:0::gm0db` — global mesh registry and cross-domain mapping.

Each namespace receives a **10 GB logical quota**. Do not preallocate 40 GB or create four physical volumes unless Koyeb's actual persistent-volume capacity supports it. Use sparse files / quota-enforced database files on the existing persistent mount. Report logical quota, allocated bytes, and physical free bytes separately.

Koyeb BS0:0 is the always-on bootstrap/network gateway because it has continuous availability and inbound/outbound networking. It is not the owner of all live computation. MC0:0 is runner-controlled and initially exposes six logical execution units.

## 2. Address grammar

The hierarchical rawroute example is:

```
nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:1,2,3
```

Interpretation:

| Component | Meaning |
|---|---|
| `GM0` | global-mesh namespace |
| `SC0` | supercluster namespace |
| `MC0` | macrocluster namespace |
| `BS0:0` | bootstrap network node 0 |
| `HW0:0` | hardware runner-ring 0 |
| `::` | network path / local target boundary |
| `HW0:1,2,3` | heads 1, 2 and 3 in that runner ring |

Grammar rules:

- `:` separates hierarchy coordinates.
- `::` separates the resolved network path from a local target expression.
- Commas select multiple targets in the same target namespace.
- A second `::` introduces a typed object association, e.g. `vector1337` or `hyperedge1337`.
- Coordinates are canonical non-negative decimal integers: no signs, whitespace, leading zeroes except the literal zero, wildcards, or implicit aliases.
- Parsing is strict. Unknown namespace kinds, out-of-range coordinates, malformed separators, and ambiguous paths fail closed.
- A route definition is stable; a route instance is its current resolution to a runner/head/storage location. Moving a runner changes the instance/generation, not the definition's identity.

Examples:

```
nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:1
nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:1,2,3
nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:1::vector1337
nan://GM0:SC0:MC0:BS0:0:HW0:0::HW0:2::hyperedge1337
```

The existing six-coordinate runner route and N16B/1 wire format remain supported as the transport-level leaf address. The hierarchical rawroute is a higher-level name that resolves to that existing transport route plus node/ring/head/object selectors. Do not change N16B bytes or existing runner identities as part of this extension.

## 3. Authority and ownership

### BS0:0 / bs0db — authoritative network bootstrap

Owns:
- node registration and stable node identities;
- committed route definitions and route generations;
- authoritative route-manifest index and digest ledger;
- namespace registry and address canonicalization policy;
- credentials/scopes/revocation metadata (never plaintext secrets);
- merge receipts, nanclock ordering and provenance;
- training-intake routing metadata and feedback references.

BS0:0 accepts registrations, validates proposed route deltas, commits manifests, and returns resolved route packets. It does not execute every head and does not become a monolithic storage owner.

### MC0:0 / mc0db — runner and hardware mapping

Owns:
- six logical runner execution-unit identities and leases;
- runner ring membership and health/capability reports;
- head-to-runner and head-to-hardware mappings;
- active-head sets, local route trees and execution placement;
- resource accounting, scheduling metadata and runner feedback;
- references to BS0 committed generations.

Runner-controlled means execution/lease ownership belongs to the runner ring. BS0 remains the reachable registration and committed-route authority.

### SC0:0 / sc0db — supercluster mapping

Initially prepare the schema and namespace; do not fabricate live superclusters. Own:
- macrocluster membership and topology;
- 256-cluster grouping definitions where configured;
- cross-macrocluster route edges and aggregation;
- hyperedge/vector association references;
- synchronization and transformation definitions;
- snapshots/digests of member generations.

### GM0:0 / gm0db — global mesh mapping

Initially prepare the schema and namespace; do not fabricate a populated global mesh. Own:
- global namespace registry and cross-domain identifiers;
- supercluster-to-supercluster route associations;
- global discovery and reverse-lookup indexes;
- transformation registry and versioned mathematical operators;
- global topology snapshots and provenance references.

Higher layers should reference lower-layer records by stable IDs and digests rather than copying all lower-layer records. A global route is a chain of references, not four duplicated copies of the same state.

## 4. Initial logical quota plans

These are planning ceilings inside each 10 GB namespace, not preallocated files. Adjust after measuring real record sizes and access patterns.

| BS0DB allocation | Logical budget |
|---|---:|
| Committed route journal and manifests | 2.5 GB |
| Node identity and registration metadata | 1.0 GB |
| Route snapshots and recovery checkpoints | 2.0 GB |
| Merge receipts, nanclock and provenance | 1.5 GB |
| Training-intake routing metadata | 1.0 GB |
| Indexes and operational metadata | 1.0 GB |
| Growth reserve | 1.0 GB |

| MC0DB allocation | Logical budget |
|---|---:|
| Six-unit runner ring / lease records | 0.5 GB |
| Hardware and node capability maps | 1.0 GB |
| Head-to-runner maps and route trees | 3.0 GB |
| Execution / scheduling history | 1.5 GB |
| Local route snapshots and recovery | 1.5 GB |
| Reverse indexes and lookup metadata | 1.5 GB |
| Growth reserve | 1.0 GB |

| SC0DB allocation | Logical budget |
|---|---:|
| Supercluster and macrocluster manifests | 1.5 GB |
| Cluster membership and topology edges | 2.5 GB |
| Aggregated route snapshots | 2.0 GB |
| Vector / hyperedge association metadata | 1.5 GB |
| Transform definitions and versions | 1.0 GB |
| Provenance, indexes and reserve | 1.5 GB |

| GM0DB allocation | Logical budget |
|---|---:|
| Global namespace and identity registry | 1.5 GB |
| Cross-supercluster route associations | 2.5 GB |
| Global discovery and reverse indexes | 2.0 GB |
| Mathematical transform registry | 1.5 GB |
| Global topology snapshots / checkpoints | 1.0 GB |
| Provenance and growth reserve | 1.5 GB |

The initial software milestone is to create the schemas, quotas, indexes, migration/version metadata and health reporting. Empty future-layer databases are valid; they must report uninitialized/empty rather than pretend a supercluster or global mesh is populated.

## 5. Common record model

Every committed route record should contain:

- canonical rawroute string and parsed coordinate tuple;
- stable route-definition ID;
- parent route ID and namespace/layer;
- target kind: node, runner, head, vector, hyperedge, transform, memory object;
- target stable ID and transport leaf route;
- generation and parent/base generation;
- nanclock tick / logical epoch;
- content digest;
- provenance / authorizing node;
- state: proposed, committed, superseded, revoked;
- optional expiry/lease for dynamic route instances.

Keep immutable committed events and materialize a compact current-state index. A route update must compare its base generation and reject stale writes. Idempotency keys prevent duplicate commits. Never silently retarget a missing head.

A typed object such as `vector1337` is a stable object identity plus an association table; it is not a giant vector copied into every routing database. The same applies to hyperedges.

## 6. Lookup and cache policy

Authoritative state stays in NaN-native persistent storage. A cache is disposable and rebuildable.

Initial implementation:
1. bounded in-process LRU for hot rawroute resolutions;
2. cache key includes canonical route definition ID and committed generation;
3. invalidate/update only after a successful manifest commit;
4. negative cache entries have short expiry;
5. cache misses resolve through the persistent authority and verify the committed digest.

Redis is **not required for the first deployment**. Add Redis only when there are multiple active service processes / runner gateways or measured route-lookup contention. If added, Redis holds hot route trees, reverse indexes, runner membership, active-head sets and immutable transform definitions. It must never be the sole copy of a route, identity, commit, or generation. A Redis flush must be recoverable by rebuilding from NaN storage.

## 7. Koyeb deployment constraints

- BS0:0 is the 24/7 externally reachable bootstrap endpoint.
- All four namespaces can initially live as separate database files under the same persistent mount, subject to actual volume capacity.
- Enforce independent per-namespace logical quotas and expose allocated/available counters.
- Do not claim 10 GB physical allocation per layer unless the volume has at least 40 GB usable capacity.
- Use transactional writes, checksums, atomic checkpoint replacement and startup recovery.
- Keep secrets in Koyeb secret configuration, never in route records or committed files.
- Expose health fields for each DB: schema version, logical quota, allocated bytes, record count, generation, digest, last checkpoint and read/write status.

## 8. Implementation sequence

1. Preserve the existing N16B/1 six-runner transport unchanged.
2. Implement a strict hierarchical rawroute parser/canonicalizer and round-trip tests.
3. Implement common route records and append-only commit journal.
4. Implement BS0DB authority and manifest resolution.
5. Implement MC0DB six-unit runner/head mapping and route-diff feedback.
6. Create SC0DB and GM0DB schemas with empty-state reporting and cross-reference validation.
7. Add in-process cache and cache-generation invalidation.
8. Benchmark; add Redis only if measured need justifies it.
9. Add bootstrap feedback intake so route observations and training-generated NaN code can propose micro-routing definitions; only validated, committed definitions enter the authoritative route manifest.

## 9. Safety invariants

- One stable address definition can have changing route instances, but no silent identity changes.
- A cache is never authority.
- Higher layers reference lower layers; they do not duplicate entire databases.
- A runner lease is not a permanent route commitment.
- Route feedback can propose updates; it cannot bypass validation or commit checks.
- Preserve all existing commits and the current N16B/1 transport contract.
