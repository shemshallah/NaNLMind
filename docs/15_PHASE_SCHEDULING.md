# Transform phase, synchronization, and scheduling

This document separates three different “4”s and records the verified
transform-phase numbers.

---

## 1. Three different fours

| object | count | meaning |
|---|---:|---|
| NaN head classes | 4 | `+sNaN`, `−sNaN`, `+qNaN`, `−qNaN` |
| transform images | 4 | `I`, `B`, `R`, `B∘R` |
| Boolean functions | 16 | the class nibble `(near << 2) | far` |

The “4 NaN types” in the original design note are the **head classes**. The
4-phase oscillator is the **transform group** acting on an address:

```text
x -> Bx -> BRx -> Rx -> x
```

where `B` is byte swap and `R` is 16-bit reversal. The operations alternate:
`B, R, B, R`. The code exposes:

```cpp
apply_transform_phase(a, phase)   // cumulative image
advance_transform_phase(a, phase) // one alternating tick
transform_orbit_size(a)
```

`phase 0 = I`, `1 = B`, `2 = B∘R`, `3 = R`.

---

## 2. Verified orbit counts

Exhaustive enumeration over all 65,536 addresses gives:

| orbit size | addresses | behaviour |
|---:|---:|---|
| 4 | **65,040** | full 4-phase oscillator |
| 2 | **480** | half rate / divide-by-2 |
| 1 | **16** | static |

The earlier 64,800 / 720 / 16 split is off by 240 in the size-2 class. The
correct decomposition is:

```text
fixed by both B and R       16
fixed by B only            240
fixed by R only            240
size-2 total               480
size-4 total            65,040
```

The 720 figure double-counts one of the 240-address fixed families. The 16
static addresses and the 240 half-rate heads are correct.

The 256 palindromic heads split as:

```text
240 half-rate heads
 16 static heads
```

So the heads are slow beat markers, while the non-fixed cells are the fast
4-phase clock phases.

---

## 3. Why local synchronization alone fails

A purely local phase oscillator on the 8-neighbour bit-flip graph can freeze
into domains: each domain is locally consistent, but the 256 nodes never agree
globally. The reported experiment is:

| coupling | synchronized runs |
|---|---:|
| local plurality only | 1 / 10 |
| local + noise | 0 / 10 |
| local + global community scratch | **10 / 10** |

The global scratch is the natural sync bus because it is already a field of
the one object. A node occasionally reads the community phase from the chart
scratch instead of a neighbour. That gives the field a common reference without
an external coordinator.

The code exposes the primitives:

- `HeadScratch` local/work areas;
- `ScratchJournal` / `ConsolidationEngine` replay;
- `Head::transform_phase` (2 bits);
- `TemporalClock` logical stamps.

The drift/dropped-host harness is the next test.

---

## 4. Bit-reversed wake scheduling

Assign wake slot `slot(i) = reverse8(i)`. For any power-of-two number of
surviving instances, the occupied slots stay evenly spread. Verified table
from `src/schedule.cpp` with 256 slots:

| alive | ideal max gap | bit-reversed | linear | random (seed 0x4E614E4C) |
|---:|---:|---:|---:|---:|
| 8 | 32 | **32** | 249 | 103 |
| 16 | 16 | **16** | 241 | 46 |
| 32 | 8 | **8** | 225 | 21 |
| 5 | 52 | **64** | 252 | 155 |

The random column is seed-dependent; the bit-reversed column is exact. Five
alive is slightly off ideal because 5 is not a power of two; the max gap is 64
against an ideal of 52.

This applies directly to the five staggered ring runners:

```text
slot(i) = reverse8(i)
```

Any power-of-two subset of survivors remains evenly spaced. For five, use the
bit-reversed slot and accept the 64/52 gap, or add a small deterministic
offset.

---

## 5. Logical time and time reversal

The oscillator is logical time, not wall time:

- a tick is an integer, not nanoseconds or milliseconds;
- the ledger carries an `epoch` on every event;
- a replica can replay the deterministic orbit to catch up;
- host clocks drift; the logical stamp does not.

Bit reversal gives a time-reversed tick:

```text
reverse8(tick)
```

A 16-bit palindromic tick is self-dual:

```text
tick == reverse16(tick)
```

There are 256 such ticks. They are irregularly spaced, so they are useful as
epoch markers, not as a regular clock. The code exposes
`is_palindromic_tick()` and `palindromic_epochs()`.

---

## 6. What is built

- `include/nanlm/nan16.hpp`: transform phases, orbit size, alternating advance.
- `include/nanlm/schedule.hpp`: bit-reversed/linear/random wake slots, max gap,
  palindromic epochs.
- `include/nanlm/head.hpp`: 2-bit `transform_phase` per head, mirrored into
  `scratch.local()[0]`.
- `include/nanlm/ledger.hpp`: `Event::epoch`.
- `include/nanlm/consolidation.hpp`: scratch journal with an epoch.
- `tests/test_phase.cpp`: orbit counts, 4-phase return, head split, wake-slot
  table, palindromic epochs.

---

## 7. Next experiment

Build a drift/dropped-host harness:

1. 256 phase oscillators, 8-neighbour graph.
2. local plurality vs local + global scratch.
3. inject phase drift and drop 1–5 hosts.
4. measure ticks to 95% consensus and the survivor gap.
5. repeat over 10 seeds.

Pass condition: global-scratch coupling reaches 95% consensus in at least 9/10
runs with drift and drops; local-only does not. Falsified if the global scratch
adds no measurable robustness.

---

## 8. Honest limits

- The transform counts are exact; the 64,800/720 figure is not.
- The global-scratch synchronization result is reported from the external
  experiment; the C++ harness is not yet in the repository.
- The bit-reversed scheduling result is exact for power-of-two subsets; five is
  approximate.
- The logical clock does not replace a physical time source for network
  timeouts. It orders state transitions; the host clock handles transport.
- The 4-phase oscillator is reversible and information-preserving, but it is
  not a source of free computation.
