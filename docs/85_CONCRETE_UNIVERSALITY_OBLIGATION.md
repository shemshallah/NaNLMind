# Concrete 23x8 universality: exact status and proof obligation

## Claim under consideration

There is a computable encoding `e(M, x)` from every finite Turing machine `M`
and input `x` to a tape configuration such that the fixed 23-state/8-symbol
Minsky table, started in its documented state, simulates `M(x)` step for step
and halts exactly when `M(x)` halts.

**Status: open. This package does not claim it.**  A **restricted native
encoder prototype** now emits the Minsky tape format from a 4-state/2-symbol
source contract (`docs/86_NATIVE_MINSKY_COMPILER.md`), but it is not a general
finite-machine compiler or a mechanized universality theorem.

The current Coq development proves the table transcription, transition lookup,
halt ordering, published trace, and a signed-address/zipper bisimulation.  None
of those implies universality.  The fixed-UTM theorem in `UTMEquivalence.v` is
about the Coq undecidability library's fixed binary machine, not the concrete
23x8 table.  Minsky's published universality theorem is literature evidence,
not a mechanized theorem for this artifact.

## Why the existing evidence is insufficient

- `minsky_table_complete`: every table cell exists.
- `find_entry_scan_all`: lookup semantics agree.
- `minsky_trace_100`: one published execution trace.
- `zipper_address_run_bisim`: two formal representations of the same table
  agree.
- Native/C++ tests: executable conformance on the published input and a short
  encoded machine.

None of these quantifies over an arbitrary encoded machine or proves the
encoder/decoder round trip.

The added `MinskyNativePages.v` supplies a bounded-run refinement for a
functional model of the current separate description/work-tape layout,
including signed 4096-cell page keys and post-write overflow semantics.
This strengthens interpreter refinement, not arbitrary-machine encoding.

## Required formal compiler/refinement

A complete proof needs at least:

1. **Source model.** A finite Turing machine with an explicit finite state and
   symbol type, transition relation, halting predicate, and tape semantics.
2. **Encoding.** Computable functions `encode_config`, `encode_machine`, and
   `decode_tape` from the source model into the Minsky tape format, with a
   proof that decoding recovers the source configuration (including blank
   cells and signed head positions).
3. **One-step commutation.** For every source configuration `c`, if the source
   machine takes a transition to `c'`, the Minsky table's next configuration
   decodes to `c'`; if the source halts, the table enters its halt entry after
   writing the final symbol and updating state/head.
4. **Finite-control proof.** The table's control state remains in `0..22` and
   the tape/head encoding remains well formed for every reachable step.
5. **Arbitrary-run lifting.** Induct over the source run (or the Minsky fuel)
   to obtain simulation for every finite run and the correct halting
   behaviour.

The existing `InterpreterRefinement.utm_run_refines` is a generic compiler
correctness lemma for an **external description graph**, not an encoding of a
source TM into the 23x8 tape.  It can serve as a template for item 3–5, but the
source-machine encoding is still missing.

## Formal target statement

```coq
Theorem minsky_concrete_universal :
  forall (M : SourceTM) (input : SourceConfig) (fuel : nat),
    exists (initial : MinskyConfig),
      encode_config M input initial /\
      decode_tape (minsky_run (simulation_fuel fuel) initial) =
        source_run fuel input.
```

The exact fuel relation and halting/undefined convention must be fixed before
this statement is useful.

## Executable obligation

A native NaN16 compiler/refinement would need to:

- accept a compact machine description in guest memory;
- emit/load the Minsky tape format;
- run the fixed table;
- decode the final tape and state;
- compare against an independent source-machine trace.

The current native fixture only executes the published Minsky trace.  It does
not implement the encoder or arbitrary source execution.

## Publication rule

Do not describe the concrete 23x8 table as "proved universal" until the
statement above is checked without axioms and a compiler/decoder proof exists.
The honest current claim is:

> a checked fixed-UTM construction, a mechanized concrete Minsky table, a
> signed-address refinement, and executable conformance evidence.

That is the claim recorded in `docs/84_VERIFIED_UTM_SYSTEM.md`.
