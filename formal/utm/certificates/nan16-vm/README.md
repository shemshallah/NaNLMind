# Raw Coq certificate: final NaN16 VM halting equivalence

This directory is the final VM-level certificate for the fixed 23x8 Minsky
table running under the Coq model of the literal NaN16 fixture
`mth/tests/mth_minsky_test.nas`.

The certified theorem is:

```text
NaNLM.MinskyNaN16Universality.nan16_run_halting_equivalence_canonical
```

It is checked by `coqc` and `coqchk` (Coq 8.20.1), has no `Admitted`,
`Axiom`, or `Parameter` in its proof, and `Print Assumptions` reports
`Closed under the global context`.

## Exact theorem

From `nan16_run_halting_equivalence_canonical.statement.txt`
(`Set Printing All`):

```text
nan16_run_halting_equivalence_canonical
     : forall (p : nat) (rows : list MinskyWideSource.WideSourceRow)
         (c : MinskyLeftInfinite.LeftInfiniteConfig)
         (_ : @List.Forall MinskyWideSource.WideSourceRow
                (MinskyWideSource.wide_row_wellformed p) rows)
         (_ : not
                (@eq (list MinskyWideSource.WideSourceRow) rows
                   (@nil MinskyWideSource.WideSourceRow)))
         (_ : @eq nat (@length bool (MinskyLeftInfinite.lic_state c)) p)
         (_ : MinskyLeftInfinite.left_infinite_ok c),
       iff (MinskyLeftInfinite.left_infinite_eventually_halts rows c)
         (@ex nat
            (fun K : nat =>
             @ex nat
               (fun t : nat =>
                and (ge K t)
                  (nan16_vm_halted
                     (MinskyNaN16Run.vm_run t
                        (nan16_vm_of_addr K
                           (MinskyAddressRefinement.embed_config
                              (lic_native_init rows c K) BinNums.Z0))
                        MinskyNaN16RunConcrete.fixture_table
                        MinskyNaN16RunConcrete.fixture_table_base)))))
```

In prose: for every finite state width `p`, every nonempty well-formed row
list, and every well-formed left-infinite source configuration, the source
machine halts **iff** there exist a left-window depth `K` and a native run
time `t` with `K >= t` such that the closed NaN16 VM run started from the
`K`-window encoding halts.  The initial VM is the explicit constructor
`nan16_vm_of_addr K (embed_config (lic_native_init rows c K) 0)`; only `K`
and `t` are existential.

## Raw assumptions

```text
$ cat nan16_run_halting_equivalence_canonical.assumptions.txt
Closed under the global context
```

The three supporting theorems are also closed:

```text
$ cat nan16_source_halt_to_vm.assumptions.txt
Closed under the global context
$ cat nan16_vm_halt_to_source.assumptions.txt
Closed under the global context
$ cat nan16_run_halting_equivalence.assumptions.txt
Closed under the global context
```

## Raw coqchk result

```text
$ grep -E 'checking cst:.*nan16_run_halting_equivalence_canonical|^Modules were successfully checked' \
    nan16_run_halting_equivalence_canonical.coqchk.summary.txt
  checking cst:NaNLM.MinskyNaN16Universality.nan16_run_halting_equivalence_canonical
Modules were successfully checked

$ tail -19 nan16_run_halting_equivalence_canonical.coqchk.summary.txt
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

`FunctionalExtensionality` is a **module-cone** fact in the full `coqchk`
context summary.  It is **not** an assumption of the certified theorem:
`Print Assumptions nan16_run_halting_equivalence_canonical` is closed, and
so are the three supporting theorems.  Use the `Print Assumptions` files,
not the module-wide context summary, for the theorem's exact assumption set.

## Files

| File | Meaning |
| --- | --- |
| `generate_certificate.v` | Coq script that `Redirect`s the statement, assumptions, and proof term. |
| `reproduce.sh` | Rebuilds the module, runs `coqchk`, generates all raw files, and prints hashes. |
| `nan16_run_halting_equivalence_canonical.statement.txt` | Exact statement with `Set Printing All`. |
| `nan16_run_halting_equivalence_canonical.assumptions.txt` | `Print Assumptions`; closed. |
| `nan16_run_halting_equivalence_canonical.proofterm.txt` | Full printed proof term. |
| `nan16_run_halting_equivalence_canonical.coqchk.summary.txt` | Target-library `coqchk` transcript and context summary. |
| `nan16_run_halting_equivalence_canonical.coqchk.txt.gz` | Full raw `coqchk -o` transcript, compressed. |
| `nan16_run_halting_equivalence_canonical.certificate.json` | Manifest: theorem, assumptions, hashes, Coq version, project dependency source/`.vo` hashes, scope, and caveats. |
| `nan16_source_halt_to_vm.assumptions.txt` | Forward direction assumptions. |
| `nan16_vm_halt_to_source.assumptions.txt` | Backward direction assumptions. |
| `nan16_run_halting_equivalence.assumptions.txt` | Quantified-VM form assumptions. |

## Anchor hashes (SHA-256)

Stable source/artifact anchors:

```text
61f5d54a8329360f23fe074009ee866320f5dca3aae4e866d471d98d1e2c0f66  MinskyNaN16Universality.v
d3ee6d5c1e5284d45f31741af35feb0eb8651201e3a28ead919fa18d1a8b8be9  nan16_run_halting_equivalence_canonical.statement.txt
188ff29b8a0705f491438ebf47623e533fe60658944f3f1f58e1f9b5badb1bcf  nan16_run_halting_equivalence_canonical.assumptions.txt
5722a3fa97254832fa204f0db6f0debe524e78191838d99422fde072cbf79a3b  nan16_run_halting_equivalence_canonical.proofterm.txt
40562ace144ab7e1b16fb0360b779829d742976e6bc11ecf58e9951d4443f5a1  nan16_run_halting_equivalence_canonical.coqchk.summary.txt
```

Build-artifact anchors (current local Coq 8.20.1 build):

```text
e331933b2b1f2ee92ef118df199c415068fbbeda76f50f0c80848f454bd2ce68  MinskyNaN16Universality.vo
c622f8a1bb945146481a8db595980baa054bd6159758d0505ce6a38caed5795c  nan16_run_halting_equivalence_canonical.coqchk.txt.gz
```

The full `coqchk` log contains absolute build paths and is machine-specific;
its gzip hash is an artifact anchor, not a reproducibility claim.

## Reproduce

From the repository root, inside an environment with Coq 8.20 on `PATH`
(the Debian proot guest used by the rest of this project works):

```sh
proot-distro login debian -- bash formal/utm/certificates/nan16-vm/reproduce.sh
```

Or, if `coqc` and `coqchk` are already on `PATH`:

```sh
bash formal/utm/certificates/nan16-vm/reproduce.sh
```

The script runs:

```text
coqc -Q formal/utm NaNLM formal/utm/MinskyNaN16Universality.v
coqchk -o -Q formal/utm NaNLM formal/utm/MinskyNaN16Universality.vo
coqc -Q formal/utm NaNLM formal/utm/certificates/nan16-vm/generate_certificate.v
```

and fails if `coqchk` does not print `Modules were successfully checked` or
does not check the canonical theorem.

## Scope and non-claims

The theorem is about the **Coq NaN16 VM model** and the fixed 23x8 table
image at `fixture_table_base = 104` with tape base `fixture_tape_base = 4096`.
It is not:

- a refinement of a host `nan16.c` reference harness or any external NaN0S
  VM; `MinskyNaN16VM.exec_instr` is a trusted Coq ISA model;
- a proof that the assembled `.nas` image or the NaN16 assembler/encoder
  matches the Coq instruction blocks;
- a proof of the assembled code, instruction encodings, or loader.  The
  Coq data-cell constants are pinned to the `.nas` labels (`tbase` 99,
  `state` 100, `head` 101, `halt` 102, `table` 104); `rlink` 103 is
  reserved and unmodelled.  The theorem still talks about the Coq VM model,
  and `check_minsky_nan16_step.py` compares memory operands symbolically
  (`@head`, `@state`, `@halt`, `@tbase`, `@table`) rather than encoding the
  image;
- a total run-time-independent encoder.  `K` may grow with the native time
  `t`; only `exists K t, K >= t` is claimed.
- a proof of the literal 100-step fixture `PASS` path or a fixed `run100`
  iteration count.
