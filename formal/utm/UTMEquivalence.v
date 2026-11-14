(** * Mechanized UTM equivalence theorem

    This file is checked against the Coq Library of Undecidability Proofs.
    The library constructs a fixed, universal, single-tape, binary Turing
    machine [UTM] by composing certified simulations:

      Krivine machine  ->  5-register Minsky machine
                       ->  multi-tape Turing machine
                       ->  single-tape Turing machine
                       ->  binary single-tape Turing machine

    The theorem below exposes the resulting halting equivalence as a local,
    named theorem.  It is a statement about a *fixed* machine, not a family of
    machines chosen per input.

    Honest scope: this is a halting equivalence for the fixed binary UTM.  It
    does not mechanize a step-for-step tape simulation of the C++ chart
    interpreter.  The latter remains a refinement obligation.
*)

From Undecidability.TM Require Import TM UTM UTM_undec.
From Undecidability.TM.Reductions Require Import
  KrivineMclosed_HALT_to_HaltUTM.
From Undecidability.L Require Import L.
From Undecidability.LambdaCalculus Require Import Lambda Krivine.
From Undecidability.Synthetic Require Import Undecidability.
From Undecidability.Shared.Libs.PSL.FiniteTypes Require Import FinTypesDef.

(** ** Fixed-UTM halting equivalence

    There is a computable encoding of every closed Krivine term into a binary
    tape such that the fixed binary [UTM] halts on that tape iff the term halts
    in the Krivine machine.  The witness is the encoding constructed by the
    certified reduction chain (Krivine -> 5-register Minsky -> multi-tape TM
    -> single-tape TM -> binary TM). *)
Theorem UTM_halting_equivalence :
  exists encode : { t : L.term | Lambda.closed t } ->
                  tape (finType_CS bool),
    forall x,
      KrivineMclosed_HALT x <-> HaltUTM (encode x).
Proof.
  exact KrivineMclosed_HALT_to_HaltUTM.reduction.
Qed.

(** The fixed machine is binary and single-tape by construction. *)
Definition UTM_is_binary_single_tape :
  TM (finType_CS bool) 1 := UTM.

(** The halting problem for this fixed machine is undecidable.  This is a
    consequence of the same fixed-UTM construction, not an extra axiom. *)
Theorem UTM_halting_undecidable : undecidable HaltUTM.
Proof.
  exact HaltUTM_undec.
Qed.

(** Print the logical assumptions of the main theorem.  It must be closed
    under the global context: no axioms, no parameters, no admits. *)
Print Assumptions UTM_halting_equivalence.
