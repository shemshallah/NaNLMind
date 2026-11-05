# Universal TM runtime

## 1. What is universal here

One `UniversalTuringMachine::step()` is fixed. It does not load a different C++
function per machine. It reads an **encoded machine description from chart tape**
and interprets it:

```text
description:
  cell 0        transition count
  cell 2 + 6i   from, read, write, move, to, halt

working tape:
  position 1<<20 + head

control:
  state / head / halt in chart address registers
```

Calling `load_machine` replaces only the tape description and initial working
tape. The interpreter code stays the same.

## 2. Machines run by the same interpreter

Tested:

1. binary increment `1011 -> 1100`;
2. unary increment `111 -> 1111`.

```text
PASS universal TM: one fixed step interprets encoded machines
```

The test also exposed and fixed a real blank-cell bug: allocated tape pages must
initialize every address-register meta to blank, otherwise unwritten cells read
stale chart metadata.

## 3. Honest boundary

This is a **UTM-class interpreter runtime**:

- fixed step, encoded machine description on chart tape;
- unbounded logical tape via allocated chart pages;
- multiple machine descriptions run on the same instance;
- not yet linked to the atlas allocator/ledger;
- no formal proof that the description format covers every TM;
- no claim of a hand-written finite transition table in ROM.

It is much stronger than the earlier per-machine `TuringMachine::load`, which
stored a different host transition table per machine.

## 4. Next

1. Define a complete, versioned TM description grammar.
2. Prove/cross-check every transition encoding against a reference TM.
3. Link tape pages to atlas allocation and ledger commits.
4. Add a universal machine description that executes a TM-encoded UTM.
5. Then use the U-word without qualifiers.
