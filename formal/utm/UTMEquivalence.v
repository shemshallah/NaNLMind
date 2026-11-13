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

From Undecidability.TM Require Import UTM UTM_undec.
From Undecidability.TM.Reductions Require Import
  KrivineMclosed_HALT_to_HaltUTM.
From Undecidability.LambdaCalculus Require Import Krivine.
From Undecidability.Synthetic Require Import Undecidability.
From Undecidability.Shared.Libs.PSL.FiniteTypes Require Import FinTypesDef.

(** The encoding used by the certified reduction.  It maps every closed
    Krivine term to a binary tape accepted by the fixed [UTM]. *)
Definition encode_closed
    (x : { t : term | closed t }) : tape (finType_CS bool) :=
  proj1_sig (KrivineMclosed_HALT_to_HaltUTM.reduction x).

(** ** Fixed-UTM halting equivalence

    For every closed Krivine term [x], the fixed binary [UTM] halts on the
    encoding of [x] if and only if [x] halts in the Krivine machine.  Since the
    Krivine machine is a universal model of computation, this is the
    mechanized universality statement for the fixed UTM's halting behaviour.
*)
Theorem UTM_halting_equivalence
    (x : { t : term | closed t }) :
  KrivineMclosed_HALT x <-> HaltUTM (encode_closed x).
Proof.
  exact (proj2_sig (KrivineMclosed_HALT_to_HaltUTM.reduction x)).
Qed.

(** The same statement with the encoding written out as a function. *)
Theorem UTM_simulates_closed_Krivine :
  forall x : { t : term | closed t },
    KrivineMclosed_HALT x <-> HaltUTM (encode_closed x).
Proof.
  intro x. apply UTM_halting_equivalence.
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
