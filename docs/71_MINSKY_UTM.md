# Minsky 23-state universal machine

## 1. What was added

The table-driven runtime now supports 32 states and 8 symbols. The complete
23-state, 8-symbol Minsky universal machine from *Computation: Finite and
Infinite Machines* (1967), Chapter 7, is loaded as ordinary chart transition
entries.

Symbols:

```text
0, 1, A, B, X, Y, M, S
```

The 184 transitions include Minsky's implicit identity quintuples, so the table
is complete for every state/symbol pair rather than relying on host fallback
behavior. `(state 4, Y)` is the halting transition.

## 2. Cross-check

The test uses the published default configuration:

```text
machine description: X0000001X0010110X0100011X0110100
machine tape:        1111YBAAXAAAAAAAXAABAAAAS
condition:           001
buffer sizes:        2 / 6
```

It runs exactly 100 host steps and compares the whole UTM tape against a Python
reference implementation of the same machine:

```text
PASS Minsky 23-state/8-symbol table matches Python reference
```

The agreed final state is UTM state 3 (zero-based 2), head position 38, with the
expected 73-symbol tape.

A second test encodes a normal, non-exploit binary machine:

```text
q0,0 -> write 1, right, q1
q1,0 -> write 1, right, q2
q2,0 -> undefined (halt)
```

It runs the Minsky table to its halt transition and checks the final 73-symbol
tape and head:

```text
PASS Minsky UTM executes a normally encoded binary machine
```

The same table is also encoded as a `TmDescription`, loaded into the fixed-step
`UniversalTuringMachine`, and used to run that encoded binary machine. Its
state/head/halt/tape trace matches the table-driven runtime for 100 steps:

```text
PASS encoded Minsky universal description runs on the chart UTM
```

## 3. Tape format

The UTM tape is:

```text
0^left_buffer
simulated_tape
M
0^t_buffer
Y
condition
description
Y
0^right_buffer
```

The head starts on the description. Each simulated binary-machine transition is
encoded as:

```text
X q(2) read(1) q'(2) write(1) direction(1)
```

This is a genuine fixed universal table with a documented finite input format,
not a host task switch.

## 4. Proof boundary

This closes the “explicit universal table” part of O1. It does not close:

- O3: the shipped test uses the published exploit/configuration, not a
  self-encoded description of the 23x8 machine;
- O5: the comparison is a 100-step reference trace, not an inductive proof for
  all inputs;
- a general compiler from arbitrary TMs into the 4-state binary input format.

The next honest step is a bounded encoder test for a normal simulated binary
machine, followed by a self-simulation attempt only after the encoder and
decoder are stable.
