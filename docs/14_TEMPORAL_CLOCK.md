# Temporal clock: logical time for distributed spaces

Source: `NaNLM_statespace/nanclock.zip` (NaN Temporal Oscillator v2).

The clock is a **logical oscillator**, not a wall clock. Its tick is not
nanoseconds or milliseconds. It gives the one global topology a deterministic
`(tick, phase)` stamp that can order events, pace commits, expire leases, and
let a replica catch up by replay.

---

## 1. What the archive actually contains

`nanclock.zip` is a standalone C prototype:

- 64 temporal memory cells;
- address `0` is the **LE / PAST** boundary;
- address `63` is the **BE / FUTURE** boundary;
- the future program is allocated at the BE boundary;
- execution is labeled BE/FUTURE;
- the result is carried toward LE/PAST as a NaN signal;
- the past rewrites the future allocation cell;
- every transition is in a causal event log;
- exact 64-bit NaN bit patterns are carried as integers;
- no floating-point NaN arithmetic is used;
- repeated temporal states are detected generically, so longer cycles can use
  the same mechanism.

The deliberate feedback rule is:

```text
future HALT -> +qNaN -> past rewrites future to LOOP
future LOOP -> -sNaN -> past rewrites future to HALT
```

so the orbit is:

```text
HALT -> +qNaN -> LOOP -> -sNaN -> HALT -> ...
```

Exact bits:

```text
+qNaN = 0x7ff8000000000000
-sNaN = 0xfff0000000000001
```

The prototype's own README is explicit: it does not claim that an ordinary
finite CPU can decide arbitrary nontermination. The LOOP branch is a primitive
future result in the prototype. The project should preserve that honesty.

### 1.1 The V4 clock-sync experiment

The newest merged archive (`NaN16_PTC_merged_R15-R23clock.zip`) contains
`experiments/r23_clock/clock_sync.py` and `docs/CLOCK_SYNC.md`. The experiment:

- 256 heads, 4-phase oscillator `x -> Sx -> RSx -> Rx -> x`;
- 3% rate drift per head;
- 30% of heads dropped for 403 ticks, then rejoin with a stale phase and epoch;
- 10 seeds, 1600 ticks;
- three modes: free-running, local plurality over 8 Hamming-1 neighbours, and
  global community scratch (phase + epoch, read probability 0.25/tick).

Results:

| mode | order before drop | during drop | late | rejoin recovered | median recovery | epoch spread |
|---|---:|---:|---:|---:|---:|---:|
| free-running | 0.282 | 0.290 | 0.286 | 0/10 | — | 121.3 |
| local plurality | 0.704 | 0.932 | 0.975 | 9/10 | 1 tick | 317.7 |
| global scratch | **0.964** | **0.963** | **0.963** | **10/10** | **10.5 ticks** | **0.4** |

Reading: local voting reaches good phase agreement but heads disagree on the
epoch count (spread 318), so it is not a usable clock. The scratch carries a
shared epoch and keeps spread under 1. Scratch phase order is capped near 0.96
by drift between reads. The earlier static test (no drift) was local-only 1/10,
scratch 10/10 in ~7 ticks.

The archive's `CLOCK_SYNC.md` states 64,800 / 720 / 16 orbit sizes. An
independent exhaustive check of the stated `B` and `R` transforms gives
**65,040 / 480 / 16**; the 720 figure appears to double-count a 240-address
family. The head split (240 half-rate, 16 static) is correct. The scheduling
result is exact: bit-reversed slots give max gap 32 for 8 alive, 16 for 16,
8 for 32; linear gives 249, 241, 225.

Caveats preserved from the archive: simulation, not real runners; one drift
level and one drop pattern; wall-clock needs a real time source in the log.

---

## 2. What we use it for

The clock is a **field of the one global topology**, not a second machine and
not a second history. It provides:

| use | mechanism |
|---|---|
| logical epoch | `tick` increments once per oscillator step |
| phase | `+qNaN` = phase 0, `-sNaN` = phase 1 |
| event ordering | `LogicalStamp{tick, phase}` compared lexicographically |
| head handoff | `HeadRunner` stamps token epochs and adds the phase bit |
| two-phase cadence | phase 0 = propose/execute future; phase 1 = rewrite/commit past |
| lease expiry | a lease names a tick; a stale tick cannot write |
| catch-up | `observe(stamp)` / `rewind_to(tick)` replays the deterministic orbit |
| distributed identity | the clock digest is included in the global digest |

The clock is **not** used for:

- wall-clock timestamps;
- network timeouts (those use the host clock);
- real-time guarantees;
- proving or deciding nontermination;
- a claim that the period-2 orbit is a physical time crystal.

---

## 3. The stamp

```text
LogicalStamp { tick: u64, phase: u8 }   // phase 0 = +qNaN, 1 = -sNaN
```

Ordering is lexicographic:

```text
(tick, phase) < (tick', phase')
```

If two events have the same stamp, the global ledger sequence and replica id
break the tie. The ledger is always the final authority.

A replica can observe a stamp:

```text
clock.observe(stamp)
  if stamp.tick <= clock.tick:
      accept only if the phase matches
  else:
      rewind_to(stamp.tick)   // replay the deterministic orbit
      verify the phase
```

Because the orbit is deterministic, a replica that missed ticks can catch up
without asking for a snapshot of the oscillator. It needs only the target tick.
This is the key property for distributed spaces: the clock is **reconstructible
from a single integer**.

---

## 4. Distributed protocol

Six head runners (`nanlm-cpu-1..6`) host regions of one object. They do not
share a physical clock. The logical protocol is:

```text
coordinator / writer:
  1. read the committed stamp S = (tick, phase)
  2. lease a page with base hash and lease tick S.tick + N
  3. apply the delta
  4. append a ledger event carrying S and the next stamp S'
  5. commit; publish S' as the new committed stamp

other replicas:
  1. read the ledger event and S'
  2. observe(S') on their local oscillator
  3. verify the phase and the page hash
  4. update the cache
```

A stale writer has a stamp older than the committed stamp; its delta is
rejected. A duplicate event is a no-op. A partition can delay a replica, but it
cannot create a second ledger. On heal, the replica replays to the committed
stamp.

### Two-phase cadence

The period-2 orbit gives a natural two-phase cadence:

| phase | signal | meaning in the distributed protocol |
|---:|---|---|
| 0 | `+qNaN` | propose / execute future; collect a delta |
| 1 | `-sNaN` | rewrite past / commit; publish the new state |

This is a **logical** two-phase commit, not a network protocol replacement. The
ledger still provides atomicity; the phase gives a deterministic ordering
cadence and a phase bit for the temporal rails.

### Lease expiry

A lease carries `lease_tick`. A write is valid only if the current committed
tick is less than or equal to `lease_tick`. This is deterministic and
replayable. Physical timeouts can still exist at the network layer, but they do
not enter the semantic state.

---

## 5. Relation to the temporal split

The temporal split has two rails:

```text
s+ : past -> future
s- : future -> past
```

The clock phase can select the rail for a scheduled operation:

- phase 0 (`+qNaN`) favors the forward rail / future execution;
- phase 1 (`-sNaN`) favors the reverse rail / past rewrite.

The pair cell still stores both rails independently. The clock does not
overwrite them; it provides a cadence for which direction is active. This is
the bridge between the oscillator and bidirectional memory.

---

## 6. Code

`include/nanlm/clock.hpp`, `src/clock.cpp`:

- `TemporalClock`: init, step, run, cycle, stamp, observe, rewind_to, digest;
- exact `kQnanPositive` / `kSnanNegative` constants;
- bounded event log and history;
- no floating point.

`HeadRunner` accepts an optional `TemporalClock*`. When present:

- the token epoch is raised to the clock tick;
- the clock phase is added to the token phase;
- the head stamp is recorded;
- the clock steps after a successful handoff.

`GlobalTopology` owns the clock and includes its digest in `global_digest()`.

`tests/test_clock.cpp` checks:

- the HALT → +qNaN → LOOP → −sNaN → HALT orbit;
- the period-2 cycle;
- exact bits;
- deterministic digest;
- stamp ordering;
- observe/rewind catch-up;
- clock-stamped runner handoff;
- clock inclusion in the global digest.

---

## 7. Failure modes

| failure | response |
|---|---|
| replica missed ticks | `observe(stamp)` replays the deterministic orbit |
| phase mismatch at the same tick | reject; the replica is divergent |
| stale lease tick | reject the write; rebase |
| duplicate stamp | ledger sequence / event id breaks the tie |
| clock digest mismatch | reject the replica's cache; refetch from the committed generation |
| host clock jumps | no effect; the clock is logical |
| long partition | replay to the committed stamp; do not invent a new oscillator |

A replica cannot fork the clock because the clock is a deterministic function of
the tick and the genesis. If it has a different digest at the same tick, it is
wrong.

---

## 8. Honest limits

- The clock's physical duration is unknown and irrelevant. It is a logical
  metronome, not a hardware timer.
- The period-2 orbit is a deterministic curiosity, not evidence of
  hypercomputation.
- The `LOOP` branch in `nanclock` is a primitive future result in the
  prototype. A physical implementation that supplied it for arbitrary programs
  would be the hard oracle; this project does not claim that.
- The clock does not make distributed consensus free. It gives a deterministic
  logical stamp; the ledger still has to order commits and reject stale writers.
- The clock does not create a second topology. It is a field of the one object.

---

## 9. Why it matters for distributed spaces

A distributed state space needs a shared notion of "when" that is:

- deterministic;
- replayable;
- independent of host clocks;
- cheap to verify;
- reconstructible after a partition.

The oscillator provides exactly that: a `(tick, phase)` stamp that is a single
integer plus one bit, with a deterministic history and a cycle detector. It is
small enough to live in the chart, strong enough to order events, and honest
enough not to pretend it knows what a nanosecond is.
