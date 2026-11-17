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
