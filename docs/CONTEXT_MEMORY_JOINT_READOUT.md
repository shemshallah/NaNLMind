# Joint context-memory readout (raw NaN16)

Status: **native readout experiment and measured held-out result**, not a
language-quality claim. This worktree ports one idea from the NaNLM v1
(`nanlm-test`) reference tracks and leaves the training tables byte-identical
to the greedy baseline.

## Result

WordNet 3.1, 117,454 usable lines, random 80/20 split (seed 99), 11,456 buckets
(10,500 exact 4-byte contexts + 956 three-byte FNV fallback), LR 0.1, 3 epochs.

| readout on the same checkpoint | full-class accuracy | loss |
|---|---:|---:|
| greedy high-nibble then low-nibble (`backoff`) | 66.8894% | 2.25456 |
| joint head-pair routing (`backoffjoint`) | **67.2385%** | 2.25456 |
| delta | **+0.3491 pp** | 0.0 |

The checkpoint is `12,464,128` bytes with SHA-256
`f61dc83951410c64feb4d40b200f2c0e8ad4cf892f59396c9fe9439bddd6cf1c`.
The corpus SHA-256 is
`18e6dff10f4af298eab92748999decd893b89c1d7453b398ff17b485f1464716`.
The committed JSON artifact is
[`artifacts/wordnet_context_score.json`](../artifacts/wordnet_context_score.json).

The gain is selection-only: the tables, gradients and cross-entropy loss are
unchanged. Joint evaluation costs about 6.6x the greedy evaluation time on this
device (`8.36 s` vs `1.26 s` for 23,491 samples) because it scores all 16
conditional low heads instead of one.

## What the readout does

The existing classifier factorizes a byte into a 4-bit high nibble and a 4-bit
low nibble:

```text
greedy: h* = argmax_h P(h | context)
        l* = argmax_l P(l | h*, context)
```

Joint head-pair routing keeps the same tables but selects the pair

```text
(h*, l*) = argmax_{h,l} P(h | context) * P(l | h, context)
```

The raw guest copies the 16 high probabilities from the softmax scratch, then
evaluates all 16 low heads at the current context bucket. A slightly less
probable high group can win when its conditional low head is much more
confident. No observed target label is used by the router.

This is the local, NaN16-compatible part of the v1 head-routing idea: the 16
conditional low heads act as persistent competing interfaces, and the joint
score is their deterministic vote. It does not introduce a shared deep trunk,
a transformer, PyTorch, or a second model.

## Files

- `mth/nan16/mth_context_hier.nas` — `mth_context_hier_joint` wrapper, joint
  head-pair loop, and the unchanged greedy path.
- `mth/nan16/mth_softmax16_table.nas` — returns the max class probability in
  `r4` for the joint score.
- `mth/drivers/field_driver.nas` — guest command `30` for joint context
  readout; command `25` remains the greedy baseline.
- `include/nanlm/raw_field.hpp`, `src/raw_field.cpp` —
  `readout_context_joint` and host-side test cell marshalling.
- `src/trunk_train.cpp` — `backoffjoint` route; `backoff` remains unchanged.
- `tests/test_context_route.cpp` — independent deterministic routing test.
- `tools/context_memory_score.py` — reproducible native benchmark and JSON
  score artifact.

## Commands

```sh
# Build the raw image, CLI and focused test.
make -j2 build/nanlm-universal build/test_context_route

# Deterministic raw kernel test.
./build/test_context_route

# Same tables, greedy vs joint held-out scoring.
python3 tools/context_memory_score.py --epochs 3 \
  --out artifacts/wordnet_context_score.json

# Equivalent CLI form: train/save the baseline checkpoint, then re-score it.
./build/nanlm-universal context-train state/wordnet_corpus.txt \
  0 3 100000 11456 4 0.1 1 0.8 backoff 10500 save=state/wn3.ctx
./build/nanlm-universal context-train state/wordnet_corpus.txt \
  0 0 100000 11456 4 0.1 1 0.8 backoffjoint 10500 load=state/wn3.ctx
```

`state/wordnet_corpus.txt` is not tracked; the score tool records its SHA-256.

## NaNLM v1 reference review

The sibling `nanlm-test` commits reviewed here are:

- `14edacd` — sparse shared-trunk reference with 255 low-rank adapters,
  top-k router and graded hotspot bias.
- `adbe93b` — independent 1 MiB per-head banks, int8 blockwise Adam, CFT
  residual and 2/3 triad + 43/85 field votes.
- `docs/SPARSE_SHARED_TRUNK.md`, `docs/INDEPENDENT_HEADS.md`,
  `docs/HYPERMATRIX_V1_V2_RECONCILIATION.md`.

What is symbiotic with this path:

1. **Sparse head routing** is directly useful. The context memory already has
   a hierarchy of 16 high groups and 16 conditional low heads per bucket. The
   joint readout is a routing kernel over those heads and is the only v1 idea
   measured to improve the held-out byte score here.
2. **Shared smooth view + sparse exact view** was tested. Training a three-byte
   backoff view on every sample and mixing/routing it with the exact view hurt
   full-class accuracy in a host probe (exact-only 67.11%; count-gated or
   confidence-gated routing 45.9-65.7% depending on threshold). The production
   code does not adopt it.
3. **Int8 Adam / per-head optimizer** is a legitimate future port, but a
   host-side probe at 5 epochs only matched the fixed-rate SGD baseline
   (67.03-67.10% on the probe split versus 67.10% SGD) while requiring moment
   state for every sparse cell. With the 4M-word guest limit there is no room
   for a full second moment table at 11,456 buckets, so this was not ported.
4. **CFT/triad/field votes** are already represented natively in NaNLMind and
   are not needed to select the readout class. They remain appropriate for
   committing weight patches, not for the score reported here.
5. **Deep sparse shared trunk and 255 transformer adapters** are not
   symbiotic with the current raw path: they need a sidecar/page budget,
   dequantization, and a shared deep trunk that the native context-memory path
   does not have. They should not be claimed from this result.

## Limits

- The result is one corpus/split and one checkpoint epoch. It is a measured
  held-out selection gain, not a general language-quality claim.
- The loss is unchanged because joint routing changes only argmax selection.
- Joint evaluation is slower; it should be used where accuracy matters, with
  the greedy path retained for throughput and as the control.
- No training-table arithmetic, checkpoint format, or greedy baseline output
  changed.
