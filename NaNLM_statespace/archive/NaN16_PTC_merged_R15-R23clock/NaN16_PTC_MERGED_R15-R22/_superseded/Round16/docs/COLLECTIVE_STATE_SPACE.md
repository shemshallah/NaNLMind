# NaN16 — Collective State Space

**Working name:** Collective State Space (CSS)  
**Principle:** One logical space. Many physical homes. Many contributing minds.

## 1. First principle: separate the brain from its substrate

The logical brain is independent of where state physically lives:

```
B = (S, T, G, H, P, E)
```

| Symbol | Meaning |
|--------|---------|
| S | Collective state space |
| T | Transition rules |
| G | Relationship / communication topology |
| H | Cognitive heads and persistent state |
| P | Programs, procedures, learned strategies |
| E | Event history and provenance |

Physical tiers implement S; they do not define it.

## 2. Liquid State Memory (tiers)

| Tier | Role | Examples |
|------|------|----------|
| 0 | Active cognition | Local RAM, active pages, firing heads |
| 1 | Local persistent | SSD, cached cognitive pages |
| 2 | Distributed liquid | DeepRepo, remote page replicas |
| 3 | Edge / cloud execution | Workers, routing, inference |
| 4 | Durable archives | Cold storage, snapshots, provenance |

A head requests a **logical page ID**. The memory manager resolves, fetches, verifies, and tracks activity. The head does not know the physical home.

## 3. The 256 cognitive heads

The 16-bit bit-reversal map has **256 fixed points** `R(a)=a`.

These are **candidates** for persistent cognitive heads — not automatic agents.

Each head state record:

| Field | Function |
|-------|----------|
| id | Stable identity 0..255 |
| activation | Current activity level |
| focus | Attended regions |
| context | Active memory references |
| history | Prior activations / outcomes |
| associations | Learned relationships |
| confidence | Uncertainty |
| pending | Message queue |
| strategy | Current procedure id |
| version | Provenance / revision |

Heads may specialize by measured activity, not by hard-coded job titles.

## 4. Hierarchy of cognition

1. **Local** — cells transform state  
2. **Paired** — mirror orientations hold complementary information  
3. **Collective** — heads coordinate larger-scale reasoning  

## 5. Event model

```
e = (id, actor, target, operation, parent, proof)
```

Collective state is derived from accepted events under deterministic rules.  
Immutable event history is separate from mutable working state.

## 6. Message types

ACTIVATE · QUERY · SIGNAL · PROPOSE · CHALLENGE · VERIFY · COMMIT · SNAPSHOT · PORTAL · RETRACT

## 7. Open-source contract (GitHub-first)

Public: address/state-space spec, transition rules, head interface, page formats, replication protocols, reference implementation, tests, contribution rules.

GitHub hosts the **public construction**, not necessarily the entire live mutable brain.

## 8. Participation levels

Observer · Researcher · Memory host · Compute host · Validator · Developer · Coordinator

## 9. Non-goals / dangers

State poisoning · silent corruption · identity confusion · uncontrolled concurrent writes · privacy leakage into public state · model/provider lock-in · resource inequality · consensus ≠ truth

## 10. Phases

I Public brain · II Cognitive core · III Liquid memory · IV Collective state · V Distributed intelligence · VI Expanding substrate

---

*Every subsequent implementation must satisfy this document.*
