# Parallel native workstreams

Status: **active implementation note**, not a final result.

## Workstreams

Six worktrees are being used so the changes do not collide:

| worktree | task |
|---|---|
| `nan-hash` | move FNV context hashing into the raw guest |
| `nan-backoff` | move exact/compact + k=3 backoff routing into the guest |
| `nan-field` | map the 16x16 class memory to 255 heads / 85 triads / 43/85 field |
| `nan-copy` | raw copy/induction route with a confidence gate |
| `nan-batch` | guest-side batch trainer/evaluator and parity/speed checks |
| `nan-eval` | inspect `../nanlm-test` architectures and build the native held-out score artifact |

The host is allowed to marshal corpus bytes, sample order, and command words.
The new routing/scoring/update arithmetic must remain in NaN16 guest code.

## Current baseline to beat

| run | held-out |
|---|---:|
| WordNet context memory, compact 4-byte + 3-byte backoff | **66.8894%** |
| WordNet context memory, pure hash | 55.9874% |
| WordNet full softmax 255 | ~21.2% |
| WordNet positional 16x16 hierarchy | 33.26% |
| WordNet sampled hinge, 100 epochs | 12.88% |

The baseline uses `context-train` with 11,456 buckets, exact top 10,500
4-byte contexts, a 3-byte fallback, LR `0.1`, and 5 epochs.

## Is 60-70% good?

For this exact task it is operationally strong:

- random 255-class next-byte: ~0.4%;
- always predict the most common byte: ~16.4%;
- held-out majority 4-gram: ~44.75%;
- current context memory: **66.89% held-out**.

It is not language understanding. It is a context-indexed n-gram class memory
with a random line split. A synset/domain split, calibration, and a
source-disjoint corpus are still required before calling it general.

## `nanlm-test` review targets

The sibling `nanlm-test` repository has two relevant newer references:

- `14edacd`: shared deep trunk + 255 low-rank adapters + top-k hotspot
  routing + 2/3 triad and 43/85 field gates.
- `adbe93b`: independent 1 MiB heads with int16 weights, int8 Adam moments,
  local loss/CFT credit, and triad/field votes.

The symbiotic pieces for NaNLMind are:

1. **Int8/int16 quantized adaptive readout state** — the context tables are
   already a class-memory bank; adding native per-row moments could reduce
   held-out loss and memory.
2. **Shared trunk residual** — a small learned feature can handle unseen
   contexts that the lookup table cannot.
3. **Hotspot routing** — use high-nibble/triad credit to gate the selected
   class-memory region instead of a hard hash route.
4. **Independent head vote/rollback** — keep rejected context updates out of
   canonical state.

Do not port the PyTorch harnesses as runtime. They are reference/control
implementations only.

## Native checkpoints

Saved context tables (loadable by `context-train ... load=`):

- `state/hw4_wordnet.ctx` — 66.8894% held-out, 12.46 MB;
- `state/hw5_gutenberg.ctx` — 40.7879% held-out, 12.46 MB.

`HW4` / `HW5` are local parallel job labels. They are not canonical HW nodes;
the topology remains one `HW0::BS0` universe.

## Agent results

- `nan-hash` commit `c81d1b9`: raw guest FNV-1a bucket selection; tests pass.
- `nan-backoff` commit `88861a8`: raw guest exact/fallback route; host-vs-guest
  parity `mismatches=0`; same-corpus `73.7821%`, held-out `66.7362%`.
- `nan-batch` commit `8836d7f`: guest batch command; 1,500-sample checkpoint
  bit parity; ~11% pinned train speedup on 20k lines.
- `nan-field`, `nan-copy`, `nan-eval`: worktree experiments; not merged.

The main tree currently has `c81d1b9` integrated. The remaining agent commits
are in isolated worktrees and are not claimed as main-tree parity.
