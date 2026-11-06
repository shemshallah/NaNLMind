# Compact binary runtime

## 1. Why

The Minsky universal tape encoding is 22 KB and the Minsky scanner must traverse
it for every simulated binary microstep. That made the recursive probe
impractically slow.

The compact path runs the compiled binary machine directly from its transition
table:

```text
source:             Minsky 23-state / 8-symbol table
binary block:       3 bits
binary states:      508
binary transitions: 1014
```

`BinaryUniversalMachine` uses `TuringTape` pages for bits and a direct table
lookup for each step. It has no Minsky description scan.

## 2. Verification

The test compiles the Minsky table into the binary machine, loads it, and runs
seven binary microsteps per source step. After each source step it decodes the
binary state and tape and compares them with the source reference:

```text
PASS compact binary runtime preserves 20 Minsky source steps
```

Files:

- `include/nanlm/binary_utm.hpp`
- `src/binary_utm.cpp`
- `tests/test_binary_utm.cpp`

## 3. Status

This is a fast one-level binary implementation of the Minsky universal table.
It is not the same result as the full recursive Minsky-tape self-run, which is
still documented as a partial probe. It is the compact execution path needed to
make deeper self-simulation practical.

## 4. Boundary

The binary runtime is still a host table interpreter with an explicit table. A
mechanized proof and a completed recursive Minsky-input self-run remain open.
