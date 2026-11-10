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
| 72 | `mth_leaf_verify` | reconstruct codebook+residual, L1 accept/reject |
| 73 | `mth_ckpt_hash` | raw FNV-1a checkpoint payload digest |

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

The phase path uses **8 bytes per window**, taken from the end of each corpus
line. It is not word-tokenized and does not use cross-window context. Thus the
current answer is:

```text
context = 8 bytes
context_words = 0 (no word tokenizer; roughly 1-2 English words in length)
```

The legacy `context-train` path uses 4-byte exact contexts with a 3-byte
fallback, also byte-level rather than word-level. Longer word context requires
a tokenized sequence builder; the current codebook does not silently pretend
that 8 bytes is a word window. Without an eval corpus, the training corpus is split into a held-out suffix.
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

## 12. Remaining production gates

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
