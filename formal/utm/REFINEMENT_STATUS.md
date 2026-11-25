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
5. **Six-byte description refinement:** `MinskyChartEncoding.v` models
   the actual C++ description encoding (count at byte 0, transition records
   beginning at byte 2, six byte values per record, movement stored as
   `move+1`). A separate Coq kernel certificate compares every decoded
   transition against the canonical table. It lifts lookup agreement to
   single address-space steps, arbitrary finite runs, and the zipper-tape
   simulation. A general row encoder/decoder roundtrip theorem also covers
   all representable movement directions.

   **Historical address-space precondition:** the former C++ runtime used the
   same `TuringTape` instance for description and working tape, offset by
   1,048,576 cells. A working head in
   `[-1048576, -1047470)` aliases the 1,106-byte description region.
   `working_address_hits_description_iff` proves that interval exactly.
   Consequently, this earlier flat byte-layout theorem alone was **not a
   proof of unrestricted runtime equivalence**.
   **Native correction (commit `c5b13eb`):** the executable runtime now uses
   independent `description_` and working `TuringTape` stores, so the old
   alias interval is removed.  Signed head addition is checked and fails
   closed on `int64_t` overflow.  `MinskyNativePages.v` adds a value-level
   model with separate immutable description and mutable work stores,
   signed 4096-cell page/slot indexing and matching overflow ordering.
   Under an explicit signed-64-bit fuel margin, its page-run refinement
   relates the full symbolic working tape to the existing address model.
   This is not a proof of C++ allocation, object ownership or compilation.
6. **Sequential C++ chart scan:** `MinskyChartScan.v` decodes each six-byte
   block in order and checks the first matching transition, modeling the
   actual linear search rather than only direct row indexing. Its generic
   refinement theorem permits repeated state/symbol keys (first match wins)
   for any finite input list with encodable movement directions. Applied to
   all 184 Minsky rows, it lifts byte-list scan equivalence to individual
   steps, every fuel-bounded run, and zipper/address bisimulation. Both Coq
   workflows compile it and independently run `coqchk` on the certificate.
   This scan proof concerns the flattened byte list; the new page model
   separately treats functional page indexing and bounded head arithmetic.
7. **NaN16 literal full-fixture run (ISA-OBL-3d), cached split:** the
   21,025-instruction literal program's full run was originally a single
   monolithic `vm_compute` proof in `MinskyNaN16LiteralRun.v` (still
   tracked, advisory). The split proves the same final postconditions in
   two halves that each stay inside a hosted runner's memory:
   - `MinskyNaN16LiteralMachine.v` holds the literal `LPState` machine
     (five-block memory, 32-bit masked word arithmetic, `lp_exec`/
     `lp_step`/`lp_run`) as **definitions only**; no proof in it reduces
     a concrete run.
   - `MinskyNaN16LiteralPrefix.v` caches the already-certified
     20,247-instruction prefix as a transparent `vm_compute` value
     (`literal_run100_valu`) and re-derives the published run100 trace
     agreement from that cache.
   - `MinskyNaN16LiteralTail.v` evaluates the remaining 778 instructions
     over the cached prefix state and proves the full-run postconditions:
     halted, `pc = 28`, payload words `2/166/0` at the action cells,
     output `"MTH MINSKY NATIVE PASS"`, register 1 = 4357, and the code
     image preserved (`code_preserved_bool`). This is the split
     equivalent of the monolithic `literal_final` claims; fuel
     composition (`20247 + 778 = 21025`) matches `lp_run_add`.
   The CI split step (`nan16-full-tests.yml`, "Compile the literal
   prefix/tail split") is **required**: a failure there means the split
   proof is wrong, not that resources ran out. The monolithic
   `MinskyNaN16LiteralRun` leaf stays advisory because its single
   21,025-instruction reduction exceeds the hosted runner's memory even
   with swap headroom.

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

- Bridge the functional 4096-cell page model in `MinskyNativePages.v` to
  actual native `Universe` allocations, register metadata, object lifetimes,
  integer conversions and memory-failure semantics. The mathematical
  page/slot decomposition does not verify the C++ allocator.
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
