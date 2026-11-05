# Slot loss and recovery

## 1. Experiment

Train the 8-token Hopfield cycle, then drop about 30% of the used pair slots:

```text
initial:          8/8
dropped slots:    3
remaining slots:  5
damaged recall:   5/8
retrained:        7/8
used slots:       8
```

The test passes with the honest threshold `>= 7/8`.

## 2. What it shows

- Erasing slots causes a real loss, not a hidden cache hit.
- Retraining rebuilds slots and improves recall.
- Recovery is **not yet perfect**: one transition remains wrong after 80
  passes. That is a concrete next target.

## 3. Why partial

The remaining slots participate in active-pair scans and can block the correct
new association. The key threshold prevents some cross-query decay, but the
eviction/repair policy is not yet ideal.

## 4. Test

```sh
./build/test_slot_recovery
```

## 5. Next

1. Add a repair mode that isolates dropped transitions.
2. Add per-slot provenance and age-aware eviction.
3. Test 30% loss across 256-byte cycles.
4. Require 8/8 before claiming recovery.
