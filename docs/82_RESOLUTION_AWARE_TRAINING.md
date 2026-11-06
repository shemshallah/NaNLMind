# Resolution-aware training and conversational learning

## Why the previous metrics appeared static

The prior Hermes curriculum presets all reached the same native `math-train`
byte-bit transition objective. Changing the stage label or corpus did not create
a lexical, word-completion, sentence, paragraph or narrative objective. The
Boolean foundation was a finite coverage gate; its 1,024 truth-row checks were
not a progressive language metric. The fixed word-after-logic control was not
a learned head result.

The Boolean learner stores 16 signed int16 operator scores in each head's
scratchpad. Those scores saturate at ±32767. Without adaptation, a previously
dominant rule can become difficult to change across later tasks. The new
`HeadView::decay_boolean_scores` applies bounded evidence decay once per
participating head per relation-training batch, preserving accumulated
preferences while allowing new evidence to change the selected rule.

## Two training paths, one native state

### Structured teacher path

Hermes emits N16REL/1 rows with train/test split, resolution, polarity,
confidence, subject, predicate, object and a source SHA-256. Only train rows
mutate the student. Test rows are measured before and after training. The
frozen topic/resolution challenge set is reused across rounds; cross-run
accuracy is compared only when the test digest matches.

### Free-form chat path

A conversational reflection may produce supported/refuted triples. Explicit
triples are converted to train-only N16REL/1 events and sent to the same native
trainer. Neutral or incomplete claims remain symbolic evidence and do not
become fabricated binary labels. A source-bound replay is an explicit no-op;
new turns have distinct source digests. Contradictions are retained as separate
hyperedges.

The verified Boolean foundation checkpoint seeds the shared
`native/global_universe.nmg` once. Legacy math training, structured relation
training and conversational relation learning all resume and extend that same
serialized topology.

## Native relation objective

For each relation event and resolution L0-L9:

1. Route subject, predicate and object to three distinct heads in the
   resolution's head partition.
2. Update all three heads' Boolean operator score tables.
3. Update the three canonical mirror-pair cells connecting those heads.
4. Preserve complementary positive/negative rails, confidence, epoch and
   source-event fingerprint in the pair cells.
5. Add temporal links and a six-member hyperedge containing the three heads
   and three pair references.
6. Commit the before/after global state digest and serialize the topology.

Exact duplicate events do not add edges or mutate heads. The command reports
`no_op` and re-evaluates the same held-out challenge.

## Metrics

Each populated resolution reports:
- train/test counts;
- pre-training and post-training relation-polarity accuracy;
- within-run delta;
- pre/post balanced accuracy;
- majority baseline.

Hermes records cross-run deltas only for the same frozen test-set digest.
Unsupported or untested resolutions are absent, not copied from byte accuracy.
These are relation-polarity metrics for teacher/chat labels, not text-generation
accuracy or independent factual verification.

## Native file protocol

Header: `N16REL/1`

Each row has eight tab-separated fields:

`split<TAB>resolution<TAB>polarity<TAB>confidence_q16<TAB>subject_hex<TAB>predicate_hex<TAB>object_hex<TAB>source_sha256`

Command:

```sh
nanlm-universal relation-train RECORDS.n16rel STATE.nmg [epochs]
```

The native command accepts 1–100 epochs. Hermes serializes train rows before
test rows, but the native evaluator computes its pre-training baseline before
any mutation. The global state digest and event ledger are authoritative;
Hermes SQLite remains an auditable additive evidence store.
