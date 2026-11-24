# Raw Coq certificate: `lic_lifted_halting_equivalence`

This directory contains the raw, kernel-checkable certificate for the fixed
23x8 Minsky-table halting equivalence proved in
`formal/utm/MinskyLeftInfiniteClockRun.v`.

It is a certificate for the **Coq model of the table**, not a refinement
certificate for the native NaN16 guest program or the NaN0S VM.  In
particular, it does not prove that `n16i`/NaN0S is a UTM, and it does not
formally link the Coq table to `mth/tests/mth_minsky*.nas`.

## Artifacts

| File | Meaning |
| --- | --- |
| `lic_lifted_halting_equivalence.statement.txt` | Exact statement with `Set Printing All`. |
| `lic_lifted_halting_equivalence.assumptions.txt` | `Print Assumptions`; the theorem is closed. |
| `lic_lifted_halting_equivalence.proofterm.txt` | Full printed proof term (raw certificate text). |
| `lic_lifted_halting_equivalence.coqchk.txt.gz` | Full raw `coqchk -o` transcript, compressed. |
| `lic_lifted_halting_equivalence.coqchk.summary.txt` | The `coqchk` status and context summary. |
| `lic_lifted_halting_equivalence.certificate.json` | Manifest: statement, assumptions, hashes, Coq version, dependency source/`.vo` hashes. |
| `generate_certificate.v` | Coq script that regenerates the statement/assumptions/proof-term text. |
| `reproduce.sh` | Rebuilds and rechecks the certificate. |

## Raw result

```text
$ cat lic_lifted_halting_equivalence.assumptions.txt
Closed under the global context
```

```text
$ tail -18 lic_lifted_halting_equivalence.coqchk.summary.txt
  checking cst:NaNLM.MinskyLeftInfiniteClockRun.lic_forward_clock_run
  checking cst:NaNLM.MinskyLeftInfiniteClockRun.lic_lifted_halting_equivalence
Modules were successfully checked

CONTEXT SUMMARY
===============

* Theory: Set is predicative
  
* Theory: Rewrite rules are not allowed
  
* Axioms:
    Coq.Logic.FunctionalExtensionality.functional_extensionality_dep
  
* Constants/Inductives relying on type-in-type: <none>
  
* Constants/Inductives relying on unsafe (co)fixpoints: <none>
  
* Inductives whose positivity is assumed: <none>
```

The `FunctionalExtensionality` line is a **module-cone** fact: it is used by a
theorem in `MinskyLeftInfinite.v`, which is loaded by the certificate module.
It is **not** an assumption of `lic_lifted_halting_equivalence`;
`Print Assumptions lic_lifted_halting_equivalence` is closed, and the proof
term in `lic_lifted_halting_equivalence.proofterm.txt` does not contain it.
Use the `Print Assumptions` output, not the module-wide context summary, for
the theorem's exact assumption set.

## Anchor hashes (SHA-256)

```text
3a2f7c1da821c71e5e58871e4694150a6e4f2ecbbed87384601b4d00270e3a92  MinskyLeftInfiniteClockRun.v
1400472a72cc1f293b0a28d6157e9ad5575efcf37ee71d65d2efb8c70245a385  MinskyLeftInfiniteClockRun.vo
d8342d708a7403f7bb314cd484747d81da3f7f922fc4c78c61a67bf0b24f1b5c  MinskyLeftInfiniteUniversality.v
4c2adc7d081414756e2807079f71f37c9f7a28ddbcc8b72f5d8e899f20278dd7  lic_lifted_halting_equivalence.statement.txt
188ff29b8a0705f491438ebf47623e533fe60658944f3f1f58e1f9b5badb1bcf  lic_lifted_halting_equivalence.assumptions.txt
9f4cf150845cf46cd400a66a2837b3f0708c41cd021a3f35e52b759204465306  lic_lifted_halting_equivalence.proofterm.txt
cacf9f42d6c24b588cf091a44d0ecfcbf07df0a29a9f9ec88847a6e54daa02bf  lic_lifted_halting_equivalence.coqchk.txt.gz
```

The `coqchk` log contains absolute paths and is machine-specific; its hash is
an artifact anchor, not a reproducibility claim.  The source, statement, and
assumptions hashes are the stable ones.

## Reproduce

Inside the Debian proot guest with Coq 8.20:

```sh
cd ~/NaNLMind
proot-distro login debian -- bash formal/utm/certificates/reproduce.sh
```

Or, with `coqc`/`coqchk` already on `PATH`:

```sh
bash formal/utm/certificates/reproduce.sh
```

## Scope

The certified theorem is:

```text
left_infinite_eventually_halts rows c
  <->
exists K t, K >= t /\
  c_halted (run t
    (if lic_halted c then dispatch_halt_at_y [] []
     else lic_q5_encode (lic_head c - Z.of_nat K - 2)
            (lic_lift_cfg c)
            (lic_book_rows (lic_lift_rows rows)) [])) = true
```

for all `p`, `rows`, `c` with:

- `Forall (wide_row_wellformed p) rows`,
- `rows <> []`,
- `length (lic_state c) = p`,
- `left_infinite_ok c`.

The left window `K` is existential and may grow with the native time `t`.
A total, run-time-independent `encode` is not claimed: wall-halt and
lookup-failure halt frames can collide.

## What this certificate is *not*

It is not:

- a refinement of `third_party/nan0s/core/nan16.c`;
- a proof that the raw NaN16 programs in `mth/tests/mth_minsky*.nas` are
  semantically equivalent to the Coq table;
- a proof that NaN0S/`n16i` is a UTM.

Those remain separate semantics-preserving bridge obligations, as recorded in
`formal/utm/DEEPSEEK_NAN16_HANDOFF.md` and `docs/79_NAN0S_TM_PROOF.md`.
