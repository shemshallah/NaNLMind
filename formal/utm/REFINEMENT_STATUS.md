# NaNLMind Minsky chart refinement: exact scope

This directory separates three different verification claims.  A successful
GitHub Actions run does not make them interchangeable.

1. **Certified fixed binary UTM:** `UTMEquivalence.v` exposes the existing
   fixed-machine halting equivalence from the pinned Coq Undecidability
   Library. This is a theorem about that library's fixed UTM, not automatically
   about the concrete 23-state/8-symbol machine below.
2. **Concrete Minsky table:** `MinskyTableData.v` matches all 184 entries in
   `tests/minsky_table.inc`, checked by `check_minsky_table.py`.
   `MinskyTable.v` proves completeness, guards against out-of-domain
   index aliasing, proves indexed/linear-scan lookup equivalence **for all
   states and symbols**, and lifts this to every fuel-bounded formal run.
   Halting transitions first write/move/update the state, then set the halted
   flag. The published 100-step trace is checked by the Coq kernel.
3. **Executable C++ conformance:** `tests/test_minsky_chart_refinement.cpp`
   runs all 184 state-symbol entries through the chart-backed
   `UniversalTuringMachine` and the direct `TuringMachine`, comparing
   write/move/state/halt effects and subsequent short runs. It also checks
   invalid states/symbols, negative tape positions and repeated halting.
   The existing 100-step native trace gate provides another concrete check.
4. **Signed-address Coq semantics:** `MinskyAddressRefinement.v` models a
   symbolic tape as `Z -> nat`, a signed head coordinate and an observable
   halted flag. It proves that indexed and scanning transition lookup yield
   identical states for every fuel-bounded address-space execution, including
   final writes on halting transitions, and independently checks the published
   100-step tape in this representation. Its `tape_bisim` representation
   invariant relates **every** cell of a zipper tape to a signed address,
   not just cells visited by a short trace. `zipper_address_step_bisim` and
   `zipper_address_run_bisim` are the corresponding one-step and arbitrary
   finite-execution proof obligations; `embed_config` constructs the
   corresponding address representation for any zipper and signed head.
   `address_run_cpp_counted` additionally models C++ `run(max_steps)`'s
   return convention: a final halting transition is executed but is not
   counted, and `address_cpp_counted_final_agree` proves that the final
   machine configuration is unchanged by this counting convention.

The Coq theorems are formal results about the Coq models. The general
zipper-to-signed-address simulation bridges these two formal representations,
not the concrete chart allocator. The C++ test is an
executable differential test, **not** a formal verification of the compiled
C++ runtime. In particular, chart-page layout, 64-bit integer overflow,
serialization, and compiler behavior are outside these Coq proofs.

The exhaustive native conformance test includes zero-fuel execution, a
nonhalting one-step run, and a halting run with a zero returned count; a
`run()` return value is not an unqualified count of transitions executed.

## Remaining research obligations

- A representation invariant and simulation theorem relating the Coq tape
  to the actual chart pages/registers of `src/universal_tm.cpp`.
- A semantics-preserving connection between the concrete Minsky 23x8 table
  and the certified fixed UTM's simulation chain (or a separate certified
  universality proof for the concrete table). Their universality cannot be
  inferred from matching a finite trace.
- A sufficiently formal C++/machine-code refinement framework if the claim
  is to cover the compiled native executable, rather than its modeled
  transition logic plus exhaustive regression tests.

## Reproduction

```
make minsky-bridge-check minsky-trace-check
make mechanized-utm
# or trigger .github/workflows/mechanized-utm.yml remotely
```

The Coq job also runs `coqchk` and emits `Print Assumptions` for the
key Minsky correspondence theorems. Its source and compiled artifacts are
uploaded by the workflow. No theorem is claimed until CI has actually passed.
