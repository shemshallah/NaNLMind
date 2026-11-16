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
