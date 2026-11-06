# Logic curriculum training

## 1. Pipeline

The runner now has a `logic` op:

```text
ring.yml --op logic
  -> ring_dispatch.py
  -> six runner workflows
  -> nanlm_worker.py --op logic
  -> runner/logic_curriculum.py
  -> state/logic_<epoch>_<slot>.json
  -> nanlm/logic/<epoch>/<slot> when tiers are available
```

Each slot runs the same deterministic puzzle family but records its own result.
If `NANLM_MERGE_URL` and `NANLM_MERGE_TOKEN` are set, the result also posts a
small logic-training delta to the Koyeb merge service.
The curriculum is independent of the head-shift packet path, so it can run
without the 2 GiB bootstrap map.

## 2. Puzzles

Five levels:

1. direct facts;
2. inheritance through `isa`;
3. exceptions (`cannot`);
4. deeper chains;
5. mixed held-out queries.

The learner is a relation memory with a learned ancestry depth. It initially
answers only direct facts, receives support examples and corrections, and
increases its usable depth when the examples justify it.

## 3. Repetition and promotion

For each level:

```text
train support facts/examples
evaluate test queries
if accuracy improved:
    apply corrections for mistakes
    repeat
else:
    stop repeating
if best accuracy >= 0.75:
    promote to the next level
```

The output records every repetition with correct/total, accuracy, depth, and
correction count. Repetition is not blind: it stops as soon as a round does not
improve.

## 4. Local run

```sh
python3 runner/logic_curriculum.py --slot 1 --epoch 0 --rounds 5
python3 runner/logic_curriculum.py --slot 1 --epoch 0 --session-rounds 5 --start-level 1
python3 runner/logic_local_ring.py --slots 6 --rounds 4
python3 runner/logic_local_ring.py --slots 1 --session-rounds 5 --start-level 1
make logic-test
```

The session mode reports five cumulative rounds. Difficulty rises across the
rounds, so accuracy can dip when the next level is introduced; the last column
shows whether the overall best score improved.

`logic_local_ring.py` launches six worker processes in parallel. Slots start at
levels 0 through 4 so one pass exercises different difficulties at once.

## 5. Honest boundary

This is a runner-side curriculum and error-driven relation learner. It is not a
claim that the byte/context model already solves compositional logic. The next
training iteration should feed the same puzzle stream into the chart's
Hopfield/word layers and compare held-out behavior against this baseline.
