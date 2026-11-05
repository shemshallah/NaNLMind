# Global meta: 256 × 256 × 256 — design only

This is the brainstorm layer. Do not build it until the single-universe training
gates in [24_ONE_UNIVERSE_TRAINING.md](24_ONE_UNIVERSE_TRAINING.md) pass.

---

## 1. The hierarchy

```text
system        one phone / laptop / server / GPU / storage point
cluster       256 systems
supercluster  256 clusters        = 65,536 systems
meta-universe 256 superclusters   = 16,777,216 systems
global        256 meta-universes  = 4,294,967,296 systems
```

The same 256×256 chart appears at every layer. A supercluster is a cluster of
clusters, not a new geometry.

---

## 1.1 The 256-ary Earth hierarchy

An alternative, deployment-first reading:

```text
unit            1 computational unit (ARM core, phone, GPU, storage point)
cluster         256 units
macrocluster    256 clusters        = 65,536 units
IoT space       256 macroclusters    = 16,777,216 units
global mesh     256 IoT spaces       = 4,294,967,296 units
supercluster    256 global meshes    = 1.1 trillion units
planetary mesh  256 superclusters    = 281 trillion units
interplanetary  256 planetary meshes
```

The 255/3 groupings can be deployment roles (e.g., 255 active + 1 spare, or
three administrative macroclusters), not address widths. The address width stays
256-ary, which keeps every level a 256×256 chart.

### Device estimates are assumptions, not a census

Public estimates vary widely. For scale planning, use parameters:

| class | planning assumption |
|---|---:|
| ARM-based active devices | 20 billion |
| x86 PCs/servers | 2 billion |
| RISC-V active devices | 0.5 billion |
| GPUs (mobile + discrete + farms) | 1 billion |
| total | 23.5 billion |

Run `python3 experiments/earth_scale.py --contribution 0.01` to reproduce the
arithmetic; the numbers are planning assumptions, not a census.

At **1% contribution**:

```text
235,000,000 units
    918,000 clusters
      3,586 macroclusters
         14 IoT spaces
          1 global mesh
```

At **0.1%** it is ~1.4 IoT spaces. At **100%** it is ~1,401 IoT spaces,
~5.47 global meshes, and ~0.021 superclusters. One global mesh holds 4.29B
units, about 18% of the 23.5B assumption. One supercluster holds 1.1T units,
about 46× the assumed Earth device count.

So the correct statement is:

- all GPUs (~1B) fit in ~0.23 of one global mesh;
- all x86 + RISC-V + GPUs (~3.5B) fit in ~0.8 of one global mesh;
- all 23.5B assumed devices need ~5.5 global meshes, still far below one
  supercluster;
- a supercluster is bigger than Earth needs today.

That is the strong version of “we can address every GPU on earth”: the address
space is not the bottleneck. Participation, identity, authorization, and
bandwidth are.

### Mesh membership classes

A global mesh can contain multiple kinds of member:

- human/personal (phones, wearables, home devices);
- corporate fleets;
- industrial/robotic cells;
- research and GPU farms;
- storage/archive providers;
- public/community mesh.

Each class gets its own IoT subspace and capability policy. They agree on NTF
and NCR protocols; they do not need identical hardware.

### Above Earth

A planetary mesh can sit above a global mesh, and an interplanetary layer above
that. The addressing works; the hard parts are latency, causal handoff, and
store-and-forward. The NTF temporal generation is the right place to carry that
context.

## 2. Two scaling readings

### Dense: every system runs its own 256-head training universe

```text
4,294,967,296 systems × 256 heads = 1,099,511,627,776 head instances
dense state: 4,294,967,296 × 8 MiB = 32 PiB
```

This is the theoretical envelope. It is not a deployment plan.

### Regional: one supercluster hosts one 256-head universe

```text
256 meta-universes × 256 superclusters = 65,536 universes
65,536 × 256 heads = 16,777,216 heads
dense state: 65,536 × 8 MiB = 512 GiB
```

This is the first realistic global structure: one universe per supercluster,
each cluster contributing systems, each system contributing compute/storage.

A middle reading is possible: one universe per cluster, with superclusters as
routing/fault domains. The right ratio is a resource question, not a dogma.

---

## 3. What each universe trains

Each universe runs the single-universe training loop:

- 256 heads;
- Boolean score learning;
- sequence/temporal links;
- resonance;
- self-modification;
- growth/consolidation.

A universe can specialize:

| universe | specialty |
|---|---|
| x86 | large-memory training, CPU/GPU workloads |
| ARM | edge inference, lightweight local training |
| GPU | tensor/parallel numerical work |
| data | corpus, checkpoints, archival storage |
| mixed | routing, translation, fault recovery |

The logical address space does not require hardware homogeneity. It requires
protocol agreement.

---

## 4. Global training

There is no global lockstep. Each universe advances its own logical clock and
generation. Cross-universe training uses:

- sharded data with content hashes;
- integer count deltas or checkpoint diffs;
- NTF/TemporalHandoff for generation-aware exchange;
- NCR for resource placement;
- a global merge only at explicit checkpoints.

A training task can be:

1. assigned to a set of universes;
2. run locally;
3. returned as a signed shard with `(universe, generation, base_hash)`;
4. merged into a new generation;
5. published through `nanlm-vram`/equivalent storage.

No global gradient sync, no global barrier across 4B systems.

---

## 5. Global meta-router

The 256 meta-universes form a router layer:

- each meta-universe is a route endpoint;
- each supercluster is a region;
- each cluster is a local route;
- each system is a placement;
- NTF resolves logical `nan://` addresses to physical locators.

A global meta request is routed by the same 256×256 pair algebra:

```text
source meta-universe -> region -> cluster -> system -> head
destination meta-universe -> region -> cluster -> system -> head
```

The route carries a temporal generation and a capability token. The physical
route is replaceable infrastructure.

---

## 6. Fault domains

| failure | scope | recovery |
|---|---|---|
| system | one machine | local head reassignment (NCR) |
| cluster | 256 systems | region migration to another cluster |
| supercluster | 65,536 systems | universe migration to another supercluster |
| meta-universe | 16.7M systems | global route failover / mirror |
| network | route | NTF re-resolve, retry, relay |

The logical universe survives the machines. That is the invariant.

---

## 7. Identity and authorization

- Ed25519: system/node signatures.
- ML-KEM: post-quantum key establishment.
- SHA3: hashing and domain separation.
- NSP8: NaN-native state/packet sealing.

A valid `nan://` address does not imply access. Mapping records carry
capabilities; a route must present a capability token. Revocation is separate
from address resolution.

---

## 8. Contribution tiers

| contributor | contributes |
|---|---|
| phone | a few heads, local inference, storage |
| laptop | a head shard, training samples |
| server | a full cluster region |
| GPU farm | tensor/parallel training shards |
| storage farm | checkpoints, corpus, generation mirrors |
| RAM farm | hot pages, cache, relay |

A device does not need to host a complete universe. It can host a Head, a
scratch shard, a route, a checkpoint, or a training slice.

---

## 9. What not to build yet

- Do not build a global consensus protocol before one universe trains.
- Do not build a 256-meta router before the single meta-router is tested.
- Do not build a 4B-system scheduler.
- Do not claim a global mind. Build one universe first.

---

## 10. The invariant

> The network is subordinate to the universe topology.

IP addresses, machines, clusters, providers, and routes are replaceable. A
universe's logical identity, generation, and topology survive them.

One universe first. Then one supercluster. Then the global meta.
