# Mechanized UTM equivalence

## 1. What is checked

`formal/utm/UTMEquivalence.v` is checked against the Coq Library of
Undecidability Proofs (`coq-8.20`, commit
`70dfc56f33a6e4835281044e68aa68279989047e`).  The library constructs a fixed,
single-tape, binary Turing machine:

```text
Krivine machine
  -> 5-register Minsky machine
  -> multi-tape Turing machine
  -> single-tape Turing machine
  -> binary single-tape Turing machine
```

The local theorem is:

```coq
Theorem UTM_halting_equivalence
    (x : { t : term | closed t }) :
  KrivineMclosed_HALT x <-> HaltUTM (encode_closed x).
```

The machine `UTM` is fixed.  It is not selected per input.  The encoding is the
one produced by the certified reduction; the proof is a composition of the
library's mechanized simulations, ending at a binary single-tape machine.

The file also exports `UTM_simulates_closed_Krivine` and
`UTM_halting_undecidable`, and ends with `Print Assumptions`, so the CI log
shows the theorem is closed under the global context (no axioms, parameters, or
admits introduced by this file).

## 2. Run it

Local (Coq 8.20 required):

```sh
make mechanized-utm
```

Remote / long-running:

```sh
gh workflow run mechanized-utm.yml -R shemshallah/nanlm_experimental
gh run watch -R shemshallah/nanlm_experimental
```

The workflow uses the `coqorg/coq:8.20` container, builds only the fixed-UTM
dependency cone, checks `UTMEquivalence.v`, runs `coqchk`, and uploads the
`.vo`/`.glob` artifact.  It is intentionally separate from the fast NaN0S TM
gate and can run for hours without blocking development.

## 3. Honest boundary

This is a **halting equivalence** for the fixed binary UTM, mechanized through a
universal model of computation.  It is stronger than the earlier checked-trace
harness because the theorem is closed under Coq's kernel.

It is not yet:

- a step-for-step tape refinement of the C++ chart interpreter in
  `src/universal_tm.cpp`;
- a mechanization of the Minsky 23×8 table itself in the chart runtime;
- a proof-assistant statement about the NaN16 guest machine.

Those remain separate refinement obligations.  Do not describe this result as
a mechanized refinement of the chart runtime until that connection is checked.
