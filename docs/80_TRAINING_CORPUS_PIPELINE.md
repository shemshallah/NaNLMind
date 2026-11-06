# Staged training corpus pipeline

## 1. Stages

```text
inverses_boolean -> deep_logic -> common_words
-> repetitive_words -> word_choice -> sentences
```

Each stage generates a deterministic bilingual-style corpus of:

- Boolean truth values and their inverses;
- deep relation chains, exceptions, and inheritance;
- common-word contexts;
- intentionally repetitive word contexts;
- word-choice completions with three candidates;
- sentence prefixes with next-word choices.

The strict `N16TXT/1` corpus and its header-free native companion are written by
`runner/training_corpus.py`.

## 2. Budgets and single tests

Every stage has a wall-clock budget:

```sh
python3 runner/training_pipeline.py --single deep_logic --stage-seconds 1.0
python3 runner/training_pipeline.py --stage-seconds 0.5
```

`--single STAGE` runs one bounded test. The full default demo is six stages at
about 1–1.5 seconds each, which is long enough to show progress but short enough
for a hackathon demo. `--max-samples` limits the corpus for a smoke run.

## 3. Runner op

The worker now exposes:

```sh
python3 runner/nanlm_worker.py --op training --slot 1 --epoch 0 \
  --stage-seconds 1.0 --max-samples 2048
```

The runner writes the corpus, stage metrics, and `state/training_<epoch>_<slot>.json`
and publishes the result to `nanlm/training/<epoch>/<slot>` when tiers exist.

## 4. HERMES adapter

`runner/hermes_pipeline.py` prepares the same N16TXT corpus, runs a stage or
prompt-selected plan, emits layer-tagged discovery events, and writes a bundle:

```text
bundle/corpus.n16txt
bundle/discoveries.jsonl
bundle/manifest.json
```

Interactive planning:

```sh
python3 runner/hermes_pipeline.py --prompt "teach deep logic" --no-train
python3 runner/hermes_pipeline.py --prompt "train words" --seconds 0.5
```

HERMES can ingest the bundle through its `MemoryStore` when the HERMES package is
on `PYTHONPATH`. The optional `--merge-url` / `--merge-token` path posts a small
scoped delta to the Koyeb merge service.

Layer mapping:

| stage | HERMES layer |
|---|---|
| inverses_boolean | 3 operators |
| deep_logic | 4 equations |
| common_words | 2 relations |
| repetitive_words | 2 relations |
| word_choice | 5 hypotheses |
| sentences | 5 hypotheses |

## 5. Clocked adapter

`ClockedAdapter` in `hermes_pipeline.py` attaches the same training session to
an epoch/clock value. The core runner op `training` is the same entry point used
by the bootstrap ring, so Clocked does not need a second training implementation.

## 6. Boundary

The Python stage models are a demo curriculum and metric harness, not a claim
that the native 256-head topology has learned general language. The native
HERMES path still runs the strict N16TXT corpus through `math-train`; this module
prepares that corpus and the layer-tagged discovery bundle.
