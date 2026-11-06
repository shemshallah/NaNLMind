# TM-to-binary compiler

## 1. Result

`compile_tm_to_binary` compiles a finite source TM into a binary TM with
fixed-width symbol blocks.

For the Minsky 23-state / 8-symbol table:

```text
source states:       23
source symbols:      8
binary block width:  3 bits
binary states:       508
binary transitions:  1014
```

The binary machine reads three bits, reconstructs the source symbol, applies the
source transition, writes three bits back, and moves exactly one source cell
(three binary cells).

## 2. Verification

The test runs 20 source steps and 20 corresponding seven-microstep binary cycles:

```text
source state/head/tape  ==  decoded binary state/head/tape
```

after each source step.

```text
PASS TM-to-binary compiler preserves 20 Minsky source steps
```

Files:

- `include/nanlm/binary_tm_compiler.hpp`
- `src/binary_tm_compiler.cpp`
- `tests/test_binary_tm_compiler.cpp`

## 3. Why this matters

This is a concrete binary implementation of the Minsky universal machine. It is
not just a host-side interpreter: the compiled object is a deterministic binary
TM transition table with 508 states.

It provides the missing bridge for self-simulation:

```text
Minsky 23x8 table
  -> binary TM (508 states)
  -> encode binary TM with p=9 state bits
  -> Minsky universal input format
```

## 4. Boundary

The compiler output has not yet been run through the full Minsky UTM tape
encoding in CI. That tape is approximately 22 KB of encoded transitions and the
Minsky UTM scans the description on every simulated binary microstep; a deep
self-simulation is too slow for the normal test budget. The compiler and the
one-level binary simulation are checked; the full Minsky-input self-simulation
and a mechanized equivalence proof remain open.
