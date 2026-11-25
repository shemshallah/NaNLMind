(* Raw certificate generator for the final NaN16 VM theorem.

   Run from formal/utm with:

     coqc -Q . NaNLM -w -notation-overridden,-stdlib-vector \
       certificates/nan16-vm/generate_certificate.v

   The Redirect outputs are renamed by reproduce.sh.  The coqchk summary is
   produced by the coqchk invocation in that same script; it cannot be
   produced by a Coq Redirect directive because it is a checker transcript,
   not a Coq vernacular output. *)

From NaNLM Require Import MinskyNaN16Universality.

Set Printing All.

Redirect "certificates/nan16-vm/nan16_run_halting_equivalence_canonical.statement.txt"
  Check nan16_run_halting_equivalence_canonical.
Redirect "certificates/nan16-vm/nan16_run_halting_equivalence_canonical.assumptions.txt"
  Print Assumptions nan16_run_halting_equivalence_canonical.
Redirect "certificates/nan16-vm/nan16_run_halting_equivalence_canonical.proofterm.txt"
  Print nan16_run_halting_equivalence_canonical.

(* Supporting direction theorems, both closed. *)
Redirect "certificates/nan16-vm/nan16_source_halt_to_vm.assumptions.txt"
  Print Assumptions nan16_source_halt_to_vm.
Redirect "certificates/nan16-vm/nan16_vm_halt_to_source.assumptions.txt"
  Print Assumptions nan16_vm_halt_to_source.
Redirect "certificates/nan16-vm/nan16_run_halting_equivalence.assumptions.txt"
  Print Assumptions nan16_run_halting_equivalence.
