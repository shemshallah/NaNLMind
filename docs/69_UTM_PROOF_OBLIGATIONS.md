# UTM proof obligations

The runtime is a fixed-step universal interpreter. That is different from a
finished formal UTM theorem. This document keeps the claim honest.

## 1. Current theorem-shaped claim

For every machine description accepted by `TmDescription::valid()` (up to 16
states, 4 symbols, 255 transitions), the encoded interpreter reaches the same
state/head/halt/tape as the table-driven `TuringMachine` for the tested traces.

Evidence:

- versioned, checksummed `TmDescription` grammar;
- 20 randomized 4-state, 3-symbol machines checked step-by-step;
- direct encoded-grammar load path;
- ledger-linked tape checkpoint and restore.

## 2. Obligations still open

### O1 — explicit finite control

A literature-backed 6-state, 4-symbol U6,4 transition table (23 defined
transitions) now loads into the table-driven runtime and matches an independent
reference for 200 steps on a blank tape. That is an explicit finite table, but
it is not yet the fixed interpreter loop and it is not the Neary-Woods tape
compiler. The host `UniversalTuringMachine::step()` remains the interpreter
under proof.

### O2 — universal symbol/state encoding

The current grammar caps states/symbols/transitions. A universal encoding must
prove that larger machines can be block-encoded rather than rejected.

### O3 — self-encoded universal description

There is no TM description that simulates another encoded machine while itself
being executed by the interpreter. This is the largest missing proof object.

### O4 — atlas/ledger ownership

Tape pages can be allocated through `Atlas` when explicitly attached. A page
root and one per-page hash record are committed to the sharded journal. The
journal still stores hashes rather than the mutable page map, so pages are not
yet fully persisted ledger-owned objects.

### O5 — equivalence proof

The randomized cross-check is evidence, not an inductive proof over all
machines and all traces. A proof needs an invariant relating encoded description
positions, control registers, working-tape position, and the reference TM
configuration.

## 3. What not to say

Do not say “proved UTM” or “UTM equivalence” until O1–O5 are closed. The current
accurate phrase is:

> fixed-step universal interpreter with a checked proof harness
