# Growth and consolidation

## 1. Growth: a head materializes a child chart

A head grows when either condition holds:

1. **sustained self-model error**: `self_error >= threshold` for at least
   `error_streak_required` consecutive observations;
2. **scratch overflow**: the scratch high-water mark reaches the work-area
   threshold.

```cpp
GrowthPolicy policy;
// self_error_threshold = 32768 (0.5 in Q16.16)
// error_streak_required = 3
// scratch_threshold = 768
// max_depth = 4
```

The head record carries:

```text
self_error       u16  normalized error
error_streak     u8   consecutive high-error observations
scratch_used     u16  high-water mark
child            u16  1 = child exists at PageId::child(chart, h)
transform_phase  u8   2-bit I/B/BR/R oscillator phase
```

A head that already has a child does not grow again. A chart at
`policy.max_depth` does not grow. The child is a coordinate region of the same
object, not a separate mind:

```text
child = PageId::child(parent, head)
```

`GlobalTopology::grow_head()`:

1. evaluates the policy;
2. creates the child chart via `add_chart`;
3. marks the head `mark_grown()`: `child = 1`, error/streak/scratch reset;
4. appends a growth event to the one ledger;
5. publishes a new manifest generation.

`GlobalTopology::scan_growth()` returns all heads currently over threshold.
`GrowthDecision` carries a human-readable reason:
`"sustained self-model error"`, `"scratch high-water mark"`, `"head already has
a child"`, or `"max depth reached"`.

### Example

```cpp
GlobalTopology g;
GrowthPolicy p;
HeadArray heads = g.root_heads();
HeadView h = heads.at(0);
for (int i = 0; i < p.error_streak_required; ++i)
    h.note_self_model_error(40000, p.self_error_threshold, p.error_streak_required);

PageId child = g.grow_head(PageId::root(), 0, p);
// child.depth == 1, child.path[0] == 0
```

---

## 2. Consolidation: replay community scratch

The chart has two scratch areas:

- 256 per-head scratchpads (`256 B local + 768 B work`);
- one 64 KiB community chart scratch.

A `ScratchJournal` is an ordered set of scratch operations against a base page:

```text
ScratchJournal {
  id
  epoch
  page
  base          // page digest before replay
  ops[]         // Chart / HeadLocal / HeadWork writes
}
```

`ConsolidationEngine::consolidate()`:

1. **duplicate check**: if `id` was applied, return `ok` with `duplicate=true`;
2. **base check**: current page digest must equal `journal.base`;
3. **workspace**: clone the page (copy-on-write);
4. **replay**: apply each scratch op with bounds checks;
5. **next hash**: compute the workspace digest;
6. **atomic page replace**: `PageTable::replace(page, workspace, base)` checks
   the base hash again;
7. **one ledger event**: kind `CONSOLIDATE`, epoch `journal.epoch`, before/after
   hashes;
8. **manifest flip**: publish `generation + 1` with the new page root, epoch,
   and page list;
9. **record the journal id** for idempotence.

The page and the manifest are only flipped after the base check succeeds. If a
scratch op is out of range, nothing is committed: no page replacement, no
ledger event, no manifest generation.

### R17 commit rules

This is the R15/R17 branch/commit model applied to scratch:

| R17 rule | consolidation implementation |
|---|---|
| stale workspace rejected | `journal.base` must equal current page digest |
| abort leaves no state | out-of-range op returns before page/ledger/manifest |
| commit is one history entry | one `CONSOLIDATE` ledger event |
| duplicate delivery is a no-op | applied journal id set |
| replay reconstructs | journal + base + page digest |
| no partial state | page replace after all ops validate |
| manifest is derived | flip after page replacement and ledger append |

### Example

```cpp
ScratchJournal j;
j.id = 1;
j.epoch = g.clock().tick();
j.page = PageId::root();
j.base = g.pages().entry(j.page)->page->digest();
j.ops.push_back({ScratchKind::Chart, 0, 0, {1,2,3}});
j.ops.push_back({ScratchKind::HeadLocal, 0, 0, {0xAA,0xBB}});

ConsolidationResult r = g.consolidate(j);
// r.ok, r.generation == previous + 1
```

---

## 3. Manifest

```text
Manifest {
  generation
  page          // last changed chart
  base          // page digest before the change
  root          // global page root hash
  epoch         // logical clock epoch
  pages[]       // all chart page ids
}
```

`ManifestStore::publish(next, expected_generation)` is compare-and-swap: it
accepts only `next.generation == expected + 1`. A concurrent writer holding a
stale generation is rejected.

The manifest is a derived pointer, not a second source of truth. If a publish
race occurs after a page replacement, the engine retries once with the latest
generation; the page and ledger are already committed.

---

## 4. Growth + consolidation together

```text
head error/scratch high
        │
        ▼
grow_head ──► child chart (same object)
        │
        ▼
community scratch writes
        │
        ▼
ScratchJournal (base hash)
        │
        ▼
COW workspace ──► replay ──► page replace ──► ledger ──► manifest flip
```

A child chart is a local coordinate region. Consolidation does not create a
second history; it advances the one manifest and the one ledger.

---

## 5. What the tests cover

`tests/test_growth.cpp`:

- sustained self-model error triggers growth;
- scratch high-water mark triggers growth;
- `grow_head` creates the child, marks the head, resets the counters;
- a head with a child does not grow again;
- max-depth stops growth;
- `scan_growth` is empty after the threshold cases are handled.

`tests/test_consolidation.cpp`:

- chart scratch and head local/work replay;
- page replaced, ledger event with the journal epoch, manifest generation +1;
- duplicate journal is an idempotent no-op;
- stale base is rejected with no page/ledger/manifest change;
- out-of-range scratch aborts with no change;
- a second valid journal flips the manifest again;
- manifest and journal digests are deterministic.

---

## 6. Open questions

1. Should self-model error be a scalar, a vector, or a distribution?
2. Should the error streak reset on a single low reading, or decay?
3. Should scratch overflow be measured by bytes, allocation attempts, or both?
4. Should a child chart inherit the parent's head phase or start at `I`?
5. Should consolidation be triggered by a journal size, an epoch, or a manual
   quorum?
6. How does a consolidation interact with a page lease and a clock tick gap?
7. Should the manifest flip be a quorum publish or a single writer?

These are deliberately testable; none is settled by the current code.
