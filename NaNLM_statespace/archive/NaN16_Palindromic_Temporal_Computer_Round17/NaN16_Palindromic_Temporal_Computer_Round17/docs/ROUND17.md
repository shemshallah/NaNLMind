# Round 17 — Continuity under disruption

## Three kinds of state

| Kind | Contents |
|------|----------|
| Head-local | associations, specialization, activation |
| Collective | shared facts, contested claims |
| Transition | event log, commit frontier, applied-id set |

## Results: 16/16

| Test | Result |
|------|--------|
| Interrupted commit | Uncommitted event discarded on restart |
| Replay | Same collective content hash |
| Duplicate delivery | Idempotent; count unchanged |
| Delayed delivery | Parent event attribution preserved |
| Head reconstruction | Identity + associations restored |
| Page migration | Tier copy preserves hash + identities |
| Collective recovery | Contested state coherent after restart |
| **Disappearing head** | **ALL PASS** |

## Star experiment

Head 3 proposes · Head 20 challenges · Head 30 records · commit · crash mid next transition · restart · replay.

Pass: identities, both claims, provenance, no dups, no partials, matching hash.
