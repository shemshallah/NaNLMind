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
transitions) loads into the table-driven runtime and matches an independent
reference for 200 steps on a blank tape. The complete 23-state, 8-symbol Minsky
universal table also loads as 184 chart transitions and matches a Python
reference for 100 steps. This is an explicit finite universal table, but it is
not yet a self-encoded description or a formal interpreter proof.

### O2 — universal symbol/state encoding

The current grammar caps states/symbols/transitions. A universal encoding must
prove that larger machines can be block-encoded rather than rejected.

### O3 — self-encoded universal description

The Minsky 23-state/8-symbol universal table is now encoded as a
`TmDescription`, loaded into the fixed-step `UniversalTuringMachine`, and used to
run another encoded binary machine against the table-driven reference for 100
steps. This is a working encoded universal description.

Still open: a description that encodes the 23x8 table **as an input to itself**
and run its own self-simulation. That needs a TM-to-binary/table compiler and a
decoder, not just the universal table.

### O4 — atlas/ledger ownership

Tape pages can be allocated through `Atlas` when explicitly attached. A page
root plus one per-page record is committed to the sharded journal. The journal
now also reconstructs a verified `TapePageIndex` of key/hash entries. The page
data remains in the tape/atlas rather than the journal, so a fully
ledger-persisted mutable page map is still open.

### O5 — equivalence proof

The exhaustive/randomized traces and encoded-description reference are checked,
but they are not an inductive proof over all machines and traces. The theorem
relation is documented in doc 72; a mechanized proof is still open.

## 3. What not to say

Do not say “proved UTM” or “UTM equivalence” until O1–O5 are closed. The current
accurate phrase is:

> fixed-step universal interpreter with a checked proof harness
