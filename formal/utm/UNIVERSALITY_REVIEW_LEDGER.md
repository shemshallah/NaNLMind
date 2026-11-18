# Concrete Minsky 23×8 universality: referee-facing proof ledger

Status date: 2026-11-16. **Full universality is NOT established.**
This ledger distinguishes computational evidence, Coq-verified lemmas, and
remaining mathematical obligations. It must not be used as a claim of
Nature-level completion while any critical obligation below is open.

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
