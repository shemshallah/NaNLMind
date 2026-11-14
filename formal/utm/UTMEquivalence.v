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

From Stdlib Require Import Vector.
From Undecidability.TM Require Import TM UTM UTM_undec.
From Undecidability.TM.Reductions Require Import
  KrivineMclosed_HALT_to_HaltUTM.
From Undecidability.L Require Import L.
From Undecidability.LambdaCalculus Require Import Lambda Krivine.
From Undecidability.Synthetic Require Import Undecidability.
From Undecidability.Shared.Libs.PSL.FiniteTypes Require Import FinTypesDef.

Import VectorNotations.

(** The explicit encoding used by the certified reduction.  This is the same
    chain as the library's reduction, but written as a transparent function so
    the theorem below can state the encoding directly. *)
Definition encode_closed
    (x : { t : L.term | Lambda.closed t }) : tape (finType_CS bool) :=
  let tm := proj1_sig x in
  let cs := KrivineMclosed_HALT_to_HaltUTM.KM_MMA.input tm in
  let ts := KrivineMclosed_HALT_to_HaltUTM.MMA_TM.encode_counters cs in
  let t := KrivineMclosed_HALT_to_HaltUTM.MTM_TM.ts' ts in
  Vector.hd (KrivineMclosed_HALT_to_HaltUTM.TM_BTM.ts' t).

(** ** Fixed-UTM halting equivalence

    For every closed Krivine term [x], the fixed binary [UTM] halts on the
    encoding of [x] if and only if [x] halts in the Krivine machine.  Since the
    Krivine machine is a universal model of computation, this is the
    mechanized universality statement for the fixed UTM's halting behaviour.
*)
Theorem UTM_halting_equivalence
    (x : { t : L.term | Lambda.closed t }) :
  KrivineMclosed_HALT x <-> HaltUTM (encode_closed x).
Proof.
  destruct x as [tm Htm].
  unfold encode_closed; simpl.
  apply (iff_trans (KrivineMclosed_HALT_to_HaltUTM.KM_MMA_iff Htm)).
  apply (iff_trans KrivineMclosed_HALT_to_HaltUTM.MMA_TM_iff).
  apply (iff_trans KrivineMclosed_HALT_to_HaltUTM.MTM_TM_iff).
  apply KrivineMclosed_HALT_to_HaltUTM.TM_BTM_iff.
Qed.

(** The same statement with the encoding written out as a function. *)
Theorem UTM_simulates_closed_Krivine :
  forall x : { t : L.term | Lambda.closed t },
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
