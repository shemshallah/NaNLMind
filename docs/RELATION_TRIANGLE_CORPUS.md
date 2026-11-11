# Relation and inverse triangle corpus

This document describes the `N16TRI/1` relation corpus, the raw contrastive
trainer, and the valid-only calibration pipeline. The corpus is a
provenance-bound WordNet 3.1 sample, not a claim that every generated negative
is false in the world. Raw triangle scores are shape-bank scores, not
probabilities; calibrated probabilities are research labels fitted on `valid`
and evaluated once on untouched `test`.

## 1. What the corpus contains

The corpus has six relation names and five row labels:

| relation | source | direction |
|---|---|---|
| `ISA` | WordNet `@` / `@i` (hypernym / instance hypernym) | forward and inverse |
| `HAS_SUBTYPE` | inverse of `ISA` | inverse-only |
| `PART_OF` | WordNet `#p` / `#m` / `#s` (part / member / substance meronym) | forward and inverse |
| `HAS_PART` | inverse of `PART_OF` | inverse-only |
| `CONTRADICTS` | WordNet `!` (antonym) | symmetric |
| `ASSOCIATED` | WordNet `&` (similar to) | symmetric |

`HAS_SUBTYPE` and `HAS_PART` are deliberately not used as forward anchors.
They are emitted by the inverse pass, so every WordNet edge appears once as a
canonical forward anchor and once as a valid inverse row. This is the inverse
corpus: the model sees both `(parent, ISA, child)` and
`(child, HAS_SUBTYPE, parent)`, plus negatives in both directions.

Each forward anchor produces:

- a `positive` row in the canonical direction;
- an `inverse` row in the swapped direction with the inverse relation name;
- one `hard_negative` row: a lexically close wrong object, or a uniform
  fallback when no lexical candidate exists;
- one `negative` row: a uniform same-POS wrong object;
- one `self_negative` row: the subject used as its own object.

`positive` and `inverse` are the positive class. `hard_negative`, `negative`,
and `self_negative` are the negative class.

### Label semantics and confidence

`confidence` is a **source prior** in `0..65535`, not a probability:

| label | confidence | meaning |
|---|---:|---|
| `positive` | 50000-65535 | direct WordNet pointer in the canonical direction |
| `inverse` | 50000-65000 | valid relation obtained by swapping the endpoints |
| `hard_negative` | 55000 | lexically close object that is not a selected WordNet pointer |
| `hard_negative` fallback | 40000 | uniform candidate used when no lexical candidate exists |
| `negative` | 45000 | uniform same-POS object that is not a selected WordNet pointer |
| `self_negative` | 65535 | subject used as its own object |

A negative is **provenance-bound**: it means "the selected WordNet pointer is
not present for this pair in this relation." It does not mean the pair is
semantically false. WordNet is incomplete, and a hard or random negative could
be true in another resource. This is why the calibration report must be read as
agreement with the corpus labeling policy, not as factual truth.

## 2. Source and provenance

The source is WordNet 3.1:

```text
archive  /storage/emulated/0/Download/NaNLMind/wn3.1.dict.zip
sha256   1820414c1056652b56717df5794609ef0c91aae033d3fc54ddc9846249294285
```

The manifest records the digest of each parsed dictionary file:

```text
data.adj   ca1033bf627eb95f6cbb2864f8990be8e6a01a3c182e7d7c7094ccf8ead242cc
data.adv   aea301f39ac1b24be9a880dbc6cc6331bc5391f58c7525a1b298a13c922f2ed3
data.noun  2cad22fe43461ee7ae61a564ae6a518c57445c8597e53542caddb5c26a6a5d94
data.verb  eb1cf196dab6e1b815a1c86fa20c909fb7413b2f34250d7fe60a0fb35ef59e03
```

Every machine row has a `source_sha256` field: the SHA-256 of the WordNet
source line that supplied the canonical forward anchor. Inverse rows share the
forward anchor's source line even though the row's subject is the anchor's
object, so the provenance chain has one root per anchor. The `file` and `line`
fields in the provenance string point to that same anchor source line.

The machine `provenance` field is pipe-delimited and contains no tabs:

```text
wordnet3.1|subject=<synset-id>|object=<synset-id>|relation=<name>|label=<label>
|subject_gloss_sha16=<16 hex>|object_gloss_sha16=<16 hex>|pointer=<symbol>
|file=<data.*>|line=<n>|anchor=forward|inverse|source_relation=<name>
|anchor_object=<synset-id>|similarity=<float>|method=<name>|fallback=<0|1>
```

The readable TSV prepends a human-readable prefix:

```text
subject [subject-id] RELATION object [object-id] | <machine provenance>
```

The manifest is the audit root: archive and file digests, synset and pointer
counts, selected anchors, label/relation/split counts, split audits, skipped
pointer reasons, label definitions, and the confidence/predicate notes.

## 3. `N16TRI/1` schema

The machine file is tab-separated with an exact `N16TRI/1` header line and nine
fields per row:

| column | type | description |
|---|---|---|
| `split` | `train` / `valid` / `test` | pair-derived split |
| `relation` | one of six names | canonical relation |
| `label` | one of five labels | positive/inverse/hard/random/self |
| `confidence` | integer `0..65535` | source prior, not a probability |
| `subject_hex` | lowercase hex | UTF-8 role text of the subject |
| `predicate_hex` | lowercase hex | UTF-8 canonical relation name |
| `object_hex` | lowercase hex | UTF-8 role text of the object |
| `source_sha256` | 64 lowercase hex | source line digest |
| `provenance` | pipe-delimited text | no tabs; see above |

The readable audit file has eleven columns:

```text
split  relation  label  confidence  subject  predicate  object
subject_id  object_id  source_sha256  provenance
```

`subject`/`object` are the first WordNet lemma with underscores replaced by
spaces and lowercased. `predicate` is the canonical relation name. The trainer
does not read the readable file.

## 4. Role encoding and the raw triangle

The trainer phase-encodes each of the three role texts independently:

- it takes the **last 8 bytes** of the role text, left-padding with spaces;
- it calls the raw guest `phase_encode_wide(window, 8, 128)` to produce a
  256-component Q16 vector;
- it concatenates subject, predicate, and object into a 768-component
  triangle input;
- `mth_geometry.nas` computes three side lengths, an area proxy (minimum side),
  a tightness score, and a signed orientation.

The predicate vector is constant per relation, so the shape is driven by the
subject/object vectors and the fixed predicate vector. The model does **not**
see the full lemma, the gloss, the synset ID, or the WordNet graph structure.
Long lemmas that share an 8-byte suffix collide, and homonyms share role text.
Provenance retains the synset IDs, but the model does not consume them. This is
the main reason the shape model is weak on some relations.

The raw contrastive score is a Q16 shape-bank score:

```text
d_pos = (|tightness - pos_tight_mean| + |area - pos_area_mean|) / 256
d_neg = (|tightness - neg_tight_mean| + |area - neg_area_mean|) / 256
score = 65536 * d_neg / (d_pos + d_neg + 1)
```

Higher is closer to the positive bank. Orientation counts are accumulated in
the banks but are not part of this score. The score is not a probability.

## 5. Split policy

The default split unit is the **unordered synset pair**:

```text
sha256(sorted(subject_id, object_id)) -> first 4 bytes -> mod 100
< 80 train, < 90 valid, else test
```

Every row's split is derived from its own endpoint pair. This guarantees:

- `positive` and `inverse` for the same anchor share a split;
- a hard/random/self negative cannot place the same unordered pair in a
  different split;
- adding anchors does not move an existing pair to another split.

The manifest reports the audit:

```text
anchor_pairs                  18802
cross_split_anchor_pairs      0
row_pairs                     121049
cross_split_row_pairs         0
cross_split_synsets           22714
```

Pair mode does **not** guarantee synset-disjoint splits. A synset can appear in
`train` as the subject of one pair and in `test` as the object of another. For a
stricter claim, use the generator's `--split-by synset` mode. It hashes each
synset, keeps a row only when both endpoints hash to the same split, and drops
anchors/rows whose endpoints disagree. That reduces the corpus size but makes
the split synset-disjoint.

### Repairing an older corpus

Corpora produced before pair-level row assignment can be repaired without
regenerating the rows:

```sh
python3 tools/resplit_relation_triangle_corpus.py \
  --tri state/relation_triangle/tri.tsv \
  --readable state/relation_triangle/tri.readable.tsv \
  --manifest state/relation_triangle/manifest.json \
  --dry-run
```

Remove `--dry-run` to rewrite the files. The tool streams both TSVs, validates
that the tri/readable rows are aligned, recomputes the split from
`subject_id|object_id`, and updates the manifest's split counts, audits,
digests, byte counts, and `resplit` note. It refuses to write if any pair still
crosses splits.

## 6. Generator

```sh
python3 tools/build_relation_triangle_corpus.py \
  --max-anchors-per-relation 5000 \
  --out state/relation_triangle/tri.tsv \
  --readable state/relation_triangle/tri.readable.tsv \
  --manifest state/relation_triangle/manifest.json
```

Use `--max-anchors-per-relation 0` for all 134,476 forward anchors. The cap is
per **forward** relation (`ISA`, `PART_OF`, `CONTRADICTS`, `ASSOCIATED`); the
inverse-only relations (`HAS_SUBTYPE`, `HAS_PART`) receive rows from those
anchors. `CONTRADICTS` and `ASSOCIATED` are symmetric, so each unordered pair
is emitted once as a forward anchor.

Options:

| option | default | meaning |
|---|---|---|
| `--archive` | `.../wn3.1.dict.zip` | WordNet 3.1 dictionary zip |
| `--out` | `state/relation_triangle/tri.tsv` | machine `N16TRI/1` file |
| `--readable` | `state/relation_triangle/tri.readable.tsv` | human-readable audit file |
| `--manifest` | `state/relation_triangle/manifest.json` | manifest JSON |
| `--seed` | `20261110` | deterministic cap shuffle and negative sampling |
| `--max-anchors-per-relation` | `0` | cap per forward relation; `0` means all |
| `--split-by` | `pair` | `pair` or stricter `synset` |
| `--self-test` | off | tiny in-memory parser/label test |

The current medium run used the 5,000 cap:

```text
synsets                    117791
pointer edges              378203
forward anchors total      134476
anchors selected            18802
rows                       143746
train / valid / test       115184 / 14333 / 14229
labels                     hard 37518, inverse 18802, negative 37602,
                           positive 18802, self 31022
tri sha256                 ea19dc43fbb989a2e897fba3ae26a5a82bc642b9bb894ecb89bd0ae032f50a97
readable sha256            b86f8eaa11eacc48fc0e256549e17db09982281ef7ff1dce465c2684f52d6038
```

`state/` is ignored by git; the generated corpus and model outputs are not
committed. The generator and calibration scripts are the committed artifacts.

## 7. Raw contrastive trainer

```sh
./build/nanlm-universal triangle-contrast-train \
  state/relation_triangle/tri.tsv \
  state/relation_triangle/contrast 0
```

The third argument is `MAX_ROWS`; `0` means all rows. The trainer:

1. reads the `N16TRI/1` header and validates every row;
2. phase-encodes each role with the raw guest;
3. calls `mth_tri_model_reset` once per bank;
4. observes train positives with `mth_tri_model_observe`;
5. observes train negatives with `mth_tri_model_observe_negative`;
6. snapshots the bank and scores `valid`/`test` with
   `mth_tri_model_score_contrast`.

It trains **six independent per-relation banks sequentially**, then one global
bank over all train rows. The per-relation banks are snapshots, not a single
jointly trained model; the global bank is the production model. Train scores are
in-sample diagnostics and must not be used for calibration.

Outputs:

| file | contents |
|---|---|
| `PREFIX.scores.tsv` | every row's raw scores and geometry, plus provenance |
| `PREFIX.banks.tsv` | positive/negative tightness and area sums/counts, orientation counts |
| `PREFIX.metrics.json` | per-relation and global raw AUC/BA/precision/recall/F1/confusion/threshold |

The scores TSV columns are:

```text
split  relation  label  confidence  relation_trained  score  global_score
shape_score  global_shape_score  side0  side1  side2  area  tightness
orientation  provenance
```

The threshold in `metrics.json` is selected on `valid` by balanced accuracy
(tie-break F1, then closeness to `32768`). The test metrics are held out. The
raw medium-run global test result was:

```text
n=14229  positives=3716  negatives=10513
AUC=0.565893  balanced accuracy=0.597998
precision=0.311655  recall=0.893703  F1=0.462149
threshold=25595  tp=3321  fp=7335  tn=3178  fn=395
```

This is a weak shape prior, not a semantic relation classifier.

## 8. Calibration

```sh
python3 tools/calibrate_triangle_relations.py \
  state/relation_triangle/contrast.scores.tsv \
  state/relation_triangle/contrast
```

The calibration script:

- reads `score` and `global_score` from the scores TSV and divides by `65536`;
- fits Platt (`sigmoid(a*score+b)`) and isotonic calibrators on **valid only**;
- chooses isotonic only if its valid log loss is at least `0.01` better than
  Platt; otherwise uses Platt;
- selects a probability threshold on **valid** by balanced accuracy
  (tie-break F1, then closeness to `0.5`);
- applies that threshold to untouched `test`;
- reports test metrics at the valid-optimal threshold **and** at `0.5`;
- reports raw AUC (ranking of the raw score) and calibrated AUC (ranking of the
  calibrated probability; ties can change AUC), Brier, log loss, ECE with 10
  equal-width bins, precision, recall, F1, balanced accuracy, and the confusion
  matrix.

The calibrated TSV has:

```text
split  relation  label  confidence  score  global_score  relation_model
platt_p  isotonic_p  calibrated_p  calibrated_threshold  calibrated_label
global_p  global_threshold  global_label  provenance
```

`calibrated_label` uses the per-relation threshold; `global_label` uses the
global threshold. The probabilities reflect the corpus prior (about 26%
positive), so `p >= 0.5` is **not** the balanced decision boundary. In this run
the global valid-optimal threshold was `0.3075`, and `p >= 0.5` predicted all
rows negative. Both results are reported so the choice is explicit.

## 9. Medium-run results

The following table is the calibrated test result at the valid-optimal
threshold. `raw AUC` is the ranking metric for the raw score; `cal AUC` is the
ranking of the calibrated probability. `ECE` and `Brier` are probability
metrics. All thresholds and calibrators were fitted on `valid`.

| relation | test n | pos | neg | raw AUC | cal AUC | BA | precision | recall | F1 | ECE | Brier | TP | FP | TN | FN | threshold |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ASSOCIATED | 3642 | 1050 | 2592 | 0.5303 | 0.5303 | 0.5588 | 0.3251 | 0.7390 | 0.4516 | 0.0187 | 0.2055 | 776 | 1611 | 981 | 274 | 0.2689 |
| CONTRADICTS | 3102 | 728 | 2374 | 0.6991 | 0.7349 | 0.6891 | 0.3849 | 0.7418 | 0.5068 | 0.0357 | 0.1387 | 540 | 863 | 1511 | 188 | 0.3160 |
| HAS_PART | 1811 | 493 | 1318 | 0.5843 | 0.5843 | 0.5756 | 0.3169 | 0.7809 | 0.4508 | 0.0081 | 0.1957 | 385 | 830 | 488 | 108 | 0.2561 |
| HAS_SUBTYPE | 1801 | 476 | 1325 | 0.5127 | 0.4873 | 0.5708 | 0.4887 | 0.2269 | 0.3099 | 0.0016 | 0.1947 | 108 | 113 | 1212 | 368 | 0.2714 |
| ISA | 1974 | 476 | 1498 | 0.5340 | 0.5340 | 0.5533 | 0.2771 | 0.6239 | 0.3837 | 0.0147 | 0.1831 | 297 | 775 | 723 | 179 | 0.2576 |
| PART_OF | 1899 | 493 | 1406 | 0.6186 | 0.6270 | 0.6160 | 0.3314 | 0.7931 | 0.4674 | 0.0127 | 0.1820 | 391 | 789 | 617 | 102 | 0.3202 |
| **global** | 14229 | 3716 | 10513 | 0.5659 | 0.5976 | 0.5980 | 0.3117 | 0.8937 | 0.4621 | 0.0044 | 0.1854 | 3321 | 7335 | 3178 | 395 | 0.3075 |

Global calibration chose isotonic. The global test metrics at the valid-optimal
threshold and at `0.5`:

| threshold | cal AUC | BA | precision | recall | F1 | TP | FP | TN | FN |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `0.3075` (valid-optimal) | 0.5976 | 0.5980 | 0.3117 | 0.8937 | 0.4621 | 3321 | 7335 | 3178 | 395 |
| `0.5` (fixed) | 0.5976 | 0.5000 | 0.0000 | 0.0000 | 0.0000 | 0 | 0 | 10513 | 3716 |

### Reading the results

- `CONTRADICTS` is the strongest relation by raw AUC (`0.6991`), followed by
  `PART_OF` (`0.6186`) and `HAS_PART` (`0.5843`).
- `ASSOCIATED` (`0.5303`) and `ISA` (`0.5340`) are close to chance.
  `HAS_SUBTYPE` is only `0.5127` raw AUC; its calibrated AUC is `0.4873` because
  the calibrator collapses score ties. The raw AUC is the appropriate ranking
  metric; the calibrated AUC shows that probability ties can reorder the
  metric.
- The global model has high recall and low precision at the balanced-accuracy
  threshold because the corpus is about 26% positive and the shape score is a
  weak separator. ECE is low (`0.0044`) because isotonic calibration fits the
  valid distribution well; low ECE does **not** mean high discrimination.
- These numbers are not evidence that the model understands relation
  semantics. They are evidence that the corpus, inverse rows, negatives,
  provenance, split audit, raw trainer, and valid-only calibration are wired
  end to end.

## 10. Tests

```sh
python3 tools/build_relation_triangle_corpus.py --self-test
python3 tools/resplit_relation_triangle_corpus.py --self-test
python3 tools/calibrate_triangle_relations.py --self-test
python3 tools/run_nan16_fixtures.py --only triangle_contrast
make -j2 build/field_driver.nan build/test_raw_field build/test_dual_head \
  build/nanlm-universal
./build/test_raw_field
./build/test_dual_head
```

The native fixture is `mth/tests/mth_triangle_contrast_test.nas`, registered as
`triangle_contrast` in `tools/run_nan16_fixtures.py`. It exercises reset,
positive observe/score, negative observe, and contrastive score. The expected
marker is:

```text
[PASS] triangle_contrast: steps=915 marker=MTH TRIANGLE CONTRAST PASS
```

The generator and calibration self-tests are deterministic and do not need the
WordNet archive or the raw VM.

## 11. Caveats and next work

- **Shape prior, not semantics.** The model sees the last 8 bytes of the role
  text and a fixed predicate vector. It does not see glosses, synset IDs, or
  graph structure. Weak relation AUCs are expected.
- **Negative labels are provenance-bound.** "Not a selected WordNet pointer" is
  not the same as false. Hard negatives are intentionally close; random
  negatives are same-POS but otherwise uniform; self-negatives are identity
  rows.
- **Pair split, not synset split.** The default split prevents pair leakage but
  allows synset leakage (`cross_split_synsets=22714`). Use `--split-by synset`
  for a stricter evaluation, and report the reduced corpus size.
- **Medium corpus.** The current run is capped at 5,000 anchors per forward
  relation (18,802 anchors, 143,746 rows). The full WordNet anchor set is
  134,476 before the cap. `--max-anchors-per-relation 0` generates it, but it
  is larger and slower; on memory-constrained Termux devices, use a cap or the
  resplit tool instead of regenerating.
- **No test tuning.** Calibrators and thresholds are fitted on `valid`; `test`
  is evaluated once. Do not select a threshold or calibrator on `test`.
- **Per-relation banks are snapshots.** They are trained independently in
  sequence; the global bank is the production model. A jointly trained
  multi-relation model is future work.
- **Calibration is corpus calibration.** `calibrated_p` is a probability under
  the corpus label distribution, not a probability that a relation is true in
  the world. The natural prior is about 26% positive, so the fixed `0.5`
  threshold is not the balanced decision boundary.
- **Orientation is not scored.** The banks accumulate positive/negative
  orientation counts, but the contrastive score uses only tightness and area.
  Adding orientation or side-ratio features would be a model change, not a
  calibration change.
- **Full-lemma and gloss features are future work.** A semantic relation model
  would need a learned role embedding (gloss, graph context, or a trained
  encoder), not just the 8-byte phase suffix.

## 12. File map

| path | role |
|---|---|
| `tools/build_relation_triangle_corpus.py` | WordNet parser, `N16TRI/1` generator, inverse/hard/random/self negatives, manifest |
| `tools/resplit_relation_triangle_corpus.py` | pair-level split repair for existing corpora |
| `tools/calibrate_triangle_relations.py` | Platt/isotonic valid-only calibration, threshold selection, ECE/Brier/log-loss |
| `src/trunk_train.cpp` | `triangle-contrast-train` CLI, role encoding, per-relation/global banks, metrics |
| `include/nanlm/trunk_train.hpp` | trainer declaration |
| `src/main.cpp` | CLI help and dispatch |
| `mth/nan16/mth_triangle_model.nas` | positive/negative banks and contrastive score |
| `mth/nan16/mth_geometry.nas` | triangle geometry and the fixed `mth_g_side` array |
| `mth/tests/mth_triangle_contrast_test.nas` | native reset/observe/contrast fixture |
| `tools/run_nan16_fixtures.py` | fixture runner entry |
| `state/relation_triangle/` | generated corpus, scores, banks, metrics, calibration (git-ignored) |
