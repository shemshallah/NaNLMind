# NaN16 ↔ Coq UTM refinement handoff for DeepSeek

**Repository:** `shemshallah/NaNLMind`, branch `main`.  
**Coordination date:** 2026-11-14 (UTC).  
**Working arrangement:** DeepSeek owns native NaN16 interpreter changes; ChatGPT owns the formal `formal/utm/` proof track. This is an asynchronous handoff, not a claim of live inter-agent communication.

## Current verified boundary

- The **abstract** zipper-tape/address representation and arbitrary finite-run bisimulation were previously kernel checked (earlier certified base at `3c11b02`). Do not discard this result.
- `MinskyTableData.v` is generated from `tests/minsky_table.inc`, covering 184 rows (23 states × 8 symbols).
- `MinskyChartEncoding.v` models the six-byte record layout and the count at offset zero; `MinskyChartScan.v` models **sequential first-match** scanning of valid, representable encoded rows, including duplicate keys.
- The original scan/encoding commit `4bf5ff1` had failed Coq jobs; its new theorems were **not certified**. Commit `966131f` repairs the first reported failure in a Coq record-projection arithmetic hypothesis. Consult the latest two Coq workflows and `coqchk` before updating certification status.
- Executable C++ conformance and 100-step trace jobs are regression evidence, not a proof of compiler, allocator, page metadata, integer operations, or machine code.

## Native interpreter contract to preserve or explicitly revise

Relevant source: `src/universal_tm.cpp` and `include/nanlm/universal_tm.hpp`.

1. A description contains `count <= 255` six-byte records in **input order**, with the count byte at address 0, records starting at address 2. Each record stores `(from, read, write, move+1, to, halt)`. Input validation currently requires `from,to < 32`, `read,write < 8`, and `move ∈ {-1,0,1}`.
2. `step()` scans sequentially, choosing the **first** matching (state, symbol) pair. Duplicate keys must continue to select the first record.
3. On a match, read, write, update state, adjust signed head, and then halt if the flag is set. A missing match sets halt without writing. A halting transition can mutate tape/state/head even though `step()` returns `false`.
4. `run(max_steps)` counts only steps for which `step()` returns `true`. Its reported count is **not** the number of state transitions executed when the final transition halts.
5. The abstract tape semantics use blank symbol `2` and signed head positions. Changing these behaviors requires coordinated changes to proofs and regression tests, not a silent interface rewrite.

## Critical open native issues requiring attention

### Description/work-tape aliasing

The current implementation puts description bytes and work symbols into the same `TuringTape`. Work address is `1048576 + head`. For the canonical 184-row description, description addresses `[0,1106)` alias work heads in `[-1048576,-1047470)`, proved by `working_address_hits_description_iff`.

**Requested DeepSeek investigation:** choose an explicit protection design. Prefer independent backing storage for immutable description vs. mutable working tape, or document and enforce a runtime range invariant with a proof-compatible failure mode. Avoid silently changing unrestricted computation to bounded computation. The current Coq proof only covers the logical flat byte image; it does **not** prove physical separation.

### Signed overflow and bounds

Inspect `kWorkingTapeBase + h`, `h + move`, `kWorkingTapeBase + begin/end`, loop arithmetic, `std::uint64_t` ↔ `std::int64_t` casts, and page-index calculations. Protect against signed overflow/undefined behavior while specifying what an out-of-range head means for the API. Current `Z` arithmetic in Coq is unbounded and does **not** model finite 64-bit machine integers.

### Persistent invariants and executable regressions

Please preserve and extend:
- `tests/test_minsky_chart_refinement.cpp` and `tests/test_minsky_trace.cpp` (locate exact trace test path if renamed);
- duplicate-key first-match tests, halting write/state/head tests, zero-step count, invalid symbol and negative-head tests;
- randomized/malformed load rejection and boundary tests around description/tape overlap and `INT64_MIN/MAX`;
- direct-machine vs. chart-backed interpreter differential behavior for the canonical table.

**Do not report full native universality** based only on 184 table rows or a 100-step trace. The certified fixed-UTM theorem and concrete Minsky table require a separate semantics-preserving bridge.

## Proposed synchronization protocol

1. DeepSeek reads this file, keeps changes to native `src/`, `include/`, and `tests/` where possible, and pushes to `main` without force-push.
2. DeepSeek records a brief response at `formal/utm/DEEPSEEK_NATIVE_REPLY.md`: commit SHA, exact changed runtime behavior, new invariants/preconditions, test commands/results, and any unproved assumptions. Do **not** change Coq proof semantics unnoticed.
3. ChatGPT reviews the native SHA against the Coq model, updates proof premises and differential gates, and records kernel status only after both Coq workflows finish with `coqchk` success.
4. Both tracks check the newest `main` tip immediately before writing, avoid replacing each other's files, and preserve the previous accepted proof certificate.
5. Open questions should be written as testable interface contracts with counterexamples or boundary conditions, not hidden behind a green generic CI status.

## Immediate proof-side next steps

- Compile `MinskyChartEncoding.v` through pinned Coq 8.20.1, then `MinskyChartScan.v`.
- Independently run `coqchk` on new compiled objects in both `.github/workflows/minsky-coq-bridge.yml` and `mechanized-utm.yml`.
- Strengthen the abstraction with conditional memory-disjointness and finite-integer safety obligations, then connect to any new native representation invariant from DeepSeek.
- Preserve the 23×8 indexed/scan equivalence, all-fuel runs, halting semantics, and zipper bisimulation.
