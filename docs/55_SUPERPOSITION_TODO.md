# SUPERPOSITION TODO — do not implement yet

**Status:** deferred design record. Not wired into the current gates. Do not use
it to claim a result.

## 1. Primitive

A candidate superposition is:

```text
list of candidate ids + signed integer amplitudes
```

- add is linear;
- opposite signs cancel;
- merge is commutative addition;
- diffuse is integer Grover-style amplitude amplification;
- collapse is either MAP or seeded Born sampling;
- abstain when the top-two margin is below a threshold.

This is classical weighted voting with signed interference. **Do not call it
quantum.**

## 2. Collapse

```text
MAP:            argmax(a²), deterministic
Born:           sample a²/Σa² with an integer seed
seed:           hash(global_digest, logical_tick, query_id)
```

The prototype only showed the function is pure in its seed. The real test is a
full ledger replay: identical digest/tick/query must produce the same collapse.

## 3. Prototype results to preserve

- amplitudes 3:1 → 90.0% / 10.0% Born frequencies;
- exception test: `+6 FLY`, `−6 NOFLY` → NOFLY wins;
- merge order A→B and B→A identical;
- tie → abstain;
- Gaussian-integer experiments: hidden parity recovery, Walsh spectrum
  sampling, phase interference, 12-step Grover on 256 candidates, weak collapse.

These are Python/prototype results, not C++ claims.

## 4. Integration plan for later

1. `contemplate` holds the unmeasured state; `commit` collapses and writes
   `(pre_digest, seed, outcome)` to the ledger.
2. Reverse frame restores the pre-collapse state.
3. Entanglement: a mirror-pair cell is a joint table; measuring one head
   conditionally selects the other row.
4. Hierarchical collapse: parent measures first, children are conditioned;
   upward flow stays linear until read.
5. Learning from collapse: correct outcome +δ amplitude, wrong −δ; symbolic
   triple store is the grader.
6. Use amplitudes in Gaussian integers `re + im·i` if phases are needed; use
   `__int128` or documented integer floor-shift renormalization.

## 5. Required tests before adoption

- C++ Z[i] simulator bit-for-bit vs the Python reference.
- Full ledger replay with same digest/tick/query — same collapse.
- Spectrum learner: sample parities from Walsh weights and recover XOR
  structure on the Boolean curriculum.
- Cassowary amplitudes: verify the exception goes from tie to NOFLY.
- Compare against kNN/score-table baselines on held-out data.
- Pre-register pass/fail thresholds before running.

## 6. Explicit non-goals

- no quantum speedup claim;
- no replacement of the current Boolean gates or symbolic baseline yet;
- no change to the 8 MiB/2 GiB memory split;
- no use in the Koyeb merge until the replay test exists.
