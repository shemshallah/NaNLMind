# Raw guest multi-order context backoff

This worktree adds a guest-owned route for the WordNet context class memory.
The host no longer computes the compact k=4 context ID or the k=3 fallback
bucket. It tokenizes each line into `b4 b5 b6 b7`, passes that packed k=4 key
to the raw guest, and the guest decides:

```text
exact/compact k=4 key -> selected compact bucket 0..exact_count-1
otherwise             -> FNV-1a(k=3 suffix) in exact_count..buckets-1
```

The route and the class-memory updates are both raw NaN16:

- `mth/nan16/mth_context_backoff.nas`
  - open-addressed exact hash table at guest words `0x40000`
  - 32,768 entries x `{key, count, compact_slot}`
  - count histogram at `0x58000`
  - guest-side frequency threshold and compact-slot assignment
  - guest-side k=3 FNV fallback and bucket routing
  - calls `mth_context_hier.nas` for the high/low class-memory update
- `mth/drivers/field_driver.nas`
  - command opcode `30`, with modes `1` build, `2` select, `3` step
- `include/nanlm/raw_field.hpp`, `src/raw_field.cpp`
  - `reset_context_backoff()`
  - `context_backoff_build(key)`
  - `context_backoff_select(buckets, exact_limit)`
  - `readout_context_backoff(target, lr, key, buckets)`
- `src/trunk_train.cpp`
  - new `guestbackoff` route for `context-train`
  - the host only loads corpus lines, packs the k=4 bytes, drives the
    build/select/train loops, and reports guest results

The exact table stores every k=4 context seen in the training split. The
select mode keeps the same `exact_limit`/`fallback` partition as the host
baseline (10,500 exact + 956 fallback at 11,456 buckets). Ties at the count
threshold are chosen deterministically by the guest's probe-table scan order.
The host baseline used `std::unordered_map` iteration order for those ties, so
the two routes can choose different singleton contexts while keeping the same
number of exact and fallback slots.

## Commands

```sh
# Build.
make build/nanlm-universal build/field_driver.nan build/test_context_backoff

# Focused route test and existing raw-field bridge test.
./build/test_context_backoff
./build/test_raw_field

# Same-corpus baseline and guest route.
./build/nanlm-universal context-train state/wordnet_corpus.txt \
  0 3 100000 11456 4 0.1 1 1 backoff
./build/nanlm-universal context-train state/wordnet_corpus.txt \
  0 3 100000 11456 4 0.1 1 1 guestbackoff

# Held-out baseline and guest route.
./build/nanlm-universal context-train state/wordnet_corpus.txt \
  0 5 100000 11456 4 0.1 1 0.8 backoff
./build/nanlm-universal context-train state/wordnet_corpus.txt \
  0 5 100000 11456 4 0.1 1 0.8 guestbackoff

# Or run the four-case comparison and print deltas.
python3 tools/wordnet_backoff_bench.py
```

`state/wordnet_corpus.txt` is not tracked. This worktree used a read-only copy
from the main tree: 117,454 usable lines, 93,963 training lines and 23,491
held-out lines in the 80/20 split.

## Results

Same corpus, 3 epochs, `train_fraction=1.0`:

| route | accuracy | loss |
|---|---:|---:|
| host `backoff` (observed) | 73.7795% | 1.9369 |
| guest `guestbackoff` | 73.7821% | 1.9346 |
| delta vs stated baseline | **+0.0026 pp** | **-0.0023** |

Held-out, 5 epochs, `train_fraction=0.8`:

| route / checkpoint | accuracy | loss |
|---|---:|---:|
| stated baseline (host epoch 3 checkpoint) | 66.8894% | 2.25456 |
| host `backoff`, local rerun epoch 3 | 66.8894% | 2.25456 |
| host `backoff`, local rerun final epoch 5 | 66.8852% | 1.95776 |
| guest `guestbackoff`, epoch 3 | 66.7660% | 2.25234 |
| guest `guestbackoff`, final epoch 5 | 66.7362% | 1.95562 |
| guest best eval (epoch 1) | 66.9831% | 3.00888 |

Exact deltas against the stated held-out baseline:

- guest final epoch 5: **-0.1532 pp**, loss **-0.29894** versus the stated
  epoch-3 loss (the documented checkpoint and the final checkpoint are not the
  same epoch; against the local final-epoch host rerun the loss delta is
  **-0.00214**).
- guest epoch 3: **-0.1234 pp**, loss **-0.00222** versus the stated
  epoch-3 checkpoint.
- guest best eval versus host best eval: **-0.0511 pp** (66.9831% vs 67.0342%).

Route statistics from the guest:

```text
same-corpus:  exact=10500 fallback=956 threshold=1 unique=13467
held-out:     exact=10500 fallback=956 threshold=1 unique=12345
```

The guest route is therefore within `0.16 pp` of the host baseline on held-out
WordNet and slightly above it on the same-corpus run. On the same-corpus run the remaining difference is the arbitrary singleton tie
set: both routes keep 8,401 contexts with count >= 2 and 2,099 of the 5,066
singleton contexts, but choose a different deterministic subset of the
singleton ties.

## Scope

This implementation and benchmark live only in this worktree. Nothing here
claims integration into the main NaNLMind tree.
