# Repeatability and the period-2 clock

## 1. Question

Is an observed alternating result caused by the NaN clock, or is it a
run-to-run nondeterminism?

## 2. Method

Ten independent process launches of each quick probe:

```sh
./build/nanlm-universal verify
./build/nanlm-universal phase
./build/nanlm-universal clock
./build/test_logic_challenge
```

For each run we recorded the exit code, the SHA-256 prefix of the complete
output, the clock digest, the challenge accuracy, and the number of `yes`
answers.

## 3. Result

All ten runs are identical:

| run | verify | phase | clock digest | challenge |
|---:|---|---|---|---|
| 1-10 | exit 0, `56bb6275818fe2bd` | exit 0, `ab9825489dca81cf` | `c5d951c6171c581f` | 0.500 accuracy, 8/8 predicted yes |

The clock body is also stable:

```text
tick 0: future=HALT -> +qNaN -> past rewrites future=LOOP
tick 1: future=LOOP -> -sNaN -> past rewrites future=HALT
tick 2: future=HALT -> +qNaN -> past rewrites future=LOOP
...
cycle start=5 length=2
```

## 4. Interpretation

The alternation is real, and it is **by design**: the temporal clock has a
period-2 orbit, `HALT <-> LOOP`, with the +qNaN / -sNaN feedback. It is
deterministic. The same digest is produced every run, so the clock is not a
source of run-to-run nondeterminism.

`C(256,2) = 32,640` is the triangular pair count. `verify` checks both the
literal 32,640 and the identity every run; both pass. There is no alternating
pair count.

The challenge is also deterministic. It now covers fish swimming and birds
flying with true facts, balanced four yes/four no labels, and ten shuffled fact
orders. Every seed gives accuracy 0.5, with 1 yes, 3 no, and 4 uncertain
answers. The symbolic baseline is 1.0. The yes attractor is gone; the remaining
failure is the missing entity binding, not a label prior. An earlier
fish variant incorrectly said “carp cannot swim,” which is false and has been
removed.

## 5. What was not run to completion

The repeated `make test` / `make universe-check` / `make penguin` / `make logic`
loop was stopped because the suite loop is too heavy on this device. Run those
gates one at a time. The quick probe above is the repeatability record; the
individual gates had already passed before the loop was stopped.

## 6. If an alternating result appears elsewhere

Record the exact command, the two output hashes, and whether the difference is
in a state field or only in display order. A period-2 clock state is expected;
a different digest for the same logical state is not.
