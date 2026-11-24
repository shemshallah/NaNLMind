# Concrete Minsky 23×8 universality: referee-facing proof ledger

Status date: 2026-11-23. **The fixed-table left-infinite simulation
theorem is established and kernel-checked.**  The final theorem
`lic_lifted_halting_equivalence` is recorded in the closing section.
Earlier sections retain their historical status and are superseded by
that section.

## Frozen target

- Transition function: the 184 rows in `tests/minsky_table.inc`,
  transcribed independently into `formal/utm/MinskyTableData.v`.
- Runtime semantics: `MinskyTable.step` and `run` with explicit
  write/move/state update and halting flag.
- Alphabet: 0–7; states: 0–22. These are **fixed**, not research variables.
- Mathematical tape: unbounded in both directions in the signed-address
  Coq model. Finite NaN16 guest memory by itself is not an unbounded tape.

## Certified fragments and their exact meanings

| Artifact | Scope | Does it prove universality? |
| --- | --- | --- |
| `MinskyTable.v` | 184-row completeness, indexed vs scan agreement, 100-step table trace | No |
| `MinskyAddressRefinement.v` | Full abstract zipper/signed-address tape bisimulation | No |
| `MinskyChartEncoding.v`, `MinskyChartScan.v` | Chart-byte and six-byte linear lookup refinement | No |
| `MinskySourceEncoding.v` | Round trip for arbitrary finite 8-symbol rows; abstract decoded interpreter and arbitrary finite runs | No |
| `MinskyConcreteEntry.v` | Left-scan induction, first 5/8/10 native-table transitions | No |
| `MinskyConcreteProgramScan.v` | Entire encoded description is scannable by the unchanged native table for arbitrary row count, provided the exact reversed tape layout | No |
| `MinskyConcreteDispatch.v` | Checked on `main`: unbounded state-2 backward and state-3 forward scans, and first-row branches through step 15/17 | No |
| `MinskyWideConcreteDispatch.v` | Checked: arbitrary-width row first-bit branches and whole-program scan, with p=9 concrete first-bit witness | No |
| `MinskyMatchMacro.v` | Checked: q0/q4 marked-prefix scans, matched-bit return, q1 skip-and-pick, q5 cleanup, q0/q4 mismatch restart, successful all-bit match loop, and mismatch restart composition | No |
| `MinskyActionMacro.v` | Checked: q6/q7/q8 action copy-return scans, q9/q10 writeback, q11 return-to-X, q12/q13 direction scans, q14 restore-to-X | No |
| `MinskyHeadMoveMacro.v` | Checked: q15 raw-bit search and q16 restore/branch to q21/q22 | No |
| `MinskyDirectionDecision.v` | Checked: q21/q22 leftward direction-mark decision and bit write | No |
| `MinskyRelocationMacro.v` | Checked: q17/q18 marker restoration, q19/q20 displaced-M relocation, and q19-to-q5 exact cycle | No |
| `MinskyDirectionRelocationCycle.v` | Checked: exact q15–q22 direction and relocation, q12/q13 reached-cursor bridges, q12/q13→q19/q20, q13→q5 and q12→q5 return paths, a fully constructed q12→q5 program-bit collision for arbitrary-wide programs, and explicit right-neighbour marker mismatch | No |
| `MinskyMarkedProgram.v` | Checked: marked 0/1→2/3 descriptions admit a logical erasure; an actual unbounded native-table scan preserves a fully decodable arbitrary-width source program and untouched suffix | No |
| `MinskyVariableBuffer.v` | Checked: exact first-state-bit dispatch after `2*n+4` native steps for all **positive** zero-buffer widths `n`; low return after `3*n+6`; high scan to next X/Y for any finite binary tail | No |
| `MinskyMacroSimulation.v` | Checked *conditional theorem*: arbitrary-run simulation and both directions of halting equivalence, assuming as-yet-unproved concrete native macro/encoding hypotheses | No |
| `MinskyWideMacroSimulation.v` | Checked *conditional arbitrary-width theorem*: halting equivalence for finite source-state width `p`, with three explicit unproved concrete bridge premises | No |
| `MinskyEncodedFixture.v` | Exact 583-transition native-fixture halted configuration, with step 582 still active | No |
| `UTMEquivalence.v` | Halting equivalence of an independently formalized fixed UTM in the pinned Undecidability Library | Not for this 23×8 table |

Each new theorem must pass both `coqc` and `coqchk` in a published
GitHub Actions run before its status is elevated from submitted to checked.
The independent `check_minsky_dispatch.py` covers 3,136
exhaustive/seeded concrete dispatch executions, with buffer widths 1–129,
plus 1,022 exhaustive matching-bit round trips over all binary skipped
prefixes of length 0–8. The round-trip theorems in `MinskyMatchMacro.v`
are **submitted pending CI**: for either matching bit and any skipped binary
prefix, they account for exactly `2*length(prefix)+4` literal table steps
from the q1 selection through q0/q4 comparison and q2 return to q1/Y,
with exact resulting tape. This does not handle an arbitrary mismatch loop
or prove a complete encoded instruction simulation.
Width zero is a real different control path, not a permitted hypothesis.

## November 14 regression findings

At commit `e5e9ece`, the fast Coq bridge workflow `43652792804` failed
to compile `MinskyWideSource.v` because its `decode_n_bits_roundtrip`
proof referenced the nonexistent hypothesis `Hrest`. The 184-entry native
table and NaN16 transcription checks passed in that run. The new
variable-width source-model results must not be called kernel-verified
until the replacement code passes `coqc` and `coqchk` in a new run.

The original p=9 native compiler fixture began at `(q0, read 0)` but its
first source instruction matched `(q0, read 1)`. It therefore did **not**
demonstrate execution of that instruction. The corrected three-row fixture
has three reachable source instructions and both movement directions;
the independent finite table interpreter reports 9,277 microsteps and a
94-cell final expected image. Its updated NaN16 guest image remains to be
rechecked on CI; neither finite execution nor independent source reachability
constitutes a complete source-to-concrete step refinement.

The new conditional macro theorem is *not* a concrete universality proof:
its two functions `encode` and `macro_cost`, and three explicit premises
(`encode_reflects_halt`, `macro_cost_positive`, `actual_table_macro_step`),
must be constructed or proved against the frozen transition table. Under
those premises, the theorem rules out premature halting at any intermediate
native step, not merely at chosen macro boundaries.

## Crucial semantics gap

`BinarySourceRow` uses **two control-state bits** and **one read bit**:
the source interpreter has four states and a binary tape. Its lookup
is by three bits, so at most eight distinct state/read keys have effect;
additional duplicate keys obey first-match semantics. Therefore the
constructive round trip for arbitrarily long row lists is **not a reduction
from arbitrary Turing machines**. Universality would require a proved
encoding of unbounded programs into the input tape and a corresponding
universal interpreter, or a separate reduction from a known universal
machine into the concrete 23×8 transition system.

A finite-state transition table can be universal on an unbounded tape,
but a successful encoded two-row example cannot establish that fact.

## Required central theorem (not yet present)

Choose one formally specified reference computational model `R` with a
mechanized or independently auditable universality theorem. Define:

1. Total, computable source and tape encoder `encode : RConfig → Config`.
2. Decoder/observable relation `represents : RConfig → Config → Prop`,
   including tape contents, source head, source control state and halting.
3. A nonzero finite (possibly state-dependent) progress bound for each
   simulated source transition, with arbitrary left/right scans and
   program-counter wraparound.
4. **One-step forward simulation:** for every well-formed source step,
   there is a finite *actual* `MinskyTable.step` run taking
   `encode(source)` to a configuration representing the source successor.
5. **No premature halting / backward soundness:** machine halting cannot
   occur in intermediate states unless the source computation has halted.
   Fair progress must rule out a stuttering interpreter that never executes
   an encoded instruction.
6. Induction to arbitrary finite source runs; transfer of finite halting
   and infinite nonhalting (with no hidden bounded-tape preconditions).
7. A universal-source reduction: arbitrary machine/input `(M,x)` maps
   effectively into that reference model, *not* only to four-state binary
   source instruction records.

The paper's advertised result should be a theorem equivalent to:

> For every reference machine `M` and input `x`, the reference run
> halts if and only if the **unchanged 23×8 table** started on the
> computably encoded tape halts.

This statement must be proved from an explicit encoding, not assumed,
derived from finite exhaustive state-table checks, or imported through
an unproved correspondence.

## Independent certification requirements

- Pin Coq and all formal dependencies by version and commit digest.
- Run `coqc`, `coqchk`, and `Print Assumptions` for the central theorem
  and every critical compiler/refinement lemma; no `Admitted`,
  local axioms, or unverified external oracle may close the gap.
- Verify the hash and orientation of all 184 table entries against the
  native source and a separately transcribed canonical source.
- Provide machine-readable input/output configurations for positive,
  negative, branching, tape-extension and halt cases.
- Make precise whether the claimed theorem concerns the mathematical
  table (reachable here) or the compiled C++/NaN16 implementation
  (requires additional allocator, arithmetic, lifetime and compiler proof).
- Invite an independent Coq maintainer/formal-methods referee to rerun
  all certificates from a clean container.

## Publication threshold

A possible first paper is a formal certification of *selected interpreter
macros and executable conformance*, accurately labeled a partial result.
A *complete concrete universality paper* requires the central theorem,
independent reproduction, technical comparison with prior machine
certifications, and a reasoned novelty statement. Suitability for
`Nature` or any journal is a separate editorial/peer-review judgment.

Authorship for any eventual manuscript: **Justin Howard-Stanley**,
Independent Researcher, Santa Cruz, California, USA.

## November 16 arbitrary-width bridge and relocation obstruction

The proposed `MinskyWideMacroSimulation.v` extends the conditional
arbitrary-run and *two-way* halting equivalence statement to the existing
`WideSourceRow`/`WideSourceConfig` interpreter, with any finite state width
`p`. This removes the four-state source limitation from the **conditional
target theorem**. The three central premises are still explicit:
`wide_encode_reflects_halt`, `wide_macro_cost_positive`, and
`wide_actual_table_macro_step`. No total concrete encoder or unconditional
one-instruction simulation has yet discharged them. A reduction from a
known universal source machine is also still required.

The new `marked_wide_program_blocks_q19_full_right_scan` checks a sharper
constraint on the concrete layout: **if** the rightward relocation scan
crosses a complete q5-marked nonempty encoded source program, q16 restores
the instruction read bit (2/3) to a raw bit (0/1), so q19 necessarily
stops before the intended next raw cell. This is a counterexample to the
naive full-program scan premise, **not** to universality of the unchanged
23-state/8-symbol table. Correct source-to-concrete encoding must either
keep that span out of the q19 relocation path or formally account for
the earlier hit and subsequent marker/return behavior.

The narrow next constructive goal is a well-formed full-configuration
invariant including source program, current source state, M=6 marker,
data tape and the two-sided q15--q22 scan regions. Establish a concrete
right/left transition for an arbitrary matching encoded row under that
invariant, then prove invariant preservation and nonpremature halting.
The arbitrary-width bridge and relocation obstruction passed independent
`coqc`/`coqchk` on `main`, including
[full bridge run 43803517428](https://github.com/shemshallah/NaNLMind/actions/runs/43803517428).

The added `q16_restores_wide_program` and
`q19_wide_program_first_restored_bit` prove more than failure of the naive
scan: after q16, every source description symbol is restored, and literal
q19 crosses the safe direction prefix, marker 7, and X=4 before marking the
FIRST raw program bit as M=6 and entering q17 or q18. For width `p>0` this
is the first current-state bit; for `p=0` it is the read bit. The remaining
program and external suffix are exact. The theorem has no arbitrary width
bound and requires only the stated safe q19 direction prefix. It does not
establish a source-instruction simulation or a complete representation
invariant. [Fast kernel check 43803517441](https://github.com/shemshallah/NaNLMind/actions/runs/43803517441) also
passed.

The subsequent `q15_q22_right_wide_program_first_hit` composition is also
checked by the independent `coqc`/`coqchk` workflow
[43806673314](https://github.com/shemshallah/NaNLMind/actions/runs/43806673314).
It starts at literal q15, executes the q16/q21–q22 direction decision,
then reaches the first marked program payload bit under a stated
full marked-program layout hypothesis. This identifies the precise
native collision, but does not discharge the full source-machine
representation, preservation, or progress obligations.

The newer `marked_wide_program_q15_entry_exists` and
`q15_q22_right_first_hit_constructive` construct that marked entry
orientation for *every nonempty encoded wide program*, including width
zero, and instantiate a literal q15 first-hit trace with a safe
direction-side cell `4`. The [full clean Coq bridge](https://github.com/shemshallah/NaNLMind/actions/runs/43808009051)
and [fast kernel check](https://github.com/shemshallah/NaNLMind/actions/runs/43808009005)
both passed for commit `c403c13`. These results establish nonvacuity of
the q15→q19 collision theorem, not a complete encoded-instruction
simulation. The full instruction-matching, writeback, source-state and
source-tape invariants, and nonpremature halting remain open.

The subsequent `q15_q22_right_collision_returns_q5` theorem follows that
constructed q15 entry all the way through the **literal** q17/q18 return
scan to q5. It identifies the exact terminal 2/3 bit mark and M=6
placement, preserves the remaining description and external tape frame,
and gives an exact finite microstep count independent of any fixed source
state width. The pinned [fast Coq kernel check](https://github.com/shemshallah/NaNLMind/actions/runs/43917169621)
and [independent full Coq rebuild](https://github.com/shemshallah/NaNLMind/actions/runs/43917169327)
passed at `c7062cb` on `main`.

**Reachability caveat:** the constructor supplies a valid q15 tape shape,
not a proof that the shape arises from the machine's canonical q5-start
encoding. The earlier q12/q13→q14→q15 theorem enters q15 with an X=4
as its nearest left symbol, whereas the constructed first-hit witness
starts with a raw binary symbol. Connecting the phases needs a different,
correctly framed q15 scan theorem; the latter constructed witness cannot
be silently substituted for an actual reached instruction phase. Neither
the source tape/head transition nor native halting reflection has been
proved by this collision cycle.

## November 15 native-compiler closure

The native NaN16 source-to-Minsky compiler track is complete for its declared
finite-window contract:

- `mth/tests/mth_minsky_compiler_test.nas`: two-bit-state regression;
- `mth/tests/mth_minsky_compiler_general_test.nas`: p=9, three transitions,
  input `1101`, initial condition q0/read1, both head directions;
- `mth/tests/mth_minsky_compiler_p16_test.nas`: p=16 state fields and
  35-bit source records.

All three are raw NaN16 programs, are driven only by assembled guest images, and
pass the publication gate.  `formal/utm/MinskyWideFixture.v` and `MinskyP16Fixture.v` are kernel-checked
traces of the p=9 (`run 9277`, 94 cells) and p=16 (`run 11603`, 104 cells)
images, cross-checked against the native expected arrays by
`formal/utm/check_minsky_wide_fixture.py`.

This closes the native compiler/execution obligation for the committed finite
fixtures.  It does **not** close the central formal theorem: the full
table-executed instruction macro and arbitrary-source universality remain open,
and no ledger row above should be promoted to a universality claim.

## November 15 marked-description representation increment

The candidate `MinskyMarkedProgram.v` formalizes a first nontrivial
representation invariant for the unchanged transition table. During the
native state-5 left scan, source-bit `0` is overwritten by `2` and `1`
by `3`; the `4` instruction separator stays in place. A logical erasure
`2→0, 3→1` recovers the complete encoded source program, not only the
first row. Its concrete scan theorem uses `MinskyTable.run` and states
the final state, left delimiter, fully decoded program, unchanged external
suffix, and nonhalting status for every finite width and well-formed
list of source rows. It explicitly requires the actual reversed zipper
entry layout. This is a **candidate pending CI coqc/coqchk**, not yet a
kernel-certified theorem.

This invariant describes the *program region only*. It does not yet
model the `M` head marker, source tape/control state, or subsequent
native scans that may rewrite additional program/control symbols. The
complete `Rep(M,c,N)` relation and source-step commuting diagram remain
open. An erasure of program marks cannot substitute for those obligations.

## November 16 constructed q12-to-q5 collision and source-neighbour mismatch

The following theorems are **kernel-checked with the frozen 23-state ×
8-symbol transition table** at
[commit `40a591b`](https://github.com/shemshallah/NaNLMind/commit/40a591b78a78710752f3bf1ffc24fb6b7492c539),
[fast Coq run `43976450108`](https://github.com/shemshallah/NaNLMind/actions/runs/43976450108).
The separate clean full rebuild is still tracked as an independent gate.

- `q12_right_marked_program_collision_at_q5` starts at an **explicit actual
  q12 configuration** containing a q5-marked encoded wide program and runs
  through q14, q15, q16, q21/q22, q19, q17/q18, and back to q5.
  It discharges the relevant scan premises from structural facts about
  arbitrary-width encoded rows and gives the exact final zipper and
  microstep count for every nonempty program. No source-level macro-step
  assumption is invoked.
- `q12_right_marked_program_target_mismatch` shows that when the first
  restored *program* payload bit differs from the intended right-hand
  *data* neighbour, the returned q5 2/3 marker differs from that
  neighbour's marker. `nine_bit_right_program_neighbor_mismatch` exhibits
  this distinction at width nine (program first bit 0, neighbour bit 1).
  The target comparison is with the neighbour, **not** with the
  source instruction's `wr_write` field, which has a different role.

The stronger `q12_right_marked_program_unavoidable_bad_neighbor`
constructively chooses `next := negb (wide_first_payload_bit row)` **for
any encoded program**, so a differing q5 marker is unavoidable for some
right-hand neighbour on this specific tape layout. It is certified by
[fast Coq run `43978028946`](https://github.com/shemshallah/NaNLMind/actions/runs/43978028946)
at [commit `404e1b6`](https://github.com/shemshallah/NaNLMind/commit/404e1b603656fbc7d2ae66408a1d213061c14438).
The independent clean rebuild remains a separate confirmation gate.

**Precise remaining boundary:** This is a constructive q12-entry execution,
not a proof of reachability of its entry from the canonical full source
configuration in native q5. It refutes the naive assumption that q19 can
cross the *restored marked-program region* unchanged; it does not prove
that this is the only possible encoding, rule out universality, or discharge
the three conditional `MinskyWideMacroSimulation.v` premises.

Next required proof: (1) derive the source-level q12/q13 entry from a
computable complete q5 representation, (2) show correct source-row
selection, write and head relocation under that representation, (3) prove
the representation invariant persists under all source steps, and
(4) prove both directions of halting reflection.

## November 17 guarded right-rail action boundary (kernel-checked)

The guarded q12->q5->q6 placement was introduced to avoid q19 crossing a
q5-marked program on the right.  The literal-table composition now covers
the q6 action phase, the q7/q8 return, the q9/q10 writeback entry, and the
second q12/q13 direction entry:

- `q12_roundtrip_no_raw_suffix_stalls_q6`: if the q6 return frame has no
  raw 0/1 suffix, q6 remains the state for every further fuel.
- `q6_guarded_rail_to_q7_or_q8`: q6 crosses the rail, marks the first raw
  bit 2/3, and enters q7/q8; exact clock `length scanned + 3`.
- `q78_scan_back_to_first_five` and
  `q78_returned_vault_to_q9_or_q10`: q7/q8 return to the first Y=5 and
  q9/q10 re-enter with the exact preserved frame; exact clock
  `length scanned + 5`.
- `q910_restored_four_to_q12_or_q13`: the next two literal transitions
  stop on the route 4 and turn back into q12/q13, leaving M=6 and the
  marked region on the **right** of the head.
- `q6_complete_return_to_q12_or_q13`: complete q6 -> q12/q13 return with
  exact clock `2 * length scanned + 10`.
- `q12_complete_return_into_six_free_vault`: complete
  q12 -> q6 -> q7/q8 -> q9/q10 -> q12/q13 cycle with exact clock
  `6 * length scanned + 32`, preserving the stored wide program verbatim.
- `q12_complete_vault_cycle_cannot_resume`: for any additional fuel, the
  state remains 12 or 13 because the left frontier
  `5 :: 0 :: encode_wide_program rows` is 6-free.

The guarded right-rail placement is consequently **not a complete
instruction cycle**.  It avoids the q19/program collision for the movement
half-cycle but destroys the left-accessible M=6 required by the next
direction phase.  A complete encoding must keep the canonical left-data /
right-program orientation and make q19 avoid the program by construction,
or keep a left-accessible 6 marker between Y and the route 4.  See
[`GUARDED_VAULT_BOUNDARY.md`](GUARDED_VAULT_BOUNDARY.md).

The fast Coq job
[44147774350](https://github.com/shemshallah/NaNLMind/actions/runs/44147774350)
passed `coqc` and `coqchk`, and the independent full bridge
[44147774314](https://github.com/shemshallah/NaNLMind/actions/runs/44147774314)
rebuilt the dependency chain and checked the cycle at `58e7eb1`.  No
source-step simulation, canonical q5 reachability, or universality claim
is added.

### Next critical path after the guarded boundary

1. Define the canonical full-configuration invariant: left data tape, M=6,
   t-buffer, Y, condition, program rows, Y, tail.
2. Prove the q5 left scan and the q1 all-match comparison reach q6 for the
   selected row, including the mismatch restart loop.
3. Prove q6-q11 writeback and q12-q22 relocation preserve the invariant,
   with q19 confined to the data/t-buffer region rather than the program.
4. Lift to arbitrary finite source runs and prove both directions of
   halting reflection.
5. Separately construct the reduction from a reference universal machine
   into the source model, or an equivalent certified universality theorem
   for that model.

## November 17 canonical q5 match to q6 (kernel-checked)

The first canonical-layout phase theorem is now checked for the frozen
23x8 table.  It starts at the native compiler's q5 entry with the source
condition left of Y=5 and the record prefix right of X=4, and reaches the
literal q6 action-copy entry.

- `wide_mark` extends the q0/q4 comparison alphabet to `{2,3,4,6,7}`.
  This lets the record delimiter X=4 sit inside the already-marked prefix
  while keeping Y=5 as the terminating left delimiter.
- `wide_mark_scans`, `q1_zero_match_with_wide_marks`,
  `q1_one_match_with_wide_marks`, `q1_match_one_bit_with_wide_marks`,
  `q1_all_matching_bits_wide`, and `q1_all_matching_bits_wide_four` lift
  the comparison macros to the extended alphabet.
- `canonical_q5_scan` runs the q5 left scan over the condition to Y=5 and
  returns q1 with the condition marked `2/3`, in exact `|bits| + 2` steps.
- `canonical_q5_match_to_q6` composes the q5 scan, the q1 all-match
  comparison against the record's current-state/read prefix, and the final
  q1 crossing of X=4.  The exact clock is

  ```text
  (|bits| + 2) + (matched_comparison_steps bits 0 1 + (|bits| + 1))
  ```

  and the result is

  ```text
  entry_config 6
    (4 :: rev (map match_raw bits) ++ 5 :: rev t-buffer ++ 6 :: rev data)
    (map match_mark bits ++ tail).
  ```

  The condition is restored raw, the record prefix is marked, and the
  data tape, M=6, t-buffer, Y=5, and program tail are untouched.

The fast Coq job
[44167307045](https://github.com/shemshallah/NaNLMind/actions/runs/44167307045)
passed `coqc` and `coqchk`, and the independent full bridge
[44167314930](https://github.com/shemshallah/NaNLMind/actions/runs/44167314930)
rebuilt the dependency chain and checked the module.  See
[`CANONICAL_Q5_MATCH.md`](CANONICAL_Q5_MATCH.md).

This closes only the first canonical phase.  The theorem assumes a matching
condition/record prefix and stops at q6.  Mismatch/restart, source-row
selection, q6 action copy, q9/q10 writeback, q12-q22 movement, and halting
reflection remain open.  The q6 entry begins with `map match_mark bits ++
tail`; the X/Y delimiters in `tail` must be handled explicitly before the
existing action macros can be composed.

## November 17 canonical q6-q11 first-bit copy cycle (kernel-checked)

After `canonical_q5_match_to_q6`, the first canonical copy cycle is now
checked for the frozen 23x8 table.  Write the condition as `c :: bits'`.

- `q6_canonical_scan_zero_to_q10` and
  `q6_canonical_scan_one_to_q9`: q6 scans the marked comparison prefix to
  the first raw record bit, marks it 2/3, and q8/q7 return to the first
  Y=5.  The exact scan clock is

  ```text
  S (length (map match_mark bits))
  + S (length (rev (map match_mark bits) ++ [4] ++ rev (map match_raw bits)))
  ```

- `canonical_q6_copy_zero_to_q6` and `canonical_q6_copy_one_to_q6`:
  q10/q9 write the copied mark into the first raw condition bit, move it to
  the left of Y, and q11 returns over the remaining raw condition bits and
  X=4 to q6.  The complete cycle has clock

  ```text
  (S |region| + S |scan|) + (1 + S |bits'|) = 4 * length bits + 4
  ```

  and result

  ```text
  entry_config 6
    (4 :: rev (map source_bit bits') ++ 2/3 :: 5 ::
     rev t-buffer ++ 6 :: rev data)
    (map match_mark bits ++ [2/3] ++ rest).
  ```

  The first condition bit is moved left of Y, the first record bit stays
  marked, the remaining condition bits stay raw, and the data tape,
  t-buffer, M=6 and Y=5 are untouched.

The fast job
[44182091042](https://github.com/shemshallah/NaNLMind/actions/runs/44182091042)
and the independent full bridge
[44182096988](https://github.com/shemshallah/NaNLMind/actions/runs/44182096988)
passed `coqc` and `coqchk`.  See
[`CANONICAL_COPY_CYCLE.md`](CANONICAL_COPY_CYCLE.md).

This is one cycle, not an induction.  Source-row selection, mismatch
restart, the write/direction fields, q12-q22 relocation, halting reflection,
and the universality reduction remain open.

## November 17 generalized canonical copy cycles (kernel-checked)

The single-cycle module was generalized to an arbitrary already-processed
condition prefix and an arbitrary marked record prefix:

- `canonical_q6_copy_zero_general` and
  `canonical_q6_copy_one_general` consume the next condition bit and the
  next raw record bit, move the condition bit left of Y, and append the
  copied record mark to the marked region.
- The invariant is

  ```text
  left  = 4 :: rev (map source_bit (c :: bits')) ++ processed ++
          5 :: rev t-buffer ++ 6 :: rev data
  right = region ++ 0/1 :: record_tail
  ```

  with `Forall q7_pass processed`, `Forall q9_pass processed`,
  `Forall q6_pass region`, and `Forall q7_pass region`.
- The exact clock is

  ```text
  S (length region)
  + S (length (rev region ++ [4] ++ rev (map source_bit (c :: bits')) ++ processed))
  + S (length processed)
  + S (length bits').
  ```

The fast job
[44202204105](https://github.com/shemshallah/NaNLMind/actions/runs/44202204105)
and the independent full bridge
[44202554008](https://github.com/shemshallah/NaNLMind/actions/runs/44202554008)
passed `coqc` and `coqchk`.  See
[`CANONICAL_COPY_GENERAL.md`](CANONICAL_COPY_GENERAL.md).

This is still one cycle, now with the induction-ready invariant.  The
induction over all condition bits, the write/direction fields, q12-q22
relocation, halting reflection, and the universality reduction remain open.

## November 18 all-condition canonical copy induction (kernel-checked)

Accepted on `main` at `2fe2425` by the fast q15-q22 job
[44234713900](https://github.com/shemshallah/NaNLMind/actions/runs/44234713900),
the independent full Minsky bridge
[44234713887](https://github.com/shemshallah/NaNLMind/actions/runs/44234713887),
the mechanized UTM job
[44234714060](https://github.com/shemshallah/NaNLMind/actions/runs/44234714060),
and `ci`.

`canonical_q6_copy_all` now closes the induction over the condition bits.
For condition bits and record bits of equal length it proves

```text
run (copy_all_clock bits record_bits processed region)
  (entry_config 6 left right) =
  entry_config 6
    (4 :: rev (map match_mark record_bits) ++ processed ++
     5 :: rev t-buffer ++ 6 :: rev data)
    (region ++ map match_mark record_bits ++ record_tail)
```

under the canonical shape premises for `left` and `right`.  Every condition
bit is consumed, the corresponding record bits are marked and appended to
`region`, and the result is the fully consumed condition frame.

The proof parameterizes the theorem over the whole left and right tape
lists, so the recursive IH matches each cycle output by construction; the
append/snoc witness is `region_snoc_cons`.  This is one source-state-copy
phase, not a source-step theorem.  The write/direction fields, q12-q22
relocation, the return to q5, halting reflection, and the universality
reduction remain open.

## November 18 canonical direction-bit capture (kernel-checked)

After the all-condition copy induction, the next phase captures the raw
direction bit:

- `q9_scan_marked_to_q12` and `q10_scan_marked_to_q13` scan a marked prefix
  to X=4 and enter q12/q13 with the correct `cfg_ml` head placement.
- `q8_reversed_frame` normalizes the q7/q8-reversed frame
  `((record_marks ++ [4]) ++ marked) ++ x :: tail` to
  `record_marks ++ 4 :: marked ++ x :: tail`.
- `canonical_q6_direction_capture` runs q6 over the marked region to the
  raw direction bit, returns via q7/q8, and enters q12 (direction 1) or q13
  (direction 0), with the clock

  ```text
  S |marked|
  + S |rev marked ++ [4] ++ rev record_marks|
  + S |record_marks|.
  ```

The fast job
[44376789679](https://github.com/shemshallah/NaNLMind/actions/runs/44376789679)
passed `coqc` and `coqchk`.  The full bridge is
[44377481394](https://github.com/shemshallah/NaNLMind/actions/runs/44377481394).

This is direction capture only.  q12-q22 relocation, the source write/head
transition, halting reflection, and the universality reduction remain open.

## November 18 canonical q12/q13 restore to q15 (kernel-checked)

The direction-capture frame is decomposed as `left = s :: remaining` so
`cfg_ml` exposes its head.  q12/q13 then scan left to M=6 and q14 restores
the marked cells rightward to X=4:

- `rev_restore_scan` normalizes the q12/q13 output reversal.
- `canonical_q12_restore_to_q15` and `canonical_q13_restore_to_q15` have
  clock

  ```text
  S |s :: remaining ++ 5 :: rev t-buffer|
  + S |t-buffer ++ [5] ++ rev remaining ++ [s]|
  ```

  and end at

  ```text
  entry_config 15
    (4 :: map q14_restore
      (rev (t-buffer ++ [5] ++ rev remaining ++ [s])) ++ 3/2 :: rev data)
    (marked ++ 2/3 :: record_tail).
  ```

The fast job
[44387137354](https://github.com/shemshallah/NaNLMind/actions/runs/44387137354)
passed `coqc` and `coqchk`.  The full bridge is
[44387853435](https://github.com/shemshallah/NaNLMind/actions/runs/44387853435).

This is a macro phase.  q15/q16 raw-bit search, q21/q22 decision, q19/q20
relocation, q17/q18 return, the source write/head transition, halting
reflection, and the universality reduction remain open.

## November 18 canonical decision, relocation and q5 return (kernel-checked)

The restore phase now continues through q15/q16, q21/q22 and, under
explicit safety premises, q19/q20 and q17/q18 back to q5.
`MinskyCanonicalDecision.v` contains:

- `canonical_restore_q12_q15_capture` and
  `canonical_restore_q13_q15_capture`: the restore clock plus
  `S |marked ++ [2/3]|` reaches the q16 cursor

  ```text
  cfg_ml 16
    (rev (marked ++ [m]) ++ 4 ::
     map q14_restore (rev T) ++ 3/2 :: rev data)
    (source_bit bit :: tail).
  ```

- `canonical_restore_q16_decision`: q16 scans the backscan and X=4,
  restores `2->0` / `3->1`, writes 7 at the raw cell behind X=4 and
  selects q21 (bit 0) or q22 (bit 1).

- `canonical_q12_restore_to_q16_decision` and
  `canonical_q13_restore_to_q16_decision`: since the canonical last
  record mark is `match_mark b`, `q14_restore` exposes exactly
  `source_bit b`, so the restore joins the decision phase without an
  extra structural premise.

- `canonical_q16_decision_to_q19` and `canonical_q16_decision_to_q20`:
  q21/q22 scan the restored direction block to the stored 3/2 marker and
  enter q19 (right) or q20 (left).

- `canonical_q16_decision_right_to_q5`: q19 displaces the next raw cell
  by 6 and q17/q18 return to a following 7 in q5, with exact clock.

- `canonical_q16_decision_left_to_q5`: q20 steps onto the left target
  raw cell, writes 6, and q17/q18 scan back to the 7 left by q16,
  returning to q5.

Verification: restore corollaries fast
[44400890924](https://github.com/shemshallah/NaNLMind/actions/runs/44400890924)
and bridge
[44402415039](https://github.com/shemshallah/NaNLMind/actions/runs/44402415039);
q16 decision and q19/q20 fast
[44405460764](https://github.com/shemshallah/NaNLMind/actions/runs/44405460764)
and bridge
[44405995495](https://github.com/shemshallah/NaNLMind/actions/runs/44405995495);
q19/q20-to-q5 fast
[44406270655](https://github.com/shemshallah/NaNLMind/actions/runs/44406270655);
restore-to-decision fast
[44408127139](https://github.com/shemshallah/NaNLMind/actions/runs/44408127139)
and full bridge
[44408794555](https://github.com/shemshallah/NaNLMind/actions/runs/44408794555)
on accepted commit `f1798b4`.

Scope: these are exact native macro compositions with explicit
passability/safety hypotheses.  The right q19 relocation requires the
restored scan to be entirely q15-passable; the left branch requires the
q17 return rail to be q17-passable.  The raw canonical layout restores
2/3 marks to 0/1, so the documented premature-raw-capture obstruction
still applies.  Discharging these side conditions requires the tagged
6/7 control channel documented above.  No single source step, halting
reflection, or universality claim is made here.

## November 18 canonical fetch: match, copy and direction capture (kernel-checked)

`MinskyCanonicalFetch.v` is the first theorem that joins three canonical
phases into one exact native clock:

1. `canonical_q5_match_to_q6`,
2. `canonical_q6_copy_all` over the next-state/write action field,
3. `canonical_q6_direction_capture`.

For condition bits `condition`, action bits `action` of equal length,
and direction bit `dir`, the literal q5 entry

```text
left  = rev (map source_bit condition) ++ 5 :: rev t-buffer ++ 6 :: rev data
right = 4 :: map source_bit condition ++ map source_bit action ++
        source_bit dir :: tail
```

runs to

```text
cfg_ml (if dir then 12 else 13)
  (rev (map match_mark action) ++ 5 :: rev t-buffer ++ 6 :: rev data)
  (4 :: ((map match_mark condition ++ map match_mark action) ++
         ((if dir then 3 else 2) :: tail))).
```

The clock is the literal sum of the q5-match clock, the
`copy_all_clock condition action [] (map match_mark condition)` clock,
and the q9/q10 direction clock.  All `Forall` premises are derived from
the record marks being `2/3`; the theorem adds no passability premise.

Verification: fast q15-q22 job
[44417282186](https://github.com/shemshallah/NaNLMind/actions/runs/44417282186)
on `ea2ae34`; full bridge
[44417941360](https://github.com/shemshallah/NaNLMind/actions/runs/44417941360)
passed on the same commit.

Scope: one record fetch/decode/capture.  It stops at q12/q13 before
restore, q15/q16, q21/q22, writeback, relocation or any source step.
The raw-control ordering obstruction and the tagged control channel
remain open, as do halting reflection and universality.

Next: generalize the q15 capture so its scan may cross the next record's
`X=4` and passable prefix, then compose this fetch result with
`canonical_q12_restore_to_q16_decision`.

## November 18 canonical direction-mark correction and next-record decision

While composing the fetch theorem with the restore/decision phase, the
native q9/q10 pairing was rechecked against the direction-capture proof:
direction 1 runs q9 and enters **q12 with right mark 3**; direction 0 runs
q10 and enters **q13 with right mark 2**.  Earlier canonical restore
statements paired q12 with 2 and q13 with 3, a valid table layout but not
the frame produced by direction capture.

Corrections, all kernel-checked:

- `canonical_q12_restore_to_q15_mark` and
  `canonical_q13_restore_to_q15_mark` keep the carried right-hand mark
  abstract.
- `canonical_restore_q12_q15_capture` now scans `marked ++ [3]` (q12),
  `canonical_restore_q13_q15_capture` scans `marked ++ [2]` (q13).
- `canonical_q12_restore_to_q16_decision` uses q16 pass mark 3 and
  trailing marker 3; the q13 version uses mark 2 and trailing 2.
- `canonical_q12_restore_q16_decision_next` and
  `canonical_q13_restore_q16_decision_next` extend the q15 scan across
  the next record's `X=4` to its first raw current bit, then apply q16.
  The q16 backscan is `4 :: rev (marked ++ [mark]) ++ [4]`, with the
  next-record `4` as the first scanned cell.

Verification: fast q15-q22 job
[44423162268](https://github.com/shemshallah/NaNLMind/actions/runs/44423162268)
on `6c6687e`; full bridge
[44423793848](https://github.com/shemshallah/NaNLMind/actions/runs/44423793848)
was dispatched on the corrected commit.

This correction is a frame-pairing fix, not a new negative result.  The
raw-control ordering obstruction and the tagged 6/7 control channel are
unchanged.  No source-step, halting, or universality claim is made.

## November 19 canonical instruction: q5 through q16 decision

`MinskyCanonicalInstruction.v` composes the canonical phases into one
exact native run:

```text
q5 match -> q6 action copy -> q9/q10 direction capture
-> q12/q13 restore -> q15 across the next X=4 -> q16 decision.
```

Entry: condition `bits`, action `action_init ++ [b]`, direction `dir`,
next record `X=4` and first raw bit.  Hypotheses are the action/condition
length equality and `Forall q12_pass`/`Forall q14_pass` on the t-buffer.

`canonical_q5_fetch_to_q16_decision` ends at

```text
cfg_ml (if b then 22 else 21)
  (map q14_restore
    (rev (map match_mark action_init) ++ 5 :: rev t-buffer) ++
   (if dir then 3 else 2) :: rev data)
  (7 :: map q16_restore
    (rev (4 :: rev
      (instruction_marked bits (action_init ++ [b]) ++
       [(if dir then 3 else 2)]) ++ [4])) ++
   source_bit bit :: tail).
```

The clock is the literal sum of `fetch_clock`, `direction_clock`,
`restore_clock`, the q15 scan across the next `X=4`, and the q16
backscan.  The direction pairing is now the native one: q12 with mark 3
(right) and q13 with mark 2 (left).

Verification: fast q15-q22 job
[44429121196](https://github.com/shemshallah/NaNLMind/actions/runs/44429121196)
on `1bfeb07`; full bridge
[44429619546](https://github.com/shemshallah/NaNLMind/actions/runs/44429619546)
passed on the same commit.

Scope: one instruction fetch/decode/action-copy/direction/restore/decision
macro.  q19/q20 relocation, q17/q18 return, the whole-source invariant,
the raw-control ordering fix, halting reflection and universality remain
open.  The documented premature-raw-capture obstruction is unchanged.

## November 19 canonical instruction to q19/q20

Two corollaries extend `canonical_q5_fetch_to_q16_decision` through the
q21/q22 decision:

- `canonical_q5_instruction_to_q19` (direction true, marker 3) ends at
  `entry_config 19 (source_bit b :: rev data)` with right tape
  `rev D ++ 7 :: map q16_restore (...next X=4...) ++ source_bit bit :: tail`.
- `canonical_q5_instruction_to_q20` (direction false, marker 2) ends at
  the corresponding `cfg_ml 20 (rev data)` frame.

Here `D` is the restored action block
`map q14_restore (rev action_marks ++ 5 :: rev t-buffer)`.  The q21/q22
scan costs exactly `S |D|`; `Forall q21_pass D` is derived from
`Forall q14_pass t-buffer`.

Verification: fast q15-q22 job
[44444802328](https://github.com/shemshallah/NaNLMind/actions/runs/44444802328)
on `6da196c`; full bridge
[44445252575](https://github.com/shemshallah/NaNLMind/actions/runs/44445252575)
was dispatched on the same commit.

Critical scope: the q19 right tape begins with the restored action block
`rev D`, which normally contains restored `0/1` cells.  The native q19
scan therefore captures the first restored control bit, not the intended
target.  This is the same premature-raw-capture obstruction documented
for the wide layout.  These theorems certify reachability of the
relocation phase; they do not certify a correct source head move.  The
tagged 6/7 control channel, whole-source invariant, halting reflection
and universality remain open.

## November 19 canonical q19 collision (kernel-checked)

`canonical_q5_instruction_q19_hits_restored_raw` proves the canonical
premature-raw capture.  Given the q5 instruction entry and a restored
action block

```text
D = map q14_restore
      (rev (map match_mark action_init) ++ 5 :: rev t-buffer)
```

that contains a raw `0/1` cell, the first-raw decomposition

```text
rev D = pre ++ source_bit hit :: post,  Forall q15_pass pre
```

gives a literal q19 run to

```text
entry_config (if hit then 18 else 17)
  (6 :: rev pre ++ source_bit b :: rev data)
  (post ++ 7 :: q16-backscan ++ source_bit bit :: tail)
```

with clock `instruction_q19_clock + S |pre|`.  The displaced-head
marker 6 is therefore written inside the restored action block, before
the 7 left by q16 and before the intended next raw record bit.

Supporting lemmas: `raw_or_pass`, `q14_restore_raw_or_pass`,
`Forall_map_q14_restore_raw`, `Forall_map_source_bit_raw`,
`first_raw_decomp`, `rev_restored_action_block`.

Verification: fast q15-q22 job
[44451052559](https://github.com/shemshallah/NaNLMind/actions/runs/44451052559)
on `9e4b846`; full bridge
[44453858351](https://github.com/shemshallah/NaNLMind/actions/runs/44453858351)
passed on the clean branch `proof/canonical-collision` at the same commit.

This is a negative result for the raw canonical layout.  It does not
prove non-universality of the frozen table; the tagged 6/7 control
channel remains the repair path.  Whole-source invariants, halting
reflection and universality remain open.

Bridge note: the clean branch `proof/canonical-collision` at `9e4b846`
passed the full rebuild in
[44453858351](https://github.com/shemshallah/NaNLMind/actions/runs/44453858351).
A later bridge run on `main` (`44451499362`) failed inside the
concurrently edited `MinskyDirectionRelocationCycle.v`; the canonical
instruction module compiled successfully before that point and its own
fast job passed.

### Unconditional form for nonempty action prefixes

`canonical_q5_instruction_q19_hits_restored_raw_nonempty` removes the
explicit raw-cell premise when `action_init <> []`, using
`rev_restored_action_block_has_raw`.  For state width `p >= 1`, the
action field has at least two bits, so `action_init` is nonempty and the
q19 collision is unconditional.  Verified by the fast job
[44457362683](https://github.com/shemshallah/NaNLMind/actions/runs/44457362683);
clean-branch bridge
[44457825847](https://github.com/shemshallah/NaNLMind/actions/runs/44457825847)
was dispatched on the same commit.

### Left-branch canonical obstruction (kernel-checked)

`canonical_q5_instruction_left_branch_hits_current_cell`: if
`rev data = source_bit d :: rev data'`, the canonical q20 entry performs
its raw step immediately and writes 6 on the current source cell:

```text
run (instruction_q20_clock + 1) (q5 instruction entry with direction false)
= entry_config (if d then 18 else 17)
    (6 :: rev data')
    (source_bit b :: rev D ++ 7 :: q16-backscan ++ source_bit bit :: tail).
```

The reason is the explicit `q20_scan_to_m` premise
`Forall q15_pass (s :: remaining)`; raw source bits are not q15-passable.
Together with the q19 collision this closes the raw canonical layout in
both directions.

Fast job [44564743286](https://github.com/shemshallah/NaNLMind/actions/runs/44564743286);
clean-branch bridge
[44565693705](https://github.com/shemshallah/NaNLMind/actions/runs/44565693705)
passed on the same commit; main
[700e702](https://github.com/shemshallah/NaNLMind/commit/700e702) passed
the full bridge, mechanized UTM and CI jobs.

## November 19 tagged-source plan and left-buffer interface gap

`TAGGED_SOURCE_PLAN.md` fixes the remaining construction:

1. left buffered tagged cycle (analogue of the verified right one),
2. normalization of q3/q2 outputs back to the tagged q15 interface,
3. source-step correspondence and halt reflection,
4. tape invariant via the address-space bisimulation.

The left analogue is blocked by an exact interface fact.  The left
relocation result is

```text
cfg_ml 5
  (dirs ++ source_bit old :: 6 :: outer)
  ((if target then 3 else 2) :: rev tags ++ source_bit next :: suffix).
```

After `cfg_ml`, if the left head is the required `6`, the immediate right
head is the raw delimiter `source_bit old` (0/1), not the buffered gate
symbol `2`.  If the raw delimiter is kept in the left tape instead, it
sits between the gate `6` and the tag rail and breaks the
`6 :: map tag rail` shape.  This is the same class of obstruction as
`q5_relocation_mark_cannot_directly_supply_six_gate`, now on the left
arrival.

The documented repair direction is the sacrificial raw bit plus protected
`5` delimiter from the obstruction package.  The left cycle is now
implemented:

- `q15_left_false_guard_native_tagged_target_dispatch` (21 literal
  steps, q15 -> q2/q3),
- `q15_left_buffer_guard_correct_iff_false` (the false guard is
  necessary and sufficient),
- `q15_left_true_guard_reverses_target_dispatch` (the true guard sends
  the dispatch to the opposite q2/q3 state).

Reentry and halt hooks are literal table facts:
`q3_at_marker_step` (q3 on X=4 enters q5) and `q3_five_halts`
(q3 on Y=5 halts, kernel-checked as a c_halted consequence).
The remaining work is the source encoder, the q2/q3 match reentry, the
tape invariant, and macro-step/halt instantiation.

A literal table check pins the left gate:
`canonical_left_gate_branches_on_old_bit` proves

```text
q1 on entry_rewrite (source_bit old):
  old = false -> q0 (mark 2)
  old = true  -> q4 (mark 3).
```

Thus the left buffered cycle must route a controlled sacrificial **false**
bit into the q1 stopper; the raw old delimiter cannot be arbitrary.  This
is a concrete layout obligation for the source encoder.  Fast job
[44572270162](https://github.com/shemshallah/NaNLMind/actions/runs/44572270162)
passed; clean-branch bridge
[44573000067](https://github.com/shemshallah/NaNLMind/actions/runs/44573000067)
was dispatched on the same commit.  No universality claim is made.

## November 19 tagged halt macro (kernel-checked)

The frozen table has a single halting transition: q3 on Y=5.
`MinskyTaggedHalt.v` proves the native halt macro from the tagged left
cycle:

- `q3_scan_to_five_halts`: q3 scans any `q3_halt_pass` list
  (`0,1,2,3,6,7`) to `5` and halts.
- `q15_left_false_guard_halt`: from

  ```text
  entry_config 15
    (source_bit old :: 6 :: 5 :: 2 :: source_bit false :: outer)
    (tag next :: tag extra :: source_bit true ::
     scanned ++ 5 :: tail)
  ```

  with `Forall q3_halt_pass scanned`, the machine halts in
  `21 + S |scanned|` native steps.

Verification: fast q15-q22 job
[44587415568](https://github.com/shemshallah/NaNLMind/actions/runs/44587415568)
on `49f629f`; clean-branch bridge
[44588286392](https://github.com/shemshallah/NaNLMind/actions/runs/44588286392)
was dispatched on the same commit.

This is a halt macro, not yet source halting reflection: the encoder must
select this target=true/end-marker path exactly when the source lookup
fails.  The match/copy integration, source encoder, tape invariant and
universality reduction remain open.

## November 19 symbol-collision constraint for the tagged encoder

The canonical restore scan cannot carry pre-existing 6-valued control
tags.  Literal table facts:

- `q12_six_exits_to_q14`: q12 on 6 writes 3 and enters q14.
- `q13_six_exits_to_q14`: q13 on 6 writes 2 and enters q14.

Thus 6 is the M delimiter, not a passable tag, in the q12/q13 phase.
Any tagged source encoding must introduce 6 tags after q12/q14 (the
movement phase writes 6 at q19/q20 and 7 at q16), or keep them outside
the q12/q14 scan window.  This is a concrete constraint on the still-open
source/match integration.

Verification: fast q15-q22 job
[44590892654](https://github.com/shemshallah/NaNLMind/actions/runs/44590892654)
on `096c55e`; clean-branch bridge
[44591572127](https://github.com/shemshallah/NaNLMind/actions/runs/44591572127)
was dispatched on the same commit.

### 4-prefix bridge candidate

The canonical q14 frame and the tagged q15 frame differ by a leading
`4` on the left tape.  Because 4 is passable in q15/q16/q19/q21 and is
fixed by q16_restore, the q16 backscan can absorb it as an extra scanned
cell before the raw delimiter.  This gives a concrete bridge direction:
generalize the tagged roundtrip with a q16-pass prefix.  The prefix may
also serve as the natural X=4 reentry to q6 for the next instruction.
No theorem is claimed yet; the checkpoint statement is recorded in
`TAGGED_SOURCE_PLAN.md`.

## November 19 4-prefix bridge checkpoint (kernel-checked)

`q15_q16_four_prefix_roundtrip` proves that the canonical q14 leading
`4` can be absorbed by the q16 backscan:

```text
run (S |rev tags| + S |rev tags ++ [4]|)
  (entry_config 15 (4 :: source_bit old :: left)
    (rev tags ++ source_bit target :: suffix))
= cfg_ml (if old then 22 else 21) left
    (7 :: map q16_restore (rev (rev tags ++ [4])) ++
     source_bit target :: suffix).
```

`q1_four_to_q6` shows the loop-closing role of that `4`:

```text
step (entry_config 1 left (4 :: tail)) =
  entry_config 6 (4 :: left) tail.
```

q1 crosses X=4 into q6, the canonical action-copy entry, so the prefix
can be the next instruction's X marker rather than a gate failure.

Verification: fast q15-q22 job
[44603700043](https://github.com/shemshallah/NaNLMind/actions/runs/44603700043)
for the checkpoint and
[44606126358](https://github.com/shemshallah/NaNLMind/actions/runs/44606126358)
for `q1_four_to_q6`; clean-branch bridge
[44606044164](https://github.com/shemshallah/NaNLMind/actions/runs/44606044164).

### 4-prefix through q22 to q19 (kernel-checked)

`q15_q22_right_four_prefix_to_q19` composes the 4-prefix q15/q16 bridge
with the q21/q22 direction decision.  The result is

```text
entry_config 19 (source_bit old :: outer)
  (rev dirs ++ 7 :: 4 ::
   map q16_restore (rev tags) ++ source_bit target :: suffix).
```

The leading `4` is now inside the q16-restored map, after the `7` marker,
and is q19-passable.  It no longer prevents the relocation scan from
reaching the raw target.

Fast job
[44611737278](https://github.com/shemshallah/NaNLMind/actions/runs/44611737278)
on `c589061`; clean-branch bridge
[44612400386](https://github.com/shemshallah/NaNLMind/actions/runs/44612400386)
was dispatched on the same commit.

### 4-prefix right return to q5 (kernel-checked)

`q15_q22_right_four_prefix_relocates_to_q5` extends the 4-prefix bridge
through q19 and q17/q18 to q5:

```text
entry_config 15
  (4 :: source_bit old :: dirs ++ 3 :: outer)
  (rev tags ++ source_bit target :: between ++ 7 :: tail)
  -[q22 + q19/q17 clocks]->
cfg_ml 5
  (rev between ++ 6 :: rev scanned ++ source_bit old :: outer)
  ((if target then 3 else 2) :: tail)
```

with `scanned = rev dirs ++ 7 :: 4 :: map q16_restore (rev tags)`.
The `4` is passable through q19 and q17/q18; it does not prevent the
scan from reaching the raw target.  The result is the tagged-style q5
return with the 4 inside the rail.

Fast job
[44638637156](https://github.com/shemshallah/NaNLMind/actions/runs/44638637156)
on `0dbce41`; clean-branch bridge
[44639211057](https://github.com/shemshallah/NaNLMind/actions/runs/44639211057)
was dispatched on the same commit.

Next: q1 scans the 6/7 rail and `q1_four_to_q6` sends the 4 into q6.

### 4-prefix q5 to q1 rail (kernel-checked)

`q15_q22_right_four_prefix_q5_q1` composes the right return with the q5
rail scan to the 5 delimiter and returns q1:

```text
entry_config 1 (5 :: stored)
  (map entry_rewrite (rev rail) ++
   (if target then 3 else 2) :: tail)
```

with

```text
rail = rev between ++ 6 ::
       rev (rev dirs ++ 7 :: 4 :: map q16_restore (rev tags)) ++
       [source_bit old].
```

The q1 head is the rewritten old-bit mark (2/3), so q1 dispatches q0
or q4 — the canonical next-row match.  The `4` remains deeper in the
rail as the X marker leading to q6.  This is the loop structure, not a
gate failure.

Fast jobs
[44646932269](https://github.com/shemshallah/NaNLMind/actions/runs/44646932269)
on `490fb3f`; clean-branch bridge
[44647605903](https://github.com/shemshallah/NaNLMind/actions/runs/44647605903)
was dispatched on the same commit.

### q1 dispatch into q0/q4 (kernel-checked)

`q15_q22_right_four_prefix_q1_step` composes the q5->q1 rail with one
literal q1 transition:

```text
if old
then entry_config 4 (1 :: 5 :: stored) (rail_tail_map ++ mark :: tail)
else entry_config 0 (0 :: 5 :: stored) (rail_tail_map ++ mark :: tail)
```

with `rail_tail_map = map entry_rewrite (rev (rev between ++ 6 ::
rev (rev dirs ++ 7 :: 4 :: map q16_restore (rev tags))))`.

This is the canonical next-row match entry (q4/q0), with the 4-prefix
still in the rail for the q6 X crossing.

Fast job
[44654274670](https://github.com/shemshallah/NaNLMind/actions/runs/44654274670)
on `fedc78a`; clean-branch bridge
[44654879521](https://github.com/shemshallah/NaNLMind/actions/runs/44654879521)
was dispatched on the same commit.

### q0 target dispatch over the returned rail (kernel-checked)

`q0_right_rail_target_dispatch` composes the q0 rail scan with the
stable control pair and the raw target:

```text
run (|prefix ++ [mark]| + 3)
  (entry_config 0 (0 :: 5 :: stored)
    ((prefix ++ [mark]) ++ [tag c1; tag c2] ++
     source_bit read :: tail))
= if read then entry_config 3 (...) tail
  else cfg_ml 2 (...) (2 :: tail).
```

Fast job
[44658366863](https://github.com/shemshallah/NaNLMind/actions/runs/44658366863)
on `dc31664`; clean-branch bridge
[44658834726](https://github.com/shemshallah/NaNLMind/actions/runs/44658834726)
was dispatched on the same commit.

The q4 (`old = true`) mirrored target dispatch remains open.

### q4 mirrored target dispatch (kernel-checked)

`q4_right_rail_target_zero` and `q4_right_rail_target_one` are the q4
counterparts of the q0 target dispatch:

```text
target 0 -> entry_config 3 (2 :: rev rail ++ 1 :: 5 :: stored) tail
target 1 -> cfg_ml 2 (rev rail ++ 1 :: 5 :: stored) (3 :: tail)
```

Together with `q0_right_rail_target_dispatch`, both q1 direction branches
(`old=false -> q0`, `old=true -> q4`) now dispatch the raw read bit into
q3 or q2 with the literal mirrored table mapping.

Fast job
[44661141653](https://github.com/shemshallah/NaNLMind/actions/runs/44661141653)
on `3b98371`; clean-branch bridge
[44661627757](https://github.com/shemshallah/NaNLMind/actions/runs/44661627757)
was dispatched on the same commit.

### q2/q3 reentry scans (kernel-checked)

`q3_scan_to_q5` and `q2_rail_reenter_q1` lift the concrete-dispatch scan
lemmas to the returned rail/cfg frames:

```text
q3: entry_config 3 left (symbols ++ 4 :: suffix)
  -> cfg_ml 5 (rev symbols ++ left) (4 :: suffix)

q2: cfg_ml 2 (rail ++ mark :: 5 :: stored) right
  -> entry_config 1 (5 :: stored) (rev (rail ++ [mark]) ++ right)
```

Fast job
[44663570913](https://github.com/shemshallah/NaNLMind/actions/runs/44663570913)
on `22886a8`; clean-branch bridge
[44664054820](https://github.com/shemshallah/NaNLMind/actions/runs/44664054820)
was dispatched on the same commit.

### Target dispatch + q2/q3 reentry (kernel-checked)

Four branch theorems now compose the q1 direction decision, the raw
target dispatch, and the q2/q3 reentry:

```text
q0, read=1 -> q3 -> q5
q0, read=0 -> q2 -> q1
q4, read=0 -> q3 -> q5
q4, read=1 -> q2 -> q1
```

Theorems: `q0_rail_read_one_to_q5`, `q0_rail_read_zero_to_q1`,
`q4_rail_read_zero_to_q5`, `q4_rail_read_one_to_q1`.
The q0/q4 target mappings are the literal mirrored table behaviour; the
q3 and q2 scans use `dispatch_right_symbol` and `dispatch_left_symbol`
respectively, with exact clocks.

Fast job
[44672011694](https://github.com/shemshallah/NaNLMind/actions/runs/44672011694)
on `7ad5cb0`; clean-branch bridge
[44672468846](https://github.com/shemshallah/NaNLMind/actions/runs/44672468846)
was dispatched on the same commit.

### Full right loop q0/read-zero (kernel-checked)

`q15_right_loop_q0_read0` is the first complete right loop from the
tagged q15 movement entry back to q1:

```text
q15 -> q22 -> q19 -> q17/q18 -> q5 -> q1
-> q0 (old=false) -> q2 -> q1
```

The clock is the exact sum of `right_q1_step_clock` and the q0
read-zero target/reentry clock.  The result is the q1 frame

```text
entry_config 1 (5 :: stored)
  (0 :: ((right_rail_map ... ++ [right_mark target]) ++ [tag c1; tag c2]) ++
   2 :: symbols ++ 4 :: suffix).
```

Verified by fast jobs
[44753509463](https://github.com/shemshallah/NaNLMind/actions/runs/44753509463)
on `2577dac`; clean-branch bridge
[44755230591](https://github.com/shemshallah/NaNLMind/actions/runs/44755230591)
was dispatched on the same commit.

The remaining right-loop cases (q0/read-one, q4/read-zero,
q4/read-one) and the left branch are analogous compositions.

### All four right loops (kernel-checked)

With the q1-output conversion lemmas, the remaining right loops are
proved:

- `q15_right_loop_q0_read0` (q0, read 0 -> q2 -> q1),
- `q15_right_loop_q0_read1` (q0, read 1 -> q3 -> q5),
- `q15_right_loop_q4_read0` (q4, read 0 -> q3 -> q5),
- `q15_right_loop_q4_read1` (q4, read 1 -> q2 -> q1).

Each starts at the canonical 4-prefixed q15 entry and returns to the
next q1/q5 phase with an exact clock.

Fast job
[44778191825](https://github.com/shemshallah/NaNLMind/actions/runs/44778191825)
on `72ae406`; clean-branch bridge
[44778826706](https://github.com/shemshallah/NaNLMind/actions/runs/44778826706)
was dispatched on the same commit.

### Left loops and left 4-prefix bridge (kernel-checked)

The tagged left movement half now has complete loops:

- `q15_left_loop_target1_to_q5` (target true: q15 -> q3 -> q5),
- `q15_left_loop_target0_to_q1` (target false: q15 -> q2 -> q1).

The left 4-prefix counterpart is also native:

- `q15_q22_left_four_prefix_to_q20`,
- `q15_q22_left_four_prefix_relocates_to_q5`,
- `q5_left_false_gate_tagged_target_prefix`.

The spacer-aware gate `q5_left_false_gate_tagged_target_spacer` and its
composition `q15_left_four_prefix_gate` are also kernel-checked and
accepted on `main` (fast run
[44826329567](https://github.com/shemshallah/NaNLMind/actions/runs/44826329567),
merged as `62990c1`).  The complete four-prefix loops are a separate
unmerged branch experiment.

### Canonical q5 movement and q5-to-q1 cycles (kernel-checked)

The canonical instruction path is now closed at the movement level:

- `canonical_q5_instruction_q19_collision_to_q5` (right, first restored
  action hit),
- `canonical_q5_instruction_left_collision_to_q5` (left, current cell),
- `canonical_q5_return_scan_to_first_five`,
- `canonical_q5_instruction_q19_collision_to_q1` (right),
- `canonical_q5_instruction_left_collision_to_q1` (left).

The q5 -> q1 theorems expose the exact q5-left decomposition as an
explicit premise and return the q1 match entry with the rewritten rail.
Fast branch acceptance:
[44847179304](https://github.com/shemshallah/NaNLMind/actions/runs/44847179304).

The next open composition is the q1/q0/q4 match of the returned rail
against the following record, then the source encoder and halt
reflection.

### q5 -> matched q1 (kernel-checked)

The q5 -> q1 cycles now compose with `q1_all_matching_bits_wide`:

- `canonical_q5_instruction_q19_collision_to_match`,
- `canonical_q5_instruction_left_collision_to_match`.

The rail decomposition is an explicit premise, so the theorem is a
conditional representation bridge rather than a source-step claim.
Fast branch acceptance:
[44847699341](https://github.com/shemshallah/NaNLMind/actions/runs/44847699341).

The next open composition is the q5-scan/q1-match/q6-copy half that
turns this q1 entry back into the next q5 fetch entry.

### q5 -> q6 next-instruction entry (kernel-checked)

Composing the matched q1 cycles with the native q1->q6 scan gives:

- `canonical_q5_instruction_q19_collision_to_q6`,
- `canonical_q5_instruction_left_collision_to_q6`.

Fast branch acceptance:
[44849983390](https://github.com/shemshallah/NaNLMind/actions/runs/44849983390).

The remaining movement half is the q6 copy/direction/restore/q16 path
back to q5; after that the q5->q6 and q6->q5 halves close the source
step.

### q6 -> q12/q13 (kernel-checked)

`canonical_q6_copy_direction_to_q12` composes the q6 action copy with
the q9/q10 direction capture and reaches the exact q12/q13 frame.
Fast branch acceptance:
[44853328187](https://github.com/shemshallah/NaNLMind/actions/runs/44853328187).

The remaining movement half is q12/q13 -> restore -> q16 decision ->
q19/q20 -> q17/q18 -> q5.

### q12/q21 -> q5 (kernel-checked)

- `canonical_q21_decision_to_q5` and its generic-map variant
  `canonical_q21_decision_to_q5_map`,
- `canonical_q12_restore_to_q5`.

Fast branch acceptance:
[44857107069](https://github.com/shemshallah/NaNLMind/actions/runs/44857107069).

The right canonical instruction movement is closed at q5:
q5 -> q6 -> q12 -> q16 -> q19 -> q17/q18 -> q5.  The left q13 branch
and the source encoder/halt reflection remain.

### q13 -> q5 (kernel-checked) and both movement halves closed

- `canonical_q22_decision_to_q5_left`,
- `canonical_q13_restore_to_q5`.

Fast branch acceptance:
[44863526932](https://github.com/shemshallah/NaNLMind/actions/runs/44863526932).

The canonical instruction movement is now closed for both directions:

```text
q5 return -> q6 -> q12/q13 -> q16 -> q19/q20 -> q17/q18 -> q5 return.
```

The next composition is the single q5-return -> q5-return macro joining
the q5->q6, q6->q12/q13, and q12/q13->q5 theorems, followed by the source
encoder and halt reflection.

### Full right instruction to q12 (kernel-checked)

`canonical_q5_instruction_full_right_to_q12` joins the q5 -> q6
match/copy and the q6 -> q12 copy/direction phases in one native run
with the exact summed clock.  Fast branch acceptance:
[44910845782](https://github.com/shemshallah/NaNLMind/actions/runs/44910845782).

The last movement composition is q5 -> q12 -> q5, using
`canonical_q12_restore_to_q5`.

### Full right instruction macro q5 -> q5 (kernel-checked)

`canonical_q5_instruction_full_right_to_q5` composes the q5 -> q12
match/copy/direction theorem with q12 -> q5 restore/relocation.  It is
the complete right instruction movement, with all representation
premises explicit and the exact summed native clock.  Fast branch
acceptance:
[44913839415](https://github.com/shemshallah/NaNLMind/actions/runs/44913839415).

The left full macro (q5 -> q13 -> q5) uses the same pattern with
`canonical_q13_restore_to_q5`.

### Full left instruction to q13 (kernel-checked)

`canonical_q5_instruction_full_left_to_q13` joins the left q5 -> q6
match/copy with the q6 -> q13 false-direction copy/direction phase.
Fast branch acceptance:
[44916335227](https://github.com/shemshallah/NaNLMind/actions/runs/44916335227).

The final left movement composition is q5 -> q13 -> q5 via
`canonical_q13_restore_to_q5`.

### Full left instruction macro q5 -> q5 (kernel-checked)

`canonical_q5_instruction_full_left_to_q5` composes the full left
q5 -> q13 match/copy/direction theorem with q13 -> q5
restore/q20/q17/q18.  Fast branch acceptance:
[44917301839](https://github.com/shemshallah/NaNLMind/actions/runs/44917301839).

Both directions now have complete q5 -> q5 instruction movement macros:

- `canonical_q5_instruction_full_right_to_q5`,
- `canonical_q5_instruction_full_left_to_q5`.

The remaining obligations are the source encoder/tape invariant, halt
reflection iff, and the universality reduction.

### Native halt shape (kernel-checked)

The frozen table has exactly one halting entry q3/5:

- `halting_entries_ok_true` (computed certificate over the 184 rows),
- `find_entry_halt_unique`,
- `scan_table_some_in`, `scan_table_some_from_read`,
- `read_write`, `move_tape_zero`,
- `step_halted_shape`.

`step_halted_shape` states that a step from a running configuration can
halt only in the encoded marker configuration (state 0, read 5) or
outside the finite table domain:

```text
c_halted c = false ->
c_halted (step c) = true ->
(c_state (step c) = 0 /\ read (c_tape (step c)) = 5) \/
(23 <= c_state (step c) \/ 8 <= read (c_tape (step c))).
```

This is the native half of halt reflection.  The encoder must show that
valid encoded configurations are in range and that the marker is reached
exactly when `source_lookup` fails.  Fast branch acceptance:
[44932476393](https://github.com/shemshallah/NaNLMind/actions/runs/44932476393).

### Packaged canonical step (kernel-checked)

`canonical_step` / `canonical_step_ok` / `canonical_step_start` /
`canonical_step_end` / `canonical_step_clock` package the full right
q5 -> q5 macro as a single reusable native step.  Fast branch
acceptance:
[44937038226](https://github.com/shemshallah/NaNLMind/actions/runs/44937038226).

The remaining encoder obligation is exactly:

```text
forall rows c,
  exists p, canonical_step_ok p /\
    canonical_step_start p = encode rows c /\
    canonical_step_end p = encode rows (source_step rows c).
```

plus the clock/positivity/halt-refinement instances.

### Packaged step clock and halt invariants (kernel-checked)

- `canonical_step_clock_positive`:
  `1 <= canonical_step_clock p` for every packaged step.
- `canonical_step_start_not_halted` / `canonical_step_end_not_halted`.
- `canonical_step_run_not_halted`:
  the packaged native step never introduces a halt.

These discharge the clock-positivity and native halt-invariant
obligations of the source encoder interface.  Fast branch acceptance:
[44939960496](https://github.com/shemshallah/NaNLMind/actions/runs/44939960496).

The remaining encoder obligation is still the concrete `encode`
construction with matching `canonical_step_start`/`end` frames.

### Wide halt-side encoder fragment (kernel-checked)

The first concrete wide-source encoder piece is formal:

- `wide_halted_marker`, `wide_halt_entry`,
- `wide_encode_halt` (halted and lookup-failure cases; running case is a
  placeholder),
- `wide_encode_halt_reflects`:
  `c_halted (wide_encode_halt rows c) = wc_halted c`,
- `wide_encode_halt_step_none`: for a running source configuration with
  `wide_source_lookup = None`, the one-step native run reaches the
  encoding of the source successor.

Full bridge acceptance:
[44946577098](https://github.com/shemshallah/NaNLMind/actions/runs/44946577098).

The remaining encoder work is the running/lookup-hit case, which must
use the packaged canonical step.

### Running-case one-row macro (kernel-checked)

- `canonical_q5_return_to_q1`,
- `canonical_q5_return_to_q6`,
- `canonical_q6_to_q5_right`,
- `canonical_q5_return_to_q5_right`.

Fast branch acceptance:
[44954850874](https://github.com/shemshallah/NaNLMind/actions/runs/44954850874).

This resolves the pipeline offset: the one-row source step is
q5-return -> q5-return, not q5-fetch -> q5-return.  The encoder can map
a source configuration to the q5 return frame and use this macro.  The
left/q13 variant and the concrete tape layout remain.

### Running-case one-row macro, both directions (kernel-checked)

- `canonical_q5_return_to_q5_right`,
- `canonical_q5_return_to_q5_left`.

Fast branch acceptance:
[44957145351](https://github.com/shemshallah/NaNLMind/actions/runs/44957145351).

Both directions now have the complete one-row running macro from a q5
return frame to the next q5 return frame.  The remaining encoder pieces
are the concrete q5-return layout and the lookup-failure/mismatch
branch.

### Packaged running return step (kernel-checked)

`canonical_return_step` / `canonical_return_step_ok` /
`canonical_return_step_start` / `_end` / `_clock` and
`canonical_return_step_run` package the q5-return -> q5-return running
macro.  Fast branch acceptance:
[44959046681](https://github.com/shemshallah/NaNLMind/actions/runs/44959046681).

The remaining encoder obligation is the concrete q5-return layout and
the invariant that the running step preserves it.  The halt-side
fragment is already proved in `MinskyWideMacroSimulation.v`.

### Running-step data shift and non-vacuity (kernel-checked)

The first packaged running-step interface shared one `data` list between
the q5 return frame, the q6 entry and the end frame.  That made
`crso_left` and `crso_prefix` inconsistent: the q5 frame ends with
`rev pre ++ b :: rev data`, while the next q6 entry needs
`data' = data ++ [b] ++ pre`.  The repair is explicit:

- `canonical_q5_return_to_q5_right` now takes `data'` and the shift
  `rev data' = rev pre ++ source_bit bprev :: rev data`;
- `canonical_q5_return_to_q5_left` takes `data_q6` with both the write
  shift and the q20 pop `rev data_q6 = source_bit d :: rev data'`;
- `canonical_return_step` has `crs_data` and `crs_data'`, and
  `canonical_return_step_ok` has `crso_shift`.

`formal/utm/MinskyReturnWitness.v` gives a concrete inhabitant of
`canonical_return_step_ok` (state marks `[false;true]`, action
`[false;false]`) and proves the packaged native run.  Hence the running
package is non-vacuous.  Fast acceptance:
[44972476708](https://github.com/shemshallah/NaNLMind/actions/runs/44972476708).

### Packaged left running step (kernel-checked)

`formal/utm/MinskyCanonicalLeftStep.v` packages
`canonical_q5_return_to_q5_left` as `canonical_left_step`, with start,
end, exact clock, `canonical_left_step_ok`, and
`canonical_left_step_run`.  The left shift and the q20 data pop are
explicit fields.  Fast acceptance:
[44972476708](https://github.com/shemshallah/NaNLMind/actions/runs/44972476708).

### Arbitrary-width tagged dispatch (kernel-checked)

`formal/utm/MinskyTaggedWideDispatch.v` generalizes the tagged q0/q5
gates to any finite list of 6/7 tags:

- `q0_tagged_control_list_dispatches_target`,
- `q5_left_false_gate_tagged_list_dispatch`,
- `q5_q1_q0_buffered_tagged_list_dispatch`,
- `q15_left_false_guard_native_tagged_list_dispatch`.

The left four-prefix loops are also checked:

- `q15_left_four_prefix_loop_read1_to_q5`,
- `q15_left_four_prefix_loop_read0_to_q1`.

The arbitrary-width *right* q15 relocation still needs the same
association cleanup; the two-tag theorem
`q15_right_buffered_native_tagged_target_dispatch` remains the checked
right interface.  Fast acceptance:
[44972476708](https://github.com/shemshallah/NaNLMind/actions/runs/44972476708).

These results remove the shared-data inconsistency and the fixed
two-bit limitation from the left tagged dispatch.  They still do not
construct the concrete `encode` from a wide source configuration, the
running-case invariant, or the halt/mismatch branch.  The claim flag
remains false.

### One-row running families with arbitrary tape (kernel-checked)

`MinskyReturnWitness.v` and `MinskyCanonicalLeftStep.v` now contain
right and left one-row families for a fixed two-bit instruction:

```text
canonical_witness_family data bprev
canonical_witness_family_ok / _run

canonical_left_witness_family data bprev
canonical_left_witness_family_ok / _run
```

The source data list and the previous write bit are arbitrary; only the
instruction bits are fixed.  The right family shifts
`data' = data ++ [bprev]`; the left family pops the written cell and
returns the old data.  Both exact native runs are checked in
[44977466571](https://github.com/shemshallah/NaNLMind/actions/runs/44977466571)
and
[44977821167](https://github.com/shemshallah/NaNLMind/actions/runs/44977821167).

This is the first non-vacuous one-row encoder step in both directions
with an arbitrary tape suffix.  The remaining generalization is from the
fixed instruction `[false;true]/[false;false]` to arbitrary `bits` and
`action` lists, followed by the wide-source lookup instantiation and the
halt/mismatch branch.  No universality claim is made.

### Machine-readable one-row example (kernel-checked)

`MinskyReturnWitness.v` now contains a concrete nonempty-tape instance:

```text
start = entry_config 5 [5;6;0;1;0]
          [2;3;4;0;1;0;0;1;0]
end   = entry_config 5 [5;0;0;1;0]
          [6;2;4;0;1;0;0;1;0]
```

and `canonical_witness_family_example_run` proves the exact packaged
native run between them.  Fast acceptance:
[44980338256](https://github.com/shemshallah/NaNLMind/actions/runs/44980338256).

This is an executable positive example for the repaired running-step
interface, not a source-machine simulation or a universality claim.

### Generic right one-row step (kernel-checked)

`formal/utm/MinskyRowStepGeneric.v` now constructs a concrete
`canonical_return_step` for an arbitrary condition and action:

```text
bits    = first_init :: init_rest ++ [pre_last; last_bit]
action  = first_action :: action_tail ++ [last_state; bnext]
```

under the single length equation
`|action ++ [bnext]| = |bits|`.  The theorem
`canonical_row_step_ok` discharges every `canonical_return_step_ok`
field by list algebra; there is no axiom or admitted lemma.  The rail is
`[pre_last]` followed by the reversed marks of the earlier condition
bits, and the q16 backscan is `[4]` followed by the raw bits.

Fast acceptance:
[44997720933](https://github.com/shemshallah/NaNLMind/actions/runs/44997720933).

This is the rightward generic row-step compiler.  The leftward generic
row step, the wide-source lookup instantiation, the running invariant,
and the halt/mismatch branch remain open.  The claim flag remains false.

### Generic left one-row step (kernel-checked)

`formal/utm/MinskyRowStepGenericLeft.v` is the leftward analogue of
the generic right row step:

```text
canonical_left_row_step
  first_init init_rest pre_last last_bit
  first_action action_tail last_state bnext data bprev rest_tail
```

with `bits = first_init :: init_rest ++ [pre_last; last_bit]`,
`action = first_action :: action_tail ++ [last_state; bnext]`, and the
same length equation.  The data shift writes `bprev` and the q20 left
move pops it, so `data' = data`.

`canonical_left_row_step_ok` discharges every `canonical_left_step_ok`
field.  Fast acceptance:
[44999141705](https://github.com/shemshallah/NaNLMind/actions/runs/44999141705).

Together with `MinskyRowStepGeneric.v`, both directions now have a
generic one-row native step for arbitrary condition/action lists of
width at least two.  The remaining encoder work is the width-one case,
the concrete `encode` from `WideSourceConfig`, the lookup invariant, and
the halt/mismatch branch.  No universality claim is made.

### q5-return orientation obstruction (kernel-checked)

`formal/utm/MinskyReturnOrientation.v` proves that the raw generic
row-step end frame cannot be the start of the canonical q5-return macro:

```text
end left  = rev hpost ++ 6 :: 5 :: bnext :: rev data'
canonical = rail ++ 5 :: rev tbuffer ++ 6 :: rev data''
```

The first 5 in the end frame occurs after the 6, so the post-5 prefix is
`bnext :: rev data'`.  It contains no 6 when `data'` is binary.  But the
canonical `crs_prefix` requires a 6 in that prefix.  The theorem
`five_six_swap_not_canonical_prefix` formalizes the contradiction.

Fast acceptance:
[45031342907](https://github.com/shemshallah/NaNLMind/actions/runs/45031342907).

Consequence: the raw one-row step is a valid single macro but is **not**
idempotent in the q5-return representation.  The running encoder must use
an explicit normalization phase or the tagged 6/7 layout.  This is a
negative result about the raw layout, not about the frozen table.  The
claim flag remains false.

### Arbitrary-width right tagged dispatch (kernel-checked)

`formal/utm/MinskyTaggedRightWide.v` completes the right direction of
the tagged dispatch:

```text
q15_right_buffered_native_tagged_list_dispatch
```

It starts at the q15 right entry with a tagged current-state rail and an
arbitrary tagged next-state list, runs the q15/q16/q22/q19/q17-q18
relocation, the buffered q5/q1 gate, and the q0 target dispatch, and
ends at q3/q2.  The only fixed cells are the one-cell `[2]` return
buffer and the `[5]` direction marker.

Fast acceptance:
[45034738248](https://github.com/shemshallah/NaNLMind/actions/runs/45034738248).

Together with the left dispatch in `MinskyTaggedWideDispatch.v`, both
tagged directions now support an arbitrary finite action rail.  The
remaining tagged obligations are the upstream canonical q12 -> q15
entry construction and the source-level normalization/halt branch.
The claim flag remains false.

### Wide row to generic native step (kernel-checked)

`formal/utm/MinskyRowStepWide.v` connects an arbitrary well-formed
`WideSourceRow` of state width at least two to the generic native step:

```text
wide_row_step r data bprev rest_tail
wide_row_step_ok :
  wide_row_wellformed p r -> 2 <= p ->
  canonical_return_step_ok (wide_row_step ...)
wide_row_step_run
```

The condition split is `wr_current r ++ [wr_read r]`; the action split is
`wr_next r ++ [wr_write r]`.  The split functions `split_init` and
`split_last` are concrete, and the only width obligation is
`|wr_next r| = |wr_current r|`, supplied by well-formedness.

Fast acceptance:
[45049700811](https://github.com/shemshallah/NaNLMind/actions/runs/45049700811).

This attaches the generic native macro to real source rows with an
arbitrary tape and program tail.  The one-bit state width is covered by
the fixed witness families.  The remaining encoder work is the concrete
program layout that makes the end frame the start frame for the next
lookup, plus the halt/mismatch branch.  The claim flag remains false.

### Wide row to the left native step (kernel-checked)

`formal/utm/MinskyRowStepWideLeft.v` is the leftward analogue:

```text
wide_row_step_left r data bprev rest_tail
wide_row_step_left_ok
wide_row_step_left_run
```

It uses the same `split_init`/`split_last` extraction and the same
well-formedness/width obligations.  Fast acceptance:
[45051589822](https://github.com/shemshallah/NaNLMind/actions/runs/45051589822).

Both native directions now have a one-row step attached to an arbitrary
well-formed `WideSourceRow` of width at least two.

**Caveat.**  The raw q5-return frame does not distinguish the source
write bit from the next read bit in the same way as `WideSource`: the
end frame's last condition bit is the write bit, while the source
semantics reads the new head cell after the move.  The raw row step is a
valid native macro and a useful phase, but it is not by itself the
`WideSource` encoder.  The tagged q15 layout, which carries `sacrificial`
(write) and `target` (read) separately, is the intended semantic bridge.
The claim flag remains false.

### Tagged dispatch continuations (kernel-checked)

`formal/utm/MinskyTaggedContinuation.v` composes the arbitrary-width
tagged right and left dispatches with the native q3 continuations:

```text
tagged_right_dispatch_halts
tagged_left_dispatch_halts
```

When the source read target is true, the dispatch reaches q3.  If the
q3 tail is a q3-passable list followed by the end marker 5, the machine
halts.  This is the concrete halt/lookup-failure branch of the tagged
layout.

The same module also proves the running true-read continuation:

```text
tagged_right_dispatch_to_q5
tagged_left_dispatch_to_q5
```

which scans q3 to the next X=4 and re-enters q5.

Fast acceptance:
[45057593387](https://github.com/shemshallah/NaNLMind/actions/runs/45057593387).

The false-read q2 -> q1 continuation is now also closed by
`MinskyTaggedReentry.v`; see the next section.

### Tagged q2 reentry and prefetched q1 fetch (kernel-checked)

`formal/utm/MinskyTaggedReentry.v` fixes the q2 endpoint of both tagged
directions:

```text
tagged_right_dispatch_to_q1
tagged_left_dispatch_to_q1
```

Both start at the literal q15 tagged entry, run the dispatch, the q3/q2
continuation, and the literal q2 left scan to the Y delimiter, ending at
a q1 entry with the preprocessed rail.  The q1 pass class
`q1_pass` in `MinskyMatchMacro.v` was widened from `{0,1}` to
`{0,1,6,7}`; q1 is the identity-right row on 6/7, so this is a strict
generalization of the existing match macros, not a new machine rule.

`formal/utm/MinskyTaggedPrefetch.v` composes those endpoints with a
*prefetched* q1 match and the q1 -> q6 X crossing:

```text
tagged_right_prefetch_to_q6
tagged_left_prefetch_to_q6
```

The caller supplies the next condition/action in the q1 rail.  This is a
concrete native macro that removes the need for a native linear search
if the encoder can place the successor row in the rail.  It is not yet a
total source encoder: the q6 -> q12/q14 -> q15 tagged continuation and
the concrete rail invariant remain open.  The claim flag remains false.

Fast acceptance: local Coq 8.20.1 `coqc` and `coqchk` for
`MinskyTaggedReentry.vo` and `MinskyTaggedPrefetch.vo`.  The full bridge
and fast q15-q22 jobs passed in
[run 45080600506](https://github.com/shemshallah/NaNLMind/actions/runs/45080600506)
at `19ff0bc`.

### Tagged q12 restore with a leftover tail (kernel-checked)

`formal/utm/MinskyTaggedRestore.v` proves
`canonical_q12_restore_with_leftover`: once q12 reaches the first M=6,
the q14 restore carries every symbol after that delimiter through
untouched as the q15 frame's outer tape.  In particular, 6/7 tags left
behind the delimiter do not have to be crossed by q12.

This removes the "q12 cannot pass a tagged rail" obstruction for tags
that are *after* the first 6.  It does not yet align the q15 right-hand
mark orientation with the tagged q15 entry; that upstream construction
remains open, so the claim flag remains false.

### Exact q12 -> tagged q15 interface (kernel-checked)

`canonical_q12_restore_to_tagged_entry` states the precise bridge
obligation: if the encoder supplies the q12 start with a `6/7` tag rail,
a raw target mark, and a restored prefix `source_bit old :: dirs`, then
q12/q14 land exactly on the tagged q15 entry used by the movement
macros.

The remaining proof is therefore isolated to one construction: produce
that q12 start from the running native phase.  The q6/direction phase
only emits `2/3` marks, so it cannot supply the `6/7` rail directly;
a genuinely different tag-introduction path is required.  The claim flag
remains false.

### November 23 buffer-exhaustion counterexample (critical)

The book-layout macro cycles are now closed for one instruction, but the
finite `0^b` buffer is not yet a total encoder invariant.  A concrete
literal-table probe exposed the gap.

Source program (p = 5): states `q0..q19`, each reading `0`, writing `0`,
moving right, with `q19,0 -> q19,0,R`; the source never halts.  The
native book tape has `p=5`, data `[0;0;0]`, `M`, an eight-cell zero
t-buffer, `Y`, condition, description, final `Y`.  The literal 23x8
table halts after 46,176 steps, while the source run does not halt.

The q19 captures show the source head advancing through the t-buffer
(`head 2,3,...,11`), then q19 reads `Y=5` at head 12, passes it, and the
machine eventually halts via the `q3/Y` entry.  This is premature
halting relative to the intended two-sided source semantics.

Consequences:

- the current `0^8` book layout is only valid for a bounded right
  excursion; the perform cycle's `b -> b-1` decreases the buffer and has
  no refill theorem;
- Minsky's published format is for a **left-infinite** simulated tape;
  the project's `WideSource` uses a two-sided `Z -> bool` tape, which is
  stronger than the table's finite-buffer layout;
- a total universality proof must either use a one-sided source model
  with a rightmost cell (matching the published tape format) or add a
  native buffer-extension/refill phase.

This does not invalidate the macro theorems; it invalidates the claim
that the current macro cycles plus a fixed eight-cell buffer already
form a total encoder.  The claim flag remains false.

## November 23 update: bounded-window simulation and encoder macros

New kernel-checked modules (all pass `coqc` and `coqchk`; no
`Admitted`/`Axiom`/`Parameter`):

- `MinskyLeftInfiniteStepRight.v` — general non-boundary right-hit
  macro for `lic_q5_encode` and the computed-first-match wrapper.
- `MinskyLeftInfiniteStepLeft.v` — general non-boundary left-hit macro,
  corrected left frame equality, and the `left_next_lo` window rule.
- `MinskyLeftInfiniteHalt.v` — halted encoder `lic_halt_encode`,
  no-match macro, and boundary frame connection.
- `MinskyLeftInfiniteLookupFull.v`,
  `MinskyLeftInfiniteLookup.v` — full `wide_source_lookup` ↔
  `book_first_match` hit/halt packaging.
- `MinskyLeftInfiniteFirstMatchApp.v` — hit/halt preservation under an
  appended row suffix.
- `MinskyLeftInfiniteEncoding.v` — duplicate-sentinel running
  description, and explicit right/left/no-match macros for it.
- `MinskyLeftInfiniteBounded.v` — padded-window finite-run simulation:

```text
lic_bounded_hit_run
lic_bounded_none_halt_run
lic_bounded_native_halt_implies_source_halt
lic_bounded_source_halt_implies_native_halt
lic_pad_hit_run
lic_pad_none_halt_run
lic_pad_native_halt_implies_source_halt
```

These prove, unconditionally, that for any source run of `n` steps that
does not reach the right wall and does not fail lookup, the frozen table
simulates it exactly with a window `head - n - 2` and a padded right
endpoint.  They do not yet give a single `encode p rows c` independent of
`n`.

Still open:

1. the empty-buffer right-boundary q19/q3 general halt frame (a focused
   agent is working in `MinskyLeftInfiniteBoundary.v`);
2. the left-window shift at `lo = head - 1` (blank pad representation);
3. the fixed-configuration encoder/`macro_cost` assembly and the three
   premises of `conditional_left_source_native_halting_equivalence`.

`claimed` remains false.

## November 23 late update: boundary trace and first-halt padding

`MinskyLeftInfiniteBoundary.v` (kernel-checked, no axioms) now contains
the empty-buffer q19/q3 trace:

```text
q19_empty_relocation
q15_q22_right_to_q5_book_empty
book_q12_restore_to_q5_right_empty
q5_scan_empty_boundary
boundary_halt_encode_from
book_q1_mismatch_halt_gen_extra
boundary_test_run_129
```

The concrete p=1 wall halt is the kernel-checked 129-step run
`boundary_test_run_129`, not a table axiom.  The only missing boundary
lemma is the first failed-row phase with a leading q1 pass list; the
pass must be included in the q0/q4 backward scan, so the output is a
`pass`-aware locate state, not yet the standard one.

`MinskyLeftInfiniteBounded.v` additionally proves:

```text
lic_halts_at_first
lic_first_halt_exists
lic_first_halt_hit_prefix
lic_encode_pad
lic_pad_source_halt_to_native
```

For a padded source run of length `n` that halts, the fixed table halts
from `lic_encode_pad rows n c`.  Combined with
`lic_pad_native_halt_implies_source_halt`, the remaining bridge to a
fixed/padded halting equivalence is padding invariance: the halt flag at
a fixed fuel is unchanged when the initial right/left blank padding is
increased.  The address tape bisimulation in
`MinskyAddressRefinement.v` is the intended tool; the encoder-side
blank-support invariant for the left padding still has to be stated.

Claim remains false.

## November 23: full empty-buffer boundary macro and marker lift

Kernel-checked on main:

- `MinskyLeftInfiniteBoundaryLocate.v`:
  pass-aware locate/halt chain and the full empty-buffer q12→q19→q5
  wall macro `book_q12_empty_boundary_halt`, ending at
  `boundary_halt_encode_from [6] steps last ...`.
- `MinskyLeftInfiniteLift.v`:
  two-bit state marker `false :: true :: s`; the lift commutes with
  `left_infinite_step`/`left_infinite_run`:
  - `left_infinite_step_lift`
  - `left_infinite_run_lift`
  - `left_infinite_halts_lift`
  - `wide_source_lookup_lifted_rotated = None`

The q19 wall retry condition is `tl hit_init ++ [hd hit_init]`.  Under
the marker lift it starts with `true`, while every lifted row condition
starts with `false`, so the retry always takes the no-match halt branch.
This removes the spurious-match unsoundness of the sentinel-retry
approach at the wall.

Bounded clock soundness is also on main:

- `lic_bounded_no_premature_halt`
- `lic_bounded_clock_native_halt_implies_source_halt`
- `lic_bounded_clock_mono`

Remaining:
1. compose the lifted boundary q12 frame into the source-level
   `lic_q5_encode` boundary step (the q12/q5 frame identities are the
   same as the nonempty right frame equality);
2. resolve the halted-frame path dependence (`extra = [6]` at the wall
   versus `extra = []` for lookup failure), either by a common canonical
   halt frame or a collision proof;
3. left-window pad and fixed `encode`/`macro_cost` assembly.

Claim remains false.

## November 23: lifted boundary and left-depth soundness

Kernel-checked on main:

- `MinskyLeftInfiniteBoundaryLookup.v`:
  `book_first_match_first_bit_halt` — the p-bit reversed source
  `tl hit_init ++ [hd hit_init]` starts with `true`, every lifted row
  condition starts with `false`, and the first-bit mismatch is a valid
  `book_failure` (not `book_lookup_bad`).
- `MinskyLeftInfiniteBoundaryLifted.v`:
  `lic_q5_encode_lifted_boundary_halt` and
  `lic_q5_encode_lifted_boundary_halt_state` — the source-row boundary
  run with the failure witnesses computed.
- `MinskyLeftInfiniteLeftDepth.v`:
  `lic_left_hit_run`, `lic_left_none_halt_run`,
  `lic_left_no_premature_halt` — actual right wall, separate left
  window, per-step right-move wall condition.

The forward lifted halting assembly is in progress.  The reverse
direction will use `lic_left_no_premature_halt` plus the first-stop scan:
if the native halts within the macro clock, the scan either finds a
source halt or the run is entirely hit/left/right; the latter contradicts
the no-premature-halt theorem.  A boundary halt at the last scanned step
is itself a source halt.

Claim remains false.

## November 23: clock independence and the last gap

Kernel-checked:

- `MinskyLeftInfiniteBounded.v`:
  `lic_step_cost_lo_ind`, `lic_bounded_clock_lo_ind`
- `MinskyLeftInfiniteClockInd.v`:
  `lic_q5_empty_boundary_clock_lo_ind`
- `MinskyLeftInfiniteLeftDepth.v`:
  `lic_left_ok_window`

Key finding: **the left-window depth does not affect any native clock.**
The `w_tape` argument of the q5 locate clock is unused, the perform
clocks use the right buffer, and the passive ptape is never scanned.
Only the frame representations depend on `lo`.

This removes the finite-window clock-growth obstruction.  The remaining
gap is purely proof exposure: the forward theorem returns an opaque `t`,
so one cannot choose `K = max k t` and reuse the same `t` at the deeper
window without an explicit-clock forward theorem:

```coq
lic_lifted_source_halt_to_native_explicit
```

stating the witness clock and its invariance under `lo`.  Once exposed,
the equivalence follows:

```text
source halts <->
exists K t, K >= t /\ native halts at t from the K-window encoding.
```

The forward direction chooses `K = max k t`; the backward direction
uses `K >= t` with `lic_lifted_native_halt_to_source` at `n = t`.
No mathematical obstruction remains, only the explicit-witness refactor.

Claim remains false until that refactor and the final equivalence are
kernel-checked.


## November 23 closure: `lic_lifted_halting_equivalence`

Kernel-checked in `formal/utm/MinskyLeftInfiniteClockRun.v`, with no
`Admitted`/`Axiom`/`Parameter` (`Print Assumptions` reports "Closed under
the global context"; `coqchk` reports "Modules were successfully
checked"):

```coq
Theorem lic_lifted_halting_equivalence :
  forall (p : nat) (rows : list WideSourceRow) (c : LeftInfiniteConfig),
    Forall (wide_row_wellformed p) rows ->
    rows <> [] ->
    length (lic_state c) = p ->
    left_infinite_ok c ->
    left_infinite_eventually_halts rows c <->
    exists K t,
      K >= t /\
      c_halted (run t
        (if lic_halted c then dispatch_halt_at_y [] []
         else lic_q5_encode (lic_head c - Z.of_nat K - 2)
                (lic_lift_cfg c)
                (lic_book_rows (lic_lift_rows rows)) [])) = true.
```

Supporting checked theorems:

- `lic_forward_clock`, `lic_forward_clock_lo_ind`,
  `lic_forward_clock_run` (the explicit recursive native clock and its
  halting run);
- `lic_step_cost_none_eq`, `lic_step_cost_right_eq`,
  `lic_step_cost_left_eq`, `lic_boundary_clock_of_eq` (branch
  alignments);
- `lic_book_rows_first_match_hit_app_bridge`,
  `lic_book_rows_first_match_hit_snoc` (source/augmented first-match
  bridge);
- `lic_step_cost_lo_ind`, `lic_bounded_clock_lo_ind`,
  `lic_q5_empty_boundary_clock_lo_ind`, `lic_left_ok_window`,
  `lic_step_cost_pos_wellformed`,
  `lic_state_length_step_general`,
  `lic_bounded_clock_at_least_steps_general`.

Scope: the frozen 23x8 `run` is a universal interpreter for the
left-infinite binary-tape source model on all well-formed inputs
(`Forall (wide_row_wellformed p) rows`, `rows <> []`,
`length (lic_state c) = p`, `left_infinite_ok c`).  The source halts iff
the native table halts from the q5 encoding with a left window `K` and
native time `t`, `K >= t`.

The existential window is essential.  A single total
`encode p rows c` independent of the run time is not claimed and is not
true for this table: a right-wall halt and a lookup-failure halt can
have the same halted source configuration but different native frames.

## November 24 NaN16 VM layer (in progress)

The table-level theorem above is unchanged and remains the certified
universality claim.  A separate, lower VM layer is being built for the
literal NaN16 fixture `mth/tests/mth_minsky_test.nas`.

Checked locally (all `Print Assumptions` closed under the global context):

```text
MinskyNaN16VM.v            ISA subset, scan block, scan_ready, table_mem_at
MinskyNaN16ScanLoop.v      184-row scan loop, hit and no-match exits
MinskyNaN16Action.v        action block, action_run, preservation lemmas
MinskyNaN16ActionPrefix.v  pc 0 -> 5
MinskyNaN16ActionMove.v    pc 5 -> 14, exact fuel 3/6/5, with r0/r7/mem frame
MinskyNaN16ActionSuffix.v  pc 14 -> 22, both halt branches, full memory
MinskyNaN16ActionRefines.v action_refines (pc 0 -> 22, pointwise action_run)
MinskyNaN16ScanFrame.v     r0/r2/r3/r13/mem/halted scan frame
MinskyNaN16ScanPhase.v     scan_phase with hit/no-match exits
MinskyNaN16Lookup.v        scan_index_from vs nan16_lookup bridge
MinskyNaN16StepHit.v       step_hit_phase (scan -> action -> pc 22)
MinskyNaN16StepNone.v      no_trans_run / step_none_phase
MinskyNaN16Step.v          native_step and native_step_refines
```

The dedicated runner is validating this cone.  **Not yet done:**

1. the literal step prelude/normalization (partially scaffolded in
   `MinskyNaN16Prelude.v`, no run theorem yet);
2. a single contiguous `.nas` step program or a checked block
   transcription gate;
3. `run100` iteration over the step routine;
4. the VM-memory/window representation of `AddressConfig` and the
   one-step source refinement to `nan16_address_step`/`MinskyTable.step`;
5. the raw VM-level certificate and any change to the spec claim.

No VM-level universality claim is made by this section.  The spec
`claim` for the Coq table remains separate and must not be read as a
NaN16 execution claim.
