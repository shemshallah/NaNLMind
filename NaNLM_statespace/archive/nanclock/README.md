# NaN Temporal Oscillator v2

Standalone prototype. **This project is intentionally separate from NaNLang.**

## What changed from v1

v2 replaces the abstract temporal allocator with an explicit finite temporal
memory model:

- addresses `0 .. 63` are temporal memory cells;
- address `0` is the LE/PAST boundary;
- address `63` is the BE/FUTURE boundary;
- the future program is allocated at the BE boundary;
- execution is explicitly labeled BE/FUTURE;
- the resulting temporal signal is sent toward LE/PAST;
- the LE/PAST rule rewrites the future allocation cell;
- every transition is recorded in a causal event log;
- exact IEEE-754 NaN encodings are carried as 64-bit integers;
- no floating-point NaN arithmetic is used;
- repeated temporal states are detected generically, so cycles longer than 2
  can be represented by the same state-history mechanism.

## Current paradox rule

The deliberate grandfather feedback rule is:

    future HALT
        -> +qNaN
        -> past rewrites future to LOOP

    future LOOP
        -> -sNaN
        -> past rewrites future to HALT

Therefore:

    HALT -> +qNaN -> LOOP -> -sNaN -> HALT -> ...

The contradiction is a temporal inconsistency between the state observed in the
BE/FUTURE execution and the state demanded by the LE/PAST rewrite.

The machine does not crash. It enters a deterministic period-2 temporal orbit.

## Exact NaN payloads

The prototype transports bit patterns, not floating-point values:

    +qNaN = 0x7ff8000000000000
    -sNaN = 0xfff0000000000001

This avoids implementation-dependent NaN canonicalization.

## Important semantic boundary

This prototype does **not** claim that an ordinary finite CPU can determine
arbitrary program nontermination.

For the LOOP branch, the temporal machine is defining `LOOP` as a primitive
future result. If a physical implementation supplied that result for arbitrary
programs, that primitive would be the difficult oracle/hypercomputational
component.

This source instead focuses on making the temporal address space, causal
direction, NaN signaling, rewrite rule, contradiction state, and cycle
detection explicit and executable.

## Build

    make
    ./temporal_nan 8
    ./temporal_nan 8 --events
    make test

## Architecture sketch

    low address                                      high address
    +----------------------------------------------------------+
    | LE / PAST  <----- temporal signal -----  BE / FUTURE     |
    |    addr 0                              addr 63           |
    +----------------------------------------------------------+
                                             ^
                                             |
                                      future program
                                             |
                                      execute / resolve
                                             |
                                     +qNaN or -sNaN
                                             |
                                             v
                                        LE / PAST
                                             |
                                       rewrite future

The address direction is a machine-defined temporal convention. It is not a
claim about ordinary CPU byte endianness.

## Separation

No NaNLang source, headers, binaries, checkpoints, or archives are required
or included by this project.
