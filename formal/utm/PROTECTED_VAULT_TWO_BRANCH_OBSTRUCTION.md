# Protected-vault two-branch obstruction — certified 2026-11-17

Author: Justin Howard-Stanley (Independent Researcher, Santa Cruz, California, USA).

Status: **Kernel-checked, layout-specific negative theorem package.**

Proof source: [MinskyDirectionRelocationCycle.v](MinskyDirectionRelocationCycle.v), using the unchanged 23-state × 8-symbol table of [MinskyTableData.v](MinskyTableData.v).

## Verification and provenance

- Proof commit: [8379d6e](https://github.com/shemshallah/NaNLMind/commit/8379d6ed119d89e5d400ad6c25a26df95bd7a0b7).
- Fast Coq compilation and kernel check: [run 44176965873](https://github.com/shemshallah/NaNLMind/actions/runs/44176965873), SUCCESS in both cycle and canonical-match jobs.
- Independent full Minsky/UTM mechanized build: [run 44176965890](https://github.com/shemshallah/NaNLMind/actions/runs/44176965890), SUCCESS.
- Minsky representation bridge: [run 44176965785](https://github.com/shemshallah/NaNLMind/actions/runs/44176965785), SUCCESS.
- Repository CI: [run 44176965687](https://github.com/shemshallah/NaNLMind/actions/runs/44176965687), SUCCESS.

## Initial configuration

Let n be the length of scanned. The checked guard q19_q5_roundtrip_railb scanned = true means each scanned symbol is 4, 6, or 7.

The q12 left tape begins with [5;6], another protected 6, and an arbitrary encoded wide program. The right tape begins with raw 0, route 4, scanned, the raw next bit, marker 7, the raw extra bit, and the raw target bit, followed by an arbitrary tail.

The earlier one-6 layout satisfied q12_complete_vault_cycle_cannot_resume: after its complete return, q12 or q13 stayed trapped for all additional finite fuel. The second protected 6 allows native reentry into q15 and q16, but its two branches introduce different errors.

## Exact certified results

| Coq theorem | Native clock | Scope | Certified effect |
| --- | ---: | --- | --- |
| q12_protected_second_six_selects_q19_or_q20 | 8n + 52 | Every guarded scan, any encoded program, arbitrary next/extra/target bits and tail | True extra enters q19; false extra enters q20. |
| q12_protected_vault_left_branch_overwrites_program_bit | 8n + 54 | Every guarded scan, **every nonempty list of wide source rows** with arbitrary fields | q20 passes row marker 4 and overwrites the first raw source-program bit as 6, entering q17/q18. |
| q12_protected_vault_right_branch_consumes_control_bit | 9n + 58 | Every guarded scan, including empty wide programs, arbitrary next/target bits and tail | q19 consumes the restored next/control bit, enters q17/q18, and leaves the intended target bit still on the right tape. |

All clocks count literal MinskyTable.run transitions, not macros. The proof handles arbitrary finite rail lengths and program widths, without relying on finite enumeration.

## Structural explanation

**Left branch (extra=false).** Each nonempty encoded wide source program starts with 4 and then at least one raw 0/1 bit. q20 can cross the 4, but the next raw bit triggers its write-6 relocation. The stored instruction is therefore damaged.

**Right branch (extra=true).** q16 restores both 2/3 direction marks into raw 0/1. The q19 right tape begins as follows:

    [7;5;7;4] ++ scanned ++ [6; source_bit next;
                             source_bit extra; source_bit target] ++ tail

The prefix ending with 6 is q19-passable, so the very next encountered raw bit is next, not target. Thus q19 relocates a control bit before the intended target.

## Requirements for any future repair

1. Keep ordinary raw encoded program bits outside q20's leftward scan until the intended source-data boundary.
2. Prevent q19 from treating a restored control bit as the first relocation target.
3. Preserve a left-accessible 6 for q12/q13 reentry.
4. Prove canonical-entry reachability and whole-instruction simulation with both program and source-tape invariants.

A phase-separated control rail that delays restoration of 2/3 control marks, combined with a protected program region, is a **hypothesis for investigation**, not a validated design.

## Scope and claim ledger

**Proved:** exact native configurations and affine clocks under explicit guards, left-branch program overwrite for any nonempty encoded wide program, and right-branch premature capture of a control bit.

**Not proved:** reachability of this q12 frame from the canonical entry; any complete source-instruction simulation; impossibility of other encodings; non-universality of the frozen 23×8 machine; or any result about unrelated NaNLM architectures.

The original literal transition table remains unchanged. The negative result is specific to this protected-vault layout.


## Protected raw-stop and five-guard continuation — certified extension

This extension was completed and independently verified on 2026-11-17/18. It refines the left-branch repair without altering the frozen 23-state by 8-symbol transition table.

Proof commit: [bde6543](https://github.com/shemshallah/NaNLMind/commit/bde6543a4e49ed9602bc663864fd9fd11794abe1).

Independent verification on the same commit:

- [Fast cycle and canonical-match coqchk, both SUCCESS](https://github.com/shemshallah/NaNLMind/actions/runs/44226433010).
- [Full independent mechanized UTM/Minsky build, SUCCESS](https://github.com/shemshallah/NaNLMind/actions/runs/44226433020).
- [Representation bridge, SUCCESS](https://github.com/shemshallah/NaNLMind/actions/runs/44226433028).
- [Repository CI, SUCCESS](https://github.com/shemshallah/NaNLMind/actions/runs/44226433204).

The revised left tape starts with [5;6], a protected 6, an extra sacrificial raw source bit, a protected 5, and finally the entire encoded wide program. The original right control rail has extra=false, a guarded scanned prefix, next, marker 7, and the intended target.

The following universal quantified theorems now hold under q19_q5_roundtrip_railb scanned = true (each scanned symbol is 4, 6 or 7):

| Coq theorem | Exact native clock | Certified outcome |
| --- | ---: | --- |
| q12_sacrificial_stop_arbitrary_suffix | 8n + 53 | q20 consumes the sacrificial raw bit; the stored suffix is unmodified at q17 or q18. |
| q12_sacrificial_five_guard_preserves_program_to_q1 | 8n + 58 | The protected 5 terminates the return through q5 and reaches q1 with all encoded source rows intact. |
| q12_sacrificial_five_guard_reenters_q0 | 8n + 60 | Two additional q1 steps reach q0, with the program still intact. |
| q12_sacrificial_guard_dispatches_early_next | 9n + 66 | q0 encounters restored next before target. A zero next enters q2; a one next enters q3. The intended target remains unconsumed in either outcome. |

These clocks measure native steps of MinskyTable.run. The proof does not assume finite enumeration, a fixed scanned length, a fixed program width, or a fixed target value. The q0 early-dispatch theorem explicitly preserves both branches and the remaining target bit.

### Mechanism of the new obstruction

The extra sacrificial raw bit fixes the original immediate program-overwrite problem. The protected 5 stops the q5 return before q5 enters the saved source program. Neither repair, however, changes the ordering of the control symbols restored by q16. Immediately before q0 dispatch, the right scan prefix is

    [sacrificial_mark;5;7;4] ++ map q16_restore scanned ++
    [6;source_bit next;0;source_bit target] ++ tail.

Every symbol before next is q0-passable. Thus the next raw bit is selected before the target on both branches. The result is an exact native layout-specific obstruction even though the encoded wide program has survived the repair.

### Required design change and open obligations

A successful whole-instruction layout needs a phase-separated control representation or a true control relocation that prevents restored next from being the first raw bit consumed by q0. Potential approaches include moving the temporary next bit outside q0's rightward scan, or protecting it with a passable marker until the intended target is processed. These are research proposals, not proved repairs.

Still open: canonical-entry reachability for the repaired frame; source-state correspondence; both left and right instruction semantics; total program preservation across a whole instruction; halting equivalence; and any universality theorem for the literal 23x8 table. Nothing here excludes other encodings of the same table.

**Publication status:** a self-contained, kernel-certified partial obstruction and repair-analysis package is available. Novelty, framing and comparison with the literature remain separate scholarly checks.


## General first-raw no-go and constructive 6/7 tag channel

Following the guarded 9n+66 obstruction, two distinct facts are now formally checked. They should not be conflated: the first is a general negative theorem, and the second is a positive local compatibility result for a different proposed layout.

### First-raw no-go for any finite q0-passable spacer

Coq theorem: q0_any_finite_passable_spacer_still_reads_first_raw.

For every finite spacer whose symbols are q0-passable (2 through 7), both choices of next and target, and arbitrary surrounding tape, q0 scans the spacer and dispatches on the first raw next bit after exactly 1 + length spacer native steps. The target bit remains farther right.

- [Commit 7537d36](https://github.com/shemshallah/NaNLMind/commit/7537d36dc2999aa5c2ada3c0d64a07ee8951c16d).
- [Fast Coq compilation and kernel check: SUCCESS](https://github.com/shemshallah/NaNLMind/actions/runs/44228628580).

Thus inserting additional 2/3/4/5/6/7 padding immediately before an early raw control bit cannot make q0 skip that bit. This is a structural no-go for a passive-spacer repair, not a claim about other encodings of the 23x8 table.

### Constructive q0-local tag pair

Proposed stable control tagging:

    stable_tag(false) = 6
    stable_tag(true)  = 7

These two symbols are passed unchanged by q0 and by q16's restore map. A revised q0 input would put both the next and extra controls in tagged form before the intended raw target.

The theorem q0_tagged_control_pair_dispatches_target proves that for every q0-passable prefix, q0 passes both tags and branches according to target after exactly length prefix + 3 native steps. The theorem q0_protected_prefix_with_tagged_controls_reads_target specializes this to the guarded protected prefix: length scanned + 8 native steps, arbitrary source suffix and both target choices.

- [Verified q0-tag commit 69f5980](https://github.com/shemshallah/NaNLMind/commit/69f598062916fec85a36f7dff613fb64c0c8192d).
- [Full independent UTM/Minsky build: SUCCESS](https://github.com/shemshallah/NaNLMind/actions/runs/44229700919).
- [Fast Coq: SUCCESS](https://github.com/shemshallah/NaNLMind/actions/runs/44229700901).

### Native q16 compatibility of arbitrary tagged rails

Coq theorem: q16_native_tagged_backscan_preserves_control_rail.

For any nonempty finite sequence of encoded Boolean control tags, an explicit native q16 backscan returns the entire tag rail unchanged, branches into q21 or q22 according to the separate raw delimiter, and has the exact fuel specified in the theorem. The associated map-level and safety lemmas hold for arbitrary finite tag rails.

- [Verified q16-tag commit b2ff42f](https://github.com/shemshallah/NaNLMind/commit/b2ff42fafaf4dcb3e0f096d7ffa75129d2cd1d87).
- [Fast Coq and coqchk: SUCCESS](https://github.com/shemshallah/NaNLMind/actions/runs/44232722252).
- [Independent full Minsky/UTM mechanized build: SUCCESS](https://github.com/shemshallah/NaNLMind/actions/runs/44232722318).
- [Representation bridge: SUCCESS](https://github.com/shemshallah/NaNLMind/actions/runs/44232722404).
- [Repository CI: SUCCESS](https://github.com/shemshallah/NaNLMind/actions/runs/44232722289).

### Exact remaining bridge

The two positive local theorems do not yet compose into a complete q12-to-q0 return. The old q12 phase begins with raw controls and q16 normally restores 2/3 marks to raw 0/1, giving the proved premature next-bit capture. The new proofs show what would work once both controls are represented by stable 6/7 tags, but the actual frozen-machine construction of that representation from the canonical q12 frame remains unproved.

The next research obligation is an exact native q12-to-tagged-q16 configuration theorem, with source-bit recoverability, preserved encoded program, and both directions. No whole-instruction simulation, halting equivalence, or universality claim is made by these local repairs.


## Certified tagged-rail q15→q5 directional package (2026-11-18)

The hypothetical 6/7-tagged control representation is now certified across a larger native-table macro. These theorems are generic over a **nonempty finite tagged rail**, arbitrary Boolean controls, and arbitrary surrounding suffixes. No transition-table entry was altered.

The two control-tag values are `6` for false and `7` for true. Their q15 passability, q16 restoration identity, and q19 passability permit one explicit tagged rail to cross several native phases without first being restored into an early raw 0/1 control.

| Coq theorem | Exact native phase | Certified scope |
| --- | --- | --- |
| `q15_q16_native_tagged_control_rail_roundtrip` | q15→q16→q21/q22; `2 × (rail length + 1)` steps | q15 scans to raw target; q16 returns to the separate raw old delimiter, preserving each tag and leaving target untouched. |
| `tagged_rail_q15_q22_right_to_q19` | q15→q16→q21/q22→q19 | Right-direction decision leaves the tagged rail intact, conditioned on a q21-safe direction scan. |
| `tagged_rail_q15_q22_left_to_q20` | q15→q16→q21/q22→q20 | Left-direction decision leaves the tagged rail intact, conditioned on a q21-safe direction scan. |
| `tagged_rail_right_relocates_to_q5` | q15→q16→q21/q22→q19→q17/q18→q5 | Right relocation ends in q5, with exact length-dependent fuel; additionally requires a q19-safe direction rail and a q17-safe forward scan. |
| `tagged_rail_left_relocates_to_q5` | q15→q16→q21/q22→q20→q17/q18→q5 | Left relocation ends in q5, with exact length-dependent fuel; additionally requires a q17-safe reverse direction rail. |

The source uses explicit `Forall` hypotheses; q21-safe alone is **not** enough for the right q19 scan, because q21 accepts raw 0/1 symbols that q19 would consume prematurely.

Authoritative source: `formal/utm/MinskyDirectionRelocationCycle.v`.

- [Initial q15/q16 composition commit be24daf](https://github.com/shemshallah/NaNLMind/commit/be24daf7f15616d2a47fe482ac47fdac802839f3) — [fast cycle](https://github.com/shemshallah/NaNLMind/actions/runs/44235201045), [independent full proof](https://github.com/shemshallah/NaNLMind/actions/runs/44235200989), [representation bridge](https://github.com/shemshallah/NaNLMind/actions/runs/44235201091), and [CI](https://github.com/shemshallah/NaNLMind/actions/runs/44235200920): all SUCCESS.
- [Both direction branches commit fa0524a](https://github.com/shemshallah/NaNLMind/commit/fa0524af587175e7c3603d475ecb4c783cdc72bb) — [fast cycle and canonical-match check](https://github.com/shemshallah/NaNLMind/actions/runs/44355420511): SUCCESS.
- [Full q5 relocation commit 9ef641c](https://github.com/shemshallah/NaNLMind/commit/9ef641c04c0c37e844131356ccd6b48d9103934d) — [fast cycle](https://github.com/shemshallah/NaNLMind/actions/runs/44357304129), [independent full Minsky/UTM](https://github.com/shemshallah/NaNLMind/actions/runs/44357304246), [representation bridge](https://github.com/shemshallah/NaNLMind/actions/runs/44357304188), and [CI](https://github.com/shemshallah/NaNLMind/actions/runs/44357304093): all SUCCESS.

**Remaining major gap:** these are genuine native transition theorems for supplied starting configurations, not proofs of their reachability from the canonical encoded source machine. In particular, the earlier q12 cycle restores raw temporary controls and provably dispatches the wrong raw bit on the guarded repaired layout. Establishing an exact q12-to-tagged-rail construction, preserving the source program and both direction semantics, is still open. So are all-instruction simulation, halt equivalence, and a universality theorem for the literal 23×8 table.

**Research status:** a strengthened, reproducible, kernel-certified partial theorem package is available. A major/open-problem closure is **not** claimed.
