# Staged logic trainer

## Stages

1. **Boolean foundation**
   - all 256 heads;
   - each head trains one of the 16 Boolean functions;
   - all four truth-table rows per head are checked.
2. **Deep logic**
   - half adder;
   - full adder;
   - majority;
   - multiplexer;
   - depth-8 alternating AND/XOR chain.
3. **Words after logic**
   - only runs after stages 1 and 2 pass;
   - held-out entity/ability relation queries;
   - byte completion is recorded as a diagnostic, not a promotion gate.

## Failure is possible

Each repetition exposes one truth-table row per head. With too few observations,
the head cannot determine its hidden function:

```text
logic-train 1 1
stage=boolean_foundation passed=no correct=595/1024 accuracy=0.581055
detail=... distinct_rules=4 failed_heads=237
result=FAIL
```

The gate also requires all 16 functions to be represented. A population that
collapses to one rule fails even if its 1,024 row checks happen to score well.

## Last full run

```text
logic_train boolean_reps=32 circuit_reps=64
stage=boolean_foundation passed=yes correct=1024/1024
stage=deep_logic_circuits passed=yes correct=32/32
stage=words_after_logic passed=yes correct=10/10
fixed_control_byte_heldout_top1=...
result=PASS
```

Six parallel local runner slots also returned `result=PASS`.

## Runner ops

```sh
python3 runner/nanlm_worker.py --op logic-core --slot 1 --epoch 0
./build/nanlm-universal logic-train 32 64
```

`logic` runs the relation-puzzle curriculum; `logic-core` runs this staged
Boolean/deep/word session through the compiled core.

## Boundary

The Boolean and circuit stages are exact against their checked truth tables.
The word stage uses the relation memory, so 10/10 is word-relation evidence, not
proof that the byte model learned words. The byte completion number is kept as a
diagnostic so the next experiment can compare held-out word learning against
plain completion.
