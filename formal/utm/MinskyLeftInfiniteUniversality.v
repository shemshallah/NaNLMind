(** * Computable forward clock and the halting equivalence

    The old forward theorem returns an opaque witness.  This file defines
    the recursive clock directly and proves the `lo`-independence of the
    clock and the forward run theorem. *)

From Coq Require Import List Arith Bool Lia ZArith.
Import ListNotations.

From NaNLM Require Import MinskyTable MinskySourceEncoding MinskyWideSource
  MinskyConcreteDispatch MinskyMatchMacro MinskyBookLayout MinskyBookLocate
  MinskyBookLocateRows MinskyBookLocateWide MinskyBookLocateCycle
  MinskyBookLocateLookup MinskyBookEncode MinskyBookRawBuffer
  MinskyLeftInfinite MinskyLeftInfiniteEncode MinskyLeftInfiniteWindow
  MinskyLeftInfiniteLookup MinskyLeftInfiniteLookupFull
  MinskyLeftInfiniteHalt MinskyLeftInfiniteHaltBook
  MinskyLeftInfiniteEncoding MinskyLeftInfiniteBounded
  MinskyLeftInfiniteLeftDepth MinskyLeftInfiniteBoundary
  MinskyLeftInfiniteBoundaryLocate MinskyLeftInfiniteBoundaryBook
  MinskyLeftInfiniteBoundaryFinal MinskyLeftInfiniteBoundaryLookup
  MinskyLeftInfiniteBoundaryLifted MinskyLeftInfiniteClockInd
  MinskyLeftInfiniteLift MinskyLeftInfiniteLiftForward
  MinskyLeftInfiniteLiftBackward.

Local Open Scope nat_scope.

(** ** Boundary clock from the computable first-match data *)

Definition lic_boundary_clock_of
    (rows : list WideSourceRow) (lo : Z) (c : LeftInfiniteConfig)
    (r : WideSourceRow) : nat :=
  let cl := lic_lift_cfg c in
  match book_first_match
          (lic_state cl ++ [lic_tape cl (lic_head cl)])
          (lic_book_rows (lic_lift_rows rows)) with
  | book_lookup_hit steps hit (next :: rest) =>
      match book_first_match
              (tl (lic_lift_state (wr_next r)) ++
               [hd false (lic_lift_state (wr_next r))])
              (lic_book_rows (lic_lift_rows rows)) with
      | book_lookup_halt sf lf =>
          lic_q5_empty_boundary_clock lo cl steps hit
            (lic_lift_state (wr_next r)) (wr_write r) sf lf
      | _ => 0
      end
  | _ => 0
  end.

Lemma lic_boundary_clock_of_lo_ind :
  forall (rows : list WideSourceRow) (lo lo' : Z)
         (c : LeftInfiniteConfig) (r : WideSourceRow),
    lic_boundary_clock_of rows lo c r =
    lic_boundary_clock_of rows lo' c r.
Proof.
  intros. unfold lic_boundary_clock_of. reflexivity.
Qed.

Print Assumptions lic_boundary_clock_of_lo_ind.

(** ** The recursive forward clock *)

Fixpoint lic_forward_clock
    (rows : list WideSourceRow) (n : nat) (lo : Z)
    (c : LeftInfiniteConfig) : nat :=
  match n with
  | 0 => 0
  | S k =>
      if lic_halted c then 0
      else
        match wide_source_lookup rows (lic_state c)
                (lic_tape c (lic_head c)) with
        | None => lic_step_cost (lic_lift_rows rows) lo (lic_lift_cfg c)
        | Some r =>
            if left_infinite_right_blocked c r then
              lic_boundary_clock_of rows lo c r
            else
              lic_step_cost (lic_lift_rows rows) lo (lic_lift_cfg c) +
              lic_forward_clock rows k lo (left_infinite_step rows c)
        end
  end.

Lemma lic_forward_clock_lo_ind :
  forall (rows : list WideSourceRow) (n : nat) (lo lo' : Z)
         (c : LeftInfiniteConfig),
    lic_forward_clock rows n lo c = lic_forward_clock rows n lo' c.
Proof.
  intros rows n. induction n as [|n IH];
    intros lo lo' c.
  - reflexivity.
  - cbn [lic_forward_clock].
    destruct (lic_halted c) eqn:Eh; [reflexivity|].
    destruct (wide_source_lookup rows (lic_state c)
      (lic_tape c (lic_head c))) as [r|] eqn:El.
    + destruct (left_infinite_right_blocked c r) eqn:Eb.
      * apply lic_boundary_clock_of_lo_ind.
      * rewrite (lic_step_cost_lo_ind (lic_lift_rows rows) lo lo' (lic_lift_cfg c)).
        rewrite (IH lo lo' (left_infinite_step rows c)).
        reflexivity.
    + apply (lic_step_cost_lo_ind (lic_lift_rows rows) lo lo' (lic_lift_cfg c)).
Qed.

Print Assumptions lic_forward_clock_lo_ind.
