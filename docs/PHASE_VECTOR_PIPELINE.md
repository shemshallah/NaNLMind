# Phase-vector streaming architecture

Status: **raw NaN16 kernels with field-driver ABI and ingest integration**.
The kernels execute in the guest and are dispatched through
`mth/drivers/field_driver.nas`; host code only transports byte windows,
codebooks, query banks, and output files.

## 1. The encoding stack

```text
byte stream
  -> trig phase encoder             mth_phase_encode.nas
  -> phase hypervector             8 complex Q16 lanes
  -> phase rotation/binding        mth_phase_rotate / mth_q16_mul
  -> product quantizer             mth_phase_pq.nas
  -> graph spectral embedding      mth_spectral_iter
  -> sparse k-N code region        mth_sparse_knn.nas
  -> matrix / leaf observer        C(256,2) vector-code map
  -> trihead + 43/85 global field
  -> remote vector leaf fetch
```

These are separate mathematical objects. A vector is not a leaf, a leaf is not
a matrix row, and a matrix row is not the reconstruction.

## 2. Implemented raw kernels

Field-driver commands:

| command | kernel | ABI summary |
|---|---|---|
| 58 | `mth_phase_rotate` | complex in 0x7000, out 0x7200, turn/lanes 0x4001/2 |
| 59 | `mth_pq_encode` | query 0x7000, codebook 0x10000, C/D 0x4001/2 |
| 60 | `mth_phase_encode_wide` | bytes 0x7000, count/D 0x4001/2, complex out 0x5200 |
| 61 | `mth_spectral_iter` | A[8][8] 0x7000, x[8] 0x7040, out 0x7080 |
| 62 | `mth_sparse_knn` | query 0x7000, bank 0x10000, N/D/k 0x4001..3 |
| 63 | `mth_phase_encode_batch` | windows 0x60000, W/D 0x4002/3, complex out 0x70000 |
| 65 | `mth_vm_reset` | clear 32,640 C(256,2) cells |
| 66 | `mth_vm_accum` | pair a/b and Q16 delta, cell 0x300000 |
| 67 | `mth_vm_probe` | best third head above threshold |
| 68 | `mth_vm_credits` | matrix row support -> 255 head credits |
| 69 | `mth_pq_train` | raw centroid training, up to 8 iterations |
| 70 | `mth_pq_residual` | sample - codebook[code] residual payload |
| 71 | `mth_pq_update` | warm-codebook update without reinitialization |
| 72 | `mth_leaf_verify` | codebook + residual reconstruction check |
| 73 | `mth_ckpt_hash` | guest checkpoint payload digest |
| 74 | `mth_tokenize` | raw word/subword/meta tokenization |
| 75 | `mth_meta_trihead_reset` | clear 85 triad votes / 255 head credits |
| 76 | `mth_meta_trihead_observe` | hash 3-word context into triad/head tables |
| 77 | `mth_temporal_reset` | clear past/future/current temporal slots |
| 78 | `mth_temporal_observe` | fill past/current/future slots per word |
| 79 | `mth_temporal_project` | merge past/future slots into trihead tables |
| 80 | `mth_ngram_reset` | clear four byte n-gram tables |
| 81 | `mth_ngram_train` | count byte orders 1..4 |
| 82 | `mth_ngram_topk` | select top 64 keys per order |
| 83 | `mth_geom_hyperbolic` | mean radius + Poincare radial proxy |
| 84 | `mth_geom_path` | length, closure, turn, curvature |
| 85 | `mth_geom_triangle` | three-vector sides/area proxy/tightness/orientation |
| 86 | `mth_geom_field_perturb` | vector -> 255 credits, 85 votes, separate field value |
| 90 | `mth_tri_model_reset` | clear semantic triangle shape stats |
| 91 | `mth_tri_model_observe` | train tightness/area/orientation stats |
| 92 | `mth_tri_model_score` | score a triangle against learned shape |
| 96 | `mth_tri_field_reset` | clear shape-gated field tables |
| 97 | `mth_tri_field_observe` | bind a triangle to a triad and quality |
| 98 | `mth_shape_field_gate` | 43/85 count gated by shape and closure |
| 99 | `mth_global_hodge256_f32` | B1 divergence + B2^T curl from 32,640 float flows |
| 100 | `mth_global_hodge256_q16` | Q16 matrix-flows adapter for the same Hodge path |
| 93 | `mth_tri_model_observe_negative` | accumulate negative-shape stats |
| 94 | `mth_tri_model_score_contrast` | positive-vs-negative shape score |
| 72 | `mth_leaf_verify` | reconstruct codebook+residual, L1 accept/reject |
| 73 | `mth_ckpt_hash` | raw FNV-1a checkpoint payload digest |
| 87 | `mth_dual_gate` | fast head / slow head / medium field / slow coherence gate |

`RawFieldVM` exposes `phase_encode_wide`, `phase_encode_batch`,
`phase_rotate`, `pq_encode`, `spectral_iter`, `sparse_knn`,
`vector_matrix_reset`, `vector_matrix_accumulate`, `vector_matrix_probe`,
`vector_matrix_credits`, `read_vector_matrix`, `pq_train`, and `pq_residuals`. The C++ methods marshal Q16 words only; the guest performs
all arithmetic, including the triangular pair index.

### Trig phase encoder

`mth_phase_encode.nas`:

```text
for byte b at position p:
    lane = (b + p) mod 8
    angle = (b*257 + p*8192) mod 65536
    cos,sin = CORDIC(angle)
    z[lane] += (cos, sin)
```

Output is eight complex Q16 lanes plus a 0..15 shard selector. This is a
streaming encoder: no corpus-sized buffer and no host trig.

### Trig rotation

`mth_phase_rotate` rotates every complex lane by a Q16 turn. This is the
rotation operator used by triheads and hotspots:

```text
z' = z * exp(i theta)
```

It uses the existing `mth_q16_sin_cos` and `mth_q16_mul`; no float host path.

### Product quantizer

`mth_pq_encode`:

- query `D` Q16 values;
- codebook `C x D`;
- exact L1 nearest codeword;
- returns code and distance.

Production target: 8 subquantizers x 256 codewords, 8-bit code + residual.
The codebook is sharded by its high-nibble region so a query only scans one
region before falling back.

### Graph spectral embedding

`mth_spectral_iter` performs one raw `v <- A v` power iteration for an 8x8 Q16
adjacency. Repeated calls produce a graph spectral embedding. The graph can be
built from code co-occurrence or from the C(256,2) pair matrix; the vector is
the spectral coordinate used as a **concept-abstraction axis**.

### Sparse k-N

`mth_sparse_knn` scans a vector bank and returns the exact local top-k by Q16
dot product. It is the sparse candidate stage before remote leaf fetch.

## 3. Sharding choice

Use **codebook-region sharding**, not matrix-row sharding:

```text
shard = phase_shard (0..15)
code_region = high_nibble of PQ code
```

Why:

- 255 heads / 16 high groups already provide 16 regions;
- each region has a small codebook and a local matrix slice;
- 43/85 field vote selects the active region;
- the matrix row capacity (256 candidate bits) is not divided across shards;
- remote vector pages are grouped by code region, so one trihead query fetches
  from one region in the common case.

The C(256,2) matrix stays global as an index, but its **rows are partitioned by
high-nibble/code region**. Sharding the row tensor itself would make trihead
completion ambiguous across regions.

## 4. Matrix mapping as one stage

For each encoded vector:

```text
code = PQ(code(phase(x)))
active = top-k of codebook/head scores
for each pair (a,b) in active:
    H[pair(a,b)] support += codes of the next/co-occurring vectors
```

The matrix gives candidate third heads. The remote vector leaf store provides
the payload. The reconstruction is:

```text
query code set
  -> pair rows
  -> candidate third heads
  -> 2/3 triheads
  -> 43/85 field
  -> fetch remote leaf
  -> codebook center + residual
  -> verify against phase vector
```

The matrix localizes candidates; it does not reconstruct a remote vector by
itself.

## 5. Triheads, hotspots and rotation

- A triad is three code/head hypotheses.
- A trihead pair gives a candidate third head from the matrix.
- Rotate each triad by its phase before scoring: `z_abc = (z_a ⊙ z_b ⊙ z_c)`
  with a triad-specific phase offset.
- Hotspot credit selects which triads are worth full scoring. The existing
  `mth_hot_trihead.nas` already scans 255 credits and produces 85 triads.
- The 43/85 field gate decides whether to fetch a remote leaf and commit the
  abstraction update.

This makes hotspots a **remote-vector fetch budget**, not just a display flag.

## 6. Other mathematical objects

The vector is only one object. Keep these distinct:

| object | role |
|---|---|
| complex phase vector | continuous carrier |
| PQ code + residual | compressed leaf payload |
| sparse head code | routing / trihead address |
| pair matrix row | candidate relation index |
| spectral coordinate | concept-abstraction axis |
| leaf record | provenance + remote payload reference |
| concept prototype | cluster centroid above leaves |
| field state | global acceptance/route |

Do not collapse them into one “embedding.” The matrix is not a vector store; the
codebook is not a concept graph; the leaf is not a synset ID.

## 7. Use after HW5 re-encoding

1. Stream each cleaned book window through `mth_phase_encode`.
2. Quantize with the sharded PQ codebook.
3. Append/dedupe a remote leaf `(code, residual, context hash, provenance)`.
4. Update the C(256,2) vector-code matrix from consecutive/co-occurring codes.
5. Build spectral coordinates from the code adjacency.
6. Evaluate trihead completion and 43/85 field acceptance.
7. Fetch remote leaves only for accepted candidates.
8. Record reconstruction error and fetch count.

The old byte-pair C(256,2) object remains a diagnostic. The new object must be
tagged `vector-code-hypermatrix` with encoder/codebook digests.

## 8. Tests

Raw fixtures:

```sh
python3 tools/run_nan16_fixtures.py --only phase_encode
python3 tools/run_nan16_fixtures.py --only phase_pq
```

Both pass. They cover phase bundling, PQ nearest code, one spectral iteration,
zero-angle rotation and sparse top-1 k-NN (the k-NN fixture uses k=1; the kernel
supports k=1..4). The spectral fixture now verifies all eight identity outputs,
not just a nonzero result.

`build/test_raw_field` also exercises the complete Q16 pipeline from C++:
wide encode, batch encode, rotation, PQ, spectral iteration, and sparse k-NN.
The corpus path is checked end to end by:

```sh
make phase-ingest-check
# PHASE_INGEST PASS ...
```

### Corpus ingest

```sh
./build/nanlm-universal phase-ingest CORPUS [MAX_LINES] [WINDOW] [DIM] [MAX_WINDOWS] [OUTPUT_PREFIX]
```

The host stages byte windows and writes:

- `state/phase_vectors.bin` — complex Q16 phase vectors;
- `state/phase_vectors.codes.bin` — PQ code and L1 residual distance;
- `state/phase_vectors.knn.bin` — nearest-neighbor index and dot score;
- `state/phase_vectors.spectral.bin` — one spectral coordinate vector;
- `PREFIX.codebook.bin` — raw-trained PQ codebook;
- `PREFIX.matrix.bin` — raw C(256,2) vector-code observer;
- `PREFIX.residuals.bin` — raw reconstruction residuals;
- `PREFIX.triads.bin` — raw 85-triad/255-head mapping after matrix credits;
- `state/phase_vectors.json` — counts, dimensions, shard histogram, matrix
  updates, probe head/score, hot heads/triads, and the 43/85 field flag.

The ingest pipeline trains its codebook in the guest with `mth_pq_train`
(up to 32 codewords from the first pipeline window, one assignment/centroid
pass), then writes residual payloads with `mth_pq_residual`. This is a
trained first-stage codebook, not yet a corpus-wide 8-subvector 256-entry
PQ model.

## 9. Honest boundary

This is a kernel prototype, not a trained corpus encoder. The production
pipeline still needs:

- trained 8-subvector PQ with residual storage, not a per-ingest local codebook;
- multiple power iterations and spectral normalization;
- codebook-region matrix observer;
- remote leaf paging (reconstruction verification is now live);
- larger book-disjoint reconstruction runs beyond the 200-line smoke corpus;
- persistent corpus-wide checkpoint sharing across distinct corpus runs (checkpoint resume is now live).

## 10. Production-width streaming ingest

The production phase path is 64 or 128 complex lanes. `phase-ingest` batches
1,024 windows per guest command and uses a raw 256-bin Q16 trig lookup table
built once by `mth_phase_table_init`; the lookup table removes the CORDIC call
from every byte window. PQ, rotation, spectral iteration and sparse k-NN accept
D=64..128.

```sh
# all paths outside the repository, selected explicitly
./build/nanlm-universal phase-ingest \
  state/gutenberg_150_clean_corpus.txt 0 8 64 0 \
  /storage/emulated/0/Download/NaNLMind/phase_bank/gutenberg150_d64
```

The command writes the vector bank, code, kNN and spectral artifacts under the
output prefix. The external `state` directory is only used by older callers;
the production runner selects the external path.

For the chunked training/metric loop over the same encoded windows, use:

```sh
./build/nanlm-universal phase-train state/gutenberg_150_train.txt \
  0 8 64 0 state/phase_train
```

`phase-train` trains the codebook in the guest, warm-updates it in 64-window
chunks with `mth_pq_update`, and emits JSONL train/eval L1, matrix probe,
hot-head/triad and 43/85 field metrics.

### 8-subvector production codebook

`phase-codebook` trains the production 8-subvector codebook from evenly spaced
corpus windows:

```sh
./build/nanlm-universal phase-codebook \
  state/gutenberg_150_clean_corpus.txt 0 8 64 256 4096 \
  state/gutenberg150_d64.codebook8x256
```

It splits the 128-value pipeline vector into 8 subvectors of 16 Q16 values,
trains 256 codewords per subvector with raw `mth_pq_train`/`mth_pq_update`,
and writes a `NANPQ2` codebook plus JSON manifest. The codebook artifact is
129 KiB and is uploaded as the release asset
`gutenberg150_d64.codebook8x256.bin`.

### Context length

The phase-vector path still uses **8 bytes per window**, taken from the end of
each corpus line. The phase bank and its codebook are unchanged:

```text
phase window = 8 bytes
phase context_words = 0
```

A separate **meta-tokenizer layer** now supplies word-level context:

```text
subword tokenizer  character base units + adjacent base bigrams
word token         FNV-1a word ID, lowercased ASCII
meta context       3 preceding words, zero-padded at document start
context field      word_id, context_hash, triad (0..84), vote mask
```

The word is decomposed into **character base units** and **adjacent base
bigrams** (with BOS/EOS boundary bases), replacing the earlier two-piece hash.
The meta tokenizer emits the word ID, a three-word context hash, a triad, and a
vote mask. `mth_meta_trihead.nas` maps the context to the same 85-triad /
255-head layer. Its tables are at guest word 0x220000 (votes) and 0x220100
(head credits); the existing raw `field_vote` and `hot_triheads` paths consume
them.

### Temporally split context slots

`mth_temporal_slots.nas` adds the explicitly split register:

```text
S+ preceding slot       3 preceding words
S- anticipatory slot    3 following words
C  current slot         separate field register (head 255 is void)
```

For each word it stores:

```text
0x234000  [preceding_hash, current_word, anticipatory_hash]
0x230000  S+ triad votes
0x230100  S+ head credits
0x231000  S- triad votes
0x231100  S- head credits
0x233000  current field slot [word,-1,index,0]
```

`mth_temporal_project` merges S+ and S- into the normal trihead tables, while
the current word remains in a separate field register; head 255 is reserved void and is not an incidence endpoint.

```sh
./build/nanlm-universal meta-tokenize \
  state/gutenberg_150_train.txt 1000 4096 \
  state/meta_tokens
```

This emits `PREFIX.words.bin`, `PREFIX.subwords.bin`, `PREFIX.meta.bin` and a
JSON summary with accepted triads, hot heads, hot triads, and 43/85 field
state. On 100 lines of Alice it produced 789 words and 9,153 base/bigram
subwords.

### Byte n-gram training

`mth_ngram_train.nas` counts **unigram, bigram, trigram and quadrigram**
events directly over raw bytes, including binary/control bytes. Four
fixed-memory tables of 65,536 buckets each are used, with a two-word
`[packed_key, count]` bucket. `mth_ngram_topk` selects 64 entries per order in
the guest.

```sh
./build/nanlm-universal ngram-train \
  state/gutenberg_150_clean_corpus.txt 0 \
  state/gutenberg150_ngrams
```

Artifacts:

```text
PREFIX.ngrams.bin   4 orders x 64 records [order, packed_key, count]
PREFIX.json         byte count, orders, top-k and boundary notes
```

The packed keys are exact byte sequences for orders 1..4. The trainer is
byte-level; it does not silently turn control or UTF-8 bytes into text. Counts
are chunk-local: a 65,536-byte chunk boundary can omit up to three n-grams
that cross the boundary.

Full-corpus run:

```text
bytes trained      100,648,974
orders             1,2,3,4
top entries/order  64
artifact           3,072 bytes
sha256             05c270b38e4d41322800107cd574952f7085ed9e7773673fdb21690fbaab3a5c
release            phase-bank-gutenberg150-d64-v1
assets             gutenberg150_ngrams.ngrams.bin / .json
```

The top unigram is space (`0x20`, 16,730,062 events), followed by newline
(`0x0a`, 2,093,889) and `f` (`0x66`, 1,674,800). Bigram, trigram and
quadrigram tables use packed exact byte keys and are trained from the same
raw byte stream. `spec/byte_ngrams.v1.json` records the full artifact digest.

For the full temporally split register:

```sh
./build/nanlm-universal temporal-tokenize \
  state/gutenberg_150_train.txt 1000 4096 \
  state/temporal_tokens
```

This writes `.words.bin`, `.subwords.bin`, `.meta.bin`, `.slots.bin` and JSON.
The slots file contains `[preceding_hash, current_word, anticipatory_hash]`
triples. The JSON reports `preceding_context_words=3`,
`anticipatory_context_words=3`, `current_slot_head=-1`, and the 43/85 field
state.

The field result is a structural hook check, not a language-quality score;
with enough distinct contexts the 85 triads can saturate.

The legacy `context-train` path uses 4-byte exact contexts with a 3-byte
fallback; that remains separate from the new word-level meta tokenizer. Without an eval corpus, the training corpus is split into a held-out suffix.
For real book-disjoint metrics, pass the held-out corpus as the final argument:

```sh
./build/nanlm-universal phase-train \
  state/gutenberg_150_train.txt 200 8 32 200 \
  state/phase_train_book state/gutenberg_150_heldout.txt
```

Measured on the first 200 lines of the book-disjoint train/held-out files:

```text
eval L1 562,105   probe hit 100%   leaf verify 100%
hot heads 135     hot triads 45    43/85 field true
```

The selected checkpoint is the lowest held-out L1, with the 43/85 field state
as a tie-break. Metrics are written to `PREFIX.metrics.jsonl` and
`PREFIX.metrics.json`; the codebook and matrix files are the selected best
checkpoint.

### Metric semantics and stability

`eval_mean_l1_q16` is a Q16.16 **L1 reconstruction distance**, not a
cross-entropy or accuracy. `65536` is `1.0`; for D=32 complex lanes the sum is
over 64 Q16 components. `eval_per_dim_l1_q16` normalizes by that component
count, and `eval_relative_l1` divides by the mean held-out vector magnitude.

`train_mean_l1_q16` is a historical cumulative diagnostic: each chunk was
encoded under the codebook that existed before that chunk's update. The
comparable current metric is `train_current_l1_q16`, evaluated on a fixed
training probe bank after each update.

The matrix `probe_hit_rate` only asks whether any partner exists, so it
saturates at 1.0. `pair_top1_rate` asks whether the probe returns the actual
next code and is the meaningful matrix metric.

Online phase training now uses three controls:

- 256 evenly spaced replay anchors in every warm codebook update;
- a prior-weighted centroid option in `mth_pq_train` (disabled by default);
- validation-gated codebook updates. A candidate update is rolled back when
  held-out L1 is worse than the best run; `codebook_rollbacks` records the
  count.

Hash-split 2,000-word experiment with replay and gating:

```text
step 1   train_current=342,115  eval=491,304
step 14  train_current=275,916  eval=474,834
step 20  train_current=274,989  eval=471,729  <- best
step 25  train_current=278,900  eval=472,054
codebook_rollbacks=18
```

The useful next architectural step is to freeze the selected global codebook
and continue training a residual/adapter and directed matrix while the global
centroid set stays stable.

### Two-head self-modification

The Boolean self-modification path now has a two-head, three-timescale gate:

```text
fast head   : triad proposal
medium gate : 43/85 field acceptance
slow head   : global coherence threshold
```

`mth_dual_gate` (command 87) commits only when the fast triad accepts, the
second/slow head accepts, the field accepts, and coherence clears the slow
threshold. The fast head proposes; the slow head owns the durable mask change.
The gate also returns fast, slow and medium credit deltas.

`RawFieldVM::propose_dual` wires this into the chart bridge:

- fast and slow head masks are evaluated through raw `mth_triad_vote`;
- `mth_field_vote` is the medium gate;
- `mth_field_coherence` is the slow gate;
- the slow head is modified only after the raw gate commits.

`tests/test_dual_head.cpp` verifies that a field rejection preserves the slow
head mask, and that a fully accepted proposal changes only the slow head.
`mth/tests/mth_dual_gate_test.nas` exercises the raw gate directly.

### Persistent checkpoints

`phase-train` writes `PREFIX.ckpt` with:

```text
magic NANCKPT1
codebook word count
matrix word count
raw FNV-1a codebook digest
raw FNV-1a matrix digest
codebook payload
C(256,2) matrix payload
```

The digest is computed by `mth_ckpt_hash` in the guest. On the next run, the
checkpoint is loaded only if dimensions and both raw digests match; otherwise
training starts fresh. `resumed=true` is recorded in the summary.

```sh
make phase-train-check       # held-out suffix + resume verification
make phase-train-book-check  # book-disjoint held-out corpus
# PHASE_TRAIN PASS ...
```

### Remote leaf verification

`mth_leaf_verify` reconstructs `codebook[code] + residual`, computes the L1
error against the expected phase vector, and accepts only when the error is
within the Q16 tolerance. `phase-train` runs it for every held-out vector and
records `leaf_verify_rate` and `leaf_mean_error_q16`; the book-disjoint run
above verifies 100% of held-out leaves at zero reconstruction error.

### NaNROUTER runner

`NaNROUTER/runner_riddle/phase_bank_runner.py` schedules the raw guest command
and keeps the large bank outside both repositories:

```sh
python3 -m runner_riddle.phase_bank_runner \
  --nanlmind /data/data/com.termux/files/home/NaNLMind \
  --corpus state/gutenberg_150_clean_corpus.txt \
  --out-dir /data/data/com.termux/files/usr/tmp/phase_bank \
  --name gutenberg150_d64 --dim 64 --window 8
```

The runner refuses repository output unless `--allow-repo` is explicit. It
does not calculate any vector, trig, PQ, spectral or kNN value; it only
schedules the guest, computes host storage digests, and writes the manifest.

### Streaming all-system training

`stream-train` reads the corpus one line at a time; it never loads the whole
file into host memory. It feeds each line through the raw tokenizer, temporal
past/current/future slots, n-gram counter and a fixed-size phase sample window.
The n-gram carry is passed back into the guest so n-grams crossing host read
chunks are counted once.

```sh
./build/nanlm-universal stream-train \
  state/gutenberg_150_train.txt 0 0 \
  state/stream_train
```

It writes:

```text
.words.bin .subwords.bin .meta.bin .slots.bin
.ngrams.bin
.codebook.bin   fixed 1,024-window phase sample, 32 codewords
.json           line/byte/token/context/field/codebook summary
```

The phase sample is bounded independently of corpus size; token, n-gram and
temporal state are streamed. The full 8x256 phase codebook remains a separate
`phase-codebook` stage.

For releases, use chunked assets so a bank never needs to exist as one large
local file:

```sh
python3 -m runner_riddle.phase_bank_runner \
  --nanlmind /data/data/com.termux/files/home/NaNLMind \
  --corpus state/gutenberg_150_clean_corpus.txt \
  --out-dir /data/data/com.termux/files/usr/tmp/phase_bank \
  --name gutenberg150_d64 --dim 64 --window 8 \
  --release --chunk-bytes 188743680 --cleanup-local
```

`--chunk-bytes` writes `PREFIX.parts.json` and ordered part assets of at most
that size. `--cleanup-local` removes the generated bank, parts and sidecars
only after every release upload succeeds.

### Completed 150-book bank

```text
corpus              state/gutenberg_150_clean_corpus.txt
samples             1,650,141
lanes               64 complex
window              8 bytes
bank bytes          844,872,192 (806 MiB)
bank sha256         88c951374e08df20b184bc811e16599b26277902c1053abba425fdd5723c06e5
release             https://github.com/shemshallah/NaNLMind/releases/tag/phase-bank-gutenberg150-d64-v1
release assets      gutenberg150_d64.part00..part01, gutenberg150_d64.chunk02..chunk13, gutenberg150_d64.parts.json
manifest            gutenberg150_d64.manifest.json
```

The 16 shard counts are balanced: 100,717, 101,850, 103,445, 105,393,
102,407, 106,305, 103,866, 110,838, 101,970, 102,053, 97,963, 103,970,
100,131, 101,891, 101,521, 105,821.

The local Download copy was removed. The bank is stored as ordered release parts: two 180 MiB parts and twelve
40 MiB chunks, all below 200 MB. `parts.json` records the original digest,
byte count and per-part hashes for reconstruction.

The D=128 runner mode is available for a stronger bank; it doubles the payload
to roughly 1.6 GiB. The current 806 MiB bank fits the external-storage budget.

## 11. Raw vector-code observer

`mth_vector_matrix.nas` implements the C(256,2) vector-code object in the guest:

```text
pair(a,b) index = a*255 - a*(a-1)/2 + (b-a-1)
matrix base     = 0x300000
cells           = 32,640 signed Q16 accumulators
sentinel        = 32,640 (same head, not a pair)
```

`mth_vm_accum` updates a pair after sorting the heads; `mth_vm_probe` scans a
row and returns the best third head above a threshold; `mth_vm_credits` turns
matrix row support into 255 head credits. Those credits feed the existing raw
hot-trihead mapper and its 43/85 field gate, so phase-ingest now reports
`hot_heads`, `hot_triads`, and `field_hot` from raw execution. This is a
candidate index tensor, not vector storage and not the old byte-pair HW5
object. The host bridge exposes reset, accumulate, probe, credits and read
operations, and `build/test_raw_field` verifies indexing, commutativity, the
sentinel, probe completion, credits and hot-trihead handoff.

## 12. 256-dimensional vector geometry

The production phase vector is now **D=128 complex lanes = 256 Q16
components**. The 8-subvector codebook is therefore:

```text
pipeline dimension  256
subvectors          8
subvector width     32
codewords/subvector 256
codebook words      65,536
artifact            262,184 bytes
sha256              f1fd9ac36c9d4491315bae3e2e9b8c8d15bafbc4b88b45fd2cd99dc569542297
release asset       gutenberg150_d256.codebook8x256.bin
```

`stream-train` now samples 256-component phase vectors and computes:

- hyperbolic radial proxy: `mean/(mean+65536)`, monotone inward/outward;
- path length, closure, turn/second difference and curvature;
- triangle side lengths, area proxy, tightness, orientation;
- field perturbation: vector components -> 255 head credits, 85 triad votes,
  and a separate field value; head 255 remains void.

The geometry is raw guest code in `mth_geometry.nas`. The triangle is the
three-component proposition object: `(subject, relation, object)` vectors give
three sides, a tightness score and a signed orientation. The current area is a
bounded proxy (minimum side), not a full floating Heron area; this keeps all
arithmetic in Q16. The stream JSON carries the measured path and triangle
values.

### Semantic word triangles

The raw tokenizer meta record now carries six fields:

```text
[word_id, three_word_context, triad, vote_mask, word_start, word_length]
```

`stream-train` extracts those spans, phase-encodes each word into a 256-component
vector, and builds consecutive word triples. Each triple is sent to the raw
triangle kernel. The JSON `word_geometry` block reports:

```text
word vectors
number of consecutive-word triangles
triangle area sum
triangle tightness sum
positive/negative orientation counts
example side lengths
word-path length, closure, turn and curvature
word field perturbation
field hot heads/triads
```

This is the semantic triangle basis for `(who, action, whom)` propositions:
the three corners are word vectors, the sides are their distances, tightness
measures how equilateral the relation is, and orientation gives the triangle's
handedness. It is no longer only a triangle over arbitrary sampled vectors.

`mth_triangle_model.nas` then fits a raw shape distribution from the observed
sentence triangles: tightness sum, area sum, count, positive orientation and
negative orientation. `mth_tri_model_score` scores a new triangle against the
learned mean tightness/area. The stream writes every triangle to
`PREFIX.triangles.bin` as:

```text
[side0, side1, side2, area_proxy, tightness, orientation, shape_score]
```

A two-line smoke test produced:

```text
DOG CHASES CAT
  sides        3127, 3197, 1902
  tightness    38989
  score        65536

RIVER DRINKS LIBRARY
  sides        2690, 4501, 4429
  tightness    39167
  score        135
```

Every word triple is also written to `PREFIX.triangles.bin` as:

```text
[side0, side1, side2, area_proxy, tightness, orientation, shape_score]
```

The model is trained by `mth_tri_model_observe` from raw sentence triangles and
scored by `mth_tri_model_score`. A two-line smoke run produced 6 word vectors and
2 scored triangles. This is the first raw shape prior; it currently trains on
positive sentence triangles only.

The raw model now accumulates both direct positive sentence triangles and
contrastive negative triangles in separate banks, and
`mth_tri_model_score_contrast` returns a Q16 score favouring shapes close to
the positive bank. `stream-train` constructs negatives from non-adjacent word
vectors in the same line and reports `contrastive_triangles`,
`contrastive_score_sum` and `contrastive_example_score`.

This is still a shape prior, not a supervised semantic truth classifier. The
source-disjoint positive/negative evaluation with calibrated thresholds is now
implemented in [Relation and inverse triangle corpus](RELATION_TRIANGLE_CORPUS.md).
On the current medium WordNet sample the global raw test AUC is 0.5659 and the
calibrated global test AUC is 0.5976 (ECE 0.0044), with weak per-relation
results. Those are corpus labels and calibrated research outputs, not semantic
truth.

### Trig rotation + hyperbolic synergy

Word phase vectors are rotated by the line turn derived from the first word ID.
The triangle and path are then measured in that rotated frame. The hyperbolic
measure uses the complex energy per lane:

```text
energy_lane = Q16(cos*cos) + Q16(sin*sin)
mean_energy = sum(energy_lane) / lanes
radial = mean_energy / (mean_energy + 65536)
```

A common phase rotation leaves `energy_lane` and therefore the hyperbolic
radial position invariant. In the current stream output, a Alice probe gives:

```text
rotation_turn   47211
phase_energy     4095
phase_radial     3854
```

The rotation changes the phase frame used by the triangles while leaving the
hyperbolic radius stable. This is the trig/rotation/hyperbolic coupling: rotation
sets the gauge, energy sets the radial tree position.

### Word-level triangle records

`stream-train` writes every consecutive-word triangle to
`PREFIX.triangles.bin`:

```text
[side0, side1, side2, area_proxy, tightness, orientation, shape_score]
```

The current smoke corpus produced 789 word vectors and 637 scored triangles.
The triangle shape model learns positive/negative tightness and area banks in
the guest and scores the first/last examples. The semantic layer is now using
actual word spans and word phase vectors, not arbitrary sample vectors.

### Shape-gated head → trihead → field

The semantic triangle is now wired into a second raw 43/85 gate:

```text
word triangle
  -> triad index from the tokenizer meta record
  -> vote mask 7 + best tightness quality
  -> 0x2F0000 votes / 0x2F0100 quality

field gate:
  votes >= 2-of-3
  quality >= mean quality
  separate current-slot endpoint closure <= path/2
  accepted triads >= 43
```

`mth_shape_field_gate` returns the accepted count, field flag and mean shape
quality. `stream-train` also records the first and last current field-slot words
and their raw endpoint closure. The temporal structural field and the semantic
shape field are reported separately:

```text
field_hot          temporal S+/S-/head-255 field
shape_field_hot    semantic triangle-shape field
current_field_first/last anchors
head255_closure    endpoint distance
```

This makes the field a geometric gate as well as a vote count.

The existing released phase bank is the earlier D64/128-component bank. The
new 256-component codebook is released separately under the same release tag.

### NaNROUTER corpus and void255 alignment

The NaNROUTER corpus releases now expose per-book batches for sentences,
paragraphs and short stories. Their complete and batch tags are mapped in
`spec/nannet_corpus_routes.v1.json`; downloads must verify `SHA256SUMS.parts`
and use a document/book-disjoint split.

The newer NaNROUTER attention contract reserves mathematical head **255 as
void/zero** and treats the 255 active heads as 0..254. NaNLMind's current slot is
therefore a **separate field register with sentinel -1**, not head 255. The
NaNLMind 43/85 field head remains an aggregate role, not an incidence endpoint.
`spec/void255_active_head_math.v1.json` and
`spec/nanrouter_integration.v1.json` record the cross-repository mapping.
`mth_global_hodge256_f32.nas` rejects nonzero pair flow incident to head 255 and
rejects any simplicial face containing it. The Q16 adapter
`mth_global_hodge256_q16.nas` converts the 32,640 vector-code matrix cells in
guest memory, admits the first 16 hot triads as oriented faces, and publishes
divergence/curl. `phase-ingest` now runs that path after matrix credits and
records `hodge_ok`, `hodge_divergence_l1` and `hodge_curl_l1` in its manifest.

### Source-disjoint relation corpus and calibration

`N16TRI/1` is the provenance-bound WordNet 3.1 relation corpus. It contains
canonical forward anchors, inverse-direction rows, hard negatives, uniform
same-POS random negatives, and self-negatives. Each row carries a pair-derived
split, a source-line digest, and a pipe-delimited provenance string. The
default pair split has zero cross-split anchor pairs and zero cross-split row
pairs; the manifest reports synset leakage separately, and `--split-by synset`
is available for a stricter evaluation.

The raw trainer fits six independent per-relation shape banks and one global
bank:

```sh
./build/nanlm-universal triangle-contrast-train \
  state/relation_triangle/tri.tsv \
  state/relation_triangle/contrast 0
```

Calibration fits Platt and isotonic models on `valid` only, chooses isotonic
only when valid log loss improves by at least `0.01`, selects a balanced
accuracy threshold on valid calibrated probabilities, and evaluates untouched
`test` at that threshold and at `0.5`:

```sh
python3 tools/calibrate_triangle_relations.py \
  state/relation_triangle/contrast.scores.tsv \
  state/relation_triangle/contrast
```

The current medium run (18,802 anchors, 143,746 rows) has global raw test AUC
`0.5659`, calibrated global test AUC `0.5976`, balanced accuracy `0.5980`, and
ECE `0.0044` at the valid-optimal threshold `0.3075`. Per-relation results are
weak: `CONTRADICTS` raw AUC `0.6991`, `PART_OF` `0.6186`, `HAS_PART` `0.5843`,
`ISA` `0.5340`, `ASSOCIATED` `0.5303`, and `HAS_SUBTYPE` `0.5127`. The model is
a shape prior over the last 8 bytes of each role text, not a semantic relation
encoder; the calibrated labels are corpus labels, not truth. See
[Relation and inverse triangle corpus](RELATION_TRIANGLE_CORPUS.md) for the
schema, commands, full metric table, and caveats.

## 13. Remaining production gates

- A corpus-wide, multi-iteration 8-subvector PQ codebook rather than the
  current per-ingest single-vector codebook and residuals.
- Repeated normalized spectral iterations and a semantic graph above the
  codebook.
- Remote leaf pages and reconstruct-and-verify through triheads and the 43/85
  field.
- Feed spectral coordinates into the trihead/remote-fetch budget; the matrix
  credit path into hot triheads is now live.
- Book-disjoint phase/PQ/matrix evaluation; the phase bank itself is not yet a
  language-quality result.
- Relation-triangle role features beyond the 8-byte phase suffix. The current
  shape model is a weak prior; calibrated relation labels are corpus labels,
  not semantic truth.
